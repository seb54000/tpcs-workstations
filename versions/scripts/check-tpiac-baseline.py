#!/usr/bin/env python3
"""Read-only check of the Mele controller against the captured IaC baseline."""
import importlib.metadata
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
BASELINE = ROOT / 'versions/baselines/tpiac-2026-09-29'


def main():
    errors = []
    if sys.version_info[:3] != (3, 12, 3):
        errors.append(f'Python: expected 3.12.3, observed {sys.version.split()[0]}')
    for line in (BASELINE / 'controller-requirements.txt').read_text().splitlines():
        name, expected = line.split('==', 1)
        try:
            actual = importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            actual = 'missing'
        if actual != expected:
            errors.append(f'{name}: expected {expected}, observed {actual}')
    try:
        tf = json.loads(subprocess.check_output(['terraform', 'version', '-json'], text=True))
        if tf['terraform_version'] != '1.11.4':
            errors.append('Terraform differs from 1.11.4')
        aws = subprocess.check_output(['aws', '--version'], text=True)
        if not aws.startswith('aws-cli/2.36.45 '):
            errors.append('AWS CLI differs from 2.36.45')
        galaxy = str(Path(sys.executable).parent / 'ansible-galaxy')
        collections = json.loads(subprocess.check_output(
            [galaxy, 'collection', 'list', '--format', 'json'], text=True))
        observed = {}
        for location in collections.values():
            for name, data in location.items():
                observed.setdefault(name, data['version'])
        for name, expected in json.loads((BASELINE / 'controller-collections.json').read_text()).items():
            if observed.get(name) != expected:
                errors.append(f'Collection {name}: expected {expected}, observed {observed.get(name)}')
    except (OSError, subprocess.CalledProcessError, ValueError) as exc:
        errors.append(str(exc))
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    print('Mele controller matches the IaC baseline (read-only check).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
