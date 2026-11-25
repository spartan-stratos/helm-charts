#!/usr/bin/env bash
# Catalogue-only variant of lgtm-stack's render, extract, check and test harness.
# Deliberate differences: one template, explicit filenames, and default duplicate-rule lint.
# Needs helm, yq and promtool (PROMTOOL overrides the binary).
set -euo pipefail
cd "$(dirname "$0")"
root=$(git rev-parse --show-toplevel)
mkdir -p "$root/.compat-tmp"
tmp=$(mktemp -d "$root/.compat-tmp/rules.XXXXXX")
trap 'rm -rf "$tmp"; rmdir "$root/.compat-tmp" 2>/dev/null || true' EXIT
helm template t ../.. -f catalogue-values.yaml -s templates/catalogue-rules.yaml | yq '.spec' > "$tmp/catalogue-rules.yaml"
helm template t ../.. -f catalogue-workloads-values.yaml -s templates/catalogue-rules.yaml | yq '.spec' > "$tmp/catalogue-workloads-rules.yaml"
yq '.tests |= map(select(.name | test("^Workloads ") | not))' catalogue-rules.test.yaml > "$tmp/catalogue-rules.test.yaml"
yq '.rule_files = ["catalogue-workloads-rules.yaml"] | .tests |= map(select(.name | test("^Workloads ")))' catalogue-rules.test.yaml > "$tmp/catalogue-workloads-rules.test.yaml"
helm template t ../.. -f rds-derived-values.yaml -s templates/catalogue-rules.yaml | yq '.spec' > "$tmp/rds-derived-rules.yaml"
cp rds-derived-rules.test.yaml "$tmp/rds-derived-rules.test.yaml"
cd "$tmp"
"${PROMTOOL:-promtool}" check rules catalogue-rules.yaml
"${PROMTOOL:-promtool}" check rules catalogue-workloads-rules.yaml
"${PROMTOOL:-promtool}" test rules catalogue-rules.test.yaml
"${PROMTOOL:-promtool}" test rules catalogue-workloads-rules.test.yaml
"${PROMTOOL:-promtool}" check rules rds-derived-rules.yaml
"${PROMTOOL:-promtool}" test rules rds-derived-rules.test.yaml
