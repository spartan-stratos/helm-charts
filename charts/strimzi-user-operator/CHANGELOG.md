# Changelog

All notable changes to this chart are documented in this file.

## [0.3.0](https://github.com/spartan-stratos/helm-charts/releases/tag/strimzi-user-operator-0.3.0) (2026-05-14)

### Features

* `externalSecret.enabled` toggle (default `true`) — when set to `false`,
  the chart skips rendering the `ExternalSecret` resource. The consumer
  is then responsible for provisioning the JAAS-format K8s Secret
  out-of-band (e.g. via Terraform `kubernetes_secret`). Useful for
  clusters that do not run the ExternalSecrets operator.

### Why

The chart's ExternalSecret made ExternalSecrets a hard prerequisite.
Some clusters intentionally don't run that operator (or run a different
secret-sync mechanism). The toggle lets the chart work in both
environments without forking.

## [0.2.0](https://github.com/spartan-stratos/helm-charts/releases/tag/strimzi-user-operator-0.2.0) (2026-05-14)

### Breaking changes

* Chart no longer creates cluster-scoped resources. The consumer must
  bootstrap these once before installing the chart (typically via
  Terraform):
  * The target Namespace (defaults to `kafka-acl`)
  * The Strimzi `KafkaUser` CRD definition (vendor the YAML from
    `https://github.com/strimzi/strimzi-kafka-operator/blob/0.45.1/install/cluster-operator/044-Crd-kafkauser.yaml`)
* `templates/namespace.yaml` removed (along with the `namespace.create` value).
* `templates/crd-kafkauser.yaml` removed (vendored CRD relocated to
  consumer bootstrap).
* RBAC narrowed from cluster-scoped `ClusterRole` +
  `ClusterRoleBinding` to namespace-scoped `Role` + `RoleBinding`.
  The operator already watches a single namespace via
  `STRIMZI_NAMESPACE`, so the cluster-wide grant was unnecessary.

### Why

The chart now fits a default-deny ArgoCD `AppProject` without
requiring a `clusterResourceWhitelist` entry for `Namespace`,
`ClusterRole`, `ClusterRoleBinding`, or `CustomResourceDefinition`.
Cluster-wide bootstrap belongs in Terraform; only the operator
runtime ships through this chart.

### Migration from 0.1.x

1. Bootstrap the Namespace + KafkaUser CRD via Terraform (`kubernetes_namespace`
   resource + `kubernetes_manifest` referencing the Strimzi 0.45.1 CRD YAML).
2. Upgrade the chart release to `0.2.0`. Helm will prune the
   `ClusterRole`/`ClusterRoleBinding`/`Namespace`/CRD resources owned
   by the 0.1.x release — the Terraform-bootstrapped equivalents take
   over.

## [0.1.0](https://github.com/spartan-stratos/helm-charts/releases/tag/strimzi-user-operator-0.1.0) (2026-05-14)

### Features

* Initial release — Strimzi User Operator (standalone mode) targeted at AWS MSK
  * Vendors the Strimzi 0.45.1 `KafkaUser` CRD definition
  * SASL/SCRAM authentication via ExternalSecrets-synced admin credential
  * `STRIMZI_PUBLIC_CA=true` + `STRIMZI_ACLS_ADMIN_API_SUPPORTED=true` for MSK compatibility
  * Placeholder CA Secrets workaround for upstream
    [Strimzi #8284](https://github.com/strimzi/strimzi-kafka-operator/issues/8284)
  * Cluster-scoped RBAC for `KafkaUser`, `Secret`, and `Event` resources
  * Reconcile cadence configurable via `fullReconciliationIntervalMs`
