import unittest
from score_predictions import score, audit_groups


class MetricsTests(unittest.TestCase):
    def setUp(self):
        self.gold = [{'id': 'a', 'label': 'yes', 'group': 'one'}, {'id': 'b', 'label': 'no', 'group': 'two'}]

    def test_missing_hard_case_counts_in_denominator(self):
        r = score(self.gold, [{'id': 'a', 'label': 'yes'}])
        self.assertEqual((r['accepted_accuracy'], r['coverage'], r['task_success']), (1, .5, .5))
        self.assertEqual(r['missing_prediction_ids'], ['b'])

    def test_always_abstain_not_perfect(self):
        r = score(self.gold, [{'id': 'a', 'label': None}, {'id': 'b', 'label': None}])
        self.assertIsNone(r['accepted_accuracy'])
        self.assertEqual((r['coverage'], r['task_success']), (0, 0))

    def test_wrong_prediction_is_error(self):
        r = score(self.gold, [{'id': 'a', 'label': 'no'}, {'id': 'b', 'label': 'no'}])
        self.assertEqual((r['incorrect'], r['task_success']), (1, .5))

    def test_duplicate_and_unknown_ids_fail(self):
        for predictions in ([{'id': 'a', 'label': 'yes'}] * 2, [{'id': 'c', 'label': 'yes'}]):
            with self.assertRaises(ValueError): score(self.gold, predictions)

    def test_empty_truth_cannot_claim_accuracy(self):
        with self.assertRaises(ValueError): score([], [])

    def test_malformed_response_not_hidden_as_abstention(self):
        with self.assertRaisesRegex(ValueError, 'Missing label'):
            score(self.gold, [{'id': 'a'}])

    def test_false_compatible_counts_explicitly(self):
        r = score(self.gold, [{'id': 'a', 'label': 'yes'}, {'id': 'b', 'label': 'yes'}])
        self.assertEqual(r['per_label']['yes']['false_positive'], 1)
        self.assertEqual(r['per_label']['yes']['precision'], .5)
        self.assertEqual(r['per_label']['no']['recall'], 0)

    def test_same_family_leak_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Leaked groups'):
            audit_groups([self.gold[0]], [{'id': 'a-new', 'label': 'no', 'group': 'one'}])

    def test_disjoint_groups_pass(self):
        self.assertEqual(audit_groups([self.gold[0]], [self.gold[1]])['test_groups'], 1)


if __name__ == '__main__': unittest.main()
