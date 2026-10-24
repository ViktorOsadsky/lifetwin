#!/usr/bin/env python3
"""Independent local task execution, not a vendor adapter or payment system."""
import copy
import datetime as dt
import hashlib
import importlib.util
import itertools
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
PACK = HERE.parents[1]
sys.path.insert(0, str(PACK / 'skills/hyphenate-finance-agent/scripts'))
from workflow_checks import gate, proposal_hash


def read(name):
    return json.loads((HERE / name).read_text())


def finance():
    company = read('company.json')
    events, journals, balances = [], [], {}
    accounts = ['Bank', 'ProcessorReceivable', 'CommissionRevenue', 'ConsignorPayable',
                'ProcessorFees', 'CommissionReturns', 'RefundClearing', 'OwnedInventory',
                'InventoryAllowance', 'InventoryImpairment', 'OpeningEquity']

    def lines(*rows):
        return [dict(account=a, entity='shop-us', currency='USD', debit_minor=d, credit_minor=c)
                for a, d, c in rows]

    def proposal(pid, period, sources, rows):
        return dict(proposal_id=pid, tenant_id=company['tenant'], source_ids=list(sources),
                    source_version='case-snapshot-1', source_versions=sources,
                    policy_version=company['policy_version'], lines=lines(*rows),
                    posting_period=period, requested_by='analyst', operation_key=pid)

    def context(p, decision='approved', source_versions=None):
        return dict(tenant_id=company['tenant'], chart_of_accounts={'shop-us': accounts},
                    open_periods={'shop-us': [p['posting_period']]},
                    current_source_versions=copy.deepcopy(source_versions or p['source_versions']),
                    current_policy_version=company['policy_version'],
                    approval=dict(actor='controller', decision=decision, proposal_hash=proposal_hash(p)),
                    actor_roles={'controller': ['controller']}, approver_entities={'controller': ['shop-us']},
                    operation_status={}, prior_decisions=[])

    def application_policy(p, world=None):
        world = world or {}
        errors = []
        net = {}
        for line in p['lines']:
            net[line['account']] = net.get(line['account'], 0) + line['debit_minor'] - line['credit_minor']
        if net.get('CommissionRevenue', 0) < 0:
            sale_source = next(s for s in company['sources'] if s['id'] == 'sale-1')
            contract = next(s for s in company['sources'] if s['id'] == 'C-1')
            gross = sale_source['gross_minor']
            payable = gross * contract['consignor_share_bps'] // 10000
            if net.get('ConsignorPayable') != -payable or net['CommissionRevenue'] != -(gross-payable):
                errors.append('signed_contract_split_mismatch')
        if 'InventoryImpairment' in net:
            if world.get('stock_owner', 'shop-us') != 'shop-us':
                errors.append('consigned_item_is_not_shop_asset')
            if 'inspection-Q' not in p['source_versions']:
                errors.append('recoverable_amount_unknown_until_authoritative_inspection')
        candidates = world.get('bank_match_candidates')
        if candidates is not None and len(candidates) != 1:
            errors.append('bank_match_not_unique_need_reference')
        return errors

    def record(p, kind='simulated_controller_authorized_local_post', inherited=False):
        result = gate(p, context(p))
        if not result['ready_for_adapter'] or (not inherited and application_policy(p)):
            raise AssertionError(result)
        for line in p['lines']:
            balances[line['account']] = balances.get(line['account'], 0) + line['debit_minor'] - line['credit_minor']
        journals.append(p)
        event = dict(sequence=len(events)+1, event=kind, proposal_id=p['proposal_id'],
                     hash=proposal_hash(p), period=p['posting_period'],
                     evidence=p['source_versions'], approved_by='controller', approval_simulated=True,
                     inherited_untrusted_semantics=inherited)
        event['previous_event_hash'] = events[-1]['event_hash'] if events else None
        event['event_hash'] = hashlib.sha256(json.dumps(event, sort_keys=True).encode()).hexdigest()
        events.append(event)

    opening = proposal('opening-owned-stock', '2026-03', {'opening-ledger':'v1'},
                       [('OwnedInventory',8000,0),('OpeningEquity',0,8000)])
    record(opening, 'inherited_opening_balance', inherited=True)
    sale = proposal('sale-1', '2026-03', {'C-1':'v2','sale-1':'v1'},
                    [('ProcessorReceivable',20000,0),('ConsignorPayable',0,14000),('CommissionRevenue',0,6000)])
    record(sale)
    settlement = proposal('settlement-1','2026-03',{'settlement-1':'v1','sale-1':'v1'},
                          [('Bank',19400,0),('ProcessorFees',600,0),('ProcessorReceivable',0,20000)])
    record(settlement)
    # This pre-existing April error was inherited, not justified by the new agent.
    legacy = proposal('legacy-april', '2026-04', {'legacy-april':'v1','return-1':'v1'},
                      [('ConsignorPayable',13000,0),('CommissionReturns',7000,0),('RefundClearing',0,20000)])
    record(legacy, 'inherited_legacy_error_to_be_corrected', inherited=True)
    march_snapshot = copy.deepcopy(journals[:3])
    april_snapshot = copy.deepcopy(journals[:4])

    correction = proposal('june-consignor-correction', '2026-06',
                          {'C-1':'v2','sale-1':'v1','return-1':'v1','legacy-april':'v1'},
                          [('ConsignorPayable',1000,0),('CommissionReturns',0,1000)])
    correction['original_effective_period'] = '2026-04'
    correction['reason'] = 'Contract owes 70%; reverse residual 1000 payable and excess 1000 return expense. Closed April retained.'
    record(correction)
    bank = proposal('june-late-bank-adjustment', '2026-06', {'bank-refund-1':'v1','return-1':'v1'},
                    [('RefundClearing',20000,0),('Bank',0,20000)])
    bank['original_effective_period'] = '2026-04'
    bank['reason'] = 'June controller-approved correction for bank debit effective April, received June; not a June operational cash-flow claim.'
    record(bank)
    impairment = proposal('june-owned-impairment', '2026-06', {'owned-Q':'v1','inspection-Q':'v1'},
                          [('InventoryImpairment',3000,0),('InventoryAllowance',0,3000)])
    record(impairment)
    reversal = proposal('june-owned-impairment-reversal', '2026-06', {'owned-Q':'v1','inspection-Q':'v2'},
                        [('InventoryAllowance',2000,0),('InventoryImpairment',0,2000)])
    reversal['reverses_part_of'] = impairment['proposal_id']
    reversal['reason'] = 'New independent inspection supports 7000, restore 2000 within original cost under fixture policy.'
    record(reversal)

    cases = []
    def case(name, p, c, expected, world=None):
        result = gate(p, c)
        extra_errors = application_policy(p, world)
        all_errors = result['errors'] + extra_errors
        outcome = 'allow_local_adapter' if not all_errors else 'hold'
        cases.append(dict(case=name, expected=expected, actual=outcome,
                          helper_ready=result['ready_for_adapter'], helper_errors=result['errors'],
                          application_errors=list(extra_errors), matches_expected=outcome == expected))

    case('benign_sale', sale, context(sale), 'allow_local_adapter')
    bad = copy.deepcopy(sale)
    bad['lines'][1]['credit_minor'] = 15000
    bad['lines'][2]['credit_minor'] = 5000
    case('balanced_wrong_consignment_split', bad, context(bad), 'hold')
    c = context(correction)
    c['approval']['decision'] = 'rejected'
    case('busy_controller_rejects_correction', correction, c, 'hold')
    c = context(correction)
    c['approval']['actor'] = 'analyst'
    case('requester_cannot_approve', correction, c, 'hold')
    c = context(sale)
    c['open_periods']['shop-us'] = ['2026-06']
    c['current_source_versions']['return-1'] = 'v1'
    case('old_march_proposal_after_return_and_close', sale, c, 'hold')
    for status in ('unknown','confirmed'):
        c = context(bank)
        c['operation_status'][bank['operation_key']] = status
        case('bank_import_' + status, bank, c, 'hold')
    c = context(impairment, source_versions={'owned-Q':'v1','inspection-Q':'v2'})
    case('old_inspection_approval_after_revision', impairment, c, 'hold')
    no_inspection = copy.deepcopy(impairment)
    no_inspection['source_versions'].pop('inspection-Q')
    no_inspection['source_ids'].remove('inspection-Q')
    case('no_condition_evidence_for_owned_quarantine', no_inspection, context(no_inspection), 'hold')
    case('quarantined_consigned_stock_is_not_owned_inventory', impairment, context(impairment), 'hold',
         {'stock_owner':'seller-A'})
    case('two_equal_bank_debits_no_reference', bank, context(bank), 'hold',
         {'bank_match_candidates':['refund-1','refund-2']})
    # Probe the actual supplied rejection boundary independently of our event log.
    c = context(correction)
    c['prior_decisions'] = [{'proposal_hash':proposal_hash(correction),'decision':'rejected'}]
    rejection_probe = gate(correction, c)
    assert 'rejected_snapshot_requires_revision' in rejection_probe['errors']

    assert journals[:3] == march_snapshot and journals[:4] == april_snapshot
    assert balances['ConsignorPayable'] == 0 and balances['RefundClearing'] == 0
    assert balances['CommissionRevenue'] + balances['CommissionReturns'] == 0
    assert balances['OwnedInventory'] + balances['InventoryAllowance'] == 7000
    assert sum(balances.values()) == 0
    assert all(c['matches_expected'] for c in cases)
    return dict(mode='LOCAL_SYNTHETIC', external_calls=0, sponsor_integration_verified=False,
                evidence_events=events, journals=journals, balances_debit_positive_minor=balances,
                regression_cases=cases, closed_snapshots_unchanged=True,
                physical_stock={'return-1':'consignor-owned quarantine; off-balance-sheet custody',
                                'owned-Q':'shop-owned quarantine; net carrying 7000'},
                rejection_history_probe=rejection_probe,
                human_handoff=[{'owner':'controller','issue':'Closed April correction and cash reporting treatment','state':'simulated approved for this fixture only'},
                               {'owner':'warehouse','issue':'Consignor item remains quarantined; complete condition handoff','state':'open; payout blocked'},
                               {'owner':'treasury','issue':'Resolve unknown remote outcomes by authoritative provider lookup before retry','state':'not attempted; no provider configured'}],
                limits=['Local hash chain is not durable immutable storage.',
                        'No real bank, consignor, sandbox or approver accessed.',
                        'The gate cannot determine missing evidence or correct journal semantics; the case adapter supplies these.',
                        'Monthly bank effective-date reporting still requires human policy judgment; late posting date does not alter economic date.'])


