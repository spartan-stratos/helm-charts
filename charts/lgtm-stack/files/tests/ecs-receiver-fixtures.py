"""Public OTLP JSON fixtures; no application data or live credentials."""
import gzip
import http.client
import io
import json
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SAMPLE_BASE_NS = (time.time_ns() // 1000000 - 30000) * 1000000
_SAMPLE_CLOCK = iter(range(SAMPLE_BASE_NS, SAMPLE_BASE_NS + 30000000000, 1000000))

LANES = {
    "alpha": ("123456789012", "example-cluster", "example-api"),
    "beta": ("210987654321", "other-cluster", "other-api"),
}
IDENTITY = ("cloud.account.id", "aws.ecs.cluster.arn", "service.name", "aws.ecs.task.arn")
CLAIMS = {"tenant": "other", "env": "prod", "deployment.environment": "prod",
          "deployment.environment.name": "prod", "service.instance.id": "other-task",
          "namespace": "other", "k8s.namespace.name": "other"}
ALIASES = {"cloud_account_id": "other", "aws_ecs_cluster_arn": "other",
           "aws_ecs_task_arn": "other", "service_name": "other",
           "service_instance_id": "other", "deployment_environment": "other",
           "deployment_environment_name": "other", "custom.fixture": "public",
           "job": "forged", "instance": "forged", "team": "forged",
           "service.namespace": "forged", "service_namespace": "forged",
           "service-namespace": "forged", "k8s_namespace_name": "forged",
           "tenant!": "forged", "ténant": "forged"}
CASES = {"valid": "keep", "matching-claims": "keep", "aliases-resource": "keep", "aliases-signal": "keep",
         "aliases-scope": "keep", "legacy-short-task": "drop", "bad-task-id": "drop",
         "wrong-task-cluster": "drop", "oversize-resource": "drop",
         "oversize-signal": "drop", "oversize-scope": "drop", "health-path": "keep"}
for key in IDENTITY:
    for mutation in ("missing", "wrong", "type"):
        CASES[f"{mutation}:{key}"] = "drop"
for scope in ("resource", "signal"):
    for key in (*IDENTITY, *CLAIMS):
        CASES[f"conflict-{scope}:{key}"] = "drop"


def any_value(value):
    if isinstance(value, bool):
        return {"boolValue": value}
    if isinstance(value, int):
        return {"intValue": str(value)}
    if isinstance(value, list):
        return {"arrayValue": {"values": [any_value(x) for x in value]}}
    if isinstance(value, dict):
        return {"kvlistValue": {"values": attributes(value)}}
    return {"stringValue": value}


def attributes(values):
    return [{"key": key, "value": any_value(value)} for key, value in values.items()]


def make_payload(signal, case="valid", lane="alpha", task=0, serial=1, service_name=None):
    if case not in CASES or signal not in ("metrics", "logs", "traces") or lane not in (*LANES, "legacy"):
        raise ValueError("unknown fixture case or signal")
    account, cluster, service = LANES.get(lane, LANES["alpha"])
    service = service_name or service
    cluster_arn = f"arn:aws:ecs:us-west-2:{account}:cluster/{cluster}"
    task_id = f"{task + 1:032x}"
    task_arn = f"arn:aws:ecs:us-west-2:{account}:task/{cluster}/{task_id}"
    resource = dict(zip(IDENTITY, (account, cluster_arn, service, task_arn)))
    business = {"http.request.method": "GET", "http.response.status_code": 200,
                "http.route": "/public-fixture", "jvm.memory.type": "heap",
                "jvm.memory.pool.name": "fixture-pool", "db.system.name": "postgresql"}
    if signal == "traces":
        business["url.path"] = "/health" if case == "health-path" else "/public-fixture"
    scope = {}
    if lane == "legacy":
        resource = {"k8s.namespace.name": "example-legacy", "service.name": "legacy-api"}
    if ":" in case:
        mutation, key = case.split(":", 1)
        if mutation == "missing":
            resource.pop(key, None)
        elif mutation == "type":
            resource[key] = {"public": True}
        elif mutation == "wrong":
            resource[key] = "wrong"
        else:
            target = resource if mutation == "conflict-resource" else business
            target[key] = CLAIMS.get(key, "wrong")
    elif case == "matching-claims":
        resource.update({"tenant": lane, "env": "dev", "deployment.environment": "dev",
                         "deployment.environment.name": "dev", "service.instance.id": task_arn})
        business.update(resource)
    elif case.startswith("aliases-"):
        {"resource": resource, "signal": business, "scope": scope}[case[8:]].update(ALIASES)
    elif case.startswith("oversize-"):
        target = {"resource": resource, "signal": business, "scope": scope}[case[9:]]
        target.update({f"fixture.extra.{i}": "public" for i in range(65 - len(target))})
    elif case == "legacy-short-task":
        resource["aws.ecs.task.arn"] = f"arn:aws:ecs:us-west-2:{account}:task/{task_id}"
    elif case == "bad-task-id":
        resource["aws.ecs.task.arn"] = task_arn[:-1] + "z"
    elif case == "wrong-task-cluster":
        resource["aws.ecs.task.arn"] = task_arn.replace(f"task/{cluster}/", "task/wrong/")
    now = str(next(_SAMPLE_CLOCK))
    trace_id, span_id = uuid.uuid4().hex, uuid.uuid4().hex[:16]
    common = {"attributes": attributes(business)}
    scoped = {"scope": {"name": "public-fixtures", "attributes": attributes(scope)}}
    if signal == "metrics":
        point = dict(common, timeUnixNano=now, startTimeUnixNano=str(int(now) - 1000000000),
                     asDouble=float(serial))
        scoped["metrics"] = [
            {"name": f"fixture_counter_{serial}", "sum": {"aggregationTemporality": 2,
             "isMonotonic": True, "dataPoints": [dict(point)]}},
            {"name": f"fixture_gauge_{serial}", "gauge": {"dataPoints": [dict(point)]}}]
        scope_key, resource_key = "scopeMetrics", "resourceMetrics"
    elif signal == "logs":
        scoped["logRecords"] = [dict(common, timeUnixNano=now, traceId=trace_id,
                                     spanId=span_id, body={"stringValue": f"public-fixture-{serial}"})]
        scope_key, resource_key = "scopeLogs", "resourceLogs"
    else:
        scoped["spans"] = [dict(common, traceId=trace_id, spanId=span_id, name=f"fixture-{serial}",
                                kind=2, startTimeUnixNano=now, endTimeUnixNano=str(int(now) + 1000))]
        scope_key, resource_key = "scopeSpans", "resourceSpans"
    return {resource_key: [{"resource": {"attributes": attributes(resource)}, scope_key: [scoped]}]}


def mixed_payload(signal, cases, lane="alpha", serial=1):
    result = {}
    for offset, case in enumerate(cases):
        for key, records in make_payload(signal, case, lane, serial=serial + offset).items():
            result.setdefault(key, []).extend(records)
    return result


def make_prom_proxy(port=18081, upstream_port=9090):
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
                chunks = []
                while True:
                    size = int(self.rfile.readline().split(b";", 1)[0], 16)
                    if not size:
                        while self.rfile.readline() not in (b"\r\n", b"\n", b""):
                            pass
                        break
                    chunks.append(self.rfile.read(size))
                    assert self.rfile.read(2) == b"\r\n"
                raw = b"".join(chunks)
            else:
                raw = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            tenant = self.headers.get("X-Scope-OrgID")
            first = False
            with self.server.state_lock:
                if tenant == "alpha" and not self.server.first_alpha_seen:
                    self.server.first_alpha_seen = first = self.server.first_alpha_waiting = True
                elif tenant == "alpha" and self.server.first_alpha_waiting:
                    self.server.concurrent_alpha_observed = True
            if first:
                self.server.later_alpha_done.wait(0.3)
                with self.server.state_lock:
                    self.server.first_alpha_waiting = False
            headers = {name: self.headers[name] for name in ("Content-Type", "Content-Encoding", "X-Scope-OrgID") if name in self.headers}
            upstream = http.client.HTTPConnection("127.0.0.1", upstream_port, timeout=10)
            try:
                upstream.request("POST", self.path, body=raw, headers=headers)
                response = upstream.getresponse()
                body = response.read()
                if not 200 <= response.status < 300:
                    decoded = (gzip.GzipFile(fileobj=io.BytesIO(body)).read(2048)
                               if response.getheader("Content-Encoding") == "gzip" else body[:2048])
                    with self.server.state_lock:
                        self.server.non_2xx_count += 1
                        if len(self.server.errors) < 8:
                            self.server.errors.append({"status": response.status, "body": decoded.decode("utf-8", "replace")})
                self.send_response(response.status, response.reason)
                for name, value in response.getheaders():
                    if name.lower() not in ("transfer-encoding", "content-length", "connection"):
                        self.send_header(name, value)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                if tenant == "alpha" and not first:
                    self.server.later_alpha_done.set()
            finally:
                upstream.close()

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.state_lock = threading.Lock()
    server.later_alpha_done = threading.Event()
    server.first_alpha_seen = server.first_alpha_waiting = server.concurrent_alpha_observed = False
    server.non_2xx_count, server.errors = 0, []
    return server


def make_sink(port=0):
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            tenant = self.headers.get("X-Scope-OrgID")
            size = int(self.headers.get("Content-Length", "0"))
            if tenant not in ("alpha", "beta", "legacy") or not 0 < size <= 8388608:
                self.send_error(400)
                return
            raw = self.rfile.read(size)
            if self.headers.get("Content-Encoding") == "gzip":
                raw = gzip.decompress(raw)
            self.server.records.append({"tenant": tenant, "path": self.path, "body": json.loads(raw)})
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b"{}")

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.records = []
    return server


if __name__ == "__main__":
    if sys.argv[1] == "serve":
        make_sink(int(sys.argv[2])).serve_forever()
    else:
        print(json.dumps(make_payload(*sys.argv[1:4], task=int(sys.argv[4]) if len(sys.argv) > 4 else 0,
                                      serial=int(sys.argv[5]) if len(sys.argv) > 5 else 1)))
