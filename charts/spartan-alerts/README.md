# spartan-alerts chart

Provide namespace-scoped alert routing with optional webhook secret synchronization and consumer-supplied rule groups.

## Introduction

This chart creates two AlertmanagerConfig objects: one matches the namespace label, and one matches the service label on alerts from outside the release namespace, so an alert carrying both labels posts once.
Both route warning and critical alerts to Slack. Rules come from consumer-supplied `groups` or the opt-in catalogue. Neither renders rules by default.

## Prerequisites

- Helm 3.x or later
- Prometheus Operator with AlertmanagerConfig and PrometheusRule CRDs and selectors that discover these objects
- External Secrets Operator with the external-secrets.io/v1 CRDs when secret synchronization is enabled
- A Slack webhook Secret with key `webhook-url`, or access to a webhook stored in AWS Secrets Manager

## Installing the Chart

```sh
helm install alerts ./charts/spartan-alerts -n notifications --create-namespace -f values.yaml
```

All objects use the release namespace. Without external secret synchronization, create the webhook Secret there before sending alerts.

## Configuration

| Key | Default | Description |
| --- | --- | --- |
| `service` | `{name: service, short: service}` | Alert identity settings. |
| `service.name` | `service` | Service matcher, rule resource name, and metric selector identity. |
| `service.short` | `service` | Short name for routing objects, receivers, and alert summaries. |
| `env` | `""` | Environment suffix in receiver names. |
| `workloadCluster` | `""` | Cluster name displayed in Slack messages. |
| `grafanaUrl` | `""` | Base URL for alert and dashboard links. |
| `nameSuffix` | `""` | Optional suffix appended with a hyphen to both AlertmanagerConfig names and the PrometheusRule name. Empty preserves existing names. |
| `routeMatchers` | `[]` | Additional `{name, value, matchType}` matchers appended to both routes. `matchType` is optional and omitted when empty. |
| `slack` | `{secretName: alert-slack, channel: ""}` | Webhook and channel settings. |
| `slack.secretName` | `alert-slack` | Webhook Secret name; also names the optional ExternalSecret and SecretStore. |
| `slack.channel` | `""` | Channel name without `#`; empty omits the channel override. |
| `externalSecrets` | `{enabled: false, secretArn: "", region: "", serviceAccount: alert-secrets, roleArn: ""}` | Optional webhook secret synchronization settings. |
| `externalSecrets.enabled` | `false` | Create an ExternalSecret, SecretStore, and ServiceAccount. |
| `externalSecrets.secretArn` | `""` | Secrets Manager secret ARN containing the webhook URL; required when enabled. |
| `externalSecrets.region` | `""` | Secrets Manager region; required when enabled. |
| `externalSecrets.serviceAccount` | `alert-secrets` | ServiceAccount used by the SecretStore for JWT authentication. |
| `externalSecrets.roleArn` | `""` | IAM role ARN annotated on the ServiceAccount; required when enabled. |
| `groups` | `[]` | PrometheusRule groups rendered verbatim into `spec.groups`, in order. Empty renders no PrometheusRule. |

The chart's namespace route matches on a static `namespace` label, so every alerting rule needs one.
For each rule with an `alert` key and no `namespace` label, the chart sets it to the release namespace; an explicit value is kept.
Recording rules are not changed. Rule content is never passed through Helm templating, so `{{ $labels.x }}` stays literal.
Keep metric selectors scoped to the intended workload when sharing Prometheus.

### Minimal Example

Use an existing Secret named `alert-slack` with key `webhook-url` in the release namespace:

```yaml
service:
  name: api
  short: api
env: dev
slack:
  secretName: alert-slack
```

No PrometheusRule or secret synchronization objects render by default. An empty channel uses the webhook's default destination.
Alertmanager message templates remain literal for Alertmanager to evaluate.

### Shared Namespace Example

Install dev and prod releases into the same `notifications` namespace with separate values files:

```yaml
# dev.yaml
env: dev
nameSuffix: dev
slack:
  secretName: alert-slack-dev
  channel: alerts-dev
externalSecrets:
  serviceAccount: alert-secrets-dev
routeMatchers:
  - name: env
    value: dev
---
# prod.yaml
env: prod
nameSuffix: prod
slack:
  secretName: alert-slack-prod
  channel: alerts-prod
externalSecrets:
  serviceAccount: alert-secrets-prod
routeMatchers:
  - name: env
    value: prod
```

