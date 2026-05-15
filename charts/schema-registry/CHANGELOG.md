# Changelog

## 0.1.0

Initial release.

- `Deployment` for `confluentinc/cp-schema-registry:7.6.1`.
- `ClusterIP` `Service` on port 8081.
- SASL/SCRAM auth to MSK using a consumer-provided K8s `Secret` (key `jaas`).
- Probes on `/subjects`.
