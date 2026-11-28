"""Assert generated receiver behavior against isolated Alloy and Prometheus."""
import base64
import json
import pathlib
import runpy
import threading
import time
import traceback
import urllib.error
import urllib.parse
import urllib.request

F = runpy.run_path(str(pathlib.Path(__file__).with_name('ecs-receiver-fixtures.py')))
SIGNALS = ('metrics', 'logs', 'traces')
FORBIDDEN = {'namespace', 'service_namespace', 'k8s_namespace_name', 'team', 'custom_fixture', 'url_path'}

def request(url, payload=None, headers=None):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def wait_for(check, seconds=90):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            if check():
                return
        except (OSError, ValueError, KeyError):
            pass
        time.sleep(0.1)
    raise AssertionError('bounded readiness/drain wait expired')


def attrs(items):
    return {item['key']: next(iter(item['value'].values())) for item in items}

def query(expression):
    code, body = request('http://127.0.0.1:9090/api/v1/query?' + urllib.parse.urlencode({'query': expression}))
    result = json.loads(body)
    assert code == 200 and result['status'] == 'success'
    return result['data']['result']


def check_labels(labels, lane, service, task, raw=False):
    if raw:
        assert labels['tenant'] == lane and labels['env'] == 'dev'
        assert labels['service.name'] == service and labels['service.instance.id'] == task
        assert labels['deployment.environment'] == labels['deployment.environment.name'] == 'dev'
        account, cluster, _ = F['LANES'][lane]
        assert labels['cloud.account.id'] == account
        assert labels['aws.ecs.cluster.arn'] == f'arn:aws:ecs:us-west-2:{account}:cluster/{cluster}'
        assert labels['aws.ecs.task.arn'] == task
        assert set(labels) == set(F['IDENTITY']) | {'tenant', 'env', 'deployment.environment', 'deployment.environment.name', 'service.instance.id'}
    else:
        assert labels['tenant'] == lane and labels['env'] == 'dev'
        assert labels['service_name'] == labels['job'] == service and labels['instance'] == task
        assert not FORBIDDEN.intersection(labels)
        assert 'forged' not in labels.values() and 'other' not in labels.values()


def check_signal_attrs(signal, actual, lane, expected_path=None):
    allowed = {'tenant', 'env', 'deployment.environment', 'deployment.environment.name',
               'http.request.method', 'http.response.status_code', 'http.route',
               'jvm.memory.type', 'jvm.memory.pool.name', 'db.system.name'}
    if signal == 'traces':
        allowed.add('url.path')
        assert actual.get('url.path') == expected_path, ('trace url.path not preserved', expected_path, actual.get('url.path'))
    assert set(actual) == allowed
    assert actual['tenant'] == lane and actual['env'] == 'dev'