```sh
helm install alerts-dev ./charts/spartan-alerts -n notifications -f dev.yaml
helm install alerts-prod ./charts/spartan-alerts -n notifications -f prod.yaml
```

Alerts must carry the matching `env` label; set it explicitly in each release's alert rule labels.
Create both webhook Secrets, or enable external secret synchronization with the required settings below for each release.

### Rule Groups Example

```yaml
groups:
  - name: api
    rules:
      - alert: ApiDown
        expr: up{job="api"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.pod }} is down"
```

### External Secrets Example

Replace the ARN placeholders with your secret and a role permitted to read it. The secret value must contain the webhook URL.

```yaml
service:
  name: api
  short: api
env: dev
workloadCluster: workload-dev
grafanaUrl: https://grafana.example
slack:
  secretName: alert-slack
  channel: alerts
externalSecrets:
  enabled: true
  secretArn: <secret-arn>
  region: us-west-2
  serviceAccount: alert-secrets
  roleArn: <role-arn>
```

The ExternalSecret refreshes hourly and writes the `webhook-url` key to `slack.secretName`.
The role must trust the configured ServiceAccount in the release namespace through the cluster's IAM OIDC provider.

## Alert Catalogue

Set `catalogue.enabled: true` to render a separate PrometheusRule named `<service.name>[-<nameSuffix>]-catalogue`.
The group name is `spartan-alerts-catalogue`. The value `nameSuffix: catalogue` is reserved when the catalogue is enabled.
Consumer `groups` remain independent.

### Catalogue Values

| Key under `catalogue` | Default | Description |
| --- | --- | --- |
| `enabled` | `false` | Render catalogue rules. |
| `alertPrefix` | `""` | Prepend to prefixable alert names only. |
| `container` | `""` | Required container name when kubeState or cadvisor is enabled. |
| `podRegex` | `""` | Required pod name regex when kubeState or cadvisor is enabled. |
| `httpSelector` | `""` | Raw PromQL label matchers. Empty uses `service_name="<service.name>"`. |
| `tagProject` | `""` | RDS and ElastiCache `tag_Project` selector. Empty uses `service.name`. |
| `runbookUrl` | `""` | Optional `runbook_url` annotation on every catalogue rule. |
| `sources` | `{kubeState: true, cadvisor: true, http: true, probe: true, rds: false, elasticache: false}` | Render a rule only when all its sources are enabled. |
| `rds.storageWarningBytes` | `0` | Free storage warning threshold in bytes. Zero omits the rule. |
| `rds.storageCriticalBytes` | `0` | Free storage critical threshold in bytes. Zero omits the rule. |
| `inhibit` | `true` | Add critical-to-warning inhibition when the catalogue is enabled. |
| `overrides` | `{}` | Map base alert names to `threshold`, `for`, `severity`, or `enabled`. |

### Catalogue Rules

This table is generated from `files/catalogue.yaml`. Thresholds are numeric values, with units in the adjacent column.
The tier follows the final severity: critical is P2 and warning is P3.

| Alert | Prefixable | Sources | Unit | Default threshold | For | Severity | Tier |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ContainerRestarting | true | kubeState | count | 0 | 1m | critical | P2 |
| PodStuckWaiting | true | kubeState | count | 1 | 5m | critical | P2 |
| PodFailed | true | kubeState | count | 0 | 5m | critical | P2 |
| NoReadyPods | true | kubeState | count | 0 | 5m | critical | P2 |
| MemoryNearLimit | true | cadvisor | ratio | 0.8 | 5m | warning | P3 |
| CpuHigh | true | cadvisor, kubeState | ratio | 0.8 | 5m | warning | P3 |
| CpuThrottled | true | cadvisor | ratio | 0.25 | 15m | warning | P3 |
| OomKilled | true | cadvisor | count | 0 | 0m | warning | P3 |
| HttpP95Slow | true | http | seconds | 1 | 5m | warning | P3 |
| Http5xx | true | http | ratio | 0.05 | 5m | warning | P3 |
| UptimeProbeFailed | true | probe | count | 0 | 2m | critical | P2 |
| RdsCpuHigh | false | rds | percent | 70 | 5m | warning | P3 |
| RdsCpuCritical | false | rds | percent | 80 | 5m | critical | P2 |
| RdsStorageLow | false | rds | bytes | 0 | 15m | warning | P3 |
| RdsStorageCritical | false | rds | bytes | 0 | 15m | critical | P2 |
| ElasticacheCpuHigh | false | elasticache | percent | 70 | 5m | warning | P3 |
| ElasticacheCpuCritical | false | elasticache | percent | 80 | 5m | critical | P2 |
| ElasticacheMemoryHigh | false | elasticache | percent | 70 | 5m | warning | P3 |
| ElasticacheMemoryCritical | false | elasticache | percent | 80 | 5m | critical | P2 |
| ElasticacheEvictions | false | elasticache | count | 0 | 0m | warning | P3 |

