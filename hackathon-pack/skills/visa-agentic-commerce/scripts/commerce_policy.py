#!/usr/bin/env python3
"""Application policy helper, NOT a Visa API schema, payment client, or approval UI.

Keep signing and durable ledger operations on a trusted backend. The --demo command
uses test doubles; it cannot create a Visa instruction or move money.
"""
import argparse
import hashlib
import hmac
import json
import os
import re
import threading
import time

CART_FIELDS = {'version', 'merchantId', 'currency', 'amountMinor', 'currencyExponent', 'items', 'contextDigest'}
ITEM_FIELDS = {'id', 'quantity', 'unitAmountMinor'}


def positive_int(value):
    return type(value) is int and value > 0


def validate_cart(cart):
    if not isinstance(cart, dict) or set(cart) != CART_FIELDS:
        raise ValueError('Cart must contain exactly the documented application fields; no raw credentials')
    if not positive_int(cart['version']) or not positive_int(cart['amountMinor']):
        raise ValueError('Positive integer version and amountMinor required')
    if not isinstance(cart['contextDigest'], str) or not re.fullmatch(r'[a-f0-9]{64}', cart['contextDigest']):
        raise ValueError('SHA256 contextDigest of variant, fulfillment, and destination references required')
    if not isinstance(cart['merchantId'], str) or not re.fullmatch(r'[A-Za-z0-9_.:-]{1,100}', cart['merchantId']):
        raise ValueError('Stable merchant identifier required')
    if not isinstance(cart['currency'], str) or not re.fullmatch(r'[A-Z]{3}', cart['currency']):
        raise ValueError('Uppercase ISO currency code required; validate supported codes in adapter')
    if type(cart['currencyExponent']) is not int or not 0 <= cart['currencyExponent'] <= 3:
        raise ValueError('Explicit currency minor-unit exponent required; adapter must verify against currency table')
    if not isinstance(cart['items'], list) or not 1 <= len(cart['items']) <= 100:
        raise ValueError('One to 100 line items required')
    total, ids = 0, set()
    for item in cart['items']:
        if not isinstance(item, dict) or set(item) != ITEM_FIELDS:
            raise ValueError('Unexpected line-item field')
        if not isinstance(item['id'], str) or not re.fullmatch(r'[A-Za-z0-9_.:-]{1,100}', item['id']) or item['id'] in ids:
            raise ValueError('Unique stable line-item identifiers required')
        if not positive_int(item['quantity']) or not positive_int(item['unitAmountMinor']):
            raise ValueError('Positive integer quantities and minor-unit prices required')
        ids.add(item['id'])
        total += item['quantity'] * item['unitAmountMinor']
    if total != cart['amountMinor']:
        raise ValueError('Final total must include all charges as explicit line items')
    return cart


