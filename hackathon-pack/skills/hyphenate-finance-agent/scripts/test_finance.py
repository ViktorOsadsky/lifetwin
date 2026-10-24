import copy
import unittest
from finance_checks import validate
from catalog_tools import catalog


class FinanceChecks(unittest.TestCase):
    def setUp(self):
        self.p = {'proposal_id': 'p1', 'tenant_id': 't1', 'source_ids': ['invoice1', 'bank1'],
                  'source_version': 'v1', 'policy_version': 'v2', 'lines': [
                      {'account': 'cash', 'entity': 'e1', 'currency': 'USD', 'debit_minor': 10001, 'credit_minor': 0},
                      {'account': 'receivable', 'entity': 'e1', 'currency': 'USD', 'debit_minor': 0, 'credit_minor': 10001}]}

    def test_valid_but_no_claim_of_accounting_correctness(self):
        self.assertEqual(validate(self.p), {'valid': True, 'errors': [], 'scope': 'syntactic_evidence_and_balance_only', 'posted': False})

    def test_cross_currency_net_zero_is_rejected(self):
        self.p['lines'][1]['currency'] = 'EUR'
        self.assertEqual(len(validate(self.p)['errors']), 2)

    def test_cross_entity_net_zero_is_rejected(self):
        self.p['lines'][1]['entity'] = 'e2'
        self.assertFalse(validate(self.p)['valid'])

    def test_float_bool_and_negative_rejected(self):
        for bad in (100.01, True, -10001):
            p = copy.deepcopy(self.p); p['lines'][0]['debit_minor'] = bad
            self.assertFalse(validate(p)['valid'])

    def test_evidence_and_replay(self):
        self.p['source_ids'] = []
        self.p['previous_proposal_ids'] = ['p1']
        self.assertEqual(set(validate(self.p)['errors']), {'missing_source_evidence', 'proposal_replay'})

    def test_balanced_wrong_account_requires_semantic_review(self):
        self.p['lines'][0]['account'] = 'invented_account'
        self.assertTrue(validate(self.p)['valid'])  # deliberately exposes this validator's limit

    def test_openapi_security_and_reference_preserved(self):
        c = catalog({'openapi': '3.1.0', 'security': [{'oauth': ['read']}], 'paths': {'/items': {
            'parameters': [{'name': 'tenant', 'in': 'header'}], 'post': {'requestBody': {'$ref': '#/components/requestBodies/Item'}}}}})
        op = c['operations'][0]
        self.assertEqual(op['security'], [{'oauth': ['read']}])
        self.assertEqual(op['requestBody']['$ref'], '#/components/requestBodies/Item')
        self.assertEqual(op['execution_review'], 'required')

    def test_mcp_pagination_not_silently_complete(self):
        self.assertEqual(catalog({'result': {'tools': [], 'nextCursor': 'page2'}})['nextCursor'], 'page2')


if __name__ == '__main__': unittest.main()
