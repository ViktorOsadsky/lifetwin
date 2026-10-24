"""Offline feasibility fixture, not a recall/compliance product or an LLM evaluation.

Run: python3 recall_policy.py
All item/finance inputs below are synthetic. Cosori facts are checked against the
separately downloaded official API record; no manufacturer form is submitted.
"""
from __future__ import annotations

from dataclasses import dataclass, replace
from pathlib import Path
import json


@dataclass(frozen=True)
class Rule:
    brand: str
    models: tuple[str, ...]
    remedy: str
    serial_required: bool = False
    source_fresh: bool = True


@dataclass(frozen=True)
class Item:
    brand: str
    model: str | None
    paid_cents: int
    serial_verified: bool = False
    owner_eligibility_confirmed: bool = False
    claim_approved: bool = False


def assess(item, rule):
    """Separates a screening match from program eligibility and spendable cash."""
    if not rule.source_fresh:
        return ('review_stale_source', 0)
    if not item.model:
        return ('review_missing_model', 0)
    if item.brand.casefold().strip() != rule.brand.casefold().strip():
        return ('no_match_in_this_rule', 0)
    # Preserve suffixes: A1652 is not A1652X, CP158-AF is not CP158-AF-R99.
    if item.model.upper().strip() not in rule.models:
        return ('no_match_in_this_rule', 0)
    if rule.serial_required and not item.serial_verified:
        return ('review_serial_required', 0)
    if not item.owner_eligibility_confirmed:
        return ('match_review_program_eligibility', 0)
    if rule.remedy == 'replace':
        return ('replacement_only_no_cash', 0)
    if rule.remedy == 'gift_card':
        return ('restricted_credit_no_cash', 0)
    if not item.claim_approved:
        return ('cash_claim_not_approved', 0)
    return ('approved_cash_claim_not_settled', 0)


class CashLedger:
    def __init__(self):
        self.events = {}

    def settle(self, transaction_id, cents):
        if not isinstance(cents, int) or isinstance(cents, bool) or cents < 0:
            raise ValueError('Expected nonnegative integer cents')
        if transaction_id in self.events and self.events[transaction_id] != cents:
            raise ValueError('Conflicting duplicate settlement')
        self.events[transaction_id] = cents
        return sum(self.events.values())


def consignment_handoff(sale_cents, paid_out, refund_approved,
                        clawback_terms_verified, confirmed_recall=True):
    """Proposed workpaper for a synthetic 50/50 full-return store policy.

    Not a universal consignment policy. No ledger is mutated and no claim is
    submitted. A recall hold survives an ordinary return-to-stock request.
    """
    proposed = {'inventory_status': 'quarantine' if confirmed_recall else 'review',
                'customer_refund_cents': sale_cents if refund_approved else None,
                'consignor_adjustment_cents': None, 'adjustment_kind': 'review',
                'cash_recovered_cents': 0}
    if refund_approved and not paid_out:
        proposed.update(consignor_adjustment_cents=sale_cents // 2,
                        adjustment_kind='proposed_pending_commission_reversal')
    elif refund_approved and clawback_terms_verified:
        proposed.update(consignor_adjustment_cents=sale_cents // 2,
                        adjustment_kind='proposed_paid_commission_charge')
    return proposed


