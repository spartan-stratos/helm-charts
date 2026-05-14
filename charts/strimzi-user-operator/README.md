# strimzi-user-operator

[Strimzi User Operator](https://strimzi.io/docs/operators/latest/deploying.html)
deployed in **standalone mode** (no Cluster Operator, no self-hosted Kafka),
pointed at an **external AWS MSK** cluster.

Manages Kafka ACL declaratively via `KafkaUser` CRDs. The operator
authenticates to MSK over SASL/SCRAM using a dedicated admin credential
provided by the consumer.

> **Opinionated:** this chart targets the specific path of "Strimzi User
> Operator + AWS MSK SCRAM auth + ExternalSecrets-synced credential +
> ACL-only KafkaUser CRDs (no `authentication:` block)." If you want
> the full Strimzi stack (Cluster Operator + Topic Operator), use the
> upstream Strimzi chart.

## When to use

Use this chart when:
- You run AWS MSK (managed Kafka) — not self-hosted Kafka
- You want to declare Kafka ACL via GitOps (`KafkaUser` CRD in git → ArgoCD)
- Credential lifecycle for the operator's admin user lives in AWS Secrets
  Manager (managed elsewhere — e.g. Terraform), and you sync into K8s
  via ExternalSecrets

## What this chart ships

All resources are **namespace-scoped** (drops in a default-deny
`AppProject`):

- `ServiceAccount` + namespace-scoped `Role`/`RoleBinding` for the
  operator (operator watches a single namespace via
  `STRIMZI_NAMESPACE`)
- `ExternalSecret` that pulls the operator's SCRAM credential from AWS
  Secrets Manager and renders it as a JAAS `admin.properties` file in a
  K8s `Secret`
- Two placeholder `Secret` objects (`placeholder-ca-cert`,
  `placeholder-ca-key`) — workaround for Strimzi standalone UO's
  startup-time CA validation
  ([Strimzi #8284](https://github.com/strimzi/strimzi-kafka-operator/issues/8284))
- `Deployment` for the User Operator pod with all required env vars

KafkaUser CRD **instances** (the actual ACL declarations) ship in the
companion `kafka-users` chart.

## Prerequisites (consumer-bootstrapped — NOT in this chart)

These cluster-scoped resources must exist BEFORE installing the chart.
Provision them once via the consumer's Terraform / one-off kubectl
(then never touch them):

1. **Target Namespace** (default `kafka-acl`).
2. **Strimzi `KafkaUser` CRD** — vendor the YAML from upstream and
   apply once:
   ```
   https://github.com/strimzi/strimzi-kafka-operator/blob/0.45.1/install/cluster-operator/044-Crd-kafkauser.yaml
   ```
3. **A K8s `Secret`** named per `mskAclAdminSecret.k8sSecretName` (default
   `msk-acl-admin-creds`) holding a single key `admin.properties` with the
   JAAS config the operator reads. Two ways to provision it:
   - **`externalSecret.enabled: true` (default)** — requires the
     ExternalSecrets operator (`external-secrets.io/v1beta1` CRDs)
     installed cluster-wide, plus a `ClusterSecretStore`/`SecretStore`
     wired to AWS Secrets Manager via IRSA (default store name
     `aws-secrets-manager` — override via `externalSecretStore.name`).
     The chart will render an `ExternalSecret` that syncs the credential
     from AWS Secrets Manager into the K8s Secret.
   - **`externalSecret.enabled: false`** — consumer creates the K8s
     Secret directly (e.g. via Terraform `kubernetes_secret` that reads
     the AWS Secrets Manager value and writes the JAAS properties).
     Use this if the cluster does not run ExternalSecrets.

## Values

| Key | Type | Default | Description |
|---|---|---|---|
| `env` | string | `""` | Environment label (e.g. `dev`, `prod`) — surfaces in pod labels |
| `namespace.name` | string | `kafka-acl` | Namespace the operator lives in — must be pre-created |
| `image.repository` | string | `quay.io/strimzi/operator` | Upstream Strimzi operator image |
| `image.tag` | string | `0.45.1` | Pinned image tag (must match the vendored CRD version) |
| `image.pullPolicy` | string | `IfNotPresent` | |
| `mskBootstrapServersSaslScram` | string | `""` | MSK SASL/SCRAM bootstrap-broker list (comma-separated `host:9096`) |
| `mskAclAdminSecret.awsSecretName` | string | `""` | Friendly name of the AWS Secrets Manager secret containing `username` + `password` JSON keys |
| `mskAclAdminSecret.k8sSecretName` | string | `msk-acl-admin-creds` | Name of the K8s `Secret` ExternalSecrets renders into |
| `externalSecret.enabled` | bool | `true` | Render the `ExternalSecret` resource. Set `false` if the cluster does not run the ExternalSecrets operator — the consumer then provisions the K8s Secret out-of-band (e.g. Terraform). |
| `externalSecretStore.kind` | string | `ClusterSecretStore` | Used only when `externalSecret.enabled` is `true`. `ClusterSecretStore` or `SecretStore`. |
| `externalSecretStore.name` | string | `aws-secrets-manager` | Used only when `externalSecret.enabled` is `true`. Name of the existing ExternalSecrets store binding. |
| `resources.*` | object | see `values.yaml` | CPU + memory requests/limits — operator is lightweight |
| `fullReconciliationIntervalMs` | int | `120000` | Reconcile cadence (ms) — matches Strimzi default |

## Bootstrap chicken-and-egg

The operator's admin user needs `Alter Cluster` ACL on MSK before it can
write any ACL — but only itself can write that ACL. Solved by relying on
Kafka's default `allow.everyone.if.no.acl.found = true`: while the cluster
keeps that default, any authenticated principal can write ACL. The first
KafkaUser CRD applied via this chart should include the operator's own
self-grant (see `kafka-users` chart `msk-acl-admin.yaml` template). After
the consumer flips `allow.everyone.if.no.acl.found = false` (typically via
Terraform on the MSK cluster config), the operator keeps working via the
explicit ACL it wrote for itself.

## Eyes-open caveats

- **Strimzi User Operator standalone against AWS MSK is mechanically
  possible but not officially supported** by the Strimzi project.
  Maintainer's framing on
  [discussion #9051](https://github.com/strimzi/strimzi-kafka-operator/discussions/9051):
  *"never tried it, was never designed specifically for that use-case."*
- Strimzi UO's stock image does **not** include `aws-msk-iam-auth` —
  hence SASL/SCRAM auth via a dedicated admin user (not SASL/IAM).
- ACL-only KafkaUser (no `authentication:` block) works via a placeholder
  CA secret workaround.
- If this approach hits a wall, fallback is a custom thin reconciler
  (~200 LOC) — same chart shape, swap the operator pod for a Job pod.

## Example consumer (ArgoCD Application)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: strimzi-user-operator-dev
spec:
  source:
    repoURL: https://spartan-stratos.github.io/helm-charts
    chart: strimzi-user-operator
    targetRevision: 0.1.0
    helm:
      releaseName: strimzi-user-operator
      valuesObject:
        env: dev
        mskBootstrapServersSaslScram: "b-1.cluster.kafka.us-west-2.amazonaws.com:9096,..."
        mskAclAdminSecret:
          awsSecretName: AmazonMSK_msk-acl-admin-dev
  destination:
    namespace: kafka-acl
```
