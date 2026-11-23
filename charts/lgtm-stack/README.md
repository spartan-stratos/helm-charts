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
    version: 0.11.0
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
| `tenantIsolation.enabled` | `false` | Enable tenant logs and traces only when backend tenant authentication is enabled |
| `placement.nodeSelector` / `.tolerations` | `{}` / `[]` | Pin every pod, e.g. to a dedicated node. Alloy and node-exporter (DaemonSets that read their own node) take only the tolerations, so they run on every node the tolerations admit; with a nodeSelector Alloy's Service uses `internalTrafficPolicy: Cluster`. To cover node pools with other taints, override both DaemonSets' tolerations under `components` |
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

### NetworkPolicy

`networkPolicy.enabled` defaults to `false`. Enabling it creates a separate `lgtm-network-policy` addon Application.
Its four ingress-only policies fence Loki, Tempo, Prometheus and Alertmanager pods in `namespace`.
They allow pods from that namespace and namespaces in `networkPolicy.allowFromNamespaces` (default `[]`) on all ports.
Grafana, the gateway, Alloy and prom-label-proxy are not fenced. Egress is unchanged.
This is a no-op unless the cluster CNI enforces NetworkPolicy. Check kubelet probe reachability when enforcement is turned on.

Rollback: set `networkPolicy.enabled: false`, sync, and verify the `lgtm-network-policy` child Application and its four NetworkPolicies are pruned.
Before turning the gateway's log or trace forwarding on for a tenant, check that each SDK's logs and spans carry the resource `k8s.namespace.name`; otherwise they are dropped.

Tenant receiver lists must contain at least one receiver, and receiver paths must start with `/`.
Gateway logs and traces without a resource namespace are dropped; namespace-less metrics remain accepted for ruler namespace injection.

### Secrets

The presets expect these Secrets in `monitoring`. They are not created by the chart; use External Secrets or create
them by hand.

| Secret | Keys | Used by |
|---|---|---|
| `grafana-admin` | `admin-user`, `admin-password` | Grafana admin. Set `components.grafana.values.admin.existingSecret: ""` to let the Grafana chart generate one |
| `grafana-secret-key` | `secret-key` | Grafana `secret_key` |
| `grafana-oauth` | `client-secret` | Grafana SSO, with `grafana.sso.provider` set |
| `alerting.slack.secretName` | `alerting.slack.secretKey` | Slack webhook URL. Required for Alertmanager reconciliation when Slack is enabled |

With `alerting.slack.enabled`, both the webhook Secret and AlertmanagerConfig `slack` must exist in `monitoring`.
The operator fails reconciliation with `failed to get global AlertmanagerConfig` when the global configuration is missing;
a missing webhook Secret also prevents reconciliation. Create the Secret before enabling Slack and sync the configuration addon.

### Tenant isolation

Tenant ids must match `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$` and contain at most 30 characters.
They use lowercase letters, digits and internal hyphens, starting and ending with a letter or digit.
The configured `platformTenant` (default `platform`) `fake` (Loki) and `single-tenant` (Tempo) are reserved tenant ids.
Tenant ids and gateway receiver ports must be unique. Ports must be integers in 1024..65535.

#### Tenant gateway receivers

A legacy tenant uses tenant-level `port` and `htpasswdSecret`, with ingress path `/<id>`.
To isolate environments under one tenant id, use `receivers` instead of those two tenant-level fields:

```yaml
tenants:
  - id: example
    namespaces: [example-dev, example-prod]
    receivers:
      - name: dev
        port: 4320
        path: /example
        namespaces: [example-dev]
        htpasswdSecret: { name: example-dev-otlp, key: htpasswd }
      - name: prod
        port: 4321
        ingress: false
        namespaces: [example-prod]
        htpasswdSecret: { name: example-prod-otlp, key: htpasswd }
gateway:
  ingress:
    enabled: true
    host: otlp.example.com
```

