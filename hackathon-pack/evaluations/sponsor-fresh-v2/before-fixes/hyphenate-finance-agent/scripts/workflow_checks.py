"""Local example only: gate a journal proposal without executing it.

Not a Hyphenate schema, authorization service, or accounting-policy engine.
Context must be supplied by trusted application adapters, never the proposing model.
"""
import hashlib
import json
from finance_checks import validate


def proposal_hash(proposal):
    """Bind every supplied proposal field, including dates, evidence and policy."""
    body = json.dumps(proposal, sort_keys=True, separators=(',', ':'), allow_nan=False)
    return hashlib.sha256(body.encode()).hexdigest()


def gate(proposal, context):
    errors = list(validate(proposal)['errors'])
    if proposal.get('tenant_id') != context.get('tenant_id'):
        errors.append('tenant_context_mismatch')
    charts = context.get('chart_of_accounts', {})
    periods = context.get('open_periods', {})
    period = proposal.get('posting_period')
    if not isinstance(period, str) or len(period) != 7:
        errors.append('missing_posting_period')
    for line in proposal.get('lines', []):
        if not isinstance(line, dict):
            continue
        entity = line.get('entity')
        if line.get('account') not in charts.get(entity, []):
            errors.append('unknown_account')
        if period not in periods.get(entity, []):
            errors.append('closed_or_unknown_period')
    snapshots = proposal.get('source_versions', {})
    latest = context.get('current_source_versions', {})
    # The context lists all required evidence for this business case. This catches
    # a new credit note as well as a changed version of a previously known invoice.
    if not snapshots or snapshots != latest or set(snapshots) != set(proposal.get('source_ids', [])):
        errors.append('stale_or_incomplete_evidence')
    if proposal.get('policy_version') != context.get('current_policy_version'):
        errors.append('stale_policy')
    requester = proposal.get('requested_by')
    approval = context.get('approval', {})
    approver = approval.get('actor')
    if not isinstance(requester, str) or not requester.strip():
        errors.append('missing_requester')
    if not isinstance(approver, str) or not approver.strip() or requester == approver:
        errors.append('independent_approver_required')
    if approval.get('decision') != 'approved':
        errors.append('approval_required')
    if approval.get('proposal_hash') != proposal_hash(proposal):
        errors.append('approval_snapshot_mismatch')
    if 'controller' not in context.get('actor_roles', {}).get(approver, []):
        errors.append('approver_role_required')
    needed = {line.get('entity') for line in proposal.get('lines', []) if isinstance(line, dict)}
    if not needed.issubset(set(context.get('approver_entities', {}).get(approver, []))):
        errors.append('approver_entity_scope_required')
    operation_key = proposal.get('operation_key')
    if not isinstance(operation_key, str) or not operation_key.strip():
        errors.append('missing_operation_key')
    else:
        status = context.get('operation_status', {}).get(operation_key)
        if status == 'confirmed':
            errors.append('already_executed')
        elif status is not None:  # includes pending, unknown and unrecognized states
            errors.append('reconcile_remote_outcome_first')
    return {'ready_for_adapter': not errors, 'errors': sorted(set(errors)),
            'execution_surface': 'local_example', 'posted': False}
