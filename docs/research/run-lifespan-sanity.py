"""Run actual pinned app Dart code on the host, using a tiny temporary Flutter package.

No simulator, product changes, new algorithm or provider. Requires installed Flutter.
"""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--app', required=True, type=Path, help='app/ from the pinned engine checkout')
    p.add_argument('--head', required=True, help='full engine commit hash; recorded, never inferred from branch name')
    p.add_argument('--flutter', required=True, type=Path)
    p.add_argument('--pub-cache', required=True, type=Path)
    p.add_argument('--out', required=True, type=Path)
    a = p.parse_args()
    assert len(a.head) == 40 and all(c in '0123456789abcdef' for c in a.head)
    here = Path(__file__).resolve().parent
    app = a.app.resolve()
    checkout = subprocess.run(['git', '-C', str(app), 'rev-parse', 'HEAD'], capture_output=True, text=True)
    if checkout.returncode == 0:
        assert checkout.stdout.strip() == a.head, 'Engine checkout HEAD must match the declared pin'
    files = [Path('lib/twin') / name for name in ['lifespan.dart', 'lifespan_data.dart', 'twin_model.dart', 'profile_mapping.dart']]
    files += sorted(f.relative_to(app) for f in (app / 'packages/lifetwin_on_device').rglob('*')
                    if f.is_file() and (f.suffix == '.dart' and '/lib/' in f.as_posix() or '/assets/' in f.as_posix() or f.name == 'pubspec.yaml'))
    hashes = {str(f): hashlib.sha256((app / f).read_bytes()).hexdigest() for f in files}
    # Only a synthetic fixture and the four production adapter files are needed.
    with tempfile.TemporaryDirectory(prefix='lifetwin-lifespan-sanity-', dir='/private/tmp') as d:
        work = Path(d)
        for f in files:
            (work / f).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(app / f, work / f)
        (work / 'test').mkdir()
        shutil.copy2(here / 'lifespan-sanity-sweep.dart', work / 'test/sweep_test.dart')
        # SDK floor is local to this host harness; production source is copied unchanged.
        (work / 'pubspec.yaml').write_text('''name: lifesim
publish_to: none
environment:
  sdk: '>=3.13.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  lifetwin_on_device:
    path: packages/lifetwin_on_device
dev_dependencies:
  flutter_test:
    sdk: flutter
''')
        env = dict(os.environ, CI='true', FLUTTER_SUPPRESS_ANALYTICS='true',
                   XDG_CONFIG_HOME=str(work / 'tool-config'), PUB_CACHE=str(a.pub_cache.resolve()),
                   LIFESPAN_SWEEP_OUT=str(a.out.resolve()), LIFESPAN_ENGINE_HEAD=a.head,
                   LIFESPAN_SSA_SOURCE=str(here / 'lifespan-sanity-ssa-2023.json'))
        cmd = [str(a.flutter.resolve()), '--suppress-analytics']
        subprocess.run([*cmd, 'pub', 'get', '--offline'], cwd=work, env=env, check=True)
        subprocess.run([*cmd, 'test', '--no-pub', 'test/sweep_test.dart', '--reporter', 'expanded'], cwd=work, env=env, check=True)
        version = subprocess.check_output([*cmd, '--version'], env=env, text=True).strip()
    data = json.loads(a.out.read_text())
    data['source_sha256'] = hashes
    data['sweep_sha256'] = hashlib.sha256((here / 'lifespan-sanity-sweep.dart').read_bytes()).hexdigest()
    data['ssa_snapshot_sha256'] = hashlib.sha256((here / 'lifespan-sanity-ssa-2023.json').read_bytes()).hexdigest()
    data['runner_version'] = version
    a.out.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
    columns = ['age', 'sex', 'profile', 'assessment_status', 'health_score_status', 'assessment_extrapolated',
               'app_summary_age', 'app_p25_age', 'app_p75_age', 'ssa_remaining_mean_years', 'ssa_attained_mean_age',
               'app_minus_ssa_attained_years', 'gap_is_lower_bound', 'app_above_ssa_by_over_8', 'absolute_gap_over_8',
               'pure_cdc_mean_age', 'pure_projection_status', 'pure_projection_median_age', 'summary_method',
               'projection_weight', 'app_status', 'app_extrapolated', 'app_median_crossing_extrapolated',
               'app_p25_open_ended', 'app_open_ended', 'app_p75_open_ended', 'five_year_survival_percent']
    with a.out.with_suffix('.csv').open('w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=columns, extrasaction='ignore', lineterminator='\n')
        writer.writeheader()
        writer.writerows(data['records'])
    print(f'Recorded actual app results and source hashes: {a.out}')


if __name__ == '__main__':
    main()
