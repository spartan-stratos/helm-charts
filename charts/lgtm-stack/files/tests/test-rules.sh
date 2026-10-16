#!/usr/bin/env bash
# promtool unit tests for the bundled PrometheusRules. Needs yq and promtool (PROMTOOL overrides the binary).
set -euo pipefail
cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for rule in ../manifests/*-rules.yaml; do
  yq '.spec' "$rule" > "$tmp/$(basename "$rule")"
done
cp ./*.test.yaml "$tmp/"
cd "$tmp"
"${PROMTOOL:-promtool}" check rules ./*-rules.yaml
"${PROMTOOL:-promtool}" test rules ./*.test.yaml
