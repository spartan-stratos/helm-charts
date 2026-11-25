#!/usr/bin/env bash
# Checks the bundled dashboards: valid JSON, unique uids, and only the datasource uids the stack provisions. Needs jq.
set -euo pipefail
cd "$(dirname "$0")/../dashboards"
files=(*/*.json)
for f in "${files[@]}"; do
  jq -e '.uid and .title' "$f" > /dev/null || { echo "$f: invalid JSON or no uid/title"; exit 1; }
  jq -e '[.. | objects | select(has("gridPos")) | .id] | length == (unique | length)' "$f" > /dev/null || { echo "$f: duplicate panel id"; exit 1; }
  jq -e '
    [.. | objects | select(has("gridPos")) | .gridPos] as $panels
    | all(range(0; $panels | length); . as $i
        | all(range($i + 1; $panels | length); . as $j
            | $panels[$i] as $a | $panels[$j] as $b
            | ($a.x >= $b.x + $b.w or $b.x >= $a.x + $a.w
               or $a.y >= $b.y + $b.h or $b.y >= $a.y + $a.h)))
  ' "$f" > /dev/null || { echo "$f: overlapping panel gridPos"; exit 1; }
  if [ "$f" = "LGTM/lgtm-self-monitoring.json" ]; then
    jq -e 'all(.. | objects | select(.type? == "stat") | .targets[]; .instant == true and ((.expr | contains("$__rate_interval")) | not))' "$f" > /dev/null || { echo "$f: stat target is not instant or uses a variable rate interval"; exit 1; }
  fi
  bad=$(jq -r '[.. | objects | select(has("datasource")) | .datasource | objects | .uid]
    | unique - ["prometheus", "loki", "tempo", "alertmanager"] | .[]' "$f")
  [ -z "$bad" ] || { echo "$f: unknown datasource uid(s): $bad"; exit 1; }
done
dups=$(jq -r '.uid' "${files[@]}" | sort | uniq -d)
[ -z "$dups" ] || { echo "duplicate dashboard uid(s): $dups"; exit 1; }
echo "${#files[@]} dashboards OK"
