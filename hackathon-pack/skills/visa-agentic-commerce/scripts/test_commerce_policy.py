"""Offline policy tests, using fake approvals/receipts. No Visa tool is invoked."""
import copy
import threading
from concurrent.futures import ThreadPoolExecutor
import unittest
from commerce_policy import CommercePolicy, digest, validate_cart


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.cart = {'version': 1, 'merchantId': 'merchant-a', 'currency': 'USD', 'amountMinor': 2500,
            'currencyExponent': 2, 'contextDigest': '0' * 64,
            'items': [{'id': 'sku-a', 'quantity': 1, 'unitAmountMinor': 2500}]}
        self.policy = CommercePolicy(b'fixture-secret-key-at-least-32-bytes')
        self.consent = self.policy.sign_after_user_approval(self.cart, 'request-a', 1100, now=1000)

    def test_approved_cart_submits(self):
        self.assertEqual(self.policy.submit(self.cart, self.consent, now=1001)['state'], 'submitted')

    def test_each_material_change_requires_new_approval(self):
        for field, value in [('merchantId', 'merchant-b'), ('currency', 'EUR'), ('version', 2), ('currencyExponent', 3)]:
            changed = copy.deepcopy(self.cart)
            changed[field] = value
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'changed'):
                self.policy.submit(changed, self.consent, now=1001)
        changed = copy.deepcopy(self.cart)
        changed['amountMinor'] = changed['items'][0]['unitAmountMinor'] = 2600
        with self.assertRaisesRegex(ValueError, 'changed'):
            self.policy.submit(changed, self.consent, now=1001)

    def test_expired_and_future_approval(self):
        for now in (999, 1100, 1200):
            with self.subTest(now=now), self.assertRaisesRegex(ValueError, 'expired|valid'):
                self.policy.submit(self.cart, self.consent, now=now)

    def test_forged_consent_denied(self):
        self.consent['payload']['expiresAt'] = 9999
        with self.assertRaisesRegex(ValueError, 'signature'):
            self.policy.submit(self.cart, self.consent, now=1001)

    def test_wrong_signing_key_denied(self):
        other = CommercePolicy(b'another-fixture-secret-at-least-32bytes')
        with self.assertRaisesRegex(ValueError, 'signature'):
            other.submit(self.cart, self.consent, now=1001)

    def test_environment_bound(self):
        sandbox = CommercePolicy(self.policy.key, environment='sandbox')
        with self.assertRaisesRegex(ValueError, 'environment'):
            sandbox.submit(self.cart, self.consent, now=1001)

    def test_duplicate_submission_blocked(self):
        self.policy.submit(self.cart, self.consent, now=1001)
        with self.assertRaisesRegex(ValueError, 'already reserved'):
            self.policy.submit(self.cart, self.consent, now=1002)

    def test_timeout_requires_reconciliation(self):
        self.policy.submit(self.cart, self.consent, now=1001)
        self.policy.record_outcome('request-a', 'unknown')
        with self.assertRaises(ValueError):
            self.policy.submit(self.cart, self.consent, now=1002)
        self.assertEqual(self.policy.record_outcome('request-a', 'confirmed', 'fixture-receipt')['state'], 'confirmed')

    def test_cannot_claim_confirmation_without_receipt(self):
        self.policy.submit(self.cart, self.consent, now=1001)
        with self.assertRaises(ValueError):
            self.policy.record_outcome('request-a', 'confirmed')

    def test_terminal_state_cannot_reopen(self):
        self.policy.submit(self.cart, self.consent, now=1001)
        self.policy.record_outcome('request-a', 'cancelled')
        with self.assertRaises(ValueError):
            self.policy.record_outcome('request-a', 'confirmed', 'fixture-receipt')

    def test_card_fields_and_nested_credentials_blocked(self):
        for target in ('root', 'item'):
            cart = copy.deepcopy(self.cart)
            (cart if target == 'root' else cart['items'][0])['pan'] = 'fixture-placeholder'
            with self.subTest(target=target), self.assertRaises(ValueError):
                validate_cart(cart)

    def test_no_float_or_boolean_money(self):
        for value in (25.00, True, -1, 0):
            cart = copy.deepcopy(self.cart)
            cart['amountMinor'] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate_cart(cart)

    def test_unaccounted_tax_or_fees_denied(self):
        self.cart['amountMinor'] += 1
        with self.assertRaisesRegex(ValueError, 'total'):
            validate_cart(self.cart)

    def test_digest_order_independent(self):
        self.assertEqual(digest(self.cart), digest(dict(reversed(list(self.cart.items())))))

    def test_parallel_same_request_reserved_once(self):
        barrier = threading.Barrier(2)
        class RacingLedger(dict):
            def __contains__(self, key):
                answer = super().__contains__(key)
                try:
                    barrier.wait(timeout=0.1)
                except threading.BrokenBarrierError:
                    pass
                return answer
        policy = CommercePolicy(self.policy.key, ledger=RacingLedger())
        def submit(_):
            try:
                policy.submit(self.cart, self.consent, now=1001)
                return True
            except ValueError:
                return False
        with ThreadPoolExecutor(max_workers=2) as pool:
            self.assertEqual(sum(pool.map(submit, range(2))), 1)

    def test_fulfillment_or_variant_change_invalidates_approval(self):
        cart = copy.deepcopy(self.cart)
        cart['contextDigest'] = 'a' * 64
        token = self.policy.sign_after_user_approval(cart, 'request-context', 1100, now=1000)
        cart['contextDigest'] = 'b' * 64
        with self.assertRaisesRegex(ValueError, 'changed'):
            self.policy.submit(cart, token, now=1001)


if __name__ == '__main__':
    unittest.main(verbosity=2)