def digest(cart):
    validate_cart(cart)
    return hashlib.sha256(json.dumps(cart, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()).hexdigest()


def canonical(data):
    return json.dumps(data, sort_keys=True, separators=(',', ':')).encode()


class CommercePolicy:
    def __init__(self, signing_key, ledger=None, environment='simulated', lock=None):
        if environment not in {'simulated', 'sandbox'}:
            raise ValueError('This helper supports simulated or sandbox integration only')
        if not isinstance(signing_key, bytes) or len(signing_key) < 32:
            raise ValueError('Backend consent signing key must be at least 32 bytes')
        self.key, self.ledger, self.environment = signing_key, ledger if ledger is not None else {}, environment
        self.lock = lock if lock is not None else threading.Lock()

    def sign_after_user_approval(self, cart, request_id, expires_at, now=None):
        """Backend only. Invoke after explicit authenticated approval of the displayed cart."""
        now = int(time.time()) if now is None else now
        if type(expires_at) is not int or not now < expires_at <= now + 900:
            raise ValueError('Approval expiry must be within the next 15 minutes')
        if not isinstance(request_id, str) or not re.fullmatch(r'[A-Za-z0-9_.:-]{1,100}', request_id):
            raise ValueError('Stable application request ID required')
        payload = {'cartDigest': digest(cart), 'requestId': request_id, 'expiresAt': expires_at,
                   'approvedAt': now, 'environment': self.environment}
        return {'payload': payload, 'signature': hmac.new(self.key, canonical(payload), hashlib.sha256).hexdigest()}

    def submit(self, cart, consent, now=None):
        """Reserve before adapter invocation. Lock protects this instance, not multiple processes.

        Share a lock for instances sharing one dictionary. Real multi-worker applications
        must replace this reservation with a database transaction + unique request ID.
        """
        now = int(time.time()) if now is None else now
        if not isinstance(consent, dict) or set(consent) != {'payload', 'signature'}:
            raise ValueError('Signed backend consent required')
        payload = consent['payload']
        expected = hmac.new(self.key, canonical(payload), hashlib.sha256).hexdigest()
        if not isinstance(consent['signature'], str) or not hmac.compare_digest(expected, consent['signature']):
            raise ValueError('Invalid approval signature')
        if not isinstance(payload, dict) or set(payload) != {'cartDigest', 'requestId', 'expiresAt', 'approvedAt', 'environment'}:
            raise ValueError('Invalid consent payload')
        if payload['environment'] != self.environment or payload['cartDigest'] != digest(cart):
            raise ValueError('Cart or environment changed; obtain fresh user approval')
        if type(payload['expiresAt']) is not int or type(payload['approvedAt']) is not int or not payload['approvedAt'] <= now < payload['expiresAt']:
            raise ValueError('Approval expired or not yet valid')
        request_id = payload['requestId']
        with self.lock:
            if request_id in self.ledger:
                raise ValueError('Request already reserved; reconcile existing state before any retry')
            self.ledger[request_id] = {'state': 'submitted', 'cartDigest': payload['cartDigest'], 'environment': self.environment}
            return dict(self.ledger[request_id])

    def record_outcome(self, request_id, outcome, receipt_reference=None):
        """Adapter reports authoritative outcome; a purchase instruction alone is not payment."""
        with self.lock:
            return self._record_outcome(request_id, outcome, receipt_reference)

    def _record_outcome(self, request_id, outcome, receipt_reference=None):
        if request_id not in self.ledger:
            raise ValueError('Unknown request')
        entry = self.ledger[request_id]
        if entry['state'] not in {'submitted', 'unknown'}:
            raise ValueError('Terminal result cannot transition again')
        if outcome not in {'confirmed', 'failed', 'unknown', 'cancelled'}:
            raise ValueError('Unsupported outcome')
        if outcome == 'confirmed' and (not isinstance(receipt_reference, str) or not re.fullmatch(r'[A-Za-z0-9_.:-]{1,100}', receipt_reference)):
            raise ValueError('Confirmed requires a sanitized authoritative receipt reference')
        entry['state'] = outcome
        if receipt_reference and outcome == 'confirmed':
            entry['receiptReference'] = receipt_reference
        return dict(entry)


def demo():
    cart = {'version': 1, 'merchantId': 'fixture-merchant', 'currency': 'USD', 'amountMinor': 2500,
            'currencyExponent': 2, 'contextDigest': hashlib.sha256(b'fixture-context').hexdigest(),
            'items': [{'id': 'fixture-item', 'quantity': 1, 'unitAmountMinor': 2500}]}
    policy = CommercePolicy(b'simulated-fixture-key-never-use-live')
    consent = policy.sign_after_user_approval(cart, 'fixture-request', 1200, now=1000)
    policy.submit(cart, consent, now=1001)
    return {'mode': 'SIMULATED TEST DOUBLE', 'visaApiInvoked': False,
            'result': policy.record_outcome('fixture-request', 'confirmed', 'simulated-receipt-001')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--demo', action='store_true')
    parser.add_argument('--manifest', help='Application cart JSON, not a Visa request')
    args = parser.parse_args()
    if args.demo:
        print(json.dumps(demo(), indent=2))
    elif args.manifest:
        with open(args.manifest) as stream:
            cart = json.load(stream)
        print(json.dumps({'valid': True, 'cartDigest': digest(cart), 'paymentAuthorized': False}, indent=2))
    else:
        parser.error('Choose --demo or --manifest')


if __name__ == '__main__':
    main()
