# lgtm-stack

LGTM Lite as ArgoCD Applications: Prometheus + Alertmanager (kube-prometheus-stack), Grafana, Loki, Alloy, Tempo and
the OpenTelemetry Operator, with the Spartan presets built in. The chart renders **ArgoCD Application CRs** (app of
apps), not the workloads themselves, so each component keeps its own sync wave, retries and ignored diffs.

A project installs it as one Application and keeps one values file. Updating the stack is a chart version bump.

## Install

The project's ArgoCD repo wraps the chart, so Dependabot's `helm` ecosystem opens a PR for every new version. The
scaffold is `templates/lgtm-stack/` in spartan-sre-wiki.

```yaml
# lgtm-stack/Chart.yaml
apiVersion: v2
name: lgtm-stack-<cluster>
version: 1.0.0
dependencies:
  - name: lgtm-stack
    version: 0.2.1
    repository: https://spartan-stratos.github.io/helm-charts
```

```yaml
# lgtm-stack/values.yaml (values go under the dependency name)
lgtm-stack:
  argocd:
    project: <argocd project>
    destination: { name: <target cluster> }
  cluster:
    name: <cluster name>
```

```yaml
# apps/lgtm-stack.yaml, read by the project's root Application
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: lgtm-stack
  namespace: argocd
spec:
  project: <argocd project>
  destination:
    name: in-cluster        # the ArgoCD cluster: the chart renders Application CRs
    namespace: argocd
  source:
    repoURL: <this repo>
    targetRevision: master
    path: lgtm-stack
    helm:
      releaseName: lgtm-stack
  syncPolicy:
    automated: { prune: true, selfHeal: true }
```

The AppProject must allow this Helm repository, the upstream chart repositories in `values.yaml`, the ArgoCD
namespace on the ArgoCD cluster (for the Application CRs) and the target cluster. It must also allow the
cluster-scoped kinds the charts render: Namespace, CustomResourceDefinition, ClusterRole, ClusterRoleBinding,
MutatingWebhookConfiguration and ValidatingWebhookConfiguration.

Before the first sync, the target cluster needs the `gp3-enc-retain` StorageClass (EBS CSI driver, gp3, encrypted,
`Retain`, `WaitForFirstConsumer`, expansion allowed). The `eks-lgtm` Terraform module creates it with the node.

## What gets created

| Application | Wave | Source |
|---|---|---|
| `lgtm-cluster-info` | 10 | ConfigMap `monitoring-cluster-info` (`CLUSTER_NAME`, read by Alloy) |
| `lgtm-prometheus-operator-crds` | 20 | `prometheus-operator-crds` |
| `lgtm-kube-prometheus-stack` | 30 | `kube-prometheus-stack` + `presets/kube-prometheus-stack.yaml` |
| `lgtm-pvc-fill-rules` | 31 | PrometheusRule `lgtm-pvc-fill` |
| `lgtm-alertmanager-config` | 32 | AlertmanagerConfig `slack` (only with `alerting.slack.enabled`) |
| `lgtm-service-rules` | 33 | PrometheusRule `lgtm-service-red` from `alerting.rules.services` |
| `lgtm-workload-rules` | 34 | PrometheusRule `lgtm-workloads` from `alerting.rules.workloads` |
| `lgtm-stack-rules` | 35 | PrometheusRule `lgtm-stack`: Loki, Tempo or Alloy dropping data |
| `lgtm-grafana` | 40 | `grafana` + `presets/grafana.yaml` (+ `grafana-sso-<provider>.yaml`) |
| `lgtm-dashboards` | 41 | Dashboard ConfigMaps from `files/dashboards/` |
| `lgtm-project` | 42 | The project folder: its dashboards and rules (only with `project.enabled`) |
| `lgtm-loki` | 50 | `loki` + `presets/loki.yaml` |
| `lgtm-grafana-datasources` | 51 | Loki and Tempo datasource ConfigMaps |
| `lgtm-alloy` | 52 | `alloy` + `presets/alloy.yaml` |
| `lgtm-tempo` | 60 | `tempo` + `presets/tempo.yaml` |
| `lgtm-opentelemetry-operator` | 61 | `opentelemetry-operator` + `presets/opentelemetry-operator.yaml` |
| `lgtm-instrumentation` | 62 | Instrumentation `monitoring/default` |

