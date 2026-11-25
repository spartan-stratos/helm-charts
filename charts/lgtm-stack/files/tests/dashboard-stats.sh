#!/usr/bin/env bash
# promtool unit tests for the LGTM self-monitoring stat panels: every stat target expr is extracted from the dashboard
# into a generated rule file (record: dashboard_stat_<panelId>_<refId>) and tested against dashboard-stats.test.yaml,
# including the absent-series paths. Needs jq and promtool (PROMTOOL overrides the binary).
set -euo pipefail
cd "$(dirname "$0")"
dash="${DASHBOARD:-../dashboards/LGTM/lgtm-self-monitoring.json}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Stat exprs are untemplated today; the sub strips a Grafana variable if one is ever added (a rate interval becomes 5m).
jq '{groups: [{name: "dashboard-stats", rules: [.. | objects | select(.type? == "stat") | .id as $id | .targets[]
  | {record: "dashboard_stat_\($id)_\(.refId)", expr: (.expr | gsub("\\$__rate_interval|\\$__interval"; "5m"))}]}]}' "$dash" > "$tmp/dashboard-stats-rules.yaml"
panels=$(jq '[.. | objects | select(.type? == "stat") | .id] | unique | length' "$dash")
# Every stat panel needs at least one test case referencing one of its generated records.
for id in $(jq -r '[.. | objects | select(.type? == "stat") | .id] | unique | .[]' "$dash"); do
  grep -q "dashboard_stat_${id}_" dashboard-stats.test.yaml || { echo "stat panel $id has no test case"; exit 1; }
done
cp dashboard-stats.test.yaml "$tmp/"
cd "$tmp"
"${PROMTOOL:-promtool}" check rules --lint=none dashboard-stats-rules.yaml
"${PROMTOOL:-promtool}" test rules dashboard-stats.test.yaml
echo "$panels stat panels tested"
