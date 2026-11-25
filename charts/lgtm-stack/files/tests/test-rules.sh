#!/usr/bin/env bash
# promtool unit tests for the bundled PrometheusRules: the plain manifests, and the bundles rendered from alerting.rules
# with rules-values.yaml. Needs helm, yq and promtool (PROMTOOL overrides the binary).
set -euo pipefail
cd "$(dirname "$0")"
here=$(pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for rule in ../manifests/*-rules.yaml; do
  if [[ "$rule" == ../manifests/stack-rules.yaml ]]; then continue; fi
  yq '.spec' "$rule" > "$tmp/$(basename "$rule")"
done
helm template t ../.. -f rules-values.yaml --set mode=addon --set addon=serviceRules | yq '.spec' > "$tmp/service-rules.yaml"
# Combine both PrometheusRule documents so promtool tests every stack rule group.
helm template t ../.. -f rules-values.yaml --set mode=addon --set addon=stackRules | yq ea '[select(.kind == "PrometheusRule") | .spec.groups[]] | {"groups": .}' > "$tmp/stack-rules.yaml"
helm template t ../.. -f rules-values.yaml --set mode=addon --set addon=workloadRules | yq '.spec' > "$tmp/workload-rules.yaml"
# dashboard-stats.test.yaml needs the rule file dashboard-stats.sh generates, so it runs there.
for test in ./*.test.yaml; do
  if [[ "$test" == ./dashboard-stats.test.yaml ]]; then continue; fi
  cp "$test" "$tmp/"
done
cd "$tmp"
# The only lint is duplicate-rules, and the services bundle repeats alert names on purpose: the default and each
# override select disjoint services
"${PROMTOOL:-promtool}" check rules --lint=none ./*-rules.yaml
"${PROMTOOL:-promtool}" test rules ./*.test.yaml
# CI runs only this script for rules, so it chains the dashboard stat tests.
"$here/dashboard-stats.sh"
