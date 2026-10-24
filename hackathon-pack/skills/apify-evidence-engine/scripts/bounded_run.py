#!/usr/bin/env python3
"""Apify REST bounded execution + paged collection. Default CLI is a local plan only.

No automatic POST retry: transport uncertainty can mean the Actor already started.
Schema validation belongs to the Actor's current input schema / platform validation.
"""
import argparse
import hashlib
import json
import math
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

TERMINAL = {'SUCCEEDED', 'FAILED', 'TIMED-OUT', 'ABORTED'}


def make_plan(actor, actor_input, budget_usd, max_items=10, timeout=120, build=None, reviewed_actor_id=None):
    if not actor or not isinstance(actor_input, dict):
        raise ValueError('Actor and object input required')
    if isinstance(budget_usd, bool) or not isinstance(budget_usd, (int, float)) or not math.isfinite(budget_usd) or budget_usd <= 0:
        raise ValueError('A finite positive explicit USD budget is required')
    if type(max_items) is not int or max_items < 1 or type(timeout) is not int or timeout < 1:
        raise ValueError('Positive integer item and time limits required')
    # Actor schemas may legitimately reuse option names. Preserve separate namespaces.
    snapshot = json.loads(json.dumps(actor_input, allow_nan=False))
    options = {'maxTotalChargeUsd': budget_usd, 'maxItems': max_items, 'timeout': timeout, 'waitForFinish': 0}
    if build:
        options['build'] = build
    plan = {'actor': actor, 'reviewedActorId': reviewed_actor_id, 'input': snapshot, 'options': options,
            'inputSha256': hashlib.sha256(json.dumps(snapshot, sort_keys=True, separators=(',', ':')).encode()).hexdigest()}
    plan['planSha256'] = plan_digest(plan)
    return plan


