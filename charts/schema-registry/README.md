# schema-registry

[Confluent Schema Registry](https://docs.confluent.io/platform/current/schema-registry/index.html)
pointed at an **external AWS MSK** cluster over SASL/SCRAM. Stateless
`Deployment` + `ClusterIP` `Service`; all durable state lives in the
Kafka `_schemas` topic.

> **Opinionated:** this chart targets one specific path — Confluent SR
> talking to AWS MSK via SASL/SCRAM, with the SCRAM credential and the
> `_schemas` topic provisioned out-of-band (Terraform). If you want the
> full Confluent Platform Helm chart with ZooKeeper bundled, use
> [cp-helm-charts](https://github.com/confluentinc/cp-helm-charts)
> upstream.

## When to use

- You run AWS MSK (managed Kafka).
- You want a thin, single-purpose SR chart you can read in one screen.
- The `_schemas` topic + SCRAM credential are managed by Terraform.

## What this chart ships

All resources are **namespace-scoped** (drops in a default-deny
`AppProject`):

- `Deployment` for the SR pod (env-only config — no `ConfigMap`)
- `ClusterIP` `Service` exposing port 8081 inside the cluster

## Prerequisites (consumer-bootstrapped — NOT in this chart)

These must exist before installing the chart. Provision once via the
consumer's Terraform.

| Resource | Owner |
|---|---|
| `Namespace` (`schema-registry` by default) | Terraform |
| `Secret` with key `jaas` holding a single-line `org.apache.kafka.common.security.scram.ScramLoginModule required username=... password=... ;` | Terraform |
| MSK `_schemas` topic with `cleanup.policy=compact`, `min.insync.replicas=2`, `replication.factor=3` (prod) | Terraform |
| Kafka ACL granting the SCRAM user `Read`+`Write` on topic `_schemas` and on group prefix `schema-registry` | Strimzi User Operator via `KafkaUser` CRD |
| EKS Fargate Profile selector on the SR namespace (if running on Fargate) | Terraform |

## Required values

```yaml
env: dev                          # observability label

mskBootstrapServersSaslScram: "b-1.<cluster>.<region>.amazonaws.com:9096,..."

scramSecret:
  name: schema-registry-creds     # Secret name created by Terraform
  jaasKey: jaas                   # Secret key holding the JAAS string

kafkaStore:
  topic: _schemas                 # MUST be _schemas — SR refuses any other value
  replicationFactor: 3            # prod: 3, dev: 1
```

## Connecting from clients

In-cluster clients reach SR at:

```
http://schema-registry.<namespace>.svc.cluster.local:8081
```

There is no Ingress in this chart by design — SR has no auth and must
stay private.

## Image

`confluentinc/cp-schema-registry:{{ .Chart.AppVersion }}` from Docker Hub.
Confluent Community License (CCL) — fine for internal self-hosted use,
no redistribution.

## Operations

- Pod restart rebuilds the in-memory index by replaying `_schemas`. Cold
  start scales linearly with the topic — 1-3 s typical, much longer once
  you have tens of thousands of schemas.
- Multiple replicas elect a leader via Kafka. Only the leader writes; all
  replicas serve reads. Bump `replicaCount` to 2-3 in prod.

## Related

- `kafka-users` chart — declare the SR SCRAM user's ACL
- `strimzi-user-operator` chart — reconcile that ACL onto MSK