CpuHigh requires both cadvisor and kubeState. It cannot fire for a container without a positive CPU limit.
NoReadyPods checks Running phase, not readiness, and stays silent when no matching series exists.
PodFailed excludes Evicted pods. Scope `podRegex` to app pods to exclude jobs.
HTTP rules assume stable OTel metric names `http_server_request_duration_seconds` and label `http_response_status_code`.
Http5xx also requires at least two errors in five minutes. It stays silent at zero traffic or a single error.
Probe rules select all `probe_success` series in the release namespace.
RDS and ElastiCache selectors exclude `name="global"` and match `tag_Project`.
Use one catalogue per tagProject to avoid duplicate cloud alerts.
Missing cloud exporter series leave these rules silent; they do not detect exporter absence.

### Overrides and Example

Override keys use base alert names, even with a prefix. Unknown names or fields fail rendering.
Allowed severities are `warning` and `critical`. Ratio thresholds must be in (0, 1]; percent thresholds must be in (0, 100].
An `enabled: false` override omits a rule. Setting it to true does not bypass source toggles or a zero storage threshold.
Two rendered rules sharing a catalogue ID cannot have the same final severity.
Overrides replace the threshold, duration, and severity independently. Descriptions keep their catalogue duration text.

```yaml
service:
  name: api
  short: api
catalogue:
  enabled: true
  alertPrefix: Backend
  container: app
  podRegex: "api-.*"
  sources:
    rds: true
  rds:
    storageWarningBytes: 6442450944
    storageCriticalBytes: 3221225472
  overrides:
    MemoryNearLimit:
      threshold: 0.9
      for: 10m
      severity: critical
    HttpP95Slow:
      enabled: false
```

This renders BackendMemoryNearLimit at ratio 0.9 for 10m with tier P2.
Cloud alert names stay unprefixed.
Derive RDS free storage thresholds from Terraform storage inputs and pass numeric byte values into Helm.
For example, 30 GiB allocated storage gives 6442450944 bytes at 20% and 3221225472 bytes at 10%.
The chart does not calculate these percentages or read Terraform state.
An explicit storage alert `threshold` override takes precedence over `rds.storageWarningBytes` or `rds.storageCriticalBytes`.

### Production Caveat

Where kube-state metrics are not yet tenant-visible in production, set `catalogue.sources.kubeState: false`.
This omits the four kubeState rules and CpuHigh. Enable the source only after its metrics are available to the tenant.

### Inhibition

With both `catalogue.enabled` and `catalogue.inhibit` true, the namespace AlertmanagerConfig adds an inhibit rule.
A critical alert with a nonempty `catalogue_id` suppresses warning notifications with equal `namespace`, `catalogue_id`, `pod`, `dimension_DBInstanceIdentifier`, and `dimension_CacheClusterId`.
Absent labels compare equal. Resource labels keep one database or cache from muting another.
The four shared-ID pairs are RDS CPU, RDS storage, ElastiCache CPU, and ElastiCache memory.
Every catalogue rule carries `namespace`, `severity`, `tier`, and `catalogue_id` labels.
Consumer rules without `catalogue_id` are not inhibited by this rule.
One OOM event can still page twice: ContainerRestarting is critical and OomKilled is warning, with different catalogue IDs.
This double page is accepted. Set `catalogue.inhibit: false` to omit catalogue inhibition.

## Upgrading the Chart

```sh
helm upgrade alerts ./charts/spartan-alerts -n notifications -f values.yaml
```

### Migrating to 0.3.0

The catalogue is disabled by default. Existing `groups` and routing stay unchanged when no new values are set.
When adopting it, remove duplicate rules from `groups` in the same change.
New catalogue labels change alert identity, so firing alerts resolve and refire once at cutover.
Match existing alert names with `alertPrefix` where needed, and supply container and pod selectors before enabling workload sources.
Keep service-specific rules (migration jobs, queues, JVM heap, connection pools) in consumer `groups`; they are outside this catalogue.

## Uninstalling the Chart

```sh
helm uninstall alerts -n notifications
```
