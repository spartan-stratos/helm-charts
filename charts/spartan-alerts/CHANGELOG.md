# Changelog

All notable changes to this chart will be documented in this file.

## 0.6.1 (2026-11-27)

### Bug Fixes

* `NoReadyPods` now fires when the namespace still reports pod-phase series but none are Running for the workload. Before, an absent Running series meant the alert never evaluated.
* Missing telemetry still does not page: with no `kube_pod_status_phase` series in the namespace, the alert stays silent.

### Migration

* A namespace scaled fully to zero has no series and still does not fire.
* A workload with all pods gone can now fire while other pods in the namespace keep reporting, including a workload scaled to zero on purpose.

## 0.6.0 (2026-11-26)

### Features

* Show the alert tier after the status in the Slack title, for example `[FIRING:1] [P2] ApiDown (critical)`. Alerts without a `tier` label keep the old title.
* Add `alerting.tierRoutes` for a per-tier repeat interval on the same receiver. Empty by default, so routing is unchanged.
* Consumer rules with a `severity` label and no `tier` label get one: critical is P2, anything else is P3. An explicit tier is kept.

### Migration

* The Slack title changes for every alert that carries a `tier` label, including all catalogue alerts.
* Consumer alerts that had a `severity` and no `tier` now carry a `tier` label, so their alert identity changes and firing alerts resolve and refire once on upgrade.

## 0.5.1 (2026-11-26)

### Features

* Add optional `runs-on` input to the reusable consumer CI check, so a caller can run it on its own runner.
* The check tools install on Linux arm64 as well as amd64, into the runner's temp directory, with no `sudo`.

## 0.5.0 (2026-11-25)

### Features

* Derive service short names and expand tenant tokens in consumer groups.
* Add optional workload disabling, P1-P3 tier overrides and RDS storage percentages.
* Preserve existing resource names and labels for explicit consumer values.

### Migration

* In 0.4.1, unset `service.short` defaulted to `service` for every consumer; in 0.5.0, it derives from `service.name` with a leading `service-` removed.
  Consumers with unset `service.short` and `service.name` other than exactly `service` get new Alertmanager receiver, route and AlertmanagerConfig names on upgrade.
  Set `service.short: service` explicitly to keep the old names.

## 0.4.1 (2026-11-25)

### Features

* Add optional `values-artifact` input to the reusable consumer CI check for caller-generated values and tests.

## 0.4.0 (2026-11-25)

### Fixes

* Catalogue HTTP rules now also select on namespace, so a same-named service in another namespace no longer leaks into them.

### Features

* Add workload-specific catalogue rules and optional durable, JVM heap, database pool, and migration alerts.
* Add reusable consumer CI checks for rendered rules and selector scope.
* Change AlertmanagerConfig grouping, inhibition, and Slack workload text only when `catalogue.workloads` is set to a non-empty list.

## 0.3.0 (2026-11-25)

### Features

* Add an opt-in alert catalogue with source toggles, per-alert overrides, storage thresholds, runbook links, and critical-to-warning inhibition.

## 0.2.0 (2026-11-22)

### Features

* Add optional route matchers and resource name suffixes so releases can share a namespace and route alerts to different channels.

## [0.1.0](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-alerts-0.1.0) (2026-11-20)

### Features

* Add namespace and service alert routing to Slack, optional webhook secret synchronization, and consumer-supplied PrometheusRule groups.
