"""LifeTwin API. Run from the parent directory: uvicorn lifetwin_handoff.service:app."""
from datetime import date
import math

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from .aggregation import aggregate_daily, aggregate_weekly
from .guidance import guidance
from .model import LifeTwinModel

model = LifeTwinModel()
app = FastAPI(title='LifeTwin survival and wellness handoff', version='1.0')


class AssessmentRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    profile: dict
    as_of_date: date = Field(default_factory=date.today)
    daily_logs: list[dict] | None = None
    weekly_summaries: list[dict] | None = None


class ComparisonRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    current_profile: dict
    alternative_profile: dict


def _prepare_profile(raw: dict):
    profile = dict(raw)
    height = profile.pop('height_cm', None)
    weight = profile.pop('weight_kg', None)
    if height is not None or weight is not None:
        if isinstance(height, bool) or isinstance(weight, bool) or not isinstance(height, (int, float)) or not isinstance(weight, (int, float)):
            raise ValueError('height_cm and weight_kg must both be finite numbers')
        if not 100 <= height <= 230 or not 25 <= weight <= 350:
            raise ValueError('height_cm or weight_kg is outside the supported entry range')
        derived = weight / (height / 100) ** 2
        if 'bmi' in profile and profile['bmi'] is not None:
            if (isinstance(profile['bmi'], bool) or not isinstance(profile['bmi'], (int, float))
                    or not math.isfinite(profile['bmi'])):
                raise ValueError('Supplied BMI must be a finite number')
            if abs(profile['bmi'] - derived) > .5:
                raise ValueError('Supplied BMI disagrees with height and weight')
        profile['bmi'] = derived
    return profile


@app.get('/health')
def health():
    return {'ready': True, 'model_version': model.spec['model_version'],
            'supported_age_range': model.spec['age_range'],
            'horizons_years': model.spec['horizons_years'],
            'death_date_prediction_available': False,
            'lifestyle_causal_effect_available': False}


@app.post('/v1/twin/assess')
def assess(request: AssessmentRequest):
    if request.daily_logs is not None and request.weekly_summaries is not None:
        raise HTTPException(status_code=422, detail='Supply daily_logs or weekly_summaries, not both')
    try:
        profile = _prepare_profile(request.profile)
        context = {'source': 'profile_snapshot'}
        if request.daily_logs is not None:
            behavior, context = aggregate_daily(request.daily_logs, request.as_of_date)
            profile.update(behavior)
        elif request.weekly_summaries is not None:
            behavior, context = aggregate_weekly(request.weekly_summaries, request.as_of_date)
            profile.update(behavior)
        result = model.predict(profile)
        cards = guidance(profile, context)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    strengths = [card['id'] for card in cards if card['level'] == 'strength']
    opportunities = [card['id'] for card in cards if card['level'] == 'opportunity']
    wellness_state = ('needs_input' if result['status'] == 'missing_inputs'
                      else 'explore_changes' if opportunities else 'steady')
    return {'as_of_date': request.as_of_date.isoformat(), 'profile_used': profile,
            'input_provenance': context, 'survival': result, 'wellness_cards': cards,
            'avatar': {'survival_display': 'annual_curve' if result['status'] == 'available' else 'unavailable',
                       'wellness_state': wellness_state,
                       'strengths': strengths, 'opportunities': opportunities},
            'display_rules': {'survival_title': 'Modeled survival of similar people',
                              'scenario_title': 'Modeled difference between profiles',
                              'never_display': ['date of death', 'years of life gained', 'guaranteed benefit']}}


@app.post('/v1/twin/compare')
def compare(request: ComparisonRequest):
    try:
        current = _prepare_profile(request.current_profile)
        alternative = _prepare_profile(request.alternative_profile)
        return model.compare(current, alternative)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
