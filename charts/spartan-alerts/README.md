# spartan-alerts chart

Provide namespace-scoped alert routing with optional alert rules and webhook secret synchronization.

## Introduction

This chart creates two AlertmanagerConfig objects: one matches the namespace label and one matches the service label.
Both route warning and critical alerts to Slack. Optional PrometheusRule definitions cover migration failures and durable workers.

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
| `slack` | `{secretName: alert-slack, channel: ""}` | Webhook and channel settings. |
| `slack.secretName` | `alert-slack` | Webhook Secret name; also names the optional ExternalSecret and SecretStore. |
| `slack.channel` | `""` | Channel name without `#`; empty omits the channel override. |
| `externalSecrets` | `{enabled: false, secretArn: "", region: "", serviceAccount: alert-secrets, roleArn: ""}` | Optional webhook secret synchronization settings. |
| `externalSecrets.enabled` | `false` | Create an ExternalSecret, SecretStore, and ServiceAccount. |
| `externalSecrets.secretArn` | `""` | Secrets Manager secret ARN containing the webhook URL; required when enabled. |
| `externalSecrets.region` | `""` | Secrets Manager region; required when enabled. |
| `externalSecrets.serviceAccount` | `alert-secrets` | ServiceAccount used by the SecretStore for JWT authentication. |
| `externalSecrets.roleArn` | `""` | IAM role ARN annotated on the ServiceAccount; required when enabled. |
| `rules` | `{migration: {enabled: false}, worker: {enabled: false}}` | Built-in rule switches. |
| `rules.migration` | `{enabled: false}` | Migration alert settings. |
| `rules.migration.enabled` | `false` | Add the MigrationJobFailed rule. |
| `rules.worker` | `{enabled: false}` | Durable worker alert settings. |
| `rules.worker.enabled` | `false` | Add DurableQueueNotDraining and DurableActivitiesNotRegistered rules. |
| `extraRules` | `[]` | Rule definitions appended after enabled built-in rules; also work alone. |

Each rule must carry a static `namespace` label matching the release namespace for routing.
Built-in rules set it automatically. Add it explicitly to every `extraRules` entry, including rules whose expressions aggregate away namespace labels.
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
rules:
  migration:
    enabled: true
  worker:
    enabled: true
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
