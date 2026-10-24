#!/usr/bin/env python3
"""Offline replay of authored planning decisions and the optional commerce policy.

Synthetic facts only. Does not call an LLM, Visa, a merchant, or a catalog API.
"""
import copy
from datetime import datetime
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
PACK = HERE.parents[2]
sys.path.insert(0, str(PACK / 'skills/visa-agentic-commerce/scripts'))
from commerce_policy import CommercePolicy  # noqa: E402


def instant(value):
    return datetime.fromisoformat(value.replace('Z', '+00:00'))


def decision(product, request, now, expires):
    """Evaluate the explicit fixture contract, not a general product recommender."""
    charges = [product.get(key) for key in ('itemMinor', 'taxMinor', 'shippingMinor')]
    total = sum(charges) if all(type(value) is int and value >= 0 for value in charges) else None
    reasons = []
    if total is None:
        reasons.append('total_unknown')
    if now >= expires:
        reasons.append('quote_expired')
    if product['digitalUsbCAudio'] is not True:
        reasons.append('wired_usb_c_audio_unverified')
    if product['microphone'] is not True:
        reasons.append('microphone_unverified')
    if product['inStock'] is not True:
        reasons.append('not_in_stock')
    if product['deliveryDate'] is None:
        reasons.append('delivery_unknown')
    elif product['deliveryDate'] > request['deliverBy']:
        reasons.append('delivery_too_late')
    if total is not None and total > request['budgetMinor']:
        reasons.append('over_budget')
    return {'id': product['id'], 'amountMinor': total, 'eligible': not reasons, 'reasons': reasons}


def blocked(call, fragment):
    try:
        call()
    except ValueError as error:
        assert fragment in str(error), str(error)
        return str(error)
    raise AssertionError('Unsafe request unexpectedly accepted')


class FixtureAdapter:
    """Fake merchant accepted the request, but its initial response was lost."""
    def __init__(self):
        self.submissions = []
        self.receipts = {}

    def purchase(self, request_id):
        self.submissions.append(request_id)
        self.receipts[request_id] = 'fixture-receipt-001'
        raise TimeoutError('Synthetic transport timeout after simulated acceptance')

    def reconcile(self, request_id):
        return self.receipts[request_id]


def main():
    catalog = json.loads((HERE / 'catalog.fixture.json').read_text())
    now, expiry = instant(catalog['observedAt']), instant(catalog['quoteExpiresAt'])
    decisions = [decision(p, catalog['request'], now, expiry) for p in catalog['products']]
    expected = {
        'harbor-c': (6901, []),
        'metro-anc': (7987, ['wired_usb_c_audio_unverified']),
        'studio-c': (7553, ['delivery_unknown']),
        'fast-c': (8529, ['over_budget']),
        'commute-c': (6510, ['not_in_stock']),
    }
    for actual in decisions:
        total, reasons = expected[actual['id']]
        assert (actual['amountMinor'], actual['reasons']) == (total, reasons), actual
    assert [r['id'] for r in decisions if r['eligible']] == ['harbor-c']
    expired = [decision(p, catalog['request'], expiry, expiry) for p in catalog['products']]
    assert all(not r['eligible'] and 'quote_expired' in r['reasons'] for r in expired)
    stricter_request = dict(catalog['request'], budgetMinor=6000)
    no_match = [decision(p, stricter_request, now, expiry) for p in catalog['products']]
    assert not any(r['eligible'] for r in no_match)
    missing_tax_product = dict(catalog['products'][0], taxMinor=None)
    missing_tax = decision(missing_tax_product, catalog['request'], now, expiry)
    assert missing_tax['amountMinor'] is None and not missing_tax['eligible']
    assert 'total_unknown' in missing_tax['reasons']

    # This is a separate hypothetical checkout adapter with fake approval/outcomes.
    # It is not implemented in the authored discovery prototype.
    cart = {'version': 1, 'merchantId': 'fixture-harbor', 'currency': 'USD',
            'amountMinor': 6901, 'currencyExponent': 2, 'contextDigest': 'a' * 64,
            'items': [{'id': 'harbor-c-digital', 'quantity': 1, 'unitAmountMinor': 5900},
                      {'id': 'fixture-tax', 'quantity': 1, 'unitAmountMinor': 501},
                      {'id': 'fixture-shipping', 'quantity': 1, 'unitAmountMinor': 500}]}
    policy = CommercePolicy(b'fixture-consent-key-not-a-visa-key-32bytes')
    adapter = FixtureAdapter()
    consent = policy.sign_after_user_approval(cart, 'fixture-order-001', 1500, now=1000)
    def guarded_purchase(candidate, moment):
        policy.submit(candidate, consent, now=moment)
        try:
            adapter.purchase('fixture-order-001')
        except TimeoutError:
            return policy.record_outcome('fixture-order-001', 'unknown')
    revised = copy.deepcopy(cart)
    revised['items'][2]['unitAmountMinor'] = 900
    revised['amountMinor'] = 7301
    changed_quote_error = blocked(lambda: guarded_purchase(revised, 1001), 'changed')
    assert policy.ledger == {}, 'Changed quote must not reserve or submit any action'
    assert adapter.submissions == [], 'Changed quote reached the fake adapter'
    unknown = guarded_purchase(cart, 1001)
    assert unknown['state'] == 'unknown'
    retry_error = blocked(lambda: guarded_purchase(cart, 1002), 'already reserved')
    # A fake authoritative reconciliation response; no second synthetic submission.
    reconciled = policy.record_outcome('fixture-order-001', 'confirmed', adapter.reconcile('fixture-order-001'))
    assert reconciled['state'] == 'confirmed' and len(policy.ledger) == 1
    assert adapter.submissions == ['fixture-order-001']
    output = {
        'mode': 'OFFLINE SYNTHETIC FIXTURE REPLAY', 'visaApiInvoked': False,
        'llmInvoked': False, 'liveCatalogInvoked': False,
        'catalogDecisions': decisions,
        'quoteExpiry': {'eligibleCount': sum(r['eligible'] for r in expired)},
        'stricterBudget': {'budgetMinor': 6000, 'eligibleCount': sum(r['eligible'] for r in no_match)},
        'unknownCharges': missing_tax,
        'optionalCheckoutReplay': {'changedQuoteBlocked': changed_quote_error,
                                   'duplicateRetryBlocked': retry_error,
                                   'syntheticAdapterSubmissions': len(adapter.submissions),
                                   'reconciled': reconciled},
        'liveVic': {'state': 'not_attempted', 'reason': 'No authorized runtime credentials or discovered schemas'},
    }
    print(json.dumps(output, indent=2))


if __name__ == '__main__':
    main()
