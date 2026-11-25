#!/usr/bin/env python3
import argparse
import json
import re
import sys

import yaml

STRING = r'"(?:[^"\\]|\\.)*"|\x27(?:[^\x27\\]|\\.)*\x27|`[^`]*`'
SELECTOR = re.compile(r'(' + STRING + r')|([a-zA-Z_:][\w:]*)?\s*\{((?:' + STRING + r'|[^{}"\x27`])*)\}')
KEYWORDS = set('and or unless bool offset by without on ignoring group_left group_right inf nan atan2'.split())


def unpinned_selectors(expr, namespace, services):
    bad = []
    pins = {'namespace': {namespace}, 'service_name': set(services), 'service': set(services)}

    def replace(match):
        if match.group(3) is None:
            return ' '
        body = match.group(3)
        pinned = False
        for label in re.finditer(r'([a-zA-Z_][\w]*)\s*(=~|!~|!=|=)\s*(' + STRING + r')', body):
            key, op, value = label.groups()
            if op != '=' or key not in pins:
                continue
            try:
                decoded = json.loads(value) if value.startswith('"') else value[1:-1]
            except ValueError:
                continue
            pinned |= decoded in pins[key]
        if not pinned:
            bad.append(match.group(0).strip())
        return ' 0 '

    rest = SELECTOR.sub(replace, str(expr))
    rest = re.sub(r'\[[^\]]*\]', ' ', rest)
    rest = re.sub(r'\b(by|without|on|ignoring|group_left|group_right)\s*\([^)]*\)', ' ', rest)
    for match in re.finditer(r'(?<![\w:.])([a-zA-Z_:][\w:]*)', rest):
        word = match.group(1)
        if word.lower() not in KEYWORDS and not re.match(r'\s*\(', rest[match.end():]):
            bad.append(word)
    return bad


def check(docs, namespace, services):
    errors = []
    allowed = {('monitoring.coreos.com/v1', 'PrometheusRule'),
               ('monitoring.coreos.com/v1alpha1', 'AlertmanagerConfig'),
               ('external-secrets.io/v1', 'SecretStore'),
               ('external-secrets.io/v1', 'ExternalSecret'), ('v1', 'ServiceAccount')}
    for doc in docs:
        if not doc:
            continue
        kind, meta = doc.get('kind'), doc.get('metadata', {})
        name = f"{kind}/{meta.get('name')}"
        if (doc.get('apiVersion'), kind) not in allowed:
            errors.append(f'{name}: kind not allowed')
            continue
        if meta.get('namespace') != namespace:
            errors.append(f'{name}: metadata.namespace must be {namespace!r}')
        spec = doc.get('spec') or {}
        if kind == 'PrometheusRule':
            for group in spec.get('groups', []):
                if not isinstance(group.get('rules'), list) or not group['rules']:
                    errors.append(f"{name}: group {group.get('name')} has no rules")
                    continue
                for rule in group['rules']:
                    identity = rule.get('alert') or rule.get('record')
                    for selector in unpinned_selectors(rule.get('expr', ''), namespace, services):
                        errors.append(f'rule {identity}: selector {selector!r} has no allowed pin')
                    if rule.get('alert') and (rule.get('labels') or {}).get('namespace') != namespace:
                        errors.append(f'rule {identity}: needs a static namespace={namespace} label')
        if kind == 'AlertmanagerConfig':
            matchers = (spec.get('route') or {}).get('matchers', [])
            if not any(m.get('matchType', '=') == '=' and
                       ((m.get('name') == 'namespace' and m.get('value') == namespace) or
                        (m.get('name') == 'service' and m.get('value') in services)) for m in matchers):
                errors.append(f'{name}: route lacks a namespace or service matcher')
    return errors


def self_test():
    good = '''
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata: {name: good, namespace: test}
spec:
  groups:
  - name: good
    rules:
    - alert: Pinned
      expr: max by (pod) (a{namespace="test",pod=~"app-[a-z0-9]{9,10}"}) / on(pod) b{service="app"} > 0
      labels: {namespace: test}
    - record: Strings
      expr: label_replace(a{service_name="app"},"dst","{foo}","src",".*") atan2 b{service="worker"} != NaN or vector(Inf)
'''
    assert not check(yaml.safe_load_all(good), 'test', ['app', 'worker'])
    for expr, expected in [('up == 0', 'up'),
                           ('a{namespace="test"} / b{job="x"}', 'b{job="x"}'),
                           ('a{service="app"} > on(job) group_left b', 'b'),
                           ('x or y{service="app"}', 'x'),
                           ('x unless y{service="app"}', 'x'),
                           ('rate(x[5m] offset 1h)', 'x'), ('x offset 5m', 'x'),
                           ('http_requests_total{job="http"}', 'http_requests_total{job="http"}')]:
        assert expected in unpinned_selectors(expr, 'test', ['app']), expr
    bad = '''
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata: {name: bad, namespace: other}
spec:
  groups:
  - {name: missing}
  - {name: empty, rules: []}
  - name: httpSelector
    rules:
    - alert: Http
      expr: http_requests_total{job="http"}
---
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata: {name: bad, namespace: test}
spec: {route: {matchers: [{name: severity, value: critical}]}}
---
apiVersion: v1
kind: Secret
metadata: {name: bad, namespace: test}
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata: {name: bad, namespace: other}
'''
    errors = check(yaml.safe_load_all(bad), 'test', ['app'])
    for expected in ['metadata.namespace', 'group missing has no rules', 'group empty has no rules',
                     'http_requests_total', 'static namespace', 'route lacks', 'kind not allowed', 'ExternalSecret/bad']:
        assert any(expected in error for error in errors), expected
    print('self-test ok: literal pinned and unpinned fixtures checked')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--namespace')
    parser.add_argument('--service-name', action='append', default=[])
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('files', nargs='*')
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if not args.namespace or not args.files:
        parser.error('--namespace and rendered files are required')
    errors = []
    for path in args.files:
        with open(path) as source:
            errors.extend(check(yaml.safe_load_all(source), args.namespace, args.service_name))
    for error in errors:
        print('UNPINNED:', error)
    return int(bool(errors))


if __name__ == '__main__':
    sys.exit(main())
