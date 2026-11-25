#!/usr/bin/env bash
set -euo pipefail
if [ "$#" -ne 1 ]; then
  echo 'Usage: compat-test.sh <base-ref>' >&2
  exit 2
fi
cd "$(git rev-parse --show-toplevel)"
mkdir -p .compat-tmp
tmp=$(mktemp -d .compat-tmp/compat.XXXXXX)
trap 'rm -rf "$tmp"; rmdir .compat-tmp 2>/dev/null || true' EXIT
git archive "$1" charts/spartan-alerts | tar -x -C "$tmp"
chart=charts/spartan-alerts
base="$tmp/$chart"

project() {
  yq -o=json -I=0 '{"kind": .kind, "name": .metadata.name, "labels": [.spec.groups[]?.rules[]?.labels]}' "$1"
}

render_pair() {
  helm template compatibility "$base" --namespace example-dev -f "$1" > "$tmp/base.yaml"
  helm template compatibility "$chart" --namespace example-dev -f "$2" "${@:3}" > "$tmp/current.yaml"
  project "$tmp/base.yaml" > "$tmp/base.json"
  project "$tmp/current.yaml" > "$tmp/current.json"
}

count=0
for fixture in "$base"/files/tests/*values*.yaml; do
  [ -f "$fixture" ] || continue
  name=$(basename "$fixture")
  render_pair "$fixture" "$chart/files/tests/$name"
  diff -u "$tmp/base.json" "$tmp/current.json"
  echo "PASS existing fixture: $name"
  count=$((count + 1))
done
[ "$count" -gt 0 ] || { echo 'No base fixtures inspected' >&2; exit 1; }
render_pair "$chart/files/tests/tenant-envsubst-values.yaml" "$chart/files/tests/tenant-platform-values.yaml"
diff -u "$tmp/base.json" "$tmp/current.json"
echo 'PASS tenant envsubst vs platform'
render_pair "$chart/files/tests/tenant-envsubst-values.yaml" "$chart/files/tests/tenant-platform-values.yaml" --set service.name=service-renamed
if diff -u "$tmp/base.json" "$tmp/current.json" > "$tmp/rename.diff"; then
  echo 'FAIL rename negative control did not detect a difference' >&2
  exit 1
fi
[ -s "$tmp/rename.diff" ] || { echo 'FAIL rename diff is empty' >&2; exit 1; }
echo 'PASS rename negative control detected a difference'
