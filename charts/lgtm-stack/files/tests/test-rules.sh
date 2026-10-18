#!/usr/bin/env bash
# promtool unit tests for the bundled PrometheusRules: the plain manifests, and the bundles rendered from alerting.rules
# with rules-values.yaml. Needs helm, yq and promtool (PROMTOOL overrides the binary).
set -euo pipefail
cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for rule in ../manifests/*-rules.yaml; do
  yq '.spec' "$rule" > "$tmp/$(basename "$rule")"
done
helm template t ../.. -f rules-values.yaml --set mode=addon --set addon=serviceRules | yq '.spec' > "$tmp/service-rules.yaml"
helm template t ../.. -f rules-values.yaml --set mode=addon --set addon=workloadRules | yq '.spec' > "$tmp/workload-rules.yaml"
cp ./*.test.yaml "$tmp/"
cd "$tmp"
# The only lint is duplicate-rules, and the services bundle repeats alert names on purpose: the default and each
# override select disjoint services
"${PROMTOOL:-promtool}" check rules --lint=none ./*-rules.yaml
"${PROMTOOL:-promtool}" test rules ./*.test.yaml
