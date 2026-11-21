# spartan-alerts chart

Provide namespace-scoped alert routing with optional webhook secret synchronization and consumer-supplied rule groups.

## Introduction

This chart creates two AlertmanagerConfig objects: one matches the namespace label, and one matches the service label on alerts from outside the release namespace, so an alert carrying both labels posts once.
Both route warning and critical alerts to Slack. The chart ships no alert definitions; a PrometheusRule renders only from the `groups` value.

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

## Upgrading the Chart

```sh
helm upgrade alerts ./charts/spartan-alerts -n notifications -f values.yaml
```

## Uninstalling the Chart

```sh
helm uninstall alerts -n notifications
```
