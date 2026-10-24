"""Offline contract and failure-injection tests; no Actor is started."""
import io
import json
import unittest
from unittest.mock import patch
from apify_mcp import DiscoveryClient, decode_rpc
from bounded_run import collect, make_plan


class FakeApi:
    def __init__(self, statuses=('RUNNING', 'SUCCEEDED'), rows=None, drift=None):
        self.statuses = iter(statuses)
        self.rows = [{'url': 'https://example.com/a'}, {'url': 'https://example.com/b'}, {'url': 'https://example.com/c'}] if rows is None else rows
        self.calls = []
        self.drift = drift or {}

    def __call__(self, method, path, query=None, body=None):
        self.calls.append((method, path, query, body))
        if path.endswith('/abort'):
            return {'data': {'status': 'ABORTING'}}
        if path.endswith('/items'):
            return self.rows[query['offset']:query['offset'] + query['limit']]
        run = {'id': 'fixture-run', 'status': next(self.statuses), 'actId':'fixture-actor-id',
               'buildNumber':'1.2.3', 'defaultDatasetId': 'fixture-dataset', 'buildId': 'fixture-build', 'usageTotalUsd': 0}
        if len([c for c in self.calls if c[1].startswith('actor-runs/')]) or run['status'] == 'SUCCEEDED':
            run.update(self.drift)
        return {'data': run}


class ApifyTests(unittest.TestCase):
    def plan(self):
        return make_plan('fixture/actor', {'query': 'products'}, 0.10, 3, 60,
                         build='1.2.3', reviewed_actor_id='fixture-actor-id')

    def test_execution_requires_reviewed_identity_before_start(self):
        for build, actor_id in ((None,None),('latest','fixture-actor-id'),
                                ('opaque-build-id','fixture-actor-id'),('1.2.3',None)):
            plan = make_plan('fixture/actor', {}, 0.1, build=build, reviewed_actor_id=actor_id)
            api = FakeApi()
            with self.subTest(build=build, actor_id=actor_id), self.assertRaises(ValueError):
                collect(api, plan)
            self.assertEqual(api.calls, [])

    def test_returned_identity_drift_holds_without_abort_or_restart(self):
        for drift in ({'actId':'other-actor'}, {'buildNumber':'1.2.4'}, {'id':'other-run'},
                      {'buildId':None}, {'buildId':'another-opaque-build-id'}, {'actId':None}, {'buildNumber':None}):
            api = FakeApi(drift=drift)
            with self.subTest(drift=drift), self.assertRaisesRegex(RuntimeError, 'identity mismatch'):
                collect(api, self.plan(), sleep=lambda _: None)
            self.assertEqual(sum(c[0]=='POST' for c in api.calls), 1)
            self.assertFalse(any(c[1].endswith('/items') or c[1].endswith('/abort') for c in api.calls))

    def test_initial_identity_drift_holds_before_polling(self):
        api = FakeApi(('SUCCEEDED',), drift={'actId':'other-actor'})
        with self.assertRaisesRegex(RuntimeError, 'identity mismatch'):
            collect(api, self.plan())
        self.assertEqual(len(api.calls), 1)

    def test_invalid_budget_blocks_before_network(self):
        for bad in (None, 0, -1, float('nan'), float('inf'), True):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                make_plan('fixture/actor', {}, bad)

    def test_legitimate_actor_limit_field_is_independent_of_run_limit(self):
        plan = make_plan('fixture/actor', {'maxItems': 2, 'timeout': 5}, 1, max_items=3)
        self.assertEqual(plan['input'], {'maxItems': 2, 'timeout': 5})
        self.assertEqual(plan['options']['maxItems'], 3)

    def test_input_is_snapshotted(self):
        source = {'urls': ['https://example.com']}
        plan = make_plan('fixture/actor', source, 1)
        source['urls'].append('https://example.net')
        self.assertEqual(len(plan['input']['urls']), 1)

    def test_modified_plan_rejected_before_network(self):
        plan = self.plan()
        plan['options']['maxTotalChargeUsd'] = 100
        with self.assertRaises(ValueError):
            collect(lambda *args: self.fail('network called'), plan)

    def test_bad_poll_delay_rejected_before_network(self):
        for delay in (-1, float('nan'), float('inf')):
            with self.subTest(delay=delay), self.assertRaises(ValueError):
                collect(lambda *args: self.fail('network called'), self.plan(), poll_seconds=delay)

    def test_limits_are_run_query_not_input(self):
        api = FakeApi()
        result = collect(api, self.plan(), sleep=lambda _: None, page_size=2)
        self.assertEqual(api.calls[0][2]['maxTotalChargeUsd'], 0.1)
        self.assertEqual(api.calls[0][3], {'query': 'products'})
        self.assertEqual(result['provenance']['runId'], 'fixture-run')
        self.assertEqual(result['provenance']['buildId'], 'fixture-build')
        self.assertEqual(result['provenance']['buildNumber'], '1.2.3')
        self.assertEqual(result['provenance']['actorId'], 'fixture-actor-id')
        self.assertEqual(len(result['items']), 3)
        self.assertEqual([c[2]['offset'] for c in api.calls if c[1].endswith('/items')], [0, 2])

    def test_failure_never_fetches_dataset_or_restarts(self):
        api = FakeApi(('RUNNING', 'FAILED'))
        with self.assertRaisesRegex(RuntimeError, 'FAILED'):
            collect(api, self.plan(), sleep=lambda _: None)
        self.assertEqual(sum(c[0] == 'POST' for c in api.calls), 1)
        self.assertFalse(any(c[1].endswith('/items') for c in api.calls))

    def test_poll_exhaustion_aborts_owned_run(self):
        api = FakeApi(('RUNNING', 'RUNNING', 'RUNNING'))
        with self.assertRaises(TimeoutError):
            collect(api, self.plan(), max_polls=2, sleep=lambda _: None)
        self.assertEqual(api.calls[-1][1], 'actor-runs/fixture-run/abort')

    def test_uncertain_start_is_not_retried(self):
        calls = []
        def uncertain(*args):
            calls.append(args)
            raise TimeoutError('transport lost after send')
        with self.assertRaises(TimeoutError):
            collect(uncertain, self.plan(), sleep=lambda _: None)
        self.assertEqual(len(calls), 1)

    def test_empty_success_is_valid_empty_dataset(self):
        result = collect(FakeApi(('SUCCEEDED',), rows=[]), self.plan())
        self.assertEqual(result['items'], [])

    def test_readonly_client_rejects_run_tool(self):
        with self.assertRaises(ValueError):
            DiscoveryClient().call('call-actor', {})

    def test_sse_and_json_protocol_frames(self):
        frame = {'jsonrpc': '2.0', 'id': 1, 'result': {'tools': []}}
        self.assertEqual(decode_rpc(json.dumps(frame).encode(), 'application/json'), frame)
        raw = ('event: message\r\ndata: ' + json.dumps(frame) + '\r\n\r\n').encode()
        self.assertEqual(decode_rpc(raw, 'text/event-stream'), frame)

    def test_tools_pagination(self):
        client = DiscoveryClient()
        with patch.object(client, 'rpc', side_effect=[{'tools': [{'name': 'one'}], 'nextCursor': 'next'}, {'tools': [{'name': 'two'}]}]) as rpc:
            self.assertEqual(len(client.tools()), 2)
            self.assertEqual(rpc.call_args_list[1].args[1], {'cursor': 'next'})


if __name__ == '__main__':
    unittest.main(verbosity=2)
