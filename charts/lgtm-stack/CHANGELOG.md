# Changelog

All notable changes to this project will be documented in this file.

## 0.11.2 (2026-11-23)

### Documentation

- Complete tenant onboarding guidance: shared client chart, secret naming, per-consumer IRSA, cross-account, force-sync, verification and alert routing.

## 0.11.1 (2026-11-23)

### Features

* Add sso.keycloak.buttonName to set the Grafana login button label, default SSO (was Keycloak).

## 0.11.0 (2026-11-23)

### Features

* Add optional Grafana organization membership from Keycloak groups via `grafana.orgMapping.enabled` and `tenants[].grafana.viewers` / `editors`, off by default.

## 0.10.0 (2026-11-23)

### Features

* Add optional gateway htpasswd ExternalSecrets per receiver or legacy tenant, including when gateway ingress is disabled.

## 0.9.1 (2026-11-23)

### Bug Fixes

* Match Prometheus and Alertmanager NetworkPolicies to their live pod labels.

## 0.9.0 (2026-11-23)

### Features

* Add optional backend ingress NetworkPolicies allowing the stack namespace and explicitly allowed namespaces.

### Bug Fixes

* Reject empty tenant receiver lists and receiver paths that do not start with `/`.
* Drop tenant logs and traces without a resource namespace; namespace-less metrics remain accepted.

## 0.8.0 (2026-11-22)

### Features

* Add per-environment gateway receivers with separate credentials, ports and namespace allowlists under one tenant id, with optional ingress paths.

## 0.7.0 (2026-11-22)

### Features

* Scrape tenant rulers and alert on unavailable rulers, rule evaluation failures and alert delivery failures in the shared channel.

## 0.6.0 (2026-11-22)

### Features

* Unclaimed warning and critical alerts now post to the shared webhook as `[UNROUTED]` by default. Set `alerting.slack.unrouted.enabled: false` to keep the old drop.

## 0.5.1 (2026-11-22)

### Bug Fixes

* The legacy Tempo datasource now sends `X-Scope-OrgID: single-tenant`, the id Tempo gives pre-flip traces when authentication is off. It sent `fake` (Loki's id), so legacy trace searches found nothing. The legacy Loki datasource is unchanged.
* `single-tenant` is now a reserved tenant id alongside `fake`: a tenant with that id would read the pre-flip traces.

## 0.5.0 (2026-11-22)

### Breaking changes

* Removed `alerting.slack.toolNamespaces` and `alerting.slack.toolSecretName` (added in 0.4.3). Routing a set of namespaces to their own channel is deployment config: give each namespace its own AlertmanagerConfig with the `spartan-alerts` chart. Rendering with neither value set is unchanged.

## 0.4.2 (2026-11-22)

### Features

* Set `alerting.rules.services.namespaces.<service>: <namespace>` to stamp a `namespace` label on that service's RED alerts. Mapped services get their own alert set (the default set excludes them); unmapped services render unchanged. Needed when Alertmanager uses the OnNamespace matcher strategy.

## 0.4.1 (2026-11-22)

### Features

* Set `alerting.slack.sharedNamespaces` to send only listed namespaces and cluster-level warning and critical alerts to the shared Slack channel. When set, it overrides `ownedNamespaces`.

## 0.4.0 (2026-11-22)

### Features

* Add default-off `addons.grafanaDatasourcesLegacy`: Loki and Tempo datasources send `X-Scope-OrgID: fake` so history written before the auth flip stays readable.
* Document the coordinated auth flip, retention, rollback data gap and tenant verification. No defaults change; the default render differs from 0.3.6 only in the child Applications' `targetRevision`, which tracks the chart version.

## 0.3.6 (2026-11-22)

### Features

* Per-component Application annotations via `components.<key>.annotations` let one Application opt out of controller-wide server-side diff. This avoids dry-run failures when an `ignoreDifferences` rule for `/data` strips a Secret's required keys.

## 0.3.5 (2026-11-21)

### Bug Fixes

* The default Instrumentation carries `java.image` from `addons.instrumentation.javaImage` (default autoinstrumentation-java 2.22.0). An operator with no built-in Java image injected an init container with an empty image and every annotated pod was rejected, so the setting now lives in git instead of on the cluster. Set it empty to omit.

## 0.3.4 (2026-11-21)

### Features

* `alerting.slack.ownedNamespaces` splits the shared Slack route: warning and critical alerts from unowned namespaces still post there, while an owned namespace posts only its critical alerts, so its own AlertmanagerConfig can route warnings to a project channel. Empty by default, which changes nothing. Add a namespace only after its own route exists.

## 0.3.3 (2026-11-21)

### Bug Fixes

* The gateway drops telemetry whose `k8s.namespace.name` is outside the tenant's `namespaces`. Before this, a tenant credential could write series for another namespace, which that namespace's alert rules would then select.

## 0.3.2 (2026-11-21)

### Bug Fixes

* Write the gateway receiver `max_request_body_size` as the string `"4MiB"`. Alloy rejects a bare integer (`unknown unit`), so every gateway pod crash-looped on start; the unit test had asserted the integer.

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
