# Changelog

All notable changes to this project will be documented in this file.

## [0.11.1](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.11.1) (2026-10-23)

### Bug Fixes

* `observability.logs.fileSidecar`:
  * `service_name` comes from the pod's `app.kubernetes.io/name`, as the node Alloy sets it. It was the release fullname, so a worker's lines (`<fullname>-worker-<name>` instead of `<appNameLabel>-<name>`) missed the dashboards and alert rules
  * `pod` joins `level`, `trace_id` and `span_id` as structured metadata, so one replica's lines can be told apart
  * Runs as the image's `alloy` user (473) with `runAsNonRoot`, so pods with a non-root `podSecurityContext` start; the log file must be readable by others or by `fsGroup`
  * Fails at render below Kubernetes 1.30, and when a `secret`/`configMap` file mount already sits at `path`

## [0.11.0](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.11.0) (2026-10-23)

### Features

* `observability.logs.fileSidecar`: an Alloy native sidecar on the Deployment and every worker that tails the app's log file into Loki, for pods no node log agent reaches (Fargate). Off by default; with it off the chart renders as on 0.10.0 (Kubernetes 1.30+ when on)
  * Reuses the directory of a `sidecars[]` entry sharing `path` (e.g. the datadog-agent's), else brings its own `emptyDir`, unlimited by default since a non-rotating `FileAppender` would get the pod evicted at a limit
  * `glob` defaults to `app.log`: a rotated name that still matches is read again from the start
  * `drainSeconds` (5): a preStop delay, since Alloy does not drain on SIGTERM; without it the last lines before a crash were lost in 5 of 6 local runs
  * Locked-down `securityContext`, optional `tenantId`; `level`, `trace_id` and `span_id` as structured metadata (Loki 3, schema v13)

## [0.10.0](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.10.0) (2026-10-16)

### Bug Fixes

* ConfigMap / Secret: render a permanent copy and a disposable hook twin, so the Deployment never mounts a hook-scoped object
  * `configmap.yaml` and `secret.yaml` stamped `helm.sh/hook`, `helm.sh/hook-weight` and `helm.sh/resource-policy: keep` onto all four objects whenever `.Values.hooks` was non-empty. The Deployment mounts two of them (`cm-as-file`, `secret-as-file`) and injects the other two via `envFrom`. A hook resource is transient while the Deployment is permanent, so once the object was collected no new pod could start: `MountVolume.SetUp failed for volume "<fullname>-cm-as-file": configmap "<fullname>-cm-as-file" not found`. `resource-policy: keep` was present and did not prevent this under ArgoCD
  * The permanent copy keeps its existing name and carries no hook annotations, so the Deployment's mount is unchanged and always satisfiable. A new `-hook`-suffixed twin (`<fullname>-cm-as-file-hook` and the other three) carries the hook annotations plus `helm.sh/hook-delete-policy: before-hook-creation` and no `resource-policy`, and the hook Job references the twin in `envFrom`, `volumeMounts` and `volumes`. Twins render only when some entry of `hooks` actually has `.commands`, matching the gate `hook.yaml` already applies to the Job
  * The twins live in new `hook-configmap.yaml` / `hook-secret.yaml` because `deployment.yaml` checksums `configmap.yaml` and `secret.yaml` whole; a twin inside those files would churn the pod template on every hook-only change
  * Unaffected: a release with no `hooks`, or with no `asFile`/`asEnv` flag set, rendered no hook annotations before and renders no twins now

### Upgrade notes

Only releases that set BOTH a non-empty `hooks` AND one of `configMap.asFile/asEnv` or `secret.asFile/asEnv` need anything here. Everyone else can bump straight across.

* **This is a minor bump, not a patch, on purpose.** For a plain `helm upgrade` consumer the upgrade needs a flag and possibly a manual annotation strip, so it is not a drop-in patch. A consumer pinned to `~0.9.x` would otherwise adopt it automatically and fail on `invalid ownership metadata` with no warning.
* **One rolling restart is expected.** `configmap.yaml` and `secret.yaml` changed content, and `deployment.yaml` checksums both files whole, so the pod template annotation changes once on this bump. The twins are deliberately outside that checksum
* **ArgoCD consumers:** a plain sync removes the stale annotations from the live objects. Verify by reading the live object, never by reading the sync status - a successful sync is exactly what would lie here:

  ```
  kubectl -n <ns> get cm <fullname>-cm-as-file -o jsonpath='{.metadata.annotations}'
  ```

  Acceptance is that `helm.sh/hook`, `helm.sh/hook-weight` and `helm.sh/resource-policy` are GONE.
* **Plain `helm upgrade` consumers:** the four objects exist in the cluster but were created as hook resources, so they carry no release-ownership metadata and `helm upgrade` refuses them with `exists and cannot be imported into the current release: invalid ownership metadata`. Use `--take-ownership`, which requires **helm >= 3.17** (3.16.4 does not have the flag and has no in-band remedy).
* **`--take-ownership` alone does not finish the job on a release that helm 3 installed.** Measured on k3d v1.31.5+k3s1, fresh install then upgrade onto the patched chart, reading the live ConfigMap back:

  | installed by | upgraded by | upgrade result | `helm.sh/hook` afterwards |
  |---|---|---|---|
  | helm 4.1.0 | helm 4.1.0 | deployed, rev 2 | gone |
  | helm 3.17.0 | helm 3.17.0 | deployed, rev 2 | still present |
  | helm 3.17.0 | helm 4.1.0 | deployed, rev 2 | still present |

  The variable is which helm INSTALLED the release, not which one runs the upgrade. In all three rows ownership transferred and the release reported `deployed`, so a helm 3 consumer sees a clean upgrade with no signal that the annotations are still there.

  What the residual annotations DO cost is a desired-versus-live difference that never converges: the rendered manifest no longer carries them, the live object does, and a client-side apply cannot remove a field absent from `last-applied-configuration`. Under ArgoCD self-heal that is a permanently OutOfSync resource being reconciled forever. It is NOT established that the original defect recurs - both Helm and ArgoCD decide whether a resource is a hook from the rendered manifest, not from the live object's annotations, so a de-hooked manifest should stop the collection that caused it. That has not been measured, so strip the annotations to converge the diff rather than on the assumption that the defect is still armed.
* **Why, and why the manual strip is the general fix rather than a lucky result.** helm 4 applies server-side: an applier that stops claiming a field it owned has that field removed by the API server, so the de-hooked manifest clears the annotations as a consequence of ownership semantics. helm 3 applies client-side with a three-way merge, which can only delete a field present in the OLD manifest - and a hook-created object is stored in the release's `hooks`, not its `manifest`, so no delete directive is ever generated. Nothing in the release wants those annotations back, and `kubectl annotate ...-` edits live state directly, which is the one path that bypasses the merge that cannot delete them. This predicts the strip holds on any helm 3.x, and is unnecessary on helm 4
* **Remediation on a helm-3-installed release**, after the upgrade:

  ```
  for o in cm/<fullname>-cm-as-file cm/<fullname>-cm-as-env \
           secret/<fullname>-secret-as-file secret/<fullname>-secret-as-env; do
    kubectl -n <ns> annotate "$o" \
      helm.sh/hook- helm.sh/hook-weight- helm.sh/resource-policy- --overwrite
  done
  ```

  Strip all three keys, so the live object matches the rendered manifest. Removing only `resource-policy` leaves `helm.sh/hook` and `hook-weight` behind and the diff unconverged.
* **There is no supported rollback to 0.9.x. Roll forward.** On 0.9.x the four objects are hook resources, so they sit in the release's `hooks` and NOT in its `manifest`; on 0.10.0 they are ordinary manifest resources with no `resource-policy: keep`. A `helm rollback` to a 0.9.x revision therefore diffs four objects against none and DELETES all four, and the rolled-back Deployment then mounts two that no longer exist and stops in `ContainerCreating`. The same applies to `helm upgrade --atomic` or `--cleanup-on-fail` if the upgrade fails after the main manifest applied. Reverting an ArgoCD `targetRevision` to 0.9.1 turns the tracked objects back into hook resources and, with auto-prune on, may prune them. Reasoned from Helm's manifest-diff semantics and the storage split measured above, not yet reproduced on a cluster. If you need to leave 0.10.0, recreate the four objects by hand before scaling the Deployment back up.
* **Do not delete the objects to force a clean recreate.** Measured: deleting the ConfigMap wedges the release - the Deployment cannot start a pod and the next hook phase does not recover it.

## [0.9.1](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.9.1) (2026-07-14)

### Bug Fixes

* CronJob: skip `sidecars[].skipDeployment` sidecars on the cronjob pod, matching the Deployment
  * `deployment.yaml` already filters `skipDeployment` sidecars out of both the shared-volume mount loop (`if and .sharedVolume (not .skipDeployment)`) and the sidecar-container injection loop (`if not $sidecar.skipDeployment`); `_cronjob.tpl` did not, so a `skipDeployment` sidecar (e.g. a hook-only `log-collector`) was still injected into the cronjob pod and its `sharedVolume` still mounted on the cronjob container
  * Impact: a service with BOTH a cronjob AND two sidecars whose `sharedVolume.mountPath` collide (e.g. `datadog-agent` + a Fluent Bit `log-collector` both at `/var/log/application/`) rendered a cronjob container with duplicate `volumeMounts` for that path. `helm template` does not validate it, but Kubernetes server-side apply rejects it (`failed to create typed patch object ... duplicate entries for key [mountPath=...]`), which breaks ArgoCD's server-side diff and stalls the sync. Now the cronjob excludes hook-only sidecars, matching the documented `skipDeployment` intent ("attach to hook Jobs only")
  * Backward compatible: sidecars without `skipDeployment` (e.g. `datadog-agent`) are unchanged on the cronjob; only `skipDeployment: true` sidecars change (now excluded, as on the Deployment)

## [0.9.0](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.9.0) (2026-07-11)

### Features

* Render `sidecars[].lifecycle` (postStart / preStop) on sidecar containers
  * Motivation: on pod termination all containers get SIGTERM concurrently, so a fast-exiting sidecar (e.g. the datadog-agent) can stop listening before the main app finishes its graceful shutdown - the app's final DogStatsD/trace sends then hit a dead port (`PortUnreachableException` on `:8125`). A `preStop` sleep on the sidecar keeps it alive through the app's drain window, ordering the shutdown without a fixed guess elsewhere
  * Example: `sidecars: [{name: datadog-agent, ..., lifecycle: {preStop: {exec: {command: ["/bin/sleep","15"]}}}}]` (keep the sleep < `terminationGracePeriodSeconds`)
  * Fully backward compatible: with no `sidecars[].lifecycle` set, rendered manifests are byte-identical to 0.8.0

## [0.8.0](https://github.com/spartan-stratos/helm-charts/releases/tag/spartan-0.8.0) (2026-07-11)

### Features

* Add `hooks[].logCollector.drain` for a deterministic hook log-collector shutdown, replacing the fixed-`sleep` guess in `stopCommand`
  * Motivation: a short-lived hook (e.g. a Liquibase/Flyway migration) can finish and be torn down before a tailing collector has shipped its final records. The old pattern - `stopCommand: "sleep N && pkill <collector>"` - has to out-guess (migration-remaining-time + flush-latency), so `N` is inherently non-deterministic: too small drops logs, too large wastes deploy time
  * When `drain.enabled: true`, the hook traps EXIT with a generated shell function that polls the collector's Fluent Bit metrics API (default `http://localhost:2020/api/v1/metrics`, each poll bounded by `curl --max-time 5`) and only stops the collector once the input count is stable across two polls (tail has finished reading an incrementally-written log) AND its output has shipped every record its input read (`proc_records >= records`), bounded by `drain.maxWaitSeconds` (default `60`) as a backstop. A stderr breadcrumb is emitted if the cap is reached. Tunable: `drain.metricsUrl`, `drain.processName` (default `fluent-bit`, the pkill process-name pattern), `drain.maxWaitSeconds`. Only valid for a single input + single output: records/proc_records are summed across all inputs/outputs, so with multiple outputs drain can stop before every output has flushed
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
