# Changelog

All notable changes to this chart are documented in this file.

## [0.3.4](https://github.com/spartan-stratos/helm-charts/releases/tag/strimzi-user-operator-0.3.4) (2026-05-14)

### Bug fixes

* Add **Starfield Services Root Certificate Authority - G2** to the
  trust-root bundle. AWS MSK serves a cross-signed `Amazon Root CA 1`
  (subject=`Amazon Root CA 1`, issuer=`Starfield G2`). Java's PKIX
  builder strict-follows the Authority Key Identifier chain rather
  than matching trust anchors by Subject DN + public key, so the
  self-signed Amazon roots in 0.3.3 were NOT sufficient — Java tried
  to chain up to Starfield G2 as the trust anchor and failed with
  `PKIX path building failed`. The bundle is renamed
  `files/amazon-trust-roots.pem` → `files/msk-trust-roots.pem` to
  reflect that it contains both Amazon and Starfield material
  needed for MSK.

## [0.3.3](https://github.com/spartan-stratos/helm-charts/releases/tag/strimzi-user-operator-0.3.3) (2026-05-14)

### Bug fixes

* Populate `placeholder-ca-cert` with the Amazon Trust Services Root CA
  bundle instead of a random `genCA` self-signed cert. Despite
  `STRIMZI_PUBLIC_CA=true`, Strimzi 0.45.x still loads the
  Cluster-CA-secret bytes into the Kafka AdminClient
  `ssl.truststore.certificates`. A random CA there caused
  `SSLHandshakeException: PKIX path building failed` against MSK
  brokers (which serve certs signed by Amazon Trust roots). Bundling
  the public Amazon Trust roots in `files/amazon-trust-roots.pem`
  produces a truststore the operator can use to complete the TLS
  handshake to MSK.

  `placeholder-ca-key` still ships a throwaway `genCA` key — the
  field is parsed but unused in authorization-only mode.

## [0.3.2](https://github.com/spartan-stratos/helm-charts/releases/tag/strimzi-user-operator-0.3.2) (2026-05-14)

### Bug fixes

* Populate the placeholder CA Secrets with a generated self-signed cert
  (`genCA`) instead of leaving them empty. Strimzi 0.45.x's startup
  actually parses these Secrets — `PemTrustSet.extractCerts()` throws
  `RuntimeException: The Secret ... does not contain any fields with the
  suffix .crt` if the Secret data is empty. The throwaway CA is never
  trusted by anything (operator talks to MSK over public-CA TLS via
  `STRIMZI_PUBLIC_CA=true`); it exists solely to satisfy the parser.

## [0.3.1](https://github.com/spartan-stratos/helm-charts/releases/tag/strimzi-user-operator-0.3.1) (2026-05-14)

### Features

* `nodeSelector`, `tolerations`, `affinity` values added to the Deployment.
  Required for clusters whose nodes carry taints (e.g. EKS Fargate adds
  `eks.amazonaws.com/compute-type=fargate:NoSchedule` to every node — pods
  without a matching toleration stay `Pending` with `FailedScheduling`).
  Defaults are empty so the chart still works on untainted clusters.

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
