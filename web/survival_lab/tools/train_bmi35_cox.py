#!/usr/bin/env python3
"""Reproduce the website-only Cox refit from the prepared NHANES CSV.

Run from this folder's repository root with the original processed data:
  python web/survival_lab/tools/train_bmi35_cox.py --data ../output/lifestyle_v2/lifestyle_long_followup.csv

The Flutter handoff deliberately remains on its separately approved artifact.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd
from lifelines import CoxPHFitter, KaplanMeierFitter
from lifelines.utils import concordance_index
from sklearn.model_selection import train_test_split
from sklearn.neighbors import NearestNeighbors

SITE = Path(__file__).resolve().parents[1]
YEARS = [1, 2, 3, 4, 5]
VERSION = 'personal-cox-bmi35-v3-20261024'
NUMERIC = ['age', 'bmi', 'sleep_hours', 'vigorous_recreation_min_week',
           'moderate_recreation_min_week', 'sedentary_min_day']
CATEGORICAL = ['sex_nhanes', 'smoking_status', 'diabetes_diagnosed',
               'hypertension_diagnosed', 'general_health']
FEATURES = NUMERIC + CATEGORICAL
BOUNDS = {'age': [18, 80], 'bmi': [10, 85], 'sleep_hours': [2, 12],
          'vigorous_recreation_min_week': [0, 10073],
          'moderate_recreation_min_week': [0, 10073],
          'sedentary_min_day': [0, 1439]}
ALLOWED = {'sex_nhanes': [1, 2], 'smoking_status': [0, 1, 2],
           'diabetes_diagnosed': [0, 1], 'hypertension_diagnosed': [0, 1],
           'general_health': [1, 2, 3, 4, 5]}
ENCODED = ['age_decade', 'bmi_below23', 'bmi_above35', 'sleep_below7',
           'sleep_above8', 'vigorous_log', 'moderate_log', 'sedentary_120',
           'female', 'former_smoker', 'current_smoker', 'diabetes',
           'hypertension', 'health_2', 'health_3', 'health_4', 'health_5']


def prepare(frame, training):
    x = frame.reindex(columns=FEATURES).apply(pd.to_numeric, errors='coerce')
    if training:
        for key, (lo, hi) in BOUNDS.items():
            x[key] = x[key].where(x[key].between(lo, hi))
        for key, allowed in ALLOWED.items():
            x[key] = x[key].where(x[key].isin(allowed))
    return x


def encode(raw, medians, modes):
    x = raw.copy()
    for key, value in medians.items():
        x[key] = x[key].fillna(value)
    for key, value in modes.items():
        x[key] = x[key].fillna(value)
    out = pd.DataFrame(index=x.index)
    out['age_decade'] = (x.age - 55) / 10
    out['bmi_below23'] = np.maximum(23 - x.bmi, 0) / 5
    out['bmi_above35'] = np.maximum(x.bmi - 35, 0) / 5
    out['sleep_below7'] = np.maximum(7 - x.sleep_hours, 0)
    out['sleep_above8'] = np.maximum(x.sleep_hours - 8, 0)
    out['vigorous_log'] = np.log1p(x.vigorous_recreation_min_week) / np.log(76)
    out['moderate_log'] = np.log1p(x.moderate_recreation_min_week) / np.log(151)
    out['sedentary_120'] = (x.sedentary_min_day - 360) / 120
    out['female'] = (x.sex_nhanes == 2).astype(float)
    out['former_smoker'] = (x.smoking_status == 1).astype(float)
    out['current_smoker'] = (x.smoking_status == 2).astype(float)
    out['diabetes'] = x.diabetes_diagnosed.astype(float)
    out['hypertension'] = x.hypertension_diagnosed.astype(float)
    for level in (2, 3, 4, 5):
        out[f'health_{level}'] = (x.general_health == level).astype(float)
    if not np.isfinite(out.to_numpy()).all():
        raise ValueError('Encoded training data contains missing or infinite values')
    return out[ENCODED]


def ipcw_brier(time, event, survival, fit_time, fit_event, horizon):
    km = KaplanMeierFitter().fit(fit_time, event_observed=1 - fit_event)
    times = km.survival_function_.index.to_numpy(dtype=float)
    values = km.survival_function_.iloc[:, 0].to_numpy(dtype=float)
    previous = np.searchsorted(times, time, side='left') - 1
    at_horizon = np.searchsorted(times, horizon, side='right') - 1
    g_event = np.where(previous >= 0, values[np.maximum(previous, 0)], 1.)
    g_h = values[max(at_horizon, 0)] if at_horizon >= 0 else 1.
    died = (time <= horizon) & (event == 1)
    alive = time > horizon
    if g_h < .05 or np.any(g_event[died] < .05):
        raise ValueError('Censoring distribution cannot support this horizon')
    weights = np.zeros(len(time))
    weights[died] = 1 / g_event[died]
    weights[alive] = 1 / g_h
    return float(np.mean(weights * (died.astype(float) - (1 - survival)) ** 2))


def evaluate(model, x, data, indices, fit_indices):
    subset = x.iloc[indices]
    time = data.duration_years.iloc[indices].to_numpy(dtype=float)
    event = data.event.iloc[indices].to_numpy(dtype=int)
    fit_time = data.duration_years.iloc[fit_indices].to_numpy(dtype=float)
    fit_event = data.event.iloc[fit_indices].to_numpy(dtype=int)
    score = model.predict_log_partial_hazard(subset).to_numpy().ravel()
    survival = model.predict_survival_function(subset, times=YEARS).T.to_numpy()
    groups = {}
    ages = data.age.iloc[indices].to_numpy()
    sex = data.sex_nhanes.iloc[indices].to_numpy()
    named_masks = [('all', np.ones(len(indices), dtype=bool)),
                   ('35-49', ages < 50), ('50-64', (ages >= 50) & (ages < 65)),
                   ('65-79', ages >= 65), ('male', sex == 1), ('female', sex == 2)]
    quintile = pd.qcut(pd.Series(1 - survival[:, -1]).rank(method='first'), 5,
                       labels=False).to_numpy()
    named_masks += [(f'risk_quintile_{i + 1}', quintile == i) for i in range(5)]
    for name, mask in named_masks:
        groups[name] = {'n': int(mask.sum()),
                        'predicted_5y_survival': float(survival[mask, -1].mean()),
                        'observed_5y_survival': float(KaplanMeierFitter().fit(
                            time[mask], event[mask]).predict(5))}
    brier = [ipcw_brier(time, event, survival[:, j], fit_time, fit_event, year)
             for j, year in enumerate(YEARS)]
    return {'n': len(indices), 'deaths': int(event.sum()),
            'c_index': float(concordance_index(time, -score, event)),
            'ipcw_brier_by_year': brier, 'mean_ipcw_brier': float(np.mean(brier)),
            'five_year_calibration': groups}


def projected_crossing(model, profile, medians, modes, step):
    cumulative = 1.
    for block_age in range(int(profile['age']), 110, step):
        future = dict(profile, age=block_age)
        encoded = encode(prepare(pd.DataFrame([future]), training=False), medians, modes)
        horizon = min(step, 110 - block_age)
        survival = model.predict_survival_function(encoded, times=range(1, horizon + 1)).iloc[:, 0]
        block_start = cumulative
        for years, conditional in enumerate(survival, start=1):
            next_survival = block_start * float(conditional)
            if cumulative > .5 >= next_survival:
                return block_age + years - 1 + (cumulative - .5) / (cumulative - next_survival)
            cumulative = next_survival
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data', type=Path, required=True)
    args = parser.parse_args()
    data_path = args.data.resolve(strict=True)
    data_sha = hashlib.sha256(data_path.read_bytes()).hexdigest()
    data = pd.read_csv(data_path, low_memory=False)
    data = data.loc[(data.age >= 35) & (data.age < 80) &
                    data.duration_years.gt(0) & data.event.isin([0, 1])].reset_index(drop=True)
    early = np.flatnonzero(data.CYCLE != '2013-2014')
    test = np.flatnonzero(data.CYCLE == '2013-2014')
    fit, validation = train_test_split(early, test_size=.22, random_state=72,
                                       stratify=data.event.to_numpy()[early])
    raw = prepare(data, training=True)
    medians = {key: float(raw[key].iloc[fit].median()) for key in NUMERIC if key != 'age'}
    modes = {key: float(raw[key].iloc[fit].mode().iloc[0]) for key in CATEGORICAL}
    x = encode(raw, medians, modes)
    training_frame = x.iloc[fit].copy()
    training_frame['duration'] = data.duration_years.iloc[fit].to_numpy()
    training_frame['event'] = data.event.iloc[fit].to_numpy()
    model = CoxPHFitter(penalizer=.02).fit(training_frame, 'duration', 'event')
    if model.params_['bmi_below23'] <= 0 or model.params_['bmi_above35'] <= 0:
        raise ValueError('BMI directions failed; do not export this fit')
    validation_metrics = evaluate(model, x, data, validation, fit)
    test_metrics = evaluate(model, x, data, test, fit)
    if validation_metrics['mean_ipcw_brier'] > .026 or test_metrics['c_index'] < .75:
        raise ValueError('Refit failed basic performance checks')
    if any(abs(group['predicted_5y_survival'] - group['observed_5y_survival']) > .02
           for group in test_metrics['five_year_calibration'].values()):
        raise ValueError('Refit failed later-cycle five-year calibration check')

    center = model._norm_mean.reindex(ENCODED)
    baseline = model.predict_survival_function(pd.DataFrame([center]), times=YEARS).iloc[:, 0]
    reference = x.iloc[early].sample(n=min(2000, len(early)), random_state=42)
    neighbors = NearestNeighbors(n_neighbors=5).fit(reference)
    calibration = x.iloc[early].sample(n=min(500, len(early)), random_state=7)
    cutoff = float(np.quantile(neighbors.kneighbors(calibration)[0][:, -1], .99))
    specification = {
        'schema_version': 1, 'model_version': VERSION,
        'model_type': 'penalized Cox; flat BMI 23-35, fitted positive high-BMI slope',
        'dataset_sha256': data_sha, 'age_range': [35, 79], 'horizons_years': YEARS,
        'input_features': FEATURES, 'encoded_features': ENCODED,
        'coefficients': [float(model.params_[key]) for key in ENCODED],
        'feature_center': [float(center[key]) for key in ENCODED],
        'baseline_survival': [float(baseline.loc[float(year)]) for year in YEARS],
        'numeric_bounds': BOUNDS, 'categorical_allowed': ALLOWED,
        'numeric_support_1_99pct': {
            key: list(map(float, raw.iloc[early][key].quantile([.01, .99]).to_numpy()))
            for key in NUMERIC},
        'neighbor_distance_cutoff': cutoff, 'neighbor_count': 5,
        'survival_semantics': 'All-cause cumulative survival at years 1-5; not a death date.',
        'causal_interpretation': False,
    }
    profiles = [
        dict(age=45, sex_nhanes=1, bmi=25, sleep_hours=7, smoking_status=0,
             diabetes_diagnosed=0, hypertension_diagnosed=0, general_health=2,
             vigorous_recreation_min_week=60, moderate_recreation_min_week=120,
             sedentary_min_day=360),
        dict(age=55, sex_nhanes=1, bmi=27, sleep_hours=7, smoking_status=2,
             diabetes_diagnosed=0, hypertension_diagnosed=0, general_health=3,
             vigorous_recreation_min_week=60, moderate_recreation_min_week=120,
             sedentary_min_day=360),
        dict(age=68, sex_nhanes=2, bmi=29, sleep_hours=8, smoking_status=1,
             diabetes_diagnosed=1, hypertension_diagnosed=1, general_health=3,
             vigorous_recreation_min_week=0, moderate_recreation_min_week=90,
             sedentary_min_day=420),
    ]
    for bmi in [35, 50, 100, 150]:
        profiles.append(dict(profiles[0], age=19, bmi=bmi))
    golden = []
    for profile in profiles:
        encoded = encode(prepare(pd.DataFrame([profile]), training=False), medians, modes)
        score = float(model.predict_log_partial_hazard(encoded).iloc[0])
        survival = model.predict_survival_function(encoded, times=YEARS).iloc[:, 0]
        golden.append({'profile': profile, 'log_relative_hazard_score': score,
                       'survival_probabilities': {str(y): float(survival.loc[float(y)]) for y in YEARS}})
    projection_vectors = []
    for profile in [profiles[0], profiles[-2], profiles[-1]]:
        projection_vectors.append({'profile': profile,
                                   'annual_50': projected_crossing(model, profile, medians, modes, 1),
                                   'five_year_50': projected_crossing(model, profile, medians, modes, 5)})
    evaluation = {'model_version': VERSION, 'training_n': len(fit),
                  'validation': validation_metrics, 'later_cycle_test': test_metrics,
                  'bmi_coefficients': {key: float(model.params_[key])
                                       for key in ['bmi_below23', 'bmi_above35']},
                  'fit_bmi_max': float(raw.bmi.iloc[fit].max()),
                  'fit_bmi_above35_n': int((raw.bmi.iloc[fit] >= 35).sum()),
                  'fit_bmi_above35_deaths': int(data.event.iloc[fit][raw.bmi.iloc[fit] >= 35].sum())}
    (SITE / 'assets/cox.json').write_text(json.dumps(specification, indent=2), encoding='utf-8')
    (SITE / 'assets/support_reference.f64').write_bytes(
        reference.to_numpy(dtype='<f8').tobytes(order='C'))
    (SITE / 'test/cox_vectors.json').write_text(json.dumps(golden, indent=2), encoding='utf-8')
    (SITE / 'test/projection_vectors.json').write_text(
        json.dumps(projection_vectors, indent=2), encoding='utf-8')
    (SITE / 'evaluation.json').write_text(json.dumps(evaluation, indent=2), encoding='utf-8')
    print(json.dumps(evaluation, indent=2))


if __name__ == '__main__':
    main()
