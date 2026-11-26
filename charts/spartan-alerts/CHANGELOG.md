# Changelog

All notable changes to this chart will be documented in this file.

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
