#!/usr/bin/env bash
# Checks the bundled dashboards: valid JSON, unique uids, and only the datasource uids the stack provisions. Needs jq.
set -euo pipefail
cd "$(dirname "$0")/../dashboards"
files=(*/*.json)
for f in "${files[@]}"; do
  jq -e '.uid and .title' "$f" > /dev/null || { echo "$f: invalid JSON or no uid/title"; exit 1; }
  bad=$(jq -r '[.. | objects | select(has("datasource")) | .datasource | objects | .uid]
    | unique - ["prometheus", "loki", "tempo", "alertmanager"] | .[]' "$f")
  [ -z "$bad" ] || { echo "$f: unknown datasource uid(s): $bad"; exit 1; }
done
dups=$(jq -r '.uid' "${files[@]}" | sort | uniq -d)
[ -z "$dups" ] || { echo "duplicate dashboard uid(s): $dups"; exit 1; }
echo "${#files[@]} dashboards OK"
