# kafka-users

Declarative `KafkaUser` CRD instances for use with the
[`strimzi-user-operator`](../strimzi-user-operator/) chart pointed at
an external AWS MSK cluster.

This chart only produces `KafkaUser` Custom Resources — the Strimzi
User Operator pod and the `KafkaUser` CRD definition itself come from
the sibling `strimzi-user-operator` chart.

## When to use

Use this chart immediately after deploying `strimzi-user-operator`
against an MSK cluster. Together, they realise a GitOps flow for Kafka
ACL: declare a `KafkaUser` here, ArgoCD syncs the CRD, the operator
reconciles ACL on MSK via the Kafka Admin API.

## Bundled principals

| Principal | Purpose | Toggle |
|---|---|---|
| `msk-acl-admin` | Self-grant for the operator's own admin user (`Alter`, `AlterConfigs`, `Describe`, `DescribeConfigs` on Cluster) — keeps the principal usable after a later flip of `allow.everyone.if.no.acl.found` to `false`. | `mskAclAdmin.enabled` |
| `samsara-producer` | External Samsara Kafka Connector — `Write,Describe` on `<topicPrefix>` (default `samsara.`), `IdempotentWrite` on Cluster, explicit `Deny All` on every `deniedTopicPrefixes[]` entry. | `samsaraProducer.enabled` |

Both principals declare `authorization.type: simple` ONLY — no
`authentication:` block. SCRAM credentials themselves live in AWS
Secrets Manager (created out-of-band, e.g. by Terraform).

## Values

| Key | Type | Default | Description |
|---|---|---|---|
| `clusterLabel` | string | `""` | Value of the required `strimzi.io/cluster` label on each KafkaUser — pick a stable string per environment (e.g. `msk-dev`). The Strimzi standalone UO does not require a matching `Kafka` CR; the label just namespaces KafkaUsers by target cluster. |
| `namespace` | string | `kafka-acl` | Namespace for the KafkaUser instances — must match where the operator watches. |
| `mskAclAdmin.enabled` | bool | `true` | Whether to render the operator's self-grant CRD. |
| `samsaraProducer.enabled` | bool | `true` | Whether to render the samsara-producer ACL CRD. |
| `samsaraProducer.topicPrefix` | string | `samsara.` | Topic prefix the principal may produce to (Strimzi uses `patternType: prefix`). Trailing dot prevents `samsara.*` from matching lookalike topics like `samsararogue`. |
| `samsaraProducer.deniedTopicPrefixes` | list | `["fleet."]` | Topic prefixes the principal is explicitly denied — defense in depth. |

## Adding a new vendor principal

Drop a new template file in `templates/<vendor>.yaml`:

```yaml
{{- if .Values.<vendor>.enabled -}}
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
  name: <vendor>-producer
  namespace: {{ .Values.namespace }}
  labels:
    strimzi.io/cluster: {{ .Values.clusterLabel }}
spec:
  authorization:
    type: simple
    acls:
      - resource:
          type: topic
          name: {{ .Values.<vendor>.topicPrefix | quote }}
          patternType: prefix
        operations: [Write, Describe]
        type: allow
      - resource: { type: cluster }
        operations: [IdempotentWrite]
        type: allow
      {{- range .Values.<vendor>.deniedTopicPrefixes }}
      - resource:
          type: topic
          name: {{ . | quote }}
          patternType: prefix
        operations: [All]
        type: deny
      {{- end }}
{{- end -}}
```

Extend `values.yaml` with `<vendor>.enabled` + topic config. Bump the
chart version (semver patch for additive change). Open a PR — the
release workflow auto-publishes after merge.

## Example consumer (ArgoCD Application)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kafka-users-dev
spec:
  source:
    repoURL: https://spartan-stratos.github.io/helm-charts
    chart: kafka-users
    targetRevision: 0.1.0
    helm:
      releaseName: kafka-users
      valuesObject:
        clusterLabel: msk-dev
        samsaraProducer:
          topicPrefix: "samsara."
          deniedTopicPrefixes: ["fleet."]
  destination:
    namespace: kafka-acl
```
