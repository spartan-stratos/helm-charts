#!/usr/bin/env bash
set -euo pipefail
base=${1:?Base revision required}
python3 - "$base" <<'PY'
import subprocess
import sys
import yaml

base = sys.argv[1]
paths = subprocess.check_output(['git', 'diff', '--name-only', base, 'HEAD'], text=True).splitlines()
if any(path.startswith('.github/scripts/spartan-alerts/') for path in paths):
    path = 'charts/spartan-alerts/Chart.yaml'
    old = yaml.safe_load(subprocess.check_output(['git', 'show', f'{base}:{path}'], text=True))
    with open(path) as source:
        new = yaml.safe_load(source)
    if old['version'] == new['version']:
        sys.exit('Shipped checker changes require a spartan-alerts chart version bump')
print('chart bump check ok')
PY