def run(results):
    results.mkdir(parents=True, exist_ok=True)
    sink = F['make_sink'](18080)
    threading.Thread(target=sink.serve_forever, daemon=True).start()
    proxy = F['make_prom_proxy'](18081)
    threading.Thread(target=proxy.serve_forever, daemon=True).start()
    expected, required, negative, trace_paths = {}, set(), set(), {}
    counter = 0
    def send(signal, lane, payload, serial, keep, required_record=True, auth=None, caller_tenant=None):
        nonlocal counter
        counter += 1
        token = base64.b64encode(f'{auth or lane}:public-{auth or lane}'.encode()).decode()
        headers = {'Content-Type': 'application/json', 'Authorization': 'Basic ' + token}
        if caller_tenant:
            headers['X-Scope-OrgID'] = caller_tenant
        port = {'alpha': 14320, 'beta': 14321, 'legacy': 14322}[lane]
        code, _ = request(f'http://127.0.0.1:{port}/{lane}/v1/{signal}', payload, headers)
        if auth:
            assert code == 401, (signal, lane, code)
            negative.add((signal, serial))
            return
        assert code == 200 if keep and required_record else code in (200, 400, 500), (signal, lane, code)
        if keep:
            record = next(iter(payload.values()))[0]
            resource = attrs(record['resource']['attributes'])
            expected.setdefault((signal, serial), []).append((lane, resource))
            if signal == 'traces':
                trace_paths[serial] = attrs(record['scopeSpans'][0]['spans'][0]['attributes'])['url.path']
            if required_record:
                required.add((signal, serial))
        else:
            negative.add((signal, serial))
    wait_for(lambda: request('http://127.0.0.1:12345/-/ready')[0] == 200)
    wait_for(lambda: request('http://127.0.0.1:9090/-/ready')[0] == 200)
    serial = 0
    for lane in F['LANES']:
        for signal in SIGNALS:
            for case, verdict in F['CASES'].items():
                serial += 1
                send(signal, lane, F['make_payload'](signal, case, lane, serial=serial), serial, verdict == 'keep')
            serial += 1
            send(signal, lane, F['make_payload'](signal, lane=lane, serial=serial), serial, True, caller_tenant='forged')
            serial += 1
            send(signal, lane, F['make_payload'](signal, lane=lane, serial=serial), serial, False, auth='beta' if lane == 'alpha' else 'alpha')
            serial += 1
            foreign = 'beta' if lane == 'alpha' else 'alpha'
            send(signal, lane, F['make_payload'](signal, lane=foreign, serial=serial), serial, False)
            serial += 1
            mixed = F['mixed_payload'](signal, ['valid', 'wrong:service.name', 'type:cloud.account.id'], lane, serial)
            good = F['make_payload'](signal, lane=lane, serial=serial)
            send(signal, lane, mixed, serial, True, required_record=False)
            expected[(signal, serial)] = [(lane, attrs(next(iter(good.values()))[0]['resource']['attributes']))]
            negative.update({(signal, serial + 1), (signal, serial + 2)})
            serial += 2
    for signal in SIGNALS:
        serial += 1
        send(signal, 'legacy', F['make_payload'](signal, lane='legacy', serial=serial), serial, True)
    start = str(F['SAMPLE_BASE_NS'] - 5000000000)
    for phase in (0, 1):
        for task in (0, 1):
            payload = F['make_payload']('metrics', task=task, serial=900001)
            for metric in payload['resourceMetrics'][0]['scopeMetrics'][0]['metrics']:
                points = metric['sum']['dataPoints'] if 'sum' in metric else metric['gauge']['dataPoints']
                points[0].update(startTimeUnixNano=start, asDouble=(task + 1) * 100 + phase * (task + 1) * 10 if 'sum' in metric else (task + 1) * 10 + phase * (task + 1))
            send('metrics', 'alpha', payload, 900001, True)
    for signal in SIGNALS:
        serial += 1
        send(signal, 'alpha', F['make_payload'](signal, serial=serial), serial, True)
    (results / 'drain-requested').touch()
    wait_for(lambda: (results / 'alloy-stopped').exists(), seconds=300)
    feedback = {'non_2xx_count': proxy.non_2xx_count, 'errors': proxy.errors,
                'concurrent_alpha_observed': proxy.concurrent_alpha_observed}
    (results / 'prometheus-feedback.json').write_text(json.dumps(feedback))
    assert not proxy.non_2xx_count, ('real Prometheus rejected OTLP', feedback)
    assert not proxy.concurrent_alpha_observed, ('alpha metrics requests were concurrent', feedback)
    seen = set()
    for captured in sink.records:
        body = captured['body']
        signal = 'logs' if 'resourceLogs' in body else 'traces'
        resource_key, scope_key, item_key = ('resourceLogs', 'scopeLogs', 'logRecords') if signal == 'logs' else ('resourceSpans', 'scopeSpans', 'spans')
        for resource in body[resource_key]:
            rattrs = attrs(resource['resource'].get('attributes', []))
            for scope in resource[scope_key]:
                for item in scope[item_key]:
                    identity = int((item['body']['stringValue'] if signal == 'logs' else item['name']).rsplit('-', 1)[1])
                    key = (signal, identity)
                    assert key in expected and key not in negative, ('unexpected sink record', key)
                    lane, original = expected[key][0]
                    assert captured['tenant'] == lane
                    if lane != 'legacy':
                        check_labels(rattrs, lane, original['service.name'], original['aws.ecs.task.arn'], raw=True)
                        assert not scope.get('scope', {}).get('attributes')
                        check_signal_attrs(signal, attrs(item.get('attributes', [])), lane, trace_paths.get(identity))
                    else:
                        assert rattrs['tenant'] == 'legacy' and rattrs['k8s.namespace.name'] == 'example-legacy'
                    seen.add(key)
    samples = query('{__name__=~"fixture_(counter|gauge)_.*"}')
    instances = {'gauge': {}, 'counter': {}}
    for sample in samples:
        labels = sample['metric']
        name = labels['__name__'].removesuffix('_total')
        identity = int(name.rsplit('_', 1)[1])
        key = ('metrics', identity)
        assert key in expected and key not in negative, ('unexpected metric', key)
        lane, original = next((lane, original) for lane, original in expected[key] if lane == 'legacy' or original['aws.ecs.task.arn'] == labels['instance'])
        if lane != 'legacy':
            check_labels(labels, lane, original['service.name'], original['aws.ecs.task.arn'])
            assert labels['http_request_method'] == 'GET' and labels['http_response_status_code'] == '200' and labels['jvm_memory_type'] == 'heap'
            assert labels['jvm_memory_pool_name'] == 'fixture-pool'
        if identity == 900001:
            instances['gauge' if 'gauge' in name else 'counter'][labels['instance']] = float(sample['value'][1])
        seen.add(key)
    assert required <= seen, ('missing positives', sorted(required - seen))
    assert sorted(instances['gauge'].values()) == [11, 22] and sorted(instances['counter'].values()) == [110, 220]
    infos = query('target_info')
    for lane in F['LANES']:
        account, cluster, service = F['LANES'][lane]
        rows = [row['metric'] for row in infos if row['metric'].get('job') == service]
        assert rows
        for labels in rows:
            assert labels['cloud_account_id'] == account
            assert labels['aws_ecs_cluster_arn'] == f'arn:aws:ecs:us-west-2:{account}:cluster/{cluster}'
            assert labels['aws_ecs_task_arn'] == labels['instance']
            assert not FORBIDDEN.intersection(labels) and 'forged' not in labels.values() and 'other' not in labels.values()
    sink.shutdown()
    proxy.shutdown()
    return {'status': 'passed', 'requests': counter, 'required_positive_ids': len(required), 'seen_ids': len(seen), 'negative_ids': len(negative), 'drained': True, 'trace_paths_preserved': True, 'tempo_red_wiring_tested': False, 'prometheus_proxy': feedback}

if __name__ == '__main__':
    directory = pathlib.Path('/results')
    try:
        outcome = run(directory)
    except Exception:
        directory.mkdir(parents=True, exist_ok=True)
        (directory / 'result.json').write_text(json.dumps({'status': 'failed', 'error': traceback.format_exc()}))
        raise
    (directory / 'result.json').write_text(json.dumps(outcome))