def plan_digest(plan):
    core = {key: value for key, value in plan.items() if key != 'planSha256'}
    return hashlib.sha256(json.dumps(core, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()).hexdigest()


class Api:
    def __init__(self, token):
        self.token = token

    def __call__(self, method, path, query=None, body=None):
        url = 'https://api.apify.com/v2/' + path
        if query:
            url += '?' + urllib.parse.urlencode(query)
        req = urllib.request.Request(url, None if body is None else json.dumps(body).encode(),
            {'Authorization': 'Bearer ' + self.token, 'Content-Type': 'application/json'}, method=method)
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as exc:
            # Do not dump response headers/request URLs/credentials into logs.
            raise RuntimeError(f'Apify HTTP {exc.code}; do not automatically retry Actor POST') from None


def collect(api, plan, max_polls=30, poll_seconds=2, sleep=time.sleep, page_size=100):
    if type(max_polls) is not int or max_polls < 1 or type(page_size) is not int or page_size < 1:
        raise ValueError('Positive poll and pagination bounds required')
    if isinstance(poll_seconds, bool) or not isinstance(poll_seconds, (int, float)) or not math.isfinite(poll_seconds) or poll_seconds < 0:
        raise ValueError('Polling delay must be finite and nonnegative')
    if plan.get('planSha256') != plan_digest(plan):
        raise ValueError('Run plan changed since review; regenerate and review it before execution')
    # REST `build` selects a tag/number, not the opaque response `buildId`.
    # Require an immutable numeric selector and independently reviewed Actor ID
    # before any billable start. Mutable tags cannot establish this boundary.
    actor_id = plan.get('reviewedActorId')
    build_number = plan.get('options', {}).get('build')
    if not isinstance(actor_id, str) or not actor_id.strip():
        raise ValueError('Execution requires reviewedActorId from actual Actor metadata')
    if not isinstance(build_number, str) or not re.fullmatch(r'\d+\.\d+\.\d+', build_number):
        raise ValueError('Execution requires an exact reviewed numeric build; tags are plan-only')

    def verify_identity(run, expected_run_id=None, expected_build_id=None):
        if (not isinstance(run, dict) or not isinstance(run.get('id'), str) or not run['id']
                or run.get('actId') != actor_id or run.get('buildNumber') != build_number
                or not isinstance(run.get('buildId'), str) or not run['buildId']
                or (expected_run_id is not None and run['id'] != expected_run_id)
                or (expected_build_id is not None and run['buildId'] != expected_build_id)):
            # Do not abort an unverified run or start another one on drift.
            run_id = run.get('id', 'unknown') if isinstance(run, dict) else 'unknown'
            raise RuntimeError(f'Actor/build/run identity mismatch for run {run_id}; reconcile; no abort or restart issued')

    actor = urllib.parse.quote(plan['actor'].replace('/', '~'), safe='~')
    run = api('POST', f'acts/{actor}/runs', plan['options'], plan['input'])['data']
    verify_identity(run)
    run_id = run['id']
    build_id = run['buildId']
    for _ in range(max_polls):
        if run['status'] in TERMINAL:
            break
        sleep(poll_seconds)
        run = api('GET', f'actor-runs/{urllib.parse.quote(run_id, safe="")}')['data']
        verify_identity(run, run_id, build_id)
    if run['status'] not in TERMINAL:
        # This run is ours. Stop ongoing compute when our local polling deadline expires.
        api('POST', f'actor-runs/{urllib.parse.quote(run_id, safe="")}/abort')
        raise TimeoutError(f'Polling exhausted; abort requested for run {run_id}; verify terminal state before retry')
    if run['status'] != 'SUCCEEDED':
        raise RuntimeError(f'Actor run {run_id} ended {run["status"]}; inspect logs; no automatic rerun')
    dataset = run.get('defaultDatasetId')
    if not dataset:
        raise ValueError('Succeeded run has no dataset ID; inspect its documented output storage')
    output, offset = [], 0
    while len(output) < plan['options']['maxItems']:
        limit = min(page_size, plan['options']['maxItems'] - len(output))
        page = api('GET', f'datasets/{urllib.parse.quote(dataset, safe="")}/items',
                   {'format': 'json', 'clean': 'true', 'offset': offset, 'limit': limit})
        if not isinstance(page, list):
            raise ValueError('Dataset response must be a JSON list')
        output.extend(page[:limit])
        offset += len(page)
        if len(page) < limit:
            break
    now = datetime.now(timezone.utc).isoformat()
    return {'provenance': {'actor': plan['actor'], 'actorId': run['actId'],
            'buildId': run['buildId'], 'buildNumber': run['buildNumber'], 'runId': run_id,
            'datasetId': dataset, 'status': run['status'], 'inputSha256': plan['inputSha256'],
            'fetchedAt': now, 'usageTotalUsd': run.get('usageTotalUsd'), 'limit': plan['options']['maxItems'],
            'sourceUrls': sorted({item['url'] for item in output if isinstance(item, dict) and isinstance(item.get('url'), str)})},
            'items': output}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--actor', required=True)
    parser.add_argument('--input', required=True, help='JSON file matching the current Actor schema')
    parser.add_argument('--budget-usd', type=float, required=True)
    parser.add_argument('--max-items', type=int, default=10)
    parser.add_argument('--timeout', type=int, default=120)
    parser.add_argument('--build')
    parser.add_argument('--reviewed-actor-id', help='Exact Actor ID from reviewed metadata; required for execution')
    parser.add_argument('--execute', action='store_true', help='Start a potentially billable Actor run; requires authorization')
    args = parser.parse_args()
    with open(args.input) as stream:
        plan = make_plan(args.actor, json.load(stream), args.budget_usd, args.max_items, args.timeout,
                         args.build, args.reviewed_actor_id)
    if not args.execute:
        print(json.dumps({'mode': 'plan-only', 'plan': plan}, indent=2))
        return
    token = os.environ.get('APIFY_TOKEN')
    if not token:
        raise SystemExit('Set APIFY_TOKEN in the environment; never pass tokens in CLI arguments')
    print(json.dumps(collect(Api(token), plan), indent=2))


if __name__ == '__main__':
    main()
