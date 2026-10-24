import concurrent.futures
import tempfile
from pathlib import Path
import unittest
from job_ledger import Ledger


class LedgerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.ledger = Ledger(Path(self.tmp.name) / 'jobs.db')
    def tearDown(self): self.tmp.cleanup()

    def test_simultaneous_double_click_reserves_once(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(lambda _: self.ledger.reserve('tenant1:purchase:one', {'total_minor': 1500}), range(32)))
        self.assertEqual(sum(r['created'] for r in results), 1)
        self.assertEqual(len(self.ledger.history('tenant1:purchase:one')), 1)

    def test_changed_payload_same_key_rejected(self):
        self.ledger.reserve('t1:one', {'currency': 'USD', 'amount_minor': 500})
        with self.assertRaisesRegex(ValueError, 'payload_conflict'):
            self.ledger.reserve('t1:one', {'currency': 'USD', 'amount_minor': 501})

    def test_stale_revision_cannot_execute_twice(self):
        self.ledger.reserve('t1:one', {})
        self.ledger.transition('t1:one', 0, 'running')
        with self.assertRaisesRegex(ValueError, 'stale_revision'):
            self.ledger.transition('t1:one', 0, 'running')
        self.assertEqual(len(self.ledger.history('t1:one')), 2)

    def test_uncertain_outcome_cannot_blind_retry(self):
        self.ledger.reserve('t1:one', {})
        for rev, target in enumerate(('running', 'awaiting_approval', 'ready', 'executing', 'uncertain')):
            self.ledger.transition('t1:one', rev, target)
        with self.assertRaisesRegex(ValueError, 'invalid_transition'):
            self.ledger.transition('t1:one', 5, 'executing')
        self.ledger.transition('t1:one', 5, 'succeeded')
        self.assertEqual(self.ledger.history('t1:one')[-1], (6, 'succeeded'))

    def test_tenant_namespace_separates_jobs(self):
        self.assertTrue(self.ledger.reserve('t1:one', {})['created'])
        self.assertTrue(self.ledger.reserve('t2:one', {})['created'])


if __name__ == '__main__': unittest.main()
