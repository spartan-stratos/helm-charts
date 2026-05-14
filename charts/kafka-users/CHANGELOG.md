# Changelog

All notable changes to this chart are documented in this file.

## [0.1.0](https://github.com/spartan-stratos/helm-charts/releases/tag/kafka-users-0.1.0) (2026-05-14)

### Features

* Initial release — companion chart to `strimzi-user-operator`.
* `users[]` list in values drives KafkaUser CRD generation. Each entry
  renders one `KafkaUser` with `authorization.type: simple` only — no
  `authentication:` block, so credential lifecycle stays with whoever
  created the SCRAM/mTLS principal upstream.
* Per-entry: `name`, `acls`, optional `labels` and `annotations`.