Each receiver has its own port, auth file and namespace filter, while all receivers write the same tenant id.
Receiver names must be unique within a tenant and DNS-1123 labels of at most 63 characters.
Each receiver requires a non-empty namespace list drawn from the tenant's namespaces.
The tenant-level namespace union still controls rulers, the label proxy and Grafana organizations.
Receiver paths default to `/<id>/<name>`; `ingress` defaults to true. Paths must be unique across all lanes,
and ingress paths cannot contain another ingress path at a `/` boundary. With `ingress: false`, send directly to
`http://alloy-gateway.monitoring.svc.cluster.local:<port>/<id>/<name>/v1/{metrics,logs,traces}`
(use the configured path when overridden). Public receivers use the ingress host and the same signal suffixes.
Namespace-less metrics still pass the filters; separate receivers do not close that existing gap. Logs and spans without a resource `k8s.namespace.name` are dropped.

The platform must label each tenant namespace `lgtm-stack/tenant=<id>` BEFORE its rules sync.
An unlabelled namespace's rules are evaluated by both the main Prometheus and the tenant ruler.

With `tenantIsolation.enabled: false`, tenant gateway receivers forward only metrics; logs and traces are dropped.
No tenant log or trace processors or exporters are generated. With `components.promLabelProxy.enabled: true`,
the tenant-org Job creates the Prometheus datasource, which queries through the tenant's label-enforcing proxy.
With `components.promLabelProxy.enabled: false`, no tenant Prometheus datasource is created.
The Job creates organizations and missing datasources; it does not remove existing ones.
Its admin Secret name and keys follow the effective Grafana `admin.existingSecret`, `admin.userKey` and `admin.passwordKey` values.

Metrics scraped inside the platform cluster carry no tenant label, so tenant rules cannot see them; tenant telemetry must arrive through the gateway.
Recording rules are not supported on tenant rulers; alerts must use self-contained expressions.

When tenant rulers are enabled and at least one tenant has namespaces, one ServiceMonitor scrapes their metrics with a `ruler` label.
Shared-channel alerts report each unavailable tenant ruler after 5m, plus rule evaluation and alert delivery failures sustained for 10m.
Check the affected ruler pod and its `prom-label-proxy-<id>` pod in `monitoring` first.

Set `tenantIsolation.enabled: true` in the same release that enables Loki `auth_enabled` and Tempo multitenancy, never before.
This restores tenant logs and traces and adds tenant Loki and Tempo datasources with fixed tenant headers.
The flag does not enable backend authentication itself. Platform Alloy and platform datasources are unaffected.

#### Auth flip

- Set all four values together in one release:
  - `tenantIsolation.enabled: true`
  - `components.loki.values.loki.auth_enabled: true`
  - `components.tempo.values.tempo.multitenancyEnabled: true` (under `tempo`; a top-level key does nothing)
  - `addons.grafanaDatasourcesLegacy.enabled: true`
- Platform Alloy and platform Grafana datasources already send the platform tenant header. The tenant gateway
  starts accepting logs and traces, and tenant Loki and Tempo datasources appear.
- Check ad-hoc readers and writers first: any other Loki or Tempo client without `X-Scope-OrgID` fails once auth is on.
- Pre-flip data belongs to tenant `fake` in Loki and `single-tenant` in Tempo; read it through the legacy datasources. Remove them once the configured
  retention has passed since the flip date. Defaults: Loki `336h` (14 days, `presets/loki.yaml`) and Tempo `168h`
  (7 days, `presets/tempo.yaml`). Deployments may override these; read the deployment's own retention values and
  count from its flip date.
- Rollback: revert the same four values together. Data written after the flip under `platform` or tenant ids is
  invisible to single-tenant Loki or Tempo, leaving a gap for that window after rollback.
- Verify Loki `/loki/api/v1/query_range` and Tempo `/api/search` with an explicit `X-Scope-OrgID: platform` or
  `X-Scope-OrgID: <tenant>` header per tenant. Platform queries must see platform data; each tenant must see only
  its own data, excluding data known to belong to another tenant.

### Grafana SSO

Keycloak (`provider: keycloak`): `url`, `realm`, `clientId`, `admin` and `member` (Keycloak group names). The client
needs redirect URI `https://<domain>/login/generic_oauth` and a **Group Membership** mapper with claim `groups` and
**Full group path off**; with it on, Keycloak sends `/sre` instead of `sre` and login fails with "IdP did not return
a role attribute". `admin` groups get Grafana Admin, `member` groups Editor, anyone else is refused.

