# kafka-users

Declarative `KafkaUser` CRD instances for use with the
[`strimzi-user-operator`](../strimzi-user-operator/) chart pointed at
an external Kafka cluster (designed for AWS MSK but works against any
Kafka the operator can reach).

This chart only produces `KafkaUser` Custom Resources from a `users[]`
list you supply. The Strimzi User Operator pod and the `KafkaUser` CRD
definition itself come from the sibling `strimzi-user-operator` chart.

## When to use

Use this chart immediately after deploying `strimzi-user-operator`.
Together, they realise a GitOps flow for Kafka ACL: declare a
`KafkaUser` here, ArgoCD (or any Helm-managed pipeline) syncs the CRD,
the operator reconciles ACL on Kafka via the Admin API.

All bundled `KafkaUser` declarations use `authorization.type: simple`
ONLY — no `authentication:` block. Credential lifecycle stays with
whoever created the SCRAM/mTLS principal upstream (e.g. Terraform).

## Values

| Key | Type | Default | Description |
|---|---|---|---|
| `clusterLabel` | string | `""` | Value of the required `strimzi.io/cluster` label on each KafkaUser. Standalone UO does not require a matching `Kafka` CR; the label namespaces KafkaUsers by target cluster. Pick a stable string per environment (e.g. `msk-dev`). |
| `namespace` | string | `kafka-acl` | Namespace for the KafkaUser instances — must match where the operator watches. |
| `users` | list | `[]` | List of principals whose ACL this chart manages. See schema below. Empty by default. |

### `users[]` entry schema

| Key | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Kafka principal name — becomes the `KafkaUser` `metadata.name` and the SCRAM username the ACL applies to. |
| `acls` | list | yes | List of Strimzi ACL rules — passed verbatim into `spec.authorization.acls`. See the upstream [AclRule reference](https://strimzi.io/docs/operators/latest/configuring.html#type-AclRule-reference). |
| `labels` | map | no | Extra labels merged into the rendered `KafkaUser` metadata. |
| `annotations` | map | no | Extra annotations on the rendered `KafkaUser` metadata. |

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
        namespace: kafka-acl
        users:
          # Self-grant for the operator's own admin principal — must exist
          # before the consumer flips `allow.everyone.if.no.acl.found = false`
          # on the cluster, otherwise the operator locks itself out.
          - name: kafka-acl-admin
            acls:
              - resource: { type: cluster }
                operations: [Alter, AlterConfigs, Describe, DescribeConfigs]
                type: allow

          # Example producer principal — Write/Describe on a topic prefix,
          # IdempotentWrite at the cluster level (required for
          # enable.idempotence = true), and an explicit Deny on a foreign
          # topic prefix for defense in depth.
          - name: my-producer
            acls:
              - resource:
                  type: topic
                  name: "my-prefix."
                  patternType: prefix
                operations: [Write, Describe]
                type: allow
              - resource: { type: cluster }
                operations: [IdempotentWrite]
                type: allow
              - resource:
                  type: topic
                  name: "other-prefix."
                  patternType: prefix
                operations: [All]
                type: deny
  destination:
    namespace: kafka-acl
```

## Bootstrap chicken-and-egg

The operator's admin principal needs ACL on the cluster before it can
write any ACL — but only itself can write that ACL. If you operate
against AWS MSK (or any cluster where you cannot set `super.users`),
rely on Kafka's default `allow.everyone.if.no.acl.found = true`: while
that flag is on, any authenticated principal can write ACL. The first
`users[]` entry should be the operator's own self-grant
(`Alter Cluster` etc.), applied during this window. After you flip
`allow.everyone.if.no.acl.found = false` on the cluster, the operator
keeps working via the explicit ACL it wrote for itself.
