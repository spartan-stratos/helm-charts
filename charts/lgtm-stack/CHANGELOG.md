# Changelog

All notable changes to this project will be documented in this file.

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
