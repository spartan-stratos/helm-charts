# Changelog

All notable changes to this chart are documented in this file.

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
