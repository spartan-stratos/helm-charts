# Changelog

All notable changes to this project will be documented in this file.

## [0.8.0](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.8.0) (2026-07-11)

### Features

* Add `hooks[].logCollector.drain` for a deterministic hook log-collector shutdown, replacing the fixed-`sleep` guess in `stopCommand`
  * Motivation: a short-lived hook (e.g. a Liquibase/Flyway migration) can finish and be torn down before a tailing collector has shipped its final records. The old pattern - `stopCommand: "sleep N && pkill <collector>"` - has to out-guess (migration-remaining-time + flush-latency), so `N` is inherently non-deterministic: too small drops logs, too large wastes deploy time
  * When `drain.enabled: true`, the hook traps EXIT with a generated shell function that polls the collector's Fluent Bit metrics API (default `http://localhost:2020/api/v1/metrics`, each poll bounded by `curl --max-time 5`) and only stops the collector once the input count is stable across two polls (tail has finished reading an incrementally-written log) AND its output has shipped every record its input read (`proc_records >= records`), bounded by `drain.maxWaitSeconds` (default `60`) as a backstop. A stderr breadcrumb is emitted if the cap is reached. Tunable: `drain.metricsUrl`, `drain.processName` (default `fluent-bit`, the pkill process-name pattern), `drain.maxWaitSeconds`. Assumes a single input + single output (records are summed)
  * With `drain.enabled`, `logCollector.stopCommand` becomes optional for a non-`datadog-agent` collector (the drain function is the stop mechanism); the collector must expose the Fluent Bit HTTP metrics server
  * Fully backward compatible: with `drain` unset, rendered manifests are byte-identical to 0.7.0 (the `stopCommand` trap path is unchanged, and it remains required for non-`datadog-agent` collectors)

## [0.7.0](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.7.0) (2026-07-09)

### Features

* Add `datadog.cloudProviderMetadataEnabled` (default `true`) across the datadog-agent renderers (sidecar / worker / hook / cronjob / deployment)
  * Set to `false` on EKS Fargate, where the pod cannot reach the EC2 IMDS (`169.254.169.254`). It renders `DD_CLOUD_PROVIDER_METADATA=""`, so the agent stops probing IMDS and logging `Could not fetch instance type for AWS: ... context deadline exceeded`
  * Fully backward compatible: with the value unset no env var is added, so rendered manifests are byte-identical to 0.6.0

## [0.6.0](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.6.0) (2026-07-09)

### Features

* Add `datadog.clusterAgentEnabled` and `datadog.orchestratorExplorerEnabled` (both default `true`) to toggle `DD_CLUSTER_AGENT_ENABLED` and `DD_ORCHESTRATOR_EXPLORER_ENABLED` on the datadog-agent containers (sidecar / worker / hook / cronjob / deployment)
  * Set both to `false` for per-pod agents that have no Datadog Cluster Agent connection wired in (e.g. EKS Fargate sidecars). This stops two coupled log-spam sources: the `failed to load cluster agent auth token: ... cluster_agent.auth_token: no such file or directory` error, and the `Cluster Agent not ready yet, skipping orchestrator_pod check` warnings/errors. The Orchestrator Explorer requires the Cluster Agent, so it is non-functional on such agents regardless
  * Fully backward compatible: with the values unset the rendered manifests are byte-identical to 0.5.0 (both env vars still `"true"`)

## [0.5.0](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.5.0) (2026-07-07)

### Features

* Make the hook log collector pluggable via an optional per-hook `logCollector` block
  * `logCollector.sidecarName` (default `datadog-agent`), `logCollector.readyCommand` (default the Datadog APM `:8126` wait), `logCollector.stopCommand` (default `sleep 10 && pkill agent`)
  * Lets a lightweight sidecar (e.g. Fluent Bit) collect the migration log instead of the full Datadog Agent image - smaller pull, faster hook start on nodes without an image cache (notably EKS Fargate)
  * Fully backward compatible: with no `logCollector` set the rendered hook Job is byte-identical to 0.4.0 (Datadog Agent readiness wait + `DD_*` env + `pkill agent` shutdown unchanged)
* Add `sidecars[].skipDeployment` (default false) to attach a sidecar to hook Jobs only, never the Deployment
  * Lets a hook-scoped log collector run on the migration Job while the long-running pod keeps its own sidecar set (e.g. the Datadog Agent for APM) unchanged
  * Default false renders the Deployment byte-identically to 0.4.0

## [0.4.0](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.4.0) (2026-05-19)

### Features

* Add `checksum/configmap` and `checksum/secret` pod-template annotations to worker Deployments
  * `deployment.yaml` already emitted these in 0.3.0 for the main Deployment; this extends parity to the worker templates in `_worker.tpl`
  * Workers now roll automatically when the chart-rendered ConfigMap or Secret content changes (env-var rotation, broker DNS change after MSK cluster recreate, SCRAM credential rotation, etc.)
  * Eliminates the manual `kubectl rollout restart` step that was previously required after Helm value changes that flow into the chart's own ConfigMap/Secret

## [0.2.0](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.2.0) (2026-05-06)

### Features

* Add `projected` volume type support in the custom `volumes` list
  * Enables Kubernetes projected ServiceAccountToken volumes required for GCP Workload Identity Federation (WIF)
  * Previously unrecognised volume types silently fell back to `emptyDir`; `projected` sources are now rendered correctly

## [0.1.23](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.23) (2026-04-28)

### Features

* Add global `podLabels` support across Spartan pod templates
  * Applies to the main Deployment, workers, CronJobs, and hooks
  * Keeps workload selectors unchanged while allowing extra operational labels on pods

## [0.1.22](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.22) (2026-04-04)
* Add optional per-path `servicePort` in Ingress for routing different paths to different Service ports.

## [0.1.21](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.21) (2026-04-03)

### Features

* Add optional `service.ports` list for multi-port Service support.
  * When `service.ports` is non-empty, the Service renders all listed ports.
  * When empty or unset, falls back to the existing `service.port` single-port behavior (no breaking change).
* Add `spartan.servicePrimaryPort` helper used by Ingress, test-connection, and NOTES.

## [0.1.20](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.20) (2026-04-01)

### Features

* Add optional top-level `terminationGracePeriodSeconds` support for the main application Deployment.

## [0.1.19](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.1.19) (2026-03-23)

### Bug Fixes

* Add optional `hooks[].deletePolicy` so Argo CD-managed hooks can rerun on every sync.

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
