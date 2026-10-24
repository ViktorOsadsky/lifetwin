"""Small, standalone runtime for the approved LifeTwin survival artifact.

Runtime dependencies: Python, NumPy. No NHANES CSV, TensorFlow or pickle.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import numpy as np

ARTIFACT_DIR = Path(__file__).parent / 'artifact'


class LifeTwinModel:
    def __init__(self, artifact_dir: Path = ARTIFACT_DIR):
        self.artifact_dir = Path(artifact_dir)
        manifest = json.loads((self.artifact_dir / 'manifest.json').read_text(encoding='utf-8'))
        for name, digest in manifest['files_sha256'].items():
            if hashlib.sha256((self.artifact_dir / name).read_bytes()).hexdigest() != digest:
                raise ValueError(f'Artifact fingerprint mismatch: {name}')
        self.spec = json.loads((self.artifact_dir / 'model.json').read_text(encoding='utf-8'))
        with np.load(self.artifact_dir / 'support_reference.npz', allow_pickle=False) as support:
            self.reference = support['encoded_reference'].copy()
        self.coefficients = np.asarray(self.spec['coefficients'], dtype=float)
        self.center = np.asarray(self.spec['feature_center'], dtype=float)
        self.baseline = np.asarray(self.spec['baseline_survival'], dtype=float)
        if (self.reference.ndim != 2 or self.reference.shape[1] != len(self.coefficients)
                or len(self.coefficients) != len(self.center)
                or len(self.coefficients) != len(self.spec['encoded_features'])
                or len(self.baseline) != len(self.spec['horizons_years'])):
            raise ValueError('Malformed artifact dimensions')
        if not np.isfinite(self.reference).all() or not np.isfinite(self.coefficients).all():
            raise ValueError('Non-finite artifact data')
        if (self.baseline <= 0).any() or (self.baseline > 1).any() or (np.diff(self.baseline) > 0).any():
            raise ValueError('Invalid baseline survival')

    def _validate(self, profile: dict):
        if not isinstance(profile, dict):
            raise ValueError('profile must be a JSON object')
        unknown = set(profile) - set(self.spec['input_features'])
        if unknown:
            raise ValueError(f'Unknown profile inputs: {sorted(unknown)}')
        missing = [name for name in self.spec['input_features'] if profile.get(name) is None]
        clean = {}
        for name in self.spec['input_features']:
            if name in missing:
                continue
            value = profile[name]
            if isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value):
                raise ValueError(f'{name} must be a finite number')
            clean[name] = float(value)
            if name == 'age':
                if not 0 <= clean[name] <= 120:
                    raise ValueError('age must be between 0 and 120')
                continue
            if name in self.spec['numeric_bounds']:
                low, high = self.spec['numeric_bounds'][name]
                if not low <= clean[name] <= high:
                    raise ValueError(f'{name} must be between {low} and {high}')
            if name in self.spec['categorical_allowed']:
                if clean[name] not in self.spec['categorical_allowed'][name]:
                    raise ValueError(f'{name} has an unsupported category')
        if missing:
            return None, missing
        if clean['sleep_hours'] * 60 + clean['sedentary_min_day'] > 1440:
            raise ValueError('Sleep and awake sitting cannot exceed 24 hours per day')
        activity = clean['vigorous_recreation_min_week'] + clean['moderate_recreation_min_week']
        if activity > 10080:
            raise ValueError('Combined recreation cannot exceed one week')
        if clean['sleep_hours'] * 60 + clean['sedentary_min_day'] + activity / 7 > 1440:
            raise ValueError('Recreation exceeds time available after sleep and sitting')
        return clean, []

    @staticmethod
    def encode(p: dict) -> np.ndarray:
        age, bmi, sleep = p['age'], p['bmi'], p['sleep_hours']
        values = [
            (age - 55) / 10,
            max(23 - bmi, 0) / 5,
            max(bmi - 27, 0) / 5,
            max(7 - sleep, 0),
            max(sleep - 8, 0),
            math.log1p(p['vigorous_recreation_min_week']) / math.log(76),
            math.log1p(p['moderate_recreation_min_week']) / math.log(151),
            (p['sedentary_min_day'] - 360) / 120,
            float(p['sex_nhanes'] == 2),
            float(p['smoking_status'] == 1),
            float(p['smoking_status'] == 2),
            p['diabetes_diagnosed'],
            p['hypertension_diagnosed'],
        ]
        values.extend(float(p['general_health'] == level) for level in (2, 3, 4, 5))
        return np.asarray(values, dtype=float)

    def predict(self, profile: dict) -> dict:
        clean, missing = self._validate(profile)
        common = {'model_version': self.spec['model_version'], 'causal_interpretation': False,
                  'horizons_years': self.spec['horizons_years'],
                  'survival_probabilities': None, 'survival_percent_by_year': None,
                  'death_date': None, 'estimated_age_at_death': None}
        if missing:
            return {**common, 'status': 'missing_inputs', 'missing_inputs': missing,
                    'message': 'Complete every model input to show annual survival percentages.'}
        if not self.spec['age_range'][0] <= clean['age'] <= self.spec['age_range'][1]:
            return {**common, 'status': 'unsupported_age', 'message': 'Annual estimates support ages 35–79 only.'}
        x = self.encode(clean)
        score = float(np.dot(x - self.center, self.coefficients))
        support_issues = []
        for name, (low, high) in self.spec['numeric_support_1_99pct'].items():
            if not low <= clean[name] <= high:
                support_issues.append(f'{name} is outside the training 1st–99th percentile range')
        distances = np.sqrt(np.sum((self.reference - x[None, :]) ** 2, axis=1))
        fifth_distance = float(np.partition(distances, self.spec['neighbor_count'] - 1)[self.spec['neighbor_count'] - 1])
        if fifth_distance > self.spec['neighbor_distance_cutoff']:
            support_issues.append('The input combination has few nearby training profiles')
        if support_issues:
            return {**common, 'status': 'unsupported_profile',
                    'message': 'Annual estimates are withheld for this profile.',
                    'support_issues': support_issues}
        survival = self.baseline ** math.exp(max(-40, min(score, 40)))
        if (survival <= 0).any() or (survival > 1).any() or (np.diff(survival) > 1e-10).any():
            raise ValueError('Invalid survival curve')
        by_year = {str(year): float(value) for year, value in zip(self.spec['horizons_years'], survival)}
        return {**common, 'status': 'available', 'log_relative_hazard_score': score,
                'survival_probabilities': by_year,
                'survival_percent_by_year': {year: 100 * value for year, value in by_year.items()},
                'interpretation': 'Estimated cumulative survival among similar survey profiles, not an individual death date or medical prognosis.'}

    def compare(self, current: dict, alternative: dict) -> dict:
        first = self.predict(current)
        second = self.predict(alternative)
        changes = [name for name in self.spec['input_features'] if current.get(name) != alternative.get(name)]
        difference = None
        if first['status'] == second['status'] == 'available':
            difference = {year: 100 * (second['survival_probabilities'][year] - value)
                          for year, value in first['survival_probabilities'].items()}
        warnings = []
        if set(changes) & {'bmi', 'sleep_hours', 'sedentary_min_day'}:
            warnings.append('BMI, sleep and sitting profile contrasts do not estimate intervention effects; the high-BMI fitted slope is near zero and slightly inverse.')
        return {'current': first, 'alternative': second, 'changed_features': changes,
                'modeled_difference_percentage_points': difference,
                'causal_interpretation': False,
                'interpretation': 'Difference between two model profiles, not the benefit of changing a habit.',
                'warnings': warnings}
