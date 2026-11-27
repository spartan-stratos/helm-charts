#!/usr/bin/env bash
# Exercise generated identity processing without exposing ports or using live telemetry.
set -euo pipefail
umask 077
here=$(cd "$(dirname "$0")" && pwd)
chart=$(cd "$here/../.." && pwd)
stage=dependencies
fail() { printf 'ECS receiver runtime failed: %s\n' "$*" >&2; exit 1; }
preflight_only=false
if [[ ${1:-} == --preflight-only ]]; then preflight_only=true; shift; fi
(( $# == 0 )) || fail 'usage: test-ecs-receiver.sh [--preflight-only]'
for tool in helm python3; do command -v "$tool" >/dev/null || fail "missing $tool"; done
python3 -c 'import yaml' || fail 'host Python requires PyYAML'
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ecs-receiver.XXXXXXXX")
docker_ready=false
nonce=$(basename "$tmp")
driver=$nonce-driver
alloy=$nonce-alloy
prom=$nonce-prometheus
cleanup() {
  run_exit=$?
  trap - EXIT
  if (( run_exit != 0 )); then
    printf 'ECS receiver runtime failure stage: %s\n' "$stage" >&2
    for container in "$driver" "$alloy" "$prom"; do
      $docker_ready || break
      if [[ $(docker inspect --format '{{index .Config.Labels "ecs-receiver-test"}}' "$container" 2>/dev/null || true) == "$nonce" ]]; then
        docker logs --tail 40 "$container" >&2 || true
      fi
    done
  fi
  for container in "$alloy" "$prom" "$driver"; do
    $docker_ready || break
    if [[ $(docker inspect --format '{{index .Config.Labels "ecs-receiver-test"}}' "$container" 2>/dev/null || true) == "$nonce" ]]; then
      docker rm -fv "$container" >/dev/null || run_exit=1
    fi
  done
  rm -rf -- "$tmp"
  exit "$run_exit"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
alloy_image=docker.io/grafana/alloy:v1.20.0
prom_image=docker.io/prom/prometheus:v3.15.0
driver_image=docker.io/library/python:3.13.2-slim
stage=render
helm template ecs-runtime "$chart" -f "$here/ecs-receiver-values.yaml" > "$tmp/rendered.yaml"
python3 - "$tmp" <<'PY'
import base64, copy, hashlib, pathlib, re, sys, yaml
directory = pathlib.Path(sys.argv[1])
documents = list(yaml.safe_load_all((directory / 'rendered.yaml').read_text()))
prom_application, = [d for d in documents if d and d.get('spec', {}).get('source', {}).get('chart') == 'kube-prometheus-stack']
prom = {'global': {'scrape_interval': '1s'}, 'scrape_configs': [], 'otlp': {
    'translation_strategy': 'UnderscoreEscapingWithSuffixes',
    'promote_resource_attributes': ['service.name', 'service.namespace', 'deployment.environment.name',
                                    'k8s.namespace.name', 'k8s.pod.name', 'team', 'tenant']}}
def validate_prometheus(application):
    spec = application['spec']['source']['helm']['valuesObject']['prometheus']['prometheusSpec']
    assert type(spec.get('enableOTLPReceiver')) is bool and spec['enableOTLPReceiver'] is True, 'OTLP receiver must be enabled'
    otlp = spec.get('otlp')
    assert type(otlp) is dict, 'missing rendered Prometheus OTLP settings'
    strategy = otlp.get('translationStrategy')
    assert type(strategy) is str and strategy == prom['otlp']['translation_strategy'], 'OTLP translation differs from harness'
    promoted = otlp.get('promoteResourceAttributes')
    assert type(promoted) is list and all(type(item) is str for item in promoted), 'OTLP promoted attributes must be a string list'
    assert promoted == prom['otlp']['promote_resource_attributes'], 'OTLP promoted attributes differ from harness'
    tsdb = spec.get('tsdb', {})
    assert type(tsdb) is dict, 'rendered TSDB settings must be an object'
    window = tsdb.get('outOfOrderTimeWindow', '0s')
    assert type(window) is str and window == '0s', 'harness requires default zero out-of-order window'
validate_prometheus(prom_application)
# Mutate the actual rendered Application, not a parallel mock of the preset.
mutations = [
    ('disabled OTLP', ('enableOTLPReceiver',), False),
    ('string OTLP flag', ('enableOTLPReceiver',), 'true'),
    ('missing OTLP settings', ('otlp',), None),
    ('different translation', ('otlp', 'translationStrategy'), 'NoTranslation'),
    ('non-list attributes', ('otlp', 'promoteResourceAttributes'), 'tenant'),
    ('different attributes', ('otlp', 'promoteResourceAttributes'), ['tenant']),
    ('non-string attribute', ('otlp', 'promoteResourceAttributes'), [7]),
    ('nonzero ordering window', ('tsdb',), {'outOfOrderTimeWindow': '1s'}),
]
for label, path, value in mutations:
    changed = copy.deepcopy(prom_application)
    parent = changed['spec']['source']['helm']['valuesObject']['prometheus']['prometheusSpec']
    for key in path[:-1]:
        parent = parent[key]
    parent[path[-1]] = value
    try:
        validate_prometheus(changed)
    except AssertionError:
        continue
    raise AssertionError(f'Prometheus preflight accepted {label}')
print(f'Prometheus rendered preflight passed; {len(mutations)} mismatch controls rejected')
gateway, = [d for d in documents if d and d.get('metadata', {}).get('name') == 'lgtm-alloy-gateway']
original = gateway['spec']['source']['helm']['valuesObject']['alloy']['configMap']['content']
text = original
def replace(old, new, count):
    global text
    assert text.count(old) == count, ('unexpected transport shape', old)
    text = text.replace(old, new)
replace('http://loki.monitoring.svc.cluster.local:3100/otlp', 'http://127.0.0.1:18080/loki', 3)
replace('http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090/api/v1/otlp', 'http://127.0.0.1:18081/api/v1/otlp', 3)
replace('tempo.monitoring.svc.cluster.local:4317', 'http://127.0.0.1:18080/tempo', 3)
replace('otelcol.exporter.otlp.tempo_', 'otelcol.exporter.otlphttp.tempo_', 3)
replace('otelcol.exporter.otlp "tempo_', 'otelcol.exporter.otlphttp "tempo_', 3)
tls = '    tls {\n      insecure = true\n    }\n'
replace(tls, '', 3)
text, count = re.subn(r'(?m)^otelcol\.exporter\.otlphttp "(?:loki|tempo)_[0-9]+" \{$', r'\g<0>\n  encoding = "json"', text)
assert count == 6
def logic(content):
    content = re.sub(r'(?ms)^otelcol\.exporter\.[^\n]+\{.*?^\}\n?', '', content)
    return content.replace('otelcol.exporter.otlphttp.tempo_', 'otelcol.exporter.otlp.tempo_')
assert logic(original) == logic(text), 'identity processing changed'
headers = r'(?m)^\s*headers = \{ "X-Scope-OrgID" = "[^"\n]+" \}$'
original_headers, rewritten_headers = [re.findall(headers, content) for content in (original, text)]
assert len(original_headers) == len(rewritten_headers) == 9
for content in (original, text):
    captured = re.findall(r'(?ms)^otelcol\.exporter\.(?:otlp|otlphttp) "(?:loki|tempo)_[0-9]+" \{.*?^\}', content)
    assert len(captured) == 6 and all(len(re.findall(headers, block)) == 1 for block in captured)
assert original_headers == rewritten_headers
(directory / 'config.alloy').write_text(text)
(directory / 'prometheus.yaml').write_text(yaml.safe_dump(prom))
for index, lane in enumerate(('alpha', 'beta', 'legacy')):
    digest = base64.b64encode(hashlib.sha1(f'public-{lane}'.encode()).digest()).decode()
    (directory / f'auth-{index}').write_text(f'{lane}:{{SHA}}{digest}\n')
for item in directory.iterdir():
    item.chmod(0o644)
(directory / 'results').mkdir()
PY
if $preflight_only; then stage=preflight-complete; exit 0; fi
stage=docker-dependencies
command -v docker >/dev/null || fail 'missing docker'
docker_endpoint=${DOCKER_HOST:-$(docker context inspect --format '{{(index .Endpoints "docker").Host}}')}
[[ $docker_endpoint == unix://* ]] || fail 'a local Docker Unix socket is required'
docker_ready=true
stage=images
for image in "$alloy_image" "$prom_image" "$driver_image"; do
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    python3 - "$image" <<'PY'
import subprocess, sys
subprocess.run(['docker', 'pull', sys.argv[1]], check=True, timeout=180)
PY
  fi
done
common=(--label "ecs-receiver-test=$nonce" --user "$(id -u):$(id -g)" --cap-drop ALL
  --security-opt no-new-privileges --read-only --tmpfs '/tmp:rw,mode=1777')
stage='driver-start'
docker run -d --name "$driver" "${common[@]}" --network none -e PYTHONDONTWRITEBYTECODE=1 \
  --mount "type=bind,src=$here/ecs-receiver-runtime.py,dst=/fixtures/ecs-receiver-runtime.py,readonly" \
  --mount "type=bind,src=$here/ecs-receiver-fixtures.py,dst=/fixtures/ecs-receiver-fixtures.py,readonly" \
  --mount "type=bind,src=$tmp/results,dst=/results" \
  "$driver_image" python /fixtures/ecs-receiver-runtime.py >/dev/null
stage='prometheus-start'
docker run -d --name "$prom" "${common[@]}" --network "container:$driver" \
  --tmpfs /prometheus:rw,mode=1777 \
  --mount "type=bind,src=$tmp/prometheus.yaml,dst=/etc/prometheus/test.yaml,readonly" \
  "$prom_image" --config.file=/etc/prometheus/test.yaml --storage.tsdb.path=/prometheus \
  --web.listen-address=127.0.0.1:9090 --web.enable-otlp-receiver >/dev/null
auth_mounts=()
for index in 0 1 2; do
  auth_mounts+=(--mount "type=bind,src=$tmp/auth-$index,dst=/etc/alloy/tenants/$index/htpasswd,readonly")
done
stage='alloy-start'
docker run -d --name "$alloy" "${common[@]}" --network "container:$driver" \
  --mount "type=bind,src=$tmp/config.alloy,dst=/etc/alloy/test.alloy,readonly" "${auth_mounts[@]}" \
  "$alloy_image" run --server.http.listen-addr=127.0.0.1:12345 --storage.path=/tmp/alloy \
  /etc/alloy/test.alloy >/dev/null
stage=requests
deadline=$((SECONDS + 240))
until [[ -f $tmp/results/drain-requested ]]; do
  [[ $(docker inspect --format '{{.State.Running}}' "$driver") == true ]] || fail 'driver exited before drain request'
  [[ $(docker inspect --format '{{.State.Running}}' "$alloy") == true ]] || fail 'Alloy exited before drain request'
  [[ $(docker inspect --format '{{.State.Running}}' "$prom") == true ]] || fail 'Prometheus exited before drain request'
  (( SECONDS < deadline )) || fail 'request deadline exceeded'
  sleep 0.2
done
stage='alloy-graceful-drain'
docker stop --time 30 "$alloy" >/dev/null
[[ $(docker inspect --format '{{.State.ExitCode}} {{.State.OOMKilled}} {{.State.Running}}' "$alloy") == '0 false false' ]] \
  || fail 'Alloy did not exit gracefully with code0'
touch "$tmp/results/alloy-stopped"
stage='driver-verdict'
deadline=$((SECONDS + 90))
while [[ $(docker inspect --format '{{.State.Running}}' "$driver") == true ]]; do
  (( SECONDS < deadline )) || fail 'driver verdict deadline exceeded'
  sleep 0.2
done
[[ $(docker inspect --format '{{.State.ExitCode}}' "$driver") == 0 ]] || fail 'driver assertions failed'
python3 - "$tmp/results/result.json" <<'PY'
import json, pathlib, sys
result = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert result['status'] == 'passed' and result['drained'] is True
print('ECS receiver runtime: ' + json.dumps(result, sort_keys=True))
PY
stage=complete
