"""Offline exercise of a live-discovered Actor contract; never starts a run."""
import copy
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
SKILL = HERE.parents[2] / 'skills' / 'apify-evidence-engine'
spec = importlib.util.spec_from_file_location('bounded_run', SKILL / 'scripts' / 'bounded_run.py')
run = importlib.util.module_from_spec(spec)
spec.loader.exec_module(run)
details = json.loads((HERE / 'website-content-details-live.json').read_text())['structuredContent']
schema = details['inputSchema']
# This is a required-field and top-level type smoke check, not a full schema validator.
def issues(value):
    errors = ['missing required field: ' + key for key in schema['required'] if key not in value]
    types = {'integer': lambda v: type(v) is int, 'boolean': lambda v: type(v) is bool,
             'object': lambda v: isinstance(v, dict), 'array': lambda v: isinstance(v, list)}
    for key, val in value.items():
        assert key in schema['properties'], 'invented Actor field: ' + key
        expected = schema['properties'][key].get('type')
        if expected in types and not types[expected](val):
            errors.append('wrong type: ' + key)
    return errors

urls = ['https://docs.apify.com/mcp', 'https://docs.apify.com/storage',
        'https://docs.apify.com/actors/running/tasks', 'https://docs.apify.com/agents/plugins',
        'https://docs.apify.com/actors/running/permissions']
draft = {'startUrls': [{'url': url} for url in urls], 'maxCrawlPages': 5,
         'maxCrawlDepth': 0, 'maxResults': 5, 'maxConcurrency': 1,
         'useSitemaps': False, 'saveMarkdown': True, 'summarize': False}
initial_errors = issues(draft)
assert initial_errors == ['missing required field: proxyConfiguration']
actor_input = {**draft, 'proxyConfiguration': {'useApifyProxy': False}}
assert issues(actor_input) == []
(HERE / 'five-page-input.json').write_text(json.dumps(actor_input, indent=2) + '\n')
# Numeric build below is synthetic for this offline execution double, not a
# currently verified executable build of the live-discovered Actor.
plan = run.make_plan(details['actorInfo']['fullName'], actor_input, .20, 5, 120,
                     build='0.0.1', reviewed_actor_id=details['actorInfo']['id'])
assert plan['options']['maxTotalChargeUsd'] == .20
assert 'maxTotalChargeUsd' not in plan['input']
assert plan['input']['maxCrawlPages'] == 5
assert plan['options']['maxItems'] == 5
(HERE / 'five-page-plan.json').write_text(json.dumps({'mode': 'plan-only', 'plan': plan}, indent=2) + '\n')

calls = []
# Generated rows below are deliberately fictional, exercising handoff rather than extraction.
fixture_rows = [{'url': url, 'markdown': 'Synthetic fixture; not captured web evidence.'} for url in urls]
def api(method, path, query=None, body=None):
    calls.append({'method': method, 'path': path, 'query': query})
    if path.endswith('/items'):
        return fixture_rows[query['offset']:query['offset'] + query['limit']]
    return {'data': {'id': 'fixture-run', 'status': 'SUCCEEDED', 'defaultDatasetId': 'fixture-dataset',
                     'actId':details['actorInfo']['id'], 'buildNumber':'0.0.1', 'buildId': 'fixture-build'}}
result = run.collect(api, plan, page_size=2)
assert len(result['items']) == 5
assert [c['query']['offset'] for c in calls if c['path'].endswith('/items')] == [0, 2, 4]
assert result['provenance']['usageTotalUsd'] is None  # Unknown cost is not zero.
assert result['provenance']['sourceUrls'] == sorted(urls)
result['evidenceMode'] = 'synthetic-fixture'
(HERE / 'collection-fixture-output.json').write_text(json.dumps(result, indent=2) + '\n')
changed = copy.deepcopy(plan)
changed['options']['maxTotalChargeUsd'] = 100
blocked = False
try:
    run.collect(lambda *args: (_ for _ in ()).throw(AssertionError('network reached')), changed)
except ValueError:
    blocked = True
assert blocked
report = {'mode': 'offline-contract-exercise', 'liveSource': 'website-content-details-live.json',
          'initialDraftRejected': initial_errors, 'correctedDraftSmokeCheck': 'pass',
          'plan': 'five-page-plan.json', 'fixtureRowsRetrieved': len(result['items']),
          'paginationOffsets': [0, 2, 4], 'budgetMutationBlockedBeforeNetwork': blocked,
          'limitations': ['No Actor run, billing, live collection or target reachability was tested.',
                          'Build 0.0.1 and returned build ID are synthetic; no live build/schema pin was verified.',
                          'Required-field/type smoke check is not full JSON Schema validation.',
                          'The $0.20 plan cap is an example, not task spending authorization.']}
(HERE / 'scenario-results.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
