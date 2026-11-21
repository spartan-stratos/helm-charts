# Changelog

All notable changes to this project will be documented in this file.

## 0.3.1 (2026-11-20)

### Bug Fixes

* Give the global Slack AlertmanagerConfig a matcher-free null root, a continuing Slack child route and the four base inhibit rules.
* Copy the gateway metric resource namespace to the datapoint namespace when missing, so tenant ruler selectors match.
* Use the effective Grafana admin Secret name and keys for tenant organization provisioning.
* Document that tenant rules require gateway telemetry and self-contained alerts; tenant rulers do not support recording rules.

### Features

* A PostSync Job creates tenant Grafana organizations and missing Prometheus datasources when the dedicated metrics proxy is enabled.
* `tenantIsolation.enabled` defaults to false, dropping tenant logs and traces and withholding their datasources until backend tenant authentication is enabled.
* Tenant ids must be DNS-1123 labels of at most 30 characters, with no trailing hyphen; `platformTenant` and `fake` are reserved.
* Require tenant ports and reject duplicate tenant ids, duplicate ports, and ports that are not integers in 1024..65535.

## 0.3.0 (2026-11-20)

### Features

* Optional authenticated OTLP/HTTP gateway with dedicated receivers and fixed tenant headers.
* Platform Alloy and Grafana datasources send tenant headers. Backend tenant authentication remains disabled.
* Slack uses the global Alertmanager configuration; other routes are restricted by namespace.

## [0.2.4](https://github.com/spartan-stratos/helm-charts/releases/tag/lgtm-stack-0.2.4) (2026-11-20)

### Bug Fixes

* node-exporter no longer takes `placement.nodeSelector`, only its tolerations, the same as Alloy. With a nodeSelector
  set it ran on the pinned node alone, so host metrics covered one node. Clusters whose node pools carry other taints
  still need a wider toleration, e.g. `components.kubePrometheusStack.values.prometheus-node-exporter.tolerations`
  and `components.alloy.values.controller.tolerations` set to `[{ operator: Exists }]`

## [0.2.3](https://github.com/spartan-stratos/helm-charts/releases/tag/lgtm-stack-0.2.3) (2026-11-09)

### Features

* Grafana loads dashboards from every namespace (`sidecar.dashboards.searchNamespace: ALL`), so a project sharing the
  cluster ships its dashboards from its own GitOps repo into its own namespace, next to its rules. Datasources still
  load only from `monitoring`; the sidecar's ClusterRole is unchanged

### Bug Fixes

* Span metrics leave out health checks (`/health`, `/healthz`, `/livez`, `/readyz`, `/ping`, `/metrics`,
  `/prometheus`, also under `/actuator`) and `OPTIONS` requests, through Tempo's `filter_policies`. Probes and CORS
  preflights inflated the request rate and pulled p95 down on the RED dashboard and in `ServiceErrorRateHigh` /
  `ServiceLatencyHigh`. The spans stay in Tempo

## [0.2.2](https://github.com/spartan-stratos/helm-charts/releases/tag/lgtm-stack-0.2.2) (2026-10-20)

### Bug Fixes

* OTel Operator: its values go to ArgoCD as `helm.values` (a string) instead of `valuesObject`. In `valuesObject` the
  nulls that remove the chart's Helm hook annotations were dropped, so the webhook cert Secret stayed a pre-upgrade
  hook and was regenerated on syncs, while the ignored `caBundle` kept the first CA. The API server then failed the
  webhook TLS (`bad certificate`) and, with `failurePolicy: Ignore`, pods started without an agent

### Upgrading

Clusters on 0.2.1 or older may already have a cert that does not match the `caBundle` (operator log
`tls: bad certificate`, `PodMissingInstrumentation` firing). After syncing 0.2.2, delete the Secret
`opentelemetry-operator-controller-manager-service-cert` and the `opentelemetry-operator-mutation` and
`opentelemetry-operator-validation` webhook configurations so ArgoCD recreates them from one render, restart the
operator, then restart the instrumented workloads.

## [0.2.1](https://github.com/spartan-stratos/helm-charts/releases/tag/lgtm-stack-0.2.1) (2026-10-19)

