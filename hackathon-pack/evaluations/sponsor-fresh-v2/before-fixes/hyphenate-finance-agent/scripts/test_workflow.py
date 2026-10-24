"""Exercise local gates against planted errors. --report prints actual decisions."""
import copy
import json
import sys
import unittest
from finance_checks import validate
from workflow_checks import gate, proposal_hash


def fixture():
    p = {'proposal_id': 'march-cash-1', 'tenant_id': 'festival',
         'source_ids': ['bank1', 'invoice1'], 'source_version': 'bundle1',
         'source_versions': {'bank1': 'v1', 'invoice1': 'v1'},
         'policy_version': 'policy1', 'posting_period': '2026-03',
         'requested_by': 'cash-agent', 'operation_key': 'festival:bank1:apply',
         'lines': [
             {'account': 'cash', 'entity': 'us', 'currency': 'USD', 'debit_minor': 9700, 'credit_minor': 0},
             {'account': 'bank_fees', 'entity': 'us', 'currency': 'USD', 'debit_minor': 300, 'credit_minor': 0},
             {'account': 'receivable', 'entity': 'us', 'currency': 'USD', 'debit_minor': 0, 'credit_minor': 10000}]}
    c = {'tenant_id': 'festival', 'chart_of_accounts': {'us': ['cash', 'bank_fees', 'receivable']},
         'open_periods': {'us': ['2026-03']}, 'current_policy_version': 'policy1',
         'current_source_versions': {'bank1': 'v1', 'invoice1': 'v1'},
         'actor_roles': {'controller1': ['controller']},
         'approver_entities': {'controller1': ['us']}, 'operation_status': {}}
    approve(p, c)
    return p, c


def approve(p, c):
    c['approval'] = {'actor': 'controller1', 'decision': 'approved',
                     'proposal_hash': proposal_hash(p)}


def scenarios():
    p, c = fixture()
    yield 'partial_settlement_plus_fee', p, c, set()
    p, c = fixture(); p['lines'][0]['account'] = 'invented'; approve(p, c)
    yield 'balanced_wrong_account', p, c, {'unknown_account'}
    p, c = fixture(); c['open_periods']['us'] = ['2026-06']
    yield 'march_period_closed_in_june', p, c, {'closed_or_unknown_period'}
    p, c = fixture(); c['approval']['actor'] = 'cash-agent'
    c['actor_roles']['cash-agent'] = ['controller']; c['approver_entities']['cash-agent'] = ['us']
    yield 'requester_cannot_self_approve', p, c, {'independent_approver_required'}
    p, c = fixture(); c['approval']['decision'] = 'rejected'
    yield 'controller_rejection', p, c, {'approval_required'}
    p, c = fixture(); p['lines'][0]['debit_minor'] = 9600; p['lines'][1]['debit_minor'] = 400
    yield 'balanced_edit_invalidates_approval', p, c, {'approval_snapshot_mismatch'}
    p, c = fixture(); c['current_source_versions']['creditnote1'] = 'v1'
    yield 'june_credit_note_blocks_old_snapshot', p, c, {'stale_or_incomplete_evidence'}
    p, c = fixture(); c['current_policy_version'] = 'policy2'
    yield 'policy_change_requires_new_decision', p, c, {'stale_policy'}
    p, c = fixture(); c['operation_status'][p['operation_key']] = 'unknown'
    yield 'timeout_requires_reconciliation', p, c, {'reconcile_remote_outcome_first'}
    p, c = fixture(); c['operation_status'][p['operation_key']] = 'confirmed'
    yield 'confirmed_replay_blocked', p, c, {'already_executed'}
    p, c = fixture(); c['approver_entities']['controller1'] = ['eu']
    yield 'controller_outside_entity_scope', p, c, {'approver_entity_scope_required'}
    p, c = fixture(); c['actor_roles']['controller1'] = ['requester']
    yield 'actor_name_does_not_grant_role', p, c, {'approver_role_required'}
    p, c = fixture(); p['tenant_id'] = 'other-company'; approve(p, c)
    yield 'same_entity_name_different_tenant', p, c, {'tenant_context_mismatch'}
    p, c = fixture(); p['posting_period'] = '2026-06'
    p['source_ids'].append('creditnote1'); p['source_versions']['creditnote1'] = 'v1'
    p['source_version'] = 'bundle2'; c['current_source_versions'] = copy.deepcopy(p['source_versions'])
    c['open_periods']['us'] = ['2026-06']; approve(p, c)
    yield 'revised_june_snapshot_independently_approved', p, c, set()


def report():
    rows = []
    for name, p, c, expected in scenarios():
        result = gate(p, c)
        rows.append({'scenario': name, 'expected_errors': sorted(expected),
                     'baseline_balance_valid': validate(p)['valid'],
                     'result': result, 'passed': set(result['errors']) == expected})
    return {'surface': 'local simulation; no API calls or postings', 'scenarios': rows,
            'passed': all(row['passed'] for row in rows)}


class WorkflowChecks(unittest.TestCase):
    def test_planted_scenarios(self):
        for row in report()['scenarios']:
            with self.subTest(row['scenario']):
                self.assertTrue(row['passed'], row)
                self.assertFalse(row['result']['posted'])

    def test_empty_context_fails_closed(self):
        p, _ = fixture()
        self.assertFalse(gate(p, {})['ready_for_adapter'])


if __name__ == '__main__':
    if '--report' in sys.argv:
        result = report(); print(json.dumps(result, indent=2)); sys.exit(0 if result['passed'] else 1)
    unittest.main()
