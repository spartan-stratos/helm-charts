# Changelog

All notable changes to this project will be documented in this file.

## [0.1.18](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.18) (2025-10-30)

### Features

* Add topologySpreadConstraints support
  * Global `topologySpreadConstraints` for the main Deployment
  * Per-worker `workers[].topologySpreadConstraints` with fallback to global
* Add per-worker PodDisruptionBudgets (PDBs)
  * Enable via `workers[].pdb.enabled`
  * Support `minAvailable` or `maxUnavailable`
  * Safe rendering only when `replicaCount > 1` or `autoscaling.minReplicas > 1`

## [0.1.17](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.17) (2025-01-XX)

### Features

* **Deployment Annotations**: Added `deploymentAnnotations` for custom deployment annotations
  * Supports any custom annotations for monitoring, backup, and other tool integrations
  * Users can define their own annotations directly in `deploymentAnnotations`
  * Examples provided for common annotation patterns (monitoring, backup, custom labels)

### Documentation

* Added comprehensive deployment annotations documentation in README.md
* Updated chart documentation with deployment annotations configuration options

## [0.1.16](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.16) (2025-09-17)

### Features

* Added optional fields on CronJob.spec and jobTemplate.spec:
  
  * concurrencyPolicy, startingDeadlineSeconds, suspend, timeZone 
  * backoffLimit, activeDeadlineSeconds, ttlSecondsAfterFinished, completions, parallelism

## [0.1.15](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.15) (2025-08-20)

### Bug Fixes

* Fix the extraEnvs when the list is empty, that caused syntax error.

## [0.1.14](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.14) (2025-05-22)

### Features

* Added support for custom `volumes` in `values.yaml`, allowing users to define and mount arbitrary volumes for
  `deployment.yaml`, including hostPath volumes.
* Added a preStop hook which will execute after the pods got signal to be terminated. After that it will execute the
  script defined in `Values.lifecycle.preStop.command`. By using that, we should add a sleep timeout for about `10s` to
  `30s` to make sure pod could successfully complete request before terminated

## [0.1.13](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.13) (2025-05-22)

### Features

* Add `args` as a configurable param in the `deployment.yaml` template of the `spartan` chart. The values can be
  configured in the `values.yaml`.

## [0.1.12](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.12) (2025-05-08)

### Features

* Fix helm issue (wrong reference to persistence values. Should be .Values.persistence instead of .persistence)

## [0.1.11](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.11) (2025-05-07)

### Features

* Add ability to add persistent volumes for the main deployment

## [0.1.10](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.10) (2025-05-05)

### Features

* Add ability to custom command of the main deployment

## [0.1.9](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.9) (2025-03-18)

### Features

* Enable transfer of HPA ownership in `keda` ScaledObject

## [0.1.8](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.8) (2025-01-22)

### Features

* Add the `keda` configuration to support autoscaling by using [Keda](https://keda.sh/)

## [0.1.7](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.7) (2025-01-20)

### Features

* Update the `cronjob` configuration
    * Fix `pkill agent` to terminate the `datadog-agent` pod
    * Add `metadata` and some common configurations

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

* Update `worker labels` to fix the duplication labels for multiple workers
  definitions [#1](https://github.com/spartan-stratos/helm-charts/pull/11)

## [0.1.2](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.2) (2024-12-27)

### Features

* Add `collectLog` field in hook to enable/disable collect the logs from
  datadog-agent [#9](https://github.com/spartan-stratos/helm-charts/pull/9)

## [0.1.1](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.1) (2024-11-20)

### Bug Fixes

* Add missing delimiters among tpl of cronjob, hook, worker and
  worker-hpa [#4](https://github.com/spartan-stratos/helm-charts/pull/4)

## [0.1.0](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.0) (2024-11-11)

### Features

* Initial commit with spartan chart.