Optional `grafana.sso.keycloak.buttonName` (default `SSO`) sets the login button label; the provider id and redirect URI are unchanged.

For optional tenant organization membership from Keycloak groups, see [Tenant Grafana access](#tenant-grafana-access).

GitHub (`provider: github`): `organization`, `clientId`, `admin` and `member` (team slugs); callback
`https://<domain>/login/github`.

Both presets turn the login form off; set `components.grafana.values."grafana.ini".auth.disable_login_form: false` to
keep it as break-glass.

## Onboarding a tenant

A tenant is a project. Every env namespace of the project writes metrics, logs and traces under one tenant id through the gateway, and its alert rules run only in the tenant ruler.

1. Namespaces: one namespace per env, unique names, each labelled `lgtm-stack/tenant=<id>` before its rules sync.
   - For namespaces created by the `eks-cluster` Terraform module, set the label with `custom_namespace_labels` (module v1.4.0 or later). Do not also manage it with a `kubernetes_labels` resource. The two fight over the label.
2. Stack values: add `tenants[]` with the id and the env namespaces. Give each env its own `receivers[]` entry (port, namespaces, auth Secret) so one credential cannot write another env's namespace. Public receivers need `gateway.ingress`; receivers on the platform cluster use `ingress: false`.
3. Credentials: one htpasswd line per receiver, stored in the Secret named by `htpasswdSecret` in `monitoring` (key `htpasswd`). Optionally set `htpasswdExternalSecret` to sync it from a secret store. The gateway pods stay Pending until that Secret exists. The matching plaintext goes to the sender as a Secret with keys `username` and `password`.
   - Use AWS secret `lgtm/tenants/<tenant>-<env>/otlp-basic-auth` with JSON keys `username`, `password` and `htpasswd`. The sender reads `username` and `password`. Gateway-side `htpasswdExternalSecret` reads `htpasswd` from the same entry. It is available since chart 0.10.0 and off by default.
   - Use one IRSA role per consumer. Trust exactly `system:serviceaccount:<ns>:<sa>`, with no wildcard. Allow only `secretsmanager:GetSecretValue` and `secretsmanager:DescribeSecret` on that one secret.
   - Cross-account: the role lives in the cluster account. The secret's resource policy and its KMS key policy must both allow that role.
   - ExternalSecrets refresh every `1h`. Apply a rotated value now with `kubectl annotate externalsecret <name> -n <ns> force-sync=<epoch> --overwrite`.
4. Telemetry: the app namespace runs an OpenTelemetry Instrumentation or SDK that exports OTLP to the tenant receiver. Logs and spans must carry the resource attribute `k8s.namespace.name`, or the gateway drops them.
   - Use the shared [lgtm-tenant-client](../lgtm-tenant-client/README.md) chart. A service must not carry its own copy of the ServiceAccount, SecretStore, ExternalSecret or Instrumentation plumbing.
   - A dev app may use in-cluster Alloy with no per-app credential. A file-tail sidecar ships logs to port `3100` at `/loki/api/v1/push`. Set `OTEL_LOGS_EXPORTER=none`. Prod sends OTLP logs through its receiver and runs no sidecar.
   - Since chart 0.9.0, the gateway drops logs and spans without a namespace attribute. It does not drop metrics. A series without a namespace label cannot be isolated by the label proxy or tenant ruler.
5. Rules and alert routes: one `spartan-alerts` release per env namespace. The tenant ruler adds `namespace=<rule namespace>` to every selector, so a rule needs no namespace matcher. Alerts with no matching AlertmanagerConfig route to the unrouted channel.
   - Slack routes match severity `warning|critical` only. The root null route drops `info`. An alert matching no route goes to `UNROUTED`. Delivery proof is exactly one `SyntheticTest` warning alert, never re-posted.

### Verify a tenant

- Search Tempo with header `X-Scope-OrgID: <tenant>`.
- In prod, Loki stores `namespace` as structured metadata. Query `{service_name="<svc>"} | namespace="<ns>"`. A `{namespace="<ns>"}` stream selector returns nothing.
- Query metrics through the tenant label proxy datasource.

### Tenant Grafana access

Off by default. Set `grafana.sso.provider: keycloak`, `grafana.orgMapping.enabled: true` and each tenant's `tenants[].grafana.viewers` / `editors` lists.
Keycloak groups `lgtm-<tenant>-viewer` and `lgtm-<tenant>-editor` must exist and be assigned to the `grafana` client `groups` claim, with **Full group path off**.
Membership of a tenant Grafana organization comes only from those groups. Groups in `grafana.sso.keycloak.admin` keep Admin in every organization via `<group>:*:Admin`; tenant groups get Viewer or Editor only, never Admin.
A tenant group name may not be empty, equal an SSO admin group, or contain `:`, `,`, whitespace or braces.
SSO admin group names are held to the same character rules when org mapping is enabled.
This defaults to off, with rendering unchanged when off. `role_attribute_path` and `role_attribute_strict` are not changed.

```yaml
grafana:
  sso: { provider: keycloak }
  orgMapping: { enabled: true }
tenants:
  - id: tenant-a
    grafana:
      viewers: [lgtm-tenant-a-viewer]
      editors: [lgtm-tenant-a-editor]
  - id: tenant-b
    grafana:
      viewers: [lgtm-tenant-b-viewer]
      editors: [lgtm-tenant-b-editor]
```

Grafana semantics (verified from the Grafana 13 documentation):

- `org_mapping` entries are `<ExternalName>:<OrgIdOrName>:<Role>`, so an organization name is accepted; the tenant organization is named after the tenant id.
- Roles from `org_mapping` and `role_attribute_path` combine, and the user gets the highest role.
- `org_attribute_path` must return an array; `groups` is one.
- `role_attribute_strict` denies login only when neither `role_attribute_path` nor `org_mapping` yields a role, so a user in only a tenant group is now admitted.
- `*` matches any organization.

Not yet exercised against a live Grafana: test on a non-production Grafana before enabling in production, including that platform admins still reach the main organization and that a user with no mapped group is refused.

### Sender on another cluster

Sender on another cluster, using an Alloy collector that forwards all three signals to a public receiver:

```alloy
otelcol.receiver.otlp "apps" {
  http { endpoint = "0.0.0.0:4318" }
  grpc { endpoint = "0.0.0.0:4317" }
  output {
    metrics = [otelcol.processor.batch.out.input]
    logs    = [otelcol.processor.batch.out.input]
    traces  = [otelcol.processor.batch.out.input]
  }
}

otelcol.processor.batch "out" {
  output {
    metrics = [otelcol.exporter.otlphttp.gateway.input]
    logs    = [otelcol.exporter.otlphttp.gateway.input]
    traces  = [otelcol.exporter.otlphttp.gateway.input]
  }
}

otelcol.auth.basic "gateway" {
  username = sys.env("OTLP_USERNAME")
  password = sys.env("OTLP_PASSWORD")
}

// The exporter appends /v1/{metrics,logs,traces} to the receiver path.
otelcol.exporter.otlphttp "gateway" {
  client {
    endpoint = "https://otlp.example.com/<id>"
    auth     = otelcol.auth.basic.gateway.handler
  }
}
```

Mount `OTLP_USERNAME` and `OTLP_PASSWORD` from the sender's Secret with `secretKeyRef`. To sync the credentials from a secret store instead of creating them by hand, an ExternalSecret in the sender's namespace maps the store entry to those two keys:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: <id>-otlp-client
spec:
  refreshInterval: 1h
  secretStoreRef: { name: <store>, kind: SecretStore }
  target: { name: <id>-otlp-client }
  data:
    - { secretKey: username, remoteRef: { key: lgtm/tenants/<tenant>-<env>/otlp-basic-auth, property: username } }
    - { secretKey: password, remoteRef: { key: lgtm/tenants/<tenant>-<env>/otlp-basic-auth, property: password } }
```

### Gateway htpasswd ExternalSecret

Set `htpasswdExternalSecret` on a receiver, or alongside `htpasswdSecret` on a legacy tenant without `receivers`:

```yaml
tenants:
  - id: <tenant>
    namespaces: [<namespace>]
    receivers:
      - name: <receiver>
        port: 4320
        namespaces: [<namespace>]
        htpasswdSecret: { name: <secret>, key: htpasswd }
        htpasswdExternalSecret:
          secretStore: { name: <store>, kind: SecretStore }
          remoteKey: <store entry>
          property: htpasswd
          refreshInterval: 1h
```

The gateway addon Application renders the ExternalSecret in the stack namespace (`namespace`, default `monitoring`),
where the External Secrets operator creates the Secret. This also works with `gateway.ingress.enabled: false`.
The operator and referenced store must already exist. `secretStore.name`, `secretStore.kind`, `remoteKey` and
`htpasswdSecret.name` are required. `property` and `htpasswdSecret.key` default to `htpasswd`;
`refreshInterval` defaults to `1h`. The target uses `creationPolicy: Owner` and `deletionPolicy: Retain`.
Without this option, create the gateway-side Secret separately. Store only references in chart values.

## Dashboards

Grafana's sidecar loads every ConfigMap labelled `grafana_dashboard: "1"`, in any namespace, and files it in the
folder named by annotation `grafana_folder`. Three sources use it:

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

### Projects sharing the cluster

`project` syncs one folder, from the repo that installs the stack. Another project on the same cluster keeps the same
folder in its own GitOps repo and deploys it with its own Application into its own namespace; nothing changes here.
Prometheus excludes rules in namespaces labelled `lgtm-stack/tenant`; tenant rulers evaluate their configured namespaces.
ServiceMonitors remain cluster-wide, and Grafana loads dashboards from every
namespace. Name the Grafana folder after the project and keep dashboard `uid`s unique across projects: two dashboards
with one `uid` replace each other.

## Alerting

Prometheus evaluates the PrometheusRules (kube-prometheus-stack's defaults, this chart's bundles below and the
project folder's rules, excluding namespaces labelled `lgtm-stack/tenant`) and Alertmanager
routes them; Grafana shows them read-only. Grafana contact points do not receive these alerts: they belong to
Grafana's own Alertmanager.

With `alerting.slack.enabled`, AlertmanagerConfig `slack` is the global config with the four base inhibit rules and a matcher-free root.
Its Slack child route continues so tenant routes still run. It sends `severity` warning and critical, grouped by alertname,
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

`alerting.slack.sharedNamespaces` limits the shared route to listed namespaces and cluster-level alerts, overriding
`ownedNamespaces`, which keeps only critical alerts from namespaces with their own routes.
`alerting.slack.unrouted.enabled` defaults to true: alerts claimed by no tenant or shared route post to the same webhook
with an `[UNROUTED]` title and guidance to add a `spartan-alerts` release or list the namespace in `sharedNamespaces`.
Severity `info` and `none` never reach this fallback; missing or other severities can. Set it false to keep the old silent drop.

### Service alerts

`alerting.rules.services` turns Tempo span metrics (server spans) into four recording rules per service
(`service:traces_spanmetrics_{calls,errors,error_ratio,latency_p95}:rate5m`) and two alerts, each at warning and
critical:

| Alert | Fires when | Default warning / critical |
|---|---|---|
| `ServiceErrorRateHigh` | share of server spans with status ERROR is above the threshold for `errorRate.for` | 2% / 5%, 10m |
| `ServiceLatencyHigh` | p95 of server spans is above the threshold (seconds) for `latencyP95.for` | 1s / 3s, 10m |

`namespaces.<service>: <namespace>` adds a static `namespace` label to that service's alerts, so tenant routes that match on namespace (OnNamespace strategy) receive them. A mapped service gets its own alert set and is excluded from the default set; unmapped services are unchanged.

Services below `minRequestRate` (0.1 req/s) are not alerted on. `overrides.<service>` is merged over the defaults for
that service, e.g. `payments: { errorRate: { critical: 0.01 } }`, or `batch: { enabled: false }` to skip it; drop a
severity's threshold to skip that severity. The alerts carry `service` (inhibition matches on it, so one service's
critical does not hide another's warning) but no `namespace`, which span metrics do not have.

Span metrics leave out health checks (`url.path` `/health`, `/healthz`, `/livez`, `/readyz`, `/ping`, `/metrics`,
`/prometheus`, each also under `/actuator`, and their subpaths) and `OPTIONS` requests, so probes and CORS preflights
do not inflate the request rate or pull p95 down. The spans stay in Tempo. To change the list, set
`components.tempo.values.tempo.overrides.defaults.metrics_generator.processor.span_metrics.filter_policies` (it
replaces the whole list).

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
