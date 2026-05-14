# Changelog

All notable changes to this chart are documented in this file.

## [0.1.0](https://github.com/spartan-stratos/helm-charts/releases/tag/kafka-users-0.1.0) (2026-05-14)

### Features

* Initial release — companion chart to `strimzi-user-operator`
* Bundled `KafkaUser` CRD templates:
  * `msk-acl-admin` — self-grant `Alter/AlterConfigs/Describe/DescribeConfigs` on Cluster (toggle via `mskAclAdmin.enabled`)
  * `samsara-producer` — Write/Describe on `samsara.` prefix, IdempotentWrite on Cluster, explicit Deny on `fleet.` prefix (toggle via `samsaraProducer.enabled`)
* `authorization.type: simple` only — no credential management (credentials live in AWS Secrets Manager, managed by Terraform)
