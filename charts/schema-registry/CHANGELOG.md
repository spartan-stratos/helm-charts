# Changelog

## 0.2.0

Broker DNS now sourced from a consumer-provided K8s `ConfigMap` instead
of a Helm value. The `mskBootstrapServersSaslScram` input is gone;
configure `brokersConfigMap.{name,key}` instead. The ConfigMap value
must already include the per-broker `SASL_SSL://` protocol prefix.

This lets Terraform own the broker DNS and roll the SR pod on MSK
broker changes without edits to ArgoCD values.

## 0.1.0

Initial release.

- `Deployment` for `confluentinc/cp-schema-registry:7.6.1`.
- `ClusterIP` `Service` on port 8081.
- SASL/SCRAM auth to MSK using a consumer-provided K8s `Secret` (key `jaas`).
- Probes on `/subjects`.