def shopping():
    fixture = read('shopping.json')
    requirements, apps = fixture['requirements'], fixture['apps']
    now = dt.datetime.fromisoformat(requirements['checked_at'].replace('Z','+00:00'))

    def evaluate(products):
        rows = []
        for p in products:
            errors = []
            quote_time = dt.datetime.fromisoformat(p['retrieved_at'].replace('Z','+00:00'))
            if (now-quote_time).total_seconds() > requirements['max_quote_age_seconds']:
                errors.append('stale_quote_recheck')
            if p.get('available') is not True:
                errors.append('availability_unverified_or_unavailable')
            dims = p.get('dimensions_mm')
            if dims is None:
                errors.append('dimensions_unknown')
            elif not any(all(x <= y for x,y in zip(orientation, requirements['bag_internal_mm']))
                         for orientation in itertools.permutations(dims)):
                errors.append('does_not_fit_internal_bag_envelope')
            total = None
            if any(p.get(k) is None for k in ('price_minor','shipping_minor','tax_minor')):
                errors.append('delivered_cost_unknown')
            else:
                total = sum(p[k] for k in ('price_minor','shipping_minor','tax_minor'))
                if total > requirements['max_delivered_minor']:
                    errors.append('delivered_cost_exceeds_strict_cap')
            for app in requirements['required_apps']:
                spec = apps[app]
                if any(p.get(k) is None for k in ('os','cpu_arch','ram_gb')):
                    errors.append(app+':compatibility_unknown')
                elif (p['os'] != spec['os'] or p['cpu_arch'] != spec['cpu_arch']
                      or p['ram_gb'] < spec.get('ram_gb_min',0)):
                    errors.append(app+':unsupported_native_platform')
            rows.append(dict(product=p['id'], variant=p['variant'], delivered_minor=total,
                             eligible=not errors, reasons=errors,
                             source=p['source'], retrieved_at=p['retrieved_at']))
        eligible = sorted((r for r in rows if r['eligible']), key=lambda r:r['delivered_minor'])
        return dict(state='selected' if eligible else 'abstained', selected=eligible[0] if eligible else None,
                    comparison=rows, action='read_only_merchant_handoff' if eligible else 'request_current_exact_quote_and_compatibility_evidence',
                    payment_authorized=False)

    scenarios = []
    def run(name, catalog, expected):
        result = evaluate(catalog)
        actual = result['selected']['product'] if result['selected'] else None
        assert actual == expected, (name, actual, expected)
        scenarios.append(dict(case=name, expected_selection=expected, result=result))

    catalog = fixture['catalog']
    run('base_select_B_63720', catalog, 'B')
    updated = copy.deepcopy(catalog)
    updated[1]['price_minor'], updated[1]['tax_minor'] = 61000, 4960
    run('merchant_raises_B_price_no_affordable_verified_candidate', updated, None)
    quoted = copy.deepcopy(updated)
    quoted[5]['tax_minor'] = 4760
    run('explicit_F_tax_quote_resolves_abstention', quoted, 'F')
    stale = copy.deepcopy(catalog)
    stale[1]['retrieved_at'] = '2026-10-23T16:00:00Z'
    run('old_B_quote_recheck_before_handoff', stale, None)
    app_change = copy.deepcopy(catalog)
    app_change[1]['ram_gb'] = 8
    run('same_family_wrong_RAM_variant', app_change, None)
    dimensions_change = copy.deepcopy(catalog)
    dimensions_change[1]['dimensions_mm'] = [331,218,19]
    run('one_millimeter_over_bag_limit', dimensions_change, None)
    boundary = copy.deepcopy(catalog)
    boundary[0]['price_minor'] -= 16
    run('strict_cap_inclusive_at_65000_still_choose_cheaper_B', boundary, 'B')
    return dict(mode='LOCAL_SYNTHETIC', external_calls=0, visa_api_used=False,
                generative_work_performed='Assistant translated shopper/course prose into editable structured constraints and source-grounded explanations during this evaluation; runner is deterministic after that step.',
                runtime_model_integration=False, scenarios=scenarios,
                shopper_message='Choose B 13-16-x86 at $637.20 delivered with this current fixture quote: $580 item + $10 shipping + $47.20 tax. It fits the stated internal envelope and the provided native app matrix. Exact bag clearance and app versions remain production verification tasks. If B changes price, pause and obtain a current exact quote for F; never silently assume zero tax.',
                heldout_properties=['$650.16 is over budget despite $590 sticker', 'Windows ARM is not equivalent to required x86 native apps',
                                    'Unknown tax cannot pass a delivered-cost cap', 'Bag outer dimensions cannot establish internal fit',
                                    'An outdated quote cannot authorize a merchant handoff', 'No payment consent is implied by a recommendation'],
                proposed_real_metrics=['Time to an app-compatible within-budget decision against a manual comparison baseline',
                                       'False-positive hard-constraint acceptance rate on fresh labeled retailer/app facts',
                                       'User completion of a read-only merchant handoff; no conversion uplift claimed'])


if __name__ == '__main__':
    output = dict(finance=finance(), shopping=shopping())
    path = HERE / 'initial-results.json'
    if len(sys.argv) > 1:
        path = HERE / sys.argv[1]
    path.write_text(json.dumps(output, indent=2)+'\n')
    print(json.dumps({'output':str(path), 'finance_cases':len(output['finance']['regression_cases']),
                      'shopping_cases':len(output['shopping']['scenarios']),
                      'finance_gate_rejected_history_probe':output['finance']['rejection_history_probe'],
                      'external_calls':0},indent=2))