Everything lands in namespace `monitoring`; the presets reference each other through `*.monitoring.svc.cluster.local`.
Apps send OTLP to `http://alloy.monitoring.svc.cluster.local:4318`.

The plain manifests (rows without an upstream chart) are rendered by this same chart in addon mode: their
Applications point back at `lgtm-stack` at the same version, so the whole stack moves with one version.

## Values

Each component's Helm values are built in this order, later wins:

1. `presets/<component>.yaml`
2. `placement`: nodeSelector and tolerations at every pod path the chart has (e.g. all six in kube-prometheus-stack)
3. settings derived from the top-level values (`cluster.name`, `grafana.*`, `alerting.*`)
4. `components.<component>.values`

The merge is key by key and keeps `false`, `""` and `null` from the later layer; a `null` removes the upstream chart's
default. Lists are replaced, not appended.

| Value | Default | Description |
|---|---|---|
| `argocd.project` | `""` | AppProject for the Applications. Required |
| `argocd.destination.name` / `.server` | `""` | Target cluster. One is required |
| `argocd.namespace` | `argocd` | Namespace of the Application CRs |
| `argocd.namePrefix` | `lgtm-` | Application name prefix |
| `argocd.syncPolicy` | automated, retry 10 | Shared syncPolicy. `RespectIgnoreDifferences=true` is added where diffs are ignored |
| `cluster.name` | `""` | `cluster` label on metrics, logs and Slack messages. Required |
| `placement.nodeSelector` / `.tolerations` | `{}` / `[]` | Pin every pod, e.g. to a dedicated node. Alloy (a DaemonSet that tails each node's logs) takes only the tolerations, so it runs on every node; with a nodeSelector its Service uses `internalTrafficPolicy: Cluster` |
| `grafana.domain` | `""` | `root_url` and Ingress host |
| `grafana.ingress.enabled` / `.className` / `.annotations` | `false` / `alb` / `{}` | Grafana Ingress |
| `grafana.sso.provider` | `none` | `keycloak` or `github` adds the matching preset; settings in `grafana.sso.<provider>` |
| `alerting.slack.enabled` | `false` | Slack receiver for warning and critical alerts |
| `alerting.slack.secretName` / `.secretKey` | `alert-slack` / `webhook-url` | Secret holding the Slack webhook URL |
| `components.<c>.enabled` | `true` | Drop a component |
| `components.<c>.chart` | pinned | Upstream chart repoURL, name and version |
| `components.<c>.values` | `{}` | Any value of the upstream chart, merged last |
| `components.<c>.ignoreDifferences` | `[]` | Appended to the built-in list |
| `addons.<a>.enabled` | `true` | `clusterInfo`, `pvcFillRules`, `stackRules`, `grafanaDatasources`, `instrumentation`, `dashboards` |
| `alerting.rules.services.*` | on, see [Service alerts](#service-alerts) | RED alerts per service; thresholds, `minRequestRate`, `overrides.<service>` |
| `alerting.rules.workloads.*` | on, `memoryLimitRatio: 0.9` | See [Workload alerts](#workload-alerts) |
| `project.enabled` | `false` | Sync the project folder (dashboards and rules) from the project's repo, see [Project folder](#project-folder) |
| `project.repoURL` / `.path` / `.targetRevision` | `""` / `""` / `HEAD` | Where that folder is. `repoURL` and `path` are required |
| `self.*` | this chart's repo and version | Where the addon Applications pull this chart; set `repoURL` (git), `path` and `targetRevision` to test a branch |

### Secrets

The presets expect these Secrets in `monitoring`. They are not created by the chart; use External Secrets or create
them by hand.

| Secret | Keys | Used by |
|---|---|---|
| `grafana-admin` | `admin-user`, `admin-password` | Grafana admin. Set `components.grafana.values.admin.existingSecret: ""` to let the Grafana chart generate one |
| `grafana-secret-key` | `secret-key` | Grafana `secret_key` |
| `grafana-oauth` | `client-secret` | Grafana SSO, with `grafana.sso.provider` set |
| `alerting.slack.secretName` | `alerting.slack.secretKey` | Slack webhook URL. Until it exists the operator skips the receiver and Alertmanager keeps running |

### Grafana SSO

Keycloak (`provider: keycloak`): `url`, `realm`, `clientId`, `admin` and `member` (Keycloak group names). The client
needs redirect URI `https://<domain>/login/generic_oauth` and a **Group Membership** mapper with claim `groups` and
**Full group path off**; with it on, Keycloak sends `/sre` instead of `sre` and login fails with "IdP did not return
a role attribute". `admin` groups get Grafana Admin, `member` groups Editor, anyone else is refused.

GitHub (`provider: github`): `organization`, `clientId`, `admin` and `member` (team slugs); callback
`https://<domain>/login/github`.

Both presets turn the login form off; set `components.grafana.values."grafana.ini".auth.disable_login_form: false` to
keep it as break-glass.

## Dashboards

Grafana's sidecar loads every ConfigMap in `monitoring` labelled `grafana_dashboard: "1"` and files it in the folder
named by annotation `grafana_folder`. Three sources use it:

| Folder | Dashboards | From |
|---|---|---|
| `Kubernetes` | Cluster, node, workload and Prometheus dashboards | kube-prometheus-stack |
| `Services` | **Service overview (RED)**: rate, errors and latency per service and route from Tempo span metrics (server spans), callers and dependencies, the service graph, recent error traces and logs | this chart |
| `LGTM` | **LGTM Lite self-monitoring**: node and pod usage against the sizing thresholds, PVCs, Prometheus series and TSDB size, Loki, Tempo and Alloy throughput and drops | this chart |

The RED dashboard is empty until a service sends traces (the `spartan` chart's `observability` block).

A project's own dashboards go in its [project folder](#project-folder).

### Changing a dashboard

Provisioned dashboards cannot be saved from the UI. Edit in Grafana (or a copy of it), then Export → JSON with
**Export for sharing externally off** so the datasource uids stay `prometheus`, `loki` and `tempo`, and commit the file.
Keep the dashboard `uid` fixed: links and bookmarks use it.

## Project folder

A project keeps its own dashboards and alert rules in one folder of its GitOps repo, synced by `project`:

```yaml
lgtm-stack:
  project:
    enabled: true
    repoURL: <this repo>
    path: observability
```

```
observability/
  Chart.yaml
  templates/dashboards.yaml   # dashboards/<folder>/<name>.json -> ConfigMap, <folder> is the Grafana folder
  templates/rules.yaml        # rules/<name>.yaml (a Prometheus rule file: groups:) -> PrometheusRule <name>
  dashboards/<folder>/<name>.json
  rules/<name>.yaml
```

ArgoCD detects the folder type, so kustomize or plain YAML work too, as long as the output is the same ConfigMaps and
PrometheusRules. The Helm chart below needs no list of files, and a rule file stays a plain Prometheus rule file, so
`promtool check rules rules/*.yaml` and `promtool test rules` run on it directly. The scaffold is
`templates/lgtm-stack/argocd/observability/` in spartan-sre-wiki.

```yaml
# observability/Chart.yaml
apiVersion: v2
name: observability
version: 1.0.0
```

```yaml
# observability/templates/dashboards.yaml
{{- range $path, $_ := .Files.Glob "dashboards/*/*.json" }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: dashboard-{{ base $path | trimSuffix ".json" }}
  labels:
    grafana_dashboard: "1"
  annotations:
    grafana_folder: {{ base (dir $path) | quote }}
data:
  {{ base $path }}: {{ $.Files.Get $path | quote }}
{{- end }}
```

```yaml
# observability/templates/rules.yaml
{{- range $path, $_ := .Files.Glob "rules/*.yaml" }}
---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: {{ base $path | trimSuffix ".yaml" }}
spec: {{- $.Files.Get $path | nindent 2 }}
{{- end }}
```

Names share `monitoring` with the stack's objects: avoid the `lgtm-` prefix. Label rules with `severity` (`info`,
`warning`, `critical`) for routing, and keep `{{ $labels.x }}` as is in annotations: Helm does not template the files.
An annotation `dashboard_url` (a Grafana path such as `/d/<uid>/<slug>?var-x={{ $labels.x }}`) adds a Dashboard link to
the Slack message.

## Alerting

Prometheus evaluates the PrometheusRules (kube-prometheus-stack's defaults, this chart's bundles below and the
project folder's rules; every PrometheusRule in the cluster is selected) and Alertmanager
routes them; Grafana shows them read-only. Grafana contact points do not receive these alerts: they belong to
Grafana's own Alertmanager.

With `alerting.slack.enabled`, AlertmanagerConfig `slack` sends `severity` warning and critical, grouped by alertname,
namespace and service, repeated every 4h, with resolved notices. Info alerts stay in Grafana. With `grafana.domain` set,
the message links to Grafana:

| Link | Opens |
| --- | --- |
| The title | Grafana's alert rule list filtered to the alert (Alertmanager's own URL is in-cluster only) |
| `Runbook` | The rule's `runbook_url` |
| `Dashboard` | The rule's `dashboard_url`: RED for service alerts, the Pod dashboard for workload alerts, self-monitoring for the stack's own |
| `Silence` | A new silence in Grafana, pre-filled with the group's `alertname`, `namespace` and `service` |

To silence a noisy kube-prometheus-stack default, set
`components.kubePrometheusStack.values.defaultRules.disabled.<AlertName>: true`.

### Service alerts

`alerting.rules.services` turns Tempo span metrics (server spans) into four recording rules per service
(`service:traces_spanmetrics_{calls,errors,error_ratio,latency_p95}:rate5m`) and two alerts, each at warning and
critical:

| Alert | Fires when | Default warning / critical |
|---|---|---|
| `ServiceErrorRateHigh` | share of server spans with status ERROR is above the threshold for `errorRate.for` | 2% / 5%, 10m |
| `ServiceLatencyHigh` | p95 of server spans is above the threshold (seconds) for `latencyP95.for` | 1s / 3s, 10m |

Services below `minRequestRate` (0.1 req/s) are not alerted on. `overrides.<service>` is merged over the defaults for
that service, e.g. `payments: { errorRate: { critical: 0.01 } }`, or `batch: { enabled: false }` to skip it; drop a
severity's threshold to skip that severity. The alerts carry `service` (inhibition matches on it, so one service's
critical does not hide another's warning) but no `namespace`, which span metrics do not have.

When one fires: open the Service overview (RED) dashboard for the service, then its recent error traces or the slowest
route, and the logs linked from the trace.

### Workload alerts

`alerting.rules.workloads` adds what kube-prometheus-stack's defaults leave out:

| Alert | Fires when |
|---|---|
| `ContainerImagePullFailing` | a container waits on `ErrImagePull` / `ImagePullBackOff` / `InvalidImageName` for 5m |
| `ContainerOOMKilled` | a container restarted in the last 15m and its last termination was `OOMKilled` |
| `ContainerMemoryNearLimit` | working set above `memoryLimitRatio` (90%) of the memory limit for 15m |
| `PodMissingInstrumentation` | a Running pod is annotated `instrumentation.opentelemetry.io/inject-*` but has no agent for 5m (it started while the OTel Operator was down; restart it) |

All are `warning`. Crash loops, failed Jobs and not-ready pods come from the defaults (`KubePodCrashLooping`,
`KubeJobFailed`, `KubePodNotReady`).

### Stack alerts

`lgtm-stack` alerts when the stack loses data it was sent. All are `warning`, after 10m:

| Alert | Fires when | Look at |
| --- | --- | --- |
| `LgtmLokiDiscardingLogs` | Loki refuses lines (`reason`: rate or stream limits, line too long, too old) | Loki limits in `components.loki.values`, the client sending the burst |
| `LgtmTempoDiscardingSpans` | Tempo refuses spans (`reason`: trace too large, rate limits) | Tempo overrides in `components.tempo.values` |
| `LgtmAlloyLokiWriteFailing` | Alloy drops log batches it could not push | Loki up and Ready, the Alloy pod's logs |
| `LgtmAlloyOtlpExportFailing` | Alloy fails to deliver app traces, metrics or logs | Tempo, Prometheus (remote-write receiver) and Loki, the Alloy pod's logs |

### PVC-fill alerts

Lite runs on fixed-size disks with no backups, so `lgtm-pvc-fill` watches the stack's own PVCs in `monitoring`:

| Alert | Fires at | For | Severity |
|---|---|---|---|
| `LgtmPvcFilling` | used bytes > 75% / 90% / 95% | 15m / 10m / 5m | info / warning / critical |
| `LgtmPvcInodesFilling` | used inodes > 90% / 95% | 10m / 5m | warning / critical |

They sit on top of kube-prometheus-stack's `KubePersistentVolumeFillingUp`, which waits until 3% free or a 4-day
prediction. The preset's inhibit rules add `persistentvolumeclaim` and `service` to `equal`, so each PVC shows only its highest tier
and one PVC's critical does not hide another's warning.

When one fires:

1. Find what grows: Prometheus `prometheus_tsdb_storage_blocks_bytes`, Loki ingestion by stream, Tempo blocks.
2. Expand the PVC: raise the component's size in `components.<c>.values` (`gp3-enc-retain` allows expansion; EBS
   grows online). For Prometheus, raise `retentionSize` with it.
3. Or shorten the component's retention.
4. Inodes: expanding the volume adds inodes; shortening retention removes files.

## Known diffs ArgoCD ignores

| Application | Ignored | Why |
|---|---|---|
| `lgtm-kube-prometheus-stack` | webhook `caBundle` | Patched by the admission Jobs after sync |
| `lgtm-grafana` | Secret `grafana` data, Deployment `checksum/secret` | Random admin password on every render when the chart generates it |
| `lgtm-opentelemetry-operator` | webhook cert Secret data, webhook `caBundle` | Cert generated on every render; the first pair is kept |

The OTel Operator's values go to ArgoCD as `helm.values` (a string), not `valuesObject`: the preset nulls the chart's
Helm hook annotations on the cert Secret, and nulls do not survive in `valuesObject`.

## Development

```sh
helm unittest charts/lgtm-stack
helm template x charts/lgtm-stack -f charts/lgtm-stack/ci/test-values.yaml
charts/lgtm-stack/files/tests/test-rules.sh   # promtool rule tests, plain and rendered bundles; needs helm, yq and promtool
charts/lgtm-stack/files/tests/test-dashboards.sh   # dashboard JSON, uids and datasource uids; needs jq
```

To change a preset, edit `presets/` and bump the chart version. A new shared dashboard is one JSON file in
`files/dashboards/<folder>/`. To bump an upstream chart, change
`components.<c>.chart.version` in `values.yaml`; keep `prometheus-operator-crds` on the CRDs that match
kube-prometheus-stack's operator.
