"""Local integration experiment; normalized fixtures, no real CREAO calls or credentials."""
import json
import sqlite3
from copy import deepcopy
from pathlib import Path


class LocalJob:
    def __init__(self):
        self.db = sqlite3.connect(':memory:')
        self.db.executescript('''
          CREATE TABLE jobs(run_id TEXT PRIMARY KEY, status TEXT, output TEXT);
          CREATE TABLE effects(run_id TEXT PRIMARY KEY, result TEXT);
          INSERT INTO jobs VALUES ('known-run', 'pending', NULL);
        ''')

    def snapshot(self):
        job = self.db.execute('SELECT status, output FROM jobs').fetchone()
        return {'status': job[0], 'output': json.loads(job[1]) if job[1] else None,
                'effects': self.db.execute('SELECT COUNT(*) FROM effects').fetchone()[0]}

    def finish(self, run_id, canonical):
        status = canonical['status']
        if status not in ('completed', 'failed', 'cancelled'):
            return 'pending'
        with self.db:
            changed = self.db.execute(
                "UPDATE jobs SET status=?, output=? WHERE run_id=? AND status='pending'",
                (status, json.dumps(canonical.get('result') if status == 'completed' else None), run_id)).rowcount
            if changed and status == 'completed':
                self.db.execute('INSERT INTO effects VALUES (?, ?)',
                                (run_id, json.dumps(canonical['result'])))
        return 'applied' if changed else 'duplicate'


def first_attempt(job, event, lookup):
    """Initial local implementation: accepts an unverified completion body."""
    return job.finish(event['runId'], event)


def revised(job, event, lookup):
    # A production adapter must normalize the current authenticated provider response.
    run_id = event.get('runId')
    known = job.db.execute('SELECT 1 FROM jobs WHERE run_id=?', (run_id,)).fetchone()
    if not known:
        return 'unknown_run'
    try:
        canonical = lookup(run_id)
    except TimeoutError:
        return 'retry_later'
    if canonical['runId'] != run_id:
        return 'mismatched_run'
    return job.finish(run_id, canonical)


def run():
    provider = {'runId': 'known-run', 'status': 'pending'}
    calls = []

    def lookup(run_id):
        calls.append(run_id)
        return deepcopy(provider)

    spoof = {'runId': 'known-run', 'status': 'completed',
             'result': {'summary': 'fabricated finding from callback'}}
    initial = LocalJob()
    first_attempt(initial, spoof, lookup)
    before = initial.snapshot()
    assert before['effects'] == 1 and before['output']['summary'].startswith('fabricated')

    job = LocalJob()
    cases = []
    cases.append({'case': 'forged_completion_while_canonical_pending',
                  'result': revised(job, spoof, lookup), 'state': job.snapshot()})
    assert job.snapshot() == {'status': 'pending', 'output': None, 'effects': 0}
    before_calls = len(calls)
    cases.append({'case': 'unknown_run', 'result': revised(job, {'runId': 'other-run'}, lookup)})
    assert cases[-1]['result'] == 'unknown_run' and len(calls) == before_calls

    def timeout(run_id):
        raise TimeoutError('fixture only')
    cases.append({'case': 'status_lookup_timeout',
                  'result': revised(job, spoof, timeout), 'state': job.snapshot()})
    assert cases[-1]['result'] == 'retry_later' and job.snapshot()['effects'] == 0

    provider.update(status='completed', result={'summary': 'canonical researched finding'})
    cases.append({'case': 'delayed_completion_reconciled_by_poll',
                  'result': revised(job, {'runId': 'known-run'}, lookup), 'state': job.snapshot()})
    for _ in range(3):
        revised(job, spoof, lookup)
    cases.append({'case': 'three_duplicate_callbacks', 'state': job.snapshot()})
    assert job.snapshot() == {'status': 'completed',
                             'output': {'summary': 'canonical researched finding'}, 'effects': 1}

    failed = LocalJob()
    provider.update(status='failed')
    cases.append({'case': 'canonical_failure_overrides_forged_success',
                  'result': revised(failed, spoof, lookup), 'state': failed.snapshot()})
    assert failed.snapshot() == {'status': 'failed', 'output': None, 'effects': 0}
    cancelled = LocalJob()
    provider.update(status='cancelled')
    revised(cancelled, spoof, lookup)
    assert cancelled.snapshot() == {'status': 'cancelled', 'output': None, 'effects': 0}
    cases.append({'case': 'canonical_cancel_overrides_forged_success', 'state': cancelled.snapshot()})
    results = {'mode': 'local synthetic exercise; no network/API use',
               'before_defect': before, 'revised_cases': cases,
               'assertions': 'all passed', 'authenticated_lookup': 'injected local fixture, not real HTTP'}
    Path(__file__).with_name('local-exercise-results.json').write_text(json.dumps(results, indent=2)+'\n')
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    run()
