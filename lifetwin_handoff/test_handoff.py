"""Meaningful packaging, mapping and API checks for the LifeTwin handoff."""
import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from lifetwin_handoff.aggregation import aggregate_daily, aggregate_weekly
from lifetwin_handoff.model import LifeTwinModel
from lifetwin_handoff.service import app

HERE = Path(__file__).parent


def example(name):
    return json.loads((HERE / 'examples' / f'{name}_request.json').read_text(encoding='utf-8'))


def test_export_exactly_reproduces_original_model():
    model = LifeTwinModel()
    golden = json.loads((HERE / 'artifact/golden_vectors.json').read_text(encoding='utf-8'))
    for case in golden:
        result = model.predict(case['profile'])
        assert result['status'] == 'available'
        assert result['log_relative_hazard_score'] == pytest.approx(case['log_relative_hazard_score'], abs=1e-12)
        for year, expected in case['survival_probabilities'].items():
            assert result['survival_probabilities'][year] == pytest.approx(expected, abs=1e-12)
        curve = list(result['survival_probabilities'].values())
        assert all(0 < later < earlier < 1 for earlier, later in zip(curve, curve[1:]))
        assert result['death_date'] is None
        assert result['estimated_age_at_death'] is None


def test_profile_support_and_invalid_values_fail_closed():
    model = LifeTwinModel()
    profile = example('compare')['current_profile']
    assert model.predict({**profile, 'age': 34})['status'] == 'unsupported_age'
    assert model.predict({**profile, 'age': 80})['status'] == 'unsupported_age'
    assert model.predict({**profile, 'age': 85})['status'] == 'unsupported_age'
    missing = dict(profile)
    del missing['sleep_hours']
    assert model.predict(missing)['status'] == 'missing_inputs'
    assert model.predict({**profile, 'bmi': 60})['status'] == 'unsupported_profile'
    with pytest.raises(ValueError):
        model.predict({**missing, 'smoking_status': 9})
    with pytest.raises(ValueError):
        model.predict({**profile, 'sex_nhanes': 3})
    with pytest.raises(ValueError):
        model.predict({**profile, 'unknown': 1})


def test_daily_weekly_mapping_and_gaps():
    from datetime import date
    daily = example('daily')
    weekly = example('weekly')
    days, day_context = aggregate_daily(daily['daily_logs'], date.fromisoformat(daily['as_of_date']))
    weeks, week_context = aggregate_weekly(weekly['weekly_summaries'], date.fromisoformat(weekly['as_of_date']))
    assert day_context['complete_weeks'] == week_context['complete_weeks'] == 1
    assert days['sleep_hours'] == weeks['sleep_hours'] == 7
    assert days['vigorous_recreation_min_week'] == weeks['vigorous_recreation_min_week'] == 60
    assert days['moderate_recreation_min_week'] == weeks['moderate_recreation_min_week'] == 165
    assert days['sedentary_min_day'] == pytest.approx(weeks['sedentary_min_day'], abs=.2)
    incomplete = daily['daily_logs'][:-1]
    with pytest.raises(ValueError):
        aggregate_daily(incomplete, date.fromisoformat(daily['as_of_date']))


def test_api_assessment_guidance_and_comparison():
    with TestClient(app) as client:
        health = client.get('/health').json()
        assert health['ready'] is True
        assert health['death_date_prediction_available'] is False
        for name in ('snapshot', 'daily', 'weekly'):
            result = client.post('/v1/twin/assess', json=example(name))
            assert result.status_code == 200, result.text
            body = result.json()
            assert body['survival']['status'] == 'available'
            assert len(body['survival']['survival_percent_by_year']) == 5
            assert body['survival']['causal_interpretation'] is False
            assert body['avatar']['survival_display'] == 'annual_curve'
            assert body['wellness_cards']
            assert all(not card['derived_from_survival_model'] and card['source_url'].startswith('https://www.cdc.gov/')
                       for card in body['wellness_cards'])
        pair = client.post('/v1/twin/compare', json=example('compare'))
        assert pair.status_code == 200
        comparison = pair.json()
        assert comparison['causal_interpretation'] is False
        assert comparison['changed_features'] == ['smoking_status']
        assert comparison['modeled_difference_percentage_points']['5'] < 0
        assert comparison['modeled_difference_percentage_points']['5'] == pytest.approx(
            100 * (comparison['alternative']['survival_probabilities']['5']
                   - comparison['current']['survival_probabilities']['5']))
        invalid = example('daily')
        invalid['weekly_summaries'] = example('weekly')['weekly_summaries']
        assert client.post('/v1/twin/assess', json=invalid).status_code == 422
        changed = example('snapshot')
        changed['profile']['bmi'] = 60
        assert client.post('/v1/twin/assess', json=changed).status_code == 422


def test_wellness_cards_are_guidelines_not_model_effects():
    from lifetwin_handoff.guidance import guidance
    profile = example('compare')['alternative_profile']
    profile['sleep_hours'] = 5
    profile['moderate_recreation_min_week'] = 0
    profile['vigorous_recreation_min_week'] = 0
    cards = guidance(profile)
    opportunities = {card['id'] for card in cards if card['level'] == 'opportunity'}
    assert {'smoking', 'activity', 'sleep'} <= opportunities
    assert all(card['derived_from_survival_model'] is False for card in cards)
