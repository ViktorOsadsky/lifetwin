"""Turn complete daily or weekly lifestyle logs into NHANES-like snapshot inputs."""
from datetime import date, timedelta
import math


BEHAVIOR_FIELDS = ('sleep_hours', 'vigorous_recreation_min_week',
                   'moderate_recreation_min_week', 'sedentary_min_day')


def _number(row, name, low, high):
    value = row.get(name)
    if isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value):
        raise ValueError(f'{name} must be a finite number')
    if not low <= value <= high:
        raise ValueError(f'{name} must be between {low} and {high}')
    return float(value)


def _date(value, name):
    try:
        return date.fromisoformat(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f'{name} must be an ISO date, YYYY-MM-DD') from exc


def aggregate_daily(logs: list[dict], as_of: date):
    """Average one to four complete, consecutive 7-day blocks ending yesterday."""
    if not isinstance(logs, list) or len(logs) not in (7, 14, 21, 28):
        raise ValueError('daily_logs must contain 7, 14, 21, or 28 complete days')
    rows = sorted(logs, key=lambda row: row.get('date', ''))
    dates = [_date(row.get('date'), 'date') for row in rows]
    if len(set(dates)) != len(dates) or dates[-1] != as_of - timedelta(days=1):
        raise ValueError('daily_logs must have unique dates and end yesterday')
    if any(day != dates[0] + timedelta(days=i) for i, day in enumerate(dates)):
        raise ValueError('daily_logs must have no missing dates')
    vigorous = moderate = sitting = 0.
    workday_sleep = []
    week_sitting = []
    for block in range(len(rows) // 7):
        week_sitting.append(0.)
        for row in rows[block * 7:(block + 1) * 7]:
            sleep = _number(row, 'sleep_hours', 2, 12)
            sit = _number(row, 'sedentary_min_day', 0, 1439)
            vig = _number(row, 'vigorous_recreation_min', 0, 1440)
            mod = _number(row, 'moderate_recreation_min', 0, 1440)
            if not isinstance(row.get('workday'), bool):
                raise ValueError('workday must be true or false for each daily log')
            if sleep * 60 + sit + vig + mod > 1440:
                raise ValueError('A daily log has more than 24 hours of sleep, sitting and recreation')
            if row['workday']:
                workday_sleep.append(sleep)
            vigorous += vig
            moderate += mod
            sitting += sit
            week_sitting[-1] += sit / 7
    if len(workday_sleep) < 3 * (len(rows) // 7):
        raise ValueError('At least three workday sleep observations per week are required')
    weeks = len(rows) / 7
    behavior = {'sleep_hours': sum(workday_sleep) / len(workday_sleep),
                'vigorous_recreation_min_week': vigorous / weeks,
                'moderate_recreation_min_week': moderate / weeks,
                'sedentary_min_day': sitting / len(rows)}
    context = {'source': 'daily_logs', 'window_start': dates[0].isoformat(),
               'window_end': dates[-1].isoformat(), 'complete_weeks': int(weeks),
               'workday_sleep_observations': len(workday_sleep),
               'sitting_first_week': week_sitting[0], 'sitting_last_week': week_sitting[-1]}
    return behavior, context


def aggregate_weekly(logs: list[dict], as_of: date):
    """Average one to four consecutive, completed Monday–Sunday summaries."""
    if not isinstance(logs, list) or not 1 <= len(logs) <= 4:
        raise ValueError('weekly_summaries must contain one to four complete weeks')
    rows = sorted(logs, key=lambda row: row.get('week_start', ''))
    starts = [_date(row.get('week_start'), 'week_start') for row in rows]
    latest_complete_monday = as_of - timedelta(days=as_of.weekday() + 7)
    if len(set(starts)) != len(starts) or starts[-1] != latest_complete_monday:
        raise ValueError('weekly_summaries must end with the latest completed Monday–Sunday week')
    if any(start.weekday() != 0 or start != starts[0] + timedelta(days=7 * i)
           for i, start in enumerate(starts)):
        raise ValueError('weekly_summaries must be consecutive Monday–Sunday weeks')
    values = {name: [] for name in BEHAVIOR_FIELDS}
    for row in rows:
        values['sleep_hours'].append(_number(row, 'sleep_hours', 2, 12))
        values['vigorous_recreation_min_week'].append(_number(row, 'vigorous_recreation_min_week', 0, 10073))
        values['moderate_recreation_min_week'].append(_number(row, 'moderate_recreation_min_week', 0, 10073))
        values['sedentary_min_day'].append(_number(row, 'sedentary_min_day', 0, 1439))
        if (values['sleep_hours'][-1] * 60 + values['sedentary_min_day'][-1]
                + (values['vigorous_recreation_min_week'][-1] + values['moderate_recreation_min_week'][-1]) / 7 > 1440):
            raise ValueError('A weekly summary exceeds the time available in a day')
    behavior = {name: sum(numbers) / len(numbers) for name, numbers in values.items()}
    context = {'source': 'weekly_summaries', 'window_start': starts[0].isoformat(),
               'window_end': (starts[-1] + timedelta(days=6)).isoformat(),
               'complete_weeks': len(rows),
               'sitting_first_week': values['sedentary_min_day'][0],
               'sitting_last_week': values['sedentary_min_day'][-1]}
    return behavior, context