### Bug Fixes

* Alloy takes only `placement`'s tolerations, not its nodeSelector, so the DaemonSet runs on every node: with a
  nodeSelector it ran only on the pinned node and missed the stdout of pods everywhere else
* Alloy's `k8sattributes` no longer filters to its own node, so OTLP routed from another node (or from Fargate) still
  gets Kubernetes attributes
* Slack messages link to Grafana when `grafana.domain` is set: the title opens the alert rule (it pointed at
  Alertmanager's in-cluster URL), plus `Dashboard` (from a rule's `dashboard_url`) and `Silence` links; the context line
  shows `service` for alerts without a namespace, and messages are grouped by `service` too

### Features

* `stackRules` addon (`lgtm-stack-rules`): `LgtmLokiDiscardingLogs`, `LgtmTempoDiscardingSpans`,
  `LgtmAlloyLokiWriteFailing`, `LgtmAlloyOtlpExportFailing`
* The chart's rules carry `dashboard_url`: RED for service alerts, the Pod dashboard for workload alerts,
  self-monitoring for PVC and stack alerts
* AIX and macOS node dashboards are off

## [0.2.0](https://github.com/spartan-stratos/helm-charts/releases/tag/lgtm-stack-0.2.0) (2026-10-18)

### Features

* Dashboards addon (`addons.dashboards`, Application `lgtm-dashboards`): one ConfigMap per `files/dashboards/<folder>/*.json`,
  loaded by the Grafana sidecar
  * `Services/Service overview (RED)` from Tempo span metrics, with callers, dependencies, error traces and logs
  * `LGTM/LGTM Lite self-monitoring`: node and pod usage, PVCs, Prometheus, Loki, Tempo and Alloy
* Alert rule bundles from `alerting.rules`, each its own Application
  * `services` (`lgtm-service-rules`): `ServiceErrorRateHigh` and `ServiceLatencyHigh` per service from Tempo span
    metrics, warning and critical, with `minRequestRate` and per-service `overrides`
  * `workloads` (`lgtm-workload-rules`): `ContainerImagePullFailing`, `ContainerOOMKilled`, `ContainerMemoryNearLimit`,
    `PodMissingInstrumentation`
* `project`: an Application (`lgtm-project`) syncing the project folder of its GitOps repo, with its dashboards and
  PrometheusRules (Helm, kustomize or plain YAML)

### Bug Fixes

* Alertmanager inhibit rules also match on `service`, so a critical on one service does not hide another's warning

## [0.1.1](https://github.com/spartan-stratos/helm-charts/releases/tag/lgtm-stack-0.1.1) (2026-10-16)

### Bug Fixes

* Annotate Prometheus and Alertmanager with `reloader.stakater.com/auto: "false"`. On a cluster whose Stakater Reloader
  runs with `--auto-reload-all`, every PrometheusRule or AlertmanagerConfig change restarted the pod and left a gap,
  although config-reloader already applies those changes in place

## [0.1.0](https://github.com/spartan-stratos/helm-charts/releases/tag/lgtm-stack-0.1.0) (2026-10-15)

### Features

* Initial LGTM Lite chart: renders one ArgoCD Application per component (kube-prometheus-stack, Grafana, Loki, Alloy,
  Tempo, OpenTelemetry Operator, plus the operator CRDs) with the Spartan presets built in
  * Plain manifests (cluster-info, PVC-fill rules, Grafana datasources, Instrumentation, Slack AlertmanagerConfig) are
    rendered by this chart in addon mode, so the whole stack moves with one chart version
  * `placement` pins every pod; `grafana.domain`, `grafana.ingress` and `grafana.sso` (Keycloak or GitHub) configure
    Grafana; `alerting.slack` adds the Slack receiver
  * `components.<c>.values` is merged last and keeps `false`, `""` and `null`
  * Upstream charts: prometheus-operator-crds 32.0.1, kube-prometheus-stack 91.9.0, grafana 13.2.6, loki 18.13.7,
    alloy 1.13.0, tempo 3.0.0, opentelemetry-operator 0.123.1
