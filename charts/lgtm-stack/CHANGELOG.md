# Changelog

All notable changes to this project will be documented in this file.

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