def run():
    cosori = Rule('Cosori', ('CP158-AF', 'CP137-AF'), 'replace')
    anker = Rule('Anker', ('A1652',), 'cash', serial_required=True)
    owner = Item('Cosori', 'CP158-AF', 10000, owner_eligibility_confirmed=True)
    cases = [
        ('replacement_is_not_cash', owner, cosori, ('replacement_only_no_cash', 0)),
        ('unknown_model', replace(owner, model=None), cosori, ('review_missing_model', 0)),
        ('suffix_is_not_equivalent', replace(owner, model='CP158-AF-R99'), cosori, ('no_match_in_this_rule', 0)),
        ('brand_conflict', replace(owner, brand='Other'), cosori, ('no_match_in_this_rule', 0)),
        ('stale_notice', owner, replace(cosori, source_fresh=False), ('review_stale_source', 0)),
        ('reseller_not_assumed_eligible', replace(owner, owner_eligibility_confirmed=False), cosori, ('match_review_program_eligibility', 0)),
        ('model_alone_not_enough', Item('Anker', 'A1652', 4000, owner_eligibility_confirmed=True), anker, ('review_serial_required', 0)),
        ('gift_card_not_payroll_cash', owner, replace(cosori, remedy='gift_card'), ('restricted_credit_no_cash', 0)),
        ('unapproved_claim_not_cash', replace(owner, claim_approved=False), replace(cosori, remedy='cash'), ('cash_claim_not_approved', 0)),
        ('approved_not_settled', replace(owner, claim_approved=True), replace(cosori, remedy='cash'), ('approved_cash_claim_not_settled', 0)),
        ('case_and_space_normalization', replace(owner, brand=' cosori ', model=' cp158-af '), cosori, ('replacement_only_no_cash', 0)),
    ]
    results = []
    for name, item, rule, expected in cases:
        actual = assess(item, rule)
        assert actual == expected, (name, actual, expected)
        results.append({'case': name, 'passed': True, 'actual': list(actual)})
    ledger = CashLedger()
    assert ledger.settle('bank-1', 2500) == 2500
    assert ledger.settle('bank-1', 2500) == 2500
    results.append({'case': 'duplicate_callback_is_idempotent', 'passed': True})
    assert ledger.settle('bank-2', 1500) == 4000
    results.append({'case': 'partial_settlements_sum_in_integer_cents', 'passed': True})
    try:
        ledger.settle('bank-1', 4000)
        raise AssertionError('conflicting event accepted')
    except ValueError:
        results.append({'case': 'conflicting_duplicate_blocked', 'passed': True})
    for value in [-1, 0.1, True]:
        try:
            ledger.settle('invalid', value)
            raise AssertionError('invalid amount accepted')
        except ValueError:
            pass
    results.append({'case': 'invalid_money_rejected', 'passed': True})
    snapshot = json.loads(Path(__file__).with_name('cpsc-live-fetch.json').read_text())
    rec = snapshot['records'][0]
    assert rec['RecallNumber'] == '23130'
    assert rec['Products'][0]['Model'] == '' and rec['ProductUPCs'] == []
    assert 'CP158-AF' in rec['Description']
    assert [x['Option'] for x in rec['RemedyOptions']] == ['Replace']
    results.append({'case': 'real_api_record_has_prose_models_and_replace_remedy', 'passed': True})
    proposal = consignment_handoff(10000, True, True, True)
    assert proposal['consignor_adjustment_cents'] == 5000
    assert proposal['cash_recovered_cents'] == 0
    results.append({'case': 'verified_terms_propose_only_consignor_share_not_full_refund', 'passed': True})
    unknown_terms = consignment_handoff(10000, True, True, False)
    assert unknown_terms['consignor_adjustment_cents'] is None
    results.append({'case': 'missing_clawback_terms_do_not_invent_consignor_debt', 'passed': True})
    unpaid = consignment_handoff(10000, False, True, False)
    assert unpaid['consignor_adjustment_cents'] == 5000
    assert unpaid['adjustment_kind'] == 'proposed_pending_commission_reversal'
    assert unpaid['cash_recovered_cents'] == 0
    results.append({'case': 'unpaid_commission_reversal_is_not_cash_recovery', 'passed': True})
    assert all(x['inventory_status'] == 'quarantine' for x in [proposal, unknown_terms, unpaid])
    assert consignment_handoff(10000, True, False, True)['consignor_adjustment_cents'] is None
    results.append({'case': 'recall_hold_survives_return_flow_and_unapproved_refund', 'passed': True})
    # Ablation: a tempting single-scalar "recovered value" rule is wrong even
    # on this single authentic remedy. This is the observed design correction.
    naive_cash = owner.paid_cents if owner.model in cosori.models else 0
    assert naive_cash == 10000 and assess(owner, cosori)[1] == 0
    output = {'passed': len(results), 'total': len(results), 'results': results,
              'ablation': {'naive_recovered_cash_cents': naive_cash,
                           'correct_spendable_cash_cents': 0,
                           'finding': 'replacement entitlement is not settled cash'},
              'limitations': ['Not an LLM accuracy test', 'Not program eligibility verification',
                             'Not customer or willingness-to-pay validation',
                             'No external state changed; finance inputs are synthetic']}
    Path(__file__).with_name('policy-results.json').write_text(json.dumps(output, indent=2)+'\n')
    print(json.dumps(output, indent=2))


if __name__ == '__main__':
    run()
