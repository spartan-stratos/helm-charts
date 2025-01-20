# Changelog

All notable changes to this project will be documented in this file.

## [0.1.6](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.6) (2025-01-20)
### Features
* Fix indentation error in `_cronjob.tpl`

## [0.1.5](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.5) (2025-01-11)
### Features
* Update PodDisruptionBudget creation condition

## [0.1.4](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.4) (2025-01-08)
### Features
* Allow users to define custom PersistentVolumeClaims
* Allow cronjobs to mount PersistentVolume

## [0.1.3](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.3) (2024-12-31)

### Features

* Update `worker labels` to fix the duplication labels for multiple workers definitions [#1](https://github.com/spartan-stratos/helm-charts/pull/11)

## [0.1.2](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.2) (2024-12-27)

### Features

* Add `collectLog` field in hook to enable/disable collect the logs from datadog-agent [#9](https://github.com/spartan-stratos/helm-charts/pull/9)

## [0.1.1](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.1) (2024-11-20)

### Bug Fixes

* Add missing delimiters among tpl of cronjob, hook, worker and worker-hpa [#4](https://github.com/spartan-stratos/helm-charts/pull/4)

## [0.1.0](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.0) (2024-11-11)

### Features

* Initial commit with spartan chart.
