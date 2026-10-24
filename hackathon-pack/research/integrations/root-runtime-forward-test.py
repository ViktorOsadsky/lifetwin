import importlib.util
import json
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

BASE = Path(__file__).resolve().parents[2] / 'skills'


def load(skill, name):
    spec = importlib.util.spec_from_file_location(name, BASE / skill / 'scripts' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


finance = load('hyphenate-finance-agent', 'finance_checks')
backend = load('hackathon-backend', 'job_ledger')
metrics = load('hackathon-ml-evals', 'score_predictions')

proposal = {'proposal_id': 'p1', 'tenant_id': 'tenantA', 'source_ids': ['invoice1'],
    'source_version': 'v1', 'policy_version': 'policy1', 'lines': [
        {'account': 'expense', 'entity': 'entityA', 'currency': 'USD', 'debit_minor': 10000, 'credit_minor': 0},
        {'account': 'payable', 'entity': 'entityB', 'currency': 'EUR', 'debit_minor': 0, 'credit_minor': 10000}]}
finance_result = finance.validate(proposal)
assert not finance_result['valid'] and not finance_result['posted']

class SimulatedProvider:
    """TEST DOUBLE: accepts once, then transport times out; lookup by app key works here."""
    def __init__(self):
        self.calls = 0
        self.accepted = {}

    def purchase(self, key):
        self.calls += 1
        self.accepted[key] = 'simulated-provider-reference'
        raise TimeoutError('simulated timeout after accepted')

    def reconcile(self, key):
        return self.accepted.get(key)


with tempfile.TemporaryDirectory() as folder:
    path = Path(folder) / 'jobs.sqlite'
    ledger = backend.Ledger(path)
    key, payload = 'tenantA:purchase:request1', {'action_id': 'request1', 'cart_hash': 'fixture-cart-v1', 'amount_minor': 2500, 'currency': 'USD'}
    first = ledger.reserve(key, payload)
    duplicate = ledger.reserve(key, payload)
    assert first['created'] and not duplicate['created']
    for revision, state in enumerate(('running', 'awaiting_approval', 'ready')):
        ledger.transition(key, revision, state)
    # Real action service must authenticate approval, verify its cart hash and expiry
    # before this ready transition. The reference ledger does not do that.
    def claim(_):
        worker = backend.Ledger(path)
        try:
            worker.transition(key, 3, 'executing')
            return 'claimed'
        except ValueError as exc:
            return str(exc)
    with ThreadPoolExecutor(max_workers=2) as pool:
        claims = list(pool.map(claim, range(2)))
    assert sorted(claims) == ['claimed', 'stale_revision']
    provider = SimulatedProvider()
    try:
        provider.purchase(key)
    except TimeoutError:
        ledger.transition(key, 4, 'uncertain')
    restarted = backend.Ledger(path)
    resume = restarted.reserve(key, payload)
    assert resume == {'created': False, 'state': 'uncertain', 'revision': 5}
    denied_retry = None
    try:
        restarted.transition(key, 5, 'executing')
    except ValueError as exc:
        denied_retry = str(exc)
    assert denied_retry == 'invalid_transition'
    assert provider.calls == 1
    receipt = provider.reconcile(key)  # Safe read in this double; no second purchase.
    terminal = restarted.transition(key, 5, 'succeeded') if receipt else None
    conflict = None
    try:
        restarted.reserve(key, dict(payload, amount_minor=2700))
    except ValueError as exc:
        conflict = str(exc)
    assert conflict == 'idempotency_key_payload_conflict'
    backend_result = {'mode': 'SIMULATED PROVIDER; REAL LOCAL SQLITE LEDGER', 'first': first,
        'duplicate': duplicate, 'parallel_claims': claims, 'after_restart': resume,
        'write_retry': denied_retry, 'provider_purchase_calls': provider.calls,
        'safe_reconcile_reference': receipt, 'final': terminal,
        'changed_payload_same_key': conflict, 'history': restarted.history(key)}

gold = [{'id': f'row{i}', 'label': 'compatible' if i < 5 else 'incompatible', 'group': 'same-model-family'} for i in range(10)]
predictions = [{'id': f'row{i}', 'label': 'compatible'} for i in range(5)]
score = metrics.score(gold, predictions)
assert score['accepted_accuracy'] == 1 and score['coverage'] == .5 and score['task_success'] == .5
leakage = None
try:
    metrics.audit_groups([{'id': 'train1', 'label': 'compatible', 'group': 'same-model-family'}], gold)
except ValueError as exc:
    leakage = str(exc)
assert leakage == 'Leaked groups: same-model-family'
results = {'finance': finance_result, 'backend': backend_result, 'ml': {'score': score, 'split_audit': leakage}}
Path(__file__).with_name('root-runtime-forward-results.json').write_text(json.dumps(results, indent=2))
print(json.dumps(results, indent=2))
