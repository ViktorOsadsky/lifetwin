#!/usr/bin/env python3
"""Copy new pack skills into an agent skills folder; never overwrite existing skills."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]


def files(path):
    return {str(p.relative_to(path)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in path.rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix != '.pyc'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, default=Path(os.environ.get('CODEX_HOME') or str(Path.home() / '.codex')) / 'skills')
    parser.add_argument('--apply', action='store_true', help='Actually copy; default only prints plan')
    args = parser.parse_args()
    source = ROOT / 'skills'
    plan = []
    for skill in sorted(source.iterdir()):
        if not skill.is_dir() or not (skill / 'SKILL.md').is_file(): continue
        if skill.is_symlink() or not re.fullmatch('[a-z0-9]+(?:-[a-z0-9]+)*', skill.name):
            raise SystemExit('Unsafe skill source: ' + str(skill))
        if any(p.is_symlink() for p in skill.rglob('*')): raise SystemExit('Symlink in skill: ' + str(skill))
        dest = args.destination / skill.name
        if dest.is_symlink(): raise SystemExit('Refusing symbolic-link destination: ' + str(dest))
        if dest.exists():
            if not dest.is_dir() or files(dest) != files(skill):
                raise SystemExit('Refusing to overwrite existing different skill: ' + str(dest))
            action = 'identical-skip'
        else: action = 'copy-new'
        plan.append((skill, dest, action))
    # Preflight every destination before any copy. An apply failure never deletes existing files.
    if args.apply:
        args.destination.mkdir(parents=True, exist_ok=True)
        for src, dest, action in plan:
            if action == 'copy-new':
                shutil.copytree(src, dest, ignore=shutil.ignore_patterns('__pycache__', '*.pyc', '.DS_Store'))
    print(json.dumps({'applied': args.apply, 'skills': [{'name': src.name, 'destination': str(dest), 'action': action} for src, dest, action in plan]}, indent=2))


if __name__ == '__main__': main()
