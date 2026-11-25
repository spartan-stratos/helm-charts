#!/usr/bin/env bash
# Catalogue-only variant of lgtm-stack's render, extract, check and test harness.
# Deliberate differences: one template, explicit filenames, and default duplicate-rule lint.
# Needs helm, yq and promtool (PROMTOOL overrides the binary).
set -euo pipefail
cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
helm template t ../.. -f catalogue-values.yaml -s templates/catalogue-rules.yaml | yq '.spec' > "$tmp/catalogue-rules.yaml"
helm template t ../.. -f catalogue-workloads-values.yaml -s templates/catalogue-rules.yaml | yq '.spec' > "$tmp/catalogue-workloads-rules.yaml"
yq '.tests |= map(select(.name | test("^Workloads ") | not))' catalogue-rules.test.yaml > "$tmp/catalogue-rules.test.yaml"
yq '.rule_files = ["catalogue-workloads-rules.yaml"] | .tests |= map(select(.name | test("^Workloads ")))' catalogue-rules.test.yaml > "$tmp/catalogue-workloads-rules.test.yaml"
cd "$tmp"
"${PROMTOOL:-promtool}" check rules catalogue-rules.yaml
"${PROMTOOL:-promtool}" check rules catalogue-workloads-rules.yaml
"${PROMTOOL:-promtool}" test rules catalogue-rules.test.yaml
"${PROMTOOL:-promtool}" test rules catalogue-workloads-rules.test.yaml
