#!/usr/bin/env bash
set -euo pipefail
chart=''
namespace=''
release=alerts
tests=''
values=()
value_files=()
services=()
negative_controls=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --chart-dir) chart=$2; shift 2 ;;
    --values-file) values+=(-f "$2"); value_files+=("$2"); shift 2 ;;
    --values-files) while IFS= read -r value; do [[ -z "$value" ]] || { values+=(-f "$value"); value_files+=("$value"); }; done <<< "$2"; shift 2 ;;
    --namespace) namespace=$2; shift 2 ;;
    --release-name) release=$2; shift 2 ;;
    --service-name) services+=(--service-name "$2"); shift 2 ;;
    --service-names) while IFS= read -r service; do [[ -z "$service" ]] || services+=(--service-name "$service"); done <<< "$2"; shift 2 ;;
    --tests-file) tests=$2; shift 2 ;;
    --set-string) values+=(--set-string "$2"); shift 2 ;;
    --negative-controls) negative_controls=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done
[[ -n "$chart" && -n "$namespace" ]] || { echo 'Required: --chart-dir and --namespace' >&2; exit 1; }
here=$(cd "$(dirname "$0")" && pwd -P)
chart=$(cd "$chart" && pwd -P)
checkout=$(git -C "$here" rev-parse --show-toplevel)
[[ "$chart" == "$checkout/"* ]] || { echo 'Chart must be from the script checkout' >&2; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if [[ "$negative_controls" == true ]]; then
  python3 - "$here/check.sh" "$chart" "$namespace" "$release" <<'PY'
from pathlib import Path
import subprocess
import sys

script, chart, namespace, release = sys.argv[1:]
fixtures = sorted((Path(chart) / 'files/tests/negative').glob('*.yaml'))
if not fixtures:
    sys.exit('No negative controls found')
for fixture in fixtures:
    result = subprocess.run(['bash', script, '--chart-dir', chart, '--namespace', namespace,
                             '--service-name', 'service',
                             '--release-name', release, '--values-file', str(fixture)],
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(result.stdout, end='')
    if result.returncode != 1 or 'UNPINNED:' not in result.stdout:
        sys.exit(f'Negative control did not fail with UNPINNED: {fixture}')
print('negative controls ok')
PY
  exit 0
fi
helm template "$release" "$chart" --namespace "$namespace" "${values[@]}" > "$tmp/rendered.yaml"
# Merge in Helm values-file order, including defaults, before deriving release pins.
yq eval-all '. as $item ireduce ({}; . * $item)' "$chart/values.yaml" "${value_files[@]}" > "$tmp/values.yaml"
while IFS= read -r service; do
  [[ -n "$service" ]] || continue
  present=false
  for existing in "${services[@]}"; do
    [[ "$existing" != "$service" ]] || present=true
  done
  [[ "$present" == true ]] || services+=(--service-name "$service")
done < <(yq -r '[.service.name, .catalogue.serviceName] | .[] | select(. != null and . != "")' "$tmp/values.yaml")
python3 "$here/check-rendered.py" --namespace "$namespace" "${services[@]}" "$tmp/rendered.yaml"
# All documents contribute groups so a second PrometheusRule cannot escape promtool.
yq ea '[select(.kind == "PrometheusRule") | .spec.groups[]] | {"groups": .}' "$tmp/rendered.yaml" > "$tmp/catalogue-rules.yaml"
"${PROMTOOL:-promtool}" check rules "$tmp/catalogue-rules.yaml"
if [[ -n "$tests" ]]; then
  # Tests must read the merged rules rather than a caller-relative rule path.
  yq '.rule_files = ["catalogue-rules.yaml"]' "$tests" > "$tmp/rules.test.yaml"
  (cd "$tmp" && "${PROMTOOL:-promtool}" test rules rules.test.yaml)
fi
