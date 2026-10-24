"""Validate our local proposal fixture. No networking or posting."""
from collections import defaultdict
import json
import sys


def validate(proposal):
    errors = []
    for field in ('proposal_id', 'tenant_id', 'source_version', 'policy_version'):
        if not isinstance(proposal.get(field), str) or not proposal[field].strip():
            errors.append('missing_or_invalid:' + field)
    sources = proposal.get('source_ids', [])
    if not isinstance(sources, list) or not sources or any(not isinstance(s, str) or not s.strip() for s in sources):
        errors.append('missing_source_evidence')
    elif len(sources) != len(set(sources)):
        errors.append('duplicate_source_reference')
    if proposal.get('proposal_id') in proposal.get('previous_proposal_ids', []):
        errors.append('proposal_replay')
    totals = defaultdict(int)
    lines = proposal.get('lines', [])
    if not isinstance(lines, list) or len(lines) < 2:
        errors.append('insufficient_lines')
        lines = []
    for i, line in enumerate(lines):
        if not isinstance(line, dict) or any(not isinstance(line.get(k), str) or not line[k].strip() for k in ('entity', 'currency', 'account')):
            errors.append('invalid_line_identity:' + str(i))
            continue
        debit, credit = line.get('debit_minor'), line.get('credit_minor')
        if type(debit) is not int or type(credit) is not int or min(debit, credit) < 0 or (debit > 0) == (credit > 0):
            errors.append('invalid_minor_units:' + str(i))
            continue
        totals[(line['entity'], line['currency'])] += debit - credit
    for (entity, currency), net in sorted(totals.items()):
        if net:
            errors.append(f'unbalanced:{entity}:{currency}:{net}')
    return {'valid': not errors, 'errors': errors,
            'scope': 'syntactic_evidence_and_balance_only', 'posted': False}


if __name__ == '__main__':
    result = validate(json.load(open(sys.argv[1])))
    print(json.dumps(result, indent=2))
    sys.exit(0 if result['valid'] else 1)
