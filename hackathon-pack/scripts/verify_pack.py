#!/usr/bin/env python3
"""Run the pack's local tests and verify local Markdown links. No network calls."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    checks = []
    skills = sorted(p.parent for p in (ROOT / 'skills').glob('*/SKILL.md'))
    expected = set(json.loads((ROOT / 'expected-skills.json').read_text()))
    actual = {p.name for p in skills}
    checks.append({'check': 'all_expected_skills_present', 'passed': expected == actual,
                   'missing': sorted(expected - actual), 'unexpected': sorted(actual - expected)})
    for skill in skills:
        content = (skill / 'SKILL.md').read_text()
        match = re.search(r'^name: (.+)$', content, re.M)
        if not match or match.group(1).strip() != skill.name:
            checks.append({'check': skill.name + ':entrypoint', 'passed': False})
        for file in skill.rglob('*.md'):
            for target in re.findall(r'(?<!!)\[[^\]]+\]\(([^)]+)\)', file.read_text()):
                target = target.split('#', 1)[0].strip('<>')
                if not target or re.match(r'\w+://|mailto:', target): continue
                path = file.parent / target
                checks.append({'check': str(file.relative_to(ROOT)) + ' → ' + target, 'passed': path.exists()})
        tests = sorted((skill / 'scripts').glob('test_*.py')) if (skill / 'scripts').is_dir() else []
        if tests:
            cmd = [sys.executable, '-m', 'unittest', 'discover', '-s', str(skill / 'scripts'), '-p', 'test_*.py', '-v']
            run = subprocess.run(cmd, capture_output=True, text=True, env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})
            checks.append({'check': skill.name + ':offline tests', 'passed': run.returncode == 0, 'output': run.stdout + run.stderr})
    design_test = ROOT / 'skills/creative-web-worlds/assets/pocket-market/basket.test.mjs'
    if design_test.exists():
        run = subprocess.run(['node', '--test', str(design_test)], capture_output=True, text=True)
        checks.append({'check': 'creative-web-worlds:basket tests', 'passed': run.returncode == 0, 'output': run.stdout + run.stderr})
    actor_test = ROOT / 'skills/apify-evidence-engine/assets/actor-template/extract.py'
    if actor_test.exists():
        run = subprocess.run([sys.executable, str(actor_test), '--self-test'], capture_output=True, text=True)
        checks.append({'check': 'apify-evidence-engine:Actor extraction', 'passed': run.returncode == 0, 'output': run.stdout + run.stderr})
    recall_test = ROOT / 'research/ideas/fixtures/recall_policy.py'
    if recall_test.exists():
        run = subprocess.run([sys.executable, str(recall_test)], capture_output=True, text=True)
        checks.append({'check': 'idea:financial-state fixtures', 'passed': run.returncode == 0, 'output': run.stdout + run.stderr})
    result = {'skills': [s.name for s in skills], 'allPassed': all(c['passed'] for c in checks),
              'scope': 'local tests and local links only; no live authenticated sponsor calls', 'checks': checks}
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'skills': len(skills), 'checks': len(checks), 'allPassed': result['allPassed'],
                      'failed': [c['check'] for c in checks if not c['passed']]}, indent=2))
    return 0 if result['allPassed'] else 1


if __name__ == '__main__': sys.exit(main())
