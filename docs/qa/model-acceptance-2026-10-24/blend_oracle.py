"""HOST oracle: independent CDC life component and weighted summary, never a device run.

Projection component parity is checked separately by canonical_oracle.dart. This
script consumes those same captured projection points, never assumes selected
annualCurve crosses at the blended summary. --host-fixture cannot claim acceptance.
"""
import importlib.util
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]


def close(actual, expected, path):
    assert actual is not None and expected is not None, f'{path}: missing is not zero'
    assert math.isfinite(actual) and math.isfinite(expected), path
    assert abs(actual - expected) <= 1e-9, f'{path}: {actual} versus {expected}'


def weight(age):
    if age <= 35 or age >= 79:
        return 0.0
    if age < 45:
        return (age - 35) / 10
    return 1.0 if age <= 70 else (79 - age) / 9


def crossing(points, threshold):
    for before, after in zip(points, points[1:]):
        if before['survival_percent'] > threshold >= after['survival_percent']:
            return after['age'] - 1 + (before['survival_percent'] - threshold) / (before['survival_percent'] - after['survival_percent'])
    return None


def points_equal(actual, expected, label):
    assert len(actual) == len(expected), f'{label} point count'
    for i, (a, e) in enumerate(zip(actual, expected, strict=True)):
        assert a['age'] == e['age'] and a['extrapolated'] == e['extrapolated'], f'{label} age/tail{i}'
        close(a['survival_percent'], e['survival_percent'], f'{label} point{i}')


def main():
    host_only = len(sys.argv) == 4 and sys.argv[3] == '--host-fixture'
    assert len(sys.argv) == 3 or host_only, 'usage: python check_fallback.py CAPTURE.json OUTPUT.json [--host-fixture]'
    capture = json.loads(Path(sys.argv[1]).read_text())
    assert capture['schema'] == 'lifetwin.qa107.engine.v2'
    assert capture['synthetic_only']
    if host_only:
        assert capture['host_fixture_only'] and capture['host_fixture_assertions_passed']
        assert not capture['owner_approved_and_merged'] and not capture['device_assertions_passed']
    else:
        assert capture['owner_approved_and_merged'] and capture['device_assertions_passed']
        assert not capture.get('host_fixture_only')
    spec = importlib.util.spec_from_file_location('qa107_lifespan_reference', ROOT / 'server/tools/lifespan_reference.py')
    reference = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = reference
    spec.loader.exec_module(reference)
    inputs = reference.Inputs()
    records = [*capture['records'], *capture['edge_records'], *capture['fractional_records']]
    rows = []
    for record in records:
        p = record['profile_used']
        age, w = p['age'], weight(p['age'])
        expected = reference.estimate_profile(inputs, p)
        actual, table = record['lifespan'], record['life_table_component']
        table_mean, table_low, table_high = (expected[k] for k in ['expected_age_at_death', 'age_25th_percentile', 'age_75th_percentile'])
        close(table['expected_age'], table_mean, f'{age} CDC mean')
        close(table['p25_age'], table_low, f'{age} CDC p25')
        close(table['p75_age'], table_high, f'{age} CDC p75')
        table_points = [{'age': int(a), 'survival_percent': 100 * s, 'extrapolated': True}
                        for a, s in expected['survival_curve'] if a == round(a)]
        points_equal(table['points'], table_points, f'{age} CDC component')
        projection = record['projection_component']
        if projection is None:
            assert w == 0 and (age < 35 or age > 79)
            mean, low, high = table_mean, table_low, table_high
            open_flags = [False, False, False]
            beyond = True
        else:
            median = projection['median_crossing_age']
            plow, phigh = crossing(projection['points'], 75), crossing(projection['points'], 25)
            mean = (1 - w) * table_mean + w * (110 if median is None else median)
            low = min((1 - w) * table_low + w * (110 if plow is None else plow), mean)
            high = max((1 - w) * table_high + w * (110 if phigh is None else phigh), mean)
            open_flags = [plow is None and low >= 110, median is None and mean >= 110, phigh is None and high >= 110]
            beyond = median is None or projection['median_crossing_extrapolated'] is True
        method = 'life_table_mean' if w == 0 else ('yearly_cox_median' if w == 1 else 'blend_life_table_mean_yearly_cox_median')
        assert actual['method'] == method
        close(actual['projection_weight'], w, f'{age} weight')
        close(actual['expected_age'], mean, f'{age} weighted mean/median')
        close(actual['p25_age'], low, f'{age} bounded weighted p25')
        close(actual['p75_age'], high, f'{age} bounded weighted p75')
        assert low <= mean <= high
        assert actual['expected_year'] == 2026 + reference.round_half_up(mean - age)
        assert actual['status'] == ('extrapolated' if w < .5 else 'available')
        assert actual['extrapolated'] == (w < .5)
        assert actual['median_crossing_extrapolated'] == beyond
        assert [actual[k] for k in ['p25_open_ended', 'open_ended', 'p75_open_ended']] == open_flags
        source = 'life_table' if w < .5 else 'yearly_cox_projection'
        assert actual['selected_curve_source'] == source
        points_equal(actual['points'], table_points if w < .5 else projection['points'], f'{age} selected curve')
        shown = [str(110) + '+' if flag else str(reference.round_half_up(value)) for value, flag in zip([mean, low, high], [open_flags[1], open_flags[0], open_flags[2]], strict=True)]
        assert actual['headline'] == f"You're likely to live to about {shown[0]}. Most people like you live to between {shown[1]} and {shown[2]}."
        assert 'rough estimate, not a prediction for you' in actual['caveat']
        if open_flags != [False] * 3:
            assert '110+' in actual['caveat']
        rows.append({'id': record['id'], 'projection_weight': w, 'summary_method': method,
                     'selected_curve_source': source, 'CDC_component_all_points_parity': True,
                     'weighted_summary_bounds_flags_headline_parity': True})
    assert len(rows) == 23, 'four primary, fourteen boundary and five fractional profiles required'
    by_age = {r['profile_used']['age']: r['lifespan']['expected_age'] for r in capture['edge_records']}
    result = {'schema': 'lifetwin.qa107.blend.v2', 'merged_sha': capture['merged_sha'],
              'host_fixture_only': host_only, 'proposed_sha': capture.get('proposed_sha'),
              'source': str(ROOT / 'server/tools/lifespan_reference.py'), 'tolerance': 1e-9,
              'requires_canonical_projection_oracle': True, 'records': rows,
              'observed_adjacent_age_differences_not_continuity_proof': {
                  '34_to_35': by_age[35] - by_age[34], '39_to_40': by_age[40] - by_age[39],
                  '74_to_75': by_age[75] - by_age[74], '78_to_79': by_age[79] - by_age[78],
                  '79_to_80': by_age[80] - by_age[79]}}
    Path(sys.argv[2]).write_text(json.dumps(result, indent=2) + '\n')
    print(f'PASS independent CDC components + blended summaries/bounds/flags/selected curves: {sys.argv[2]} (host_fixture_only={host_only})')


if __name__ == '__main__':
    main()
