{{/* Reject removed switches even when explicitly set to false. */}}
{{- define "lgtm-stack.validateRemovedGrafanaKeys" -}}
{{- range $key := list "orgMapping" "tenantFolders" "tenantDashboards" -}}
{{- if hasKey (index $.Values.grafana $key | default dict) "enabled" -}}
{{- fail (printf "grafana.%s.enabled was removed in 0.13.0: org mapping is now on when a tenant has grafana.viewers or grafana.editors groups; delete the key" $key) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Mapping applies to all tenants when any tenant declares Grafana groups. */}}
{{- define "lgtm-stack.orgMapping" -}}
{{- $active := false -}}
{{- range .Values.tenants -}}
{{- $grafana := .grafana | default dict -}}
{{- if or $grafana.viewers $grafana.editors -}}{{- $active = true -}}{{- end -}}
{{- end -}}
{{- if $active -}}true{{- end -}}
{{- end -}}

{{/* Dashboard providers require the org and folder provisioned by org mapping. */}}
{{- define "lgtm-stack.validateTenantDashboards" -}}
{{- $mapping := include "lgtm-stack.orgMapping" . -}}
{{- range .Values.tenants -}}
{{- if and (hasKey (.grafana | default dict) "orgId") (not $mapping) -}}
{{- fail "tenants[].grafana.orgId requires tenant Grafana viewers or editors groups; dashboards need the organization and folder from the tenant-orgs job" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "lgtm-stack.validateSettleSeconds" -}}
{{- $mapping := include "lgtm-stack.orgMapping" . -}}
{{- if $mapping -}}
{{- $settle := dig "settleSeconds" 120 .Values.grafana.orgMapping -}}
{{- if not (regexMatch "^[0-9]+$" (toString $settle)) -}}
{{- fail "grafana.orgMapping.settleSeconds must be a non-negative integer" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "lgtm-stack.hasTenantDashboards" -}}
{{- range .Values.tenants -}}
{{- if hasKey (.grafana | default dict) "orgId" -}}true{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Deep merge (list dst src): src wins key by key, including false, "" and null, which sprig's mergeOverwrite would skip.
A null reaches the upstream chart as null, so it still deletes that chart's default. Mutates dst.
*/}}
{{- define "lgtm-stack.merge" -}}
{{- $dst := index . 0 -}}
{{- range $k, $v := index . 1 -}}
{{- if and (kindIs "map" $v) (kindIs "map" (index $dst $k)) -}}
{{- include "lgtm-stack.merge" (list (index $dst $k) $v) -}}
{{- else -}}
{{- $_ := set $dst $k (deepCopy $v) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Flatten receivers so legacy tenants retain their lane index and rendered names. */}}
{{- define "lgtm-stack.gatewayLanes" -}}
{{- $lanes := list -}}
{{- range .Values.tenants -}}
{{- $tenant := . -}}
{{- if hasKey . "receivers" -}}
{{- range .receivers -}}
{{- $ingress := true -}}
{{- if hasKey . "ingress" -}}{{- $ingress = .ingress -}}{{- end -}}
{{- $lanes = append $lanes (dict "id" $tenant.id "name" .name "port" .port "path" (.path | default (printf "/%s/%s" $tenant.id .name)) "ingress" $ingress "namespaces" .namespaces "htpasswdSecret" (.htpasswdSecret | default dict)) -}}
{{- end -}}
{{- else -}}
{{- $lanes = append $lanes (dict "id" .id "name" .id "port" .port "path" (printf "/%s" .id) "ingress" true "namespaces" .namespaces "htpasswdSecret" (.htpasswdSecret | default dict)) -}}
{{- end -}}
{{- end -}}
{{- toYaml $lanes -}}
{{- end -}}

{{/* Nested map from a dotted path: (list "a.b" $leaf) -> {a: {b: $leaf}}; "" returns $leaf */}}
{{- define "lgtm-stack.atPath" -}}
{{- $out := index . 1 -}}
{{- if index . 0 -}}
{{- range reverse (splitList "." (index . 0)) -}}
{{- $out = dict . $out -}}
{{- end -}}
{{- end -}}
{{- toYaml $out -}}
{{- end -}}

{{/*
The components: Application name, Helm release, sync wave, preset files, where each chart takes nodeSelector and
tolerations, and the diffs ArgoCD must ignore. Returned as YAML; keys match .Values.components.
*/}}
{{- define "lgtm-stack.components" -}}
prometheusOperatorCrds:
  app: prometheus-operator-crds
  wave: 20
  presets: []
  placement: []
kubePrometheusStack:
  app: kube-prometheus-stack
  wave: 30
  presets: [kube-prometheus-stack.yaml]
  placement:
    - prometheusOperator
    - prometheusOperator.admissionWebhooks.patch
    - prometheus.prometheusSpec
    - alertmanager.alertmanagerSpec
    - kube-state-metrics
  # node-exporter is absent: it is a DaemonSet reading its own node, so it takes only tolerations (generated below)
  # The admission Jobs patch the webhook caBundle after sync
  ignoreDifferences:
    - group: admissionregistration.k8s.io
      kind: MutatingWebhookConfiguration
      jqPathExpressions: ['.webhooks[]?.clientConfig.caBundle']
    - group: admissionregistration.k8s.io
      kind: ValidatingWebhookConfiguration
      jqPathExpressions: ['.webhooks[]?.clientConfig.caBundle']
grafana:
  app: grafana
  wave: 40
  presets: [grafana.yaml]
  placement: [""]
  # The chart makes a new random admin password on every render when no existing Secret is set; keep the first one
  ignoreDifferences:
    - kind: Secret
      name: grafana
      jsonPointers: [/data]
    - group: apps
      kind: Deployment
      name: grafana
      jqPathExpressions: ['.spec.template.metadata.annotations."checksum/secret"']
loki:
  app: loki
  wave: 50
  presets: [loki.yaml]
  placement: [singleBinary]
# The DaemonSet tails logs on its own node, so it must run on every node: it takes placement's tolerations
# (generated below), never its nodeSelector
alloy:
  app: alloy
  wave: 52
  presets: [alloy.yaml]
  placement: []
tempo:
  app: tempo
  wave: 60
  presets: [tempo.yaml]
  placement: [""]
alloyGateway:
  app: alloy-gateway
  wave: 53
  presets: [alloy-gateway.yaml]
  placement: [controller]
opentelemetryOperator:
  app: opentelemetry-operator
  wave: 61
  presets: [opentelemetry-operator.yaml]
  placement: [""]
  # The chart generates the webhook cert on every render; as a plain resource (hook annotations nulled below) ArgoCD
  # creates it once and keeps it with the matching caBundle. The nulls survive only in helm.values: in valuesObject
  # they are dropped, the hooks stay, and every sync makes a new cert that no longer matches the caBundle.
  valuesAsString: true
  ignoreDifferences:
    - group: admissionregistration.k8s.io
      kind: MutatingWebhookConfiguration
      jqPathExpressions: ['.webhooks[]?.clientConfig.caBundle']
    - group: admissionregistration.k8s.io
      kind: ValidatingWebhookConfiguration
      jqPathExpressions: ['.webhooks[]?.clientConfig.caBundle']
    - kind: Secret
      name: opentelemetry-operator-controller-manager-service-cert
      jsonPointers: [/data]
{{- end -}}

{{/* Addons: Application name, sync wave, manifest files (or dashboards: ConfigMaps from files/dashboards) */}}
{{- define "lgtm-stack.addons" -}}
clusterInfo:
  app: cluster-info
  wave: 10
  files: [cluster-info.yaml]
networkPolicy:
  app: network-policy
  wave: 10
  files: []
gateway:
  app: gateway
  wave: 54
  files: []
tenantRules:
  app: tenant-rules
  wave: 32
  files: []
logRules:
  app: log-rules
  wave: 49
  files: []
tenantOrgs:
  app: grafana-tenant-orgs
  wave: 61
  files: []
# One ConfigMap per files/dashboards/<folder>/<name>.json; the Grafana sidecar loads them, so no ordering is needed
dashboards:
  app: dashboards
  wave: 41
  dashboards: true
# Needs the PrometheusRule CRD
pvcFillRules:
  app: pvc-fill-rules
  wave: 31
  files: [pvc-fill-rules.yaml]
# Loki, Tempo or Alloy dropping data
stackRules:
  app: stack-rules
  wave: 35
  files: [stack-rules.yaml]
# Rendered from alerting.rules.services / .workloads; need the PrometheusRule CRD
serviceRules:
  app: service-rules
  wave: 33
  rules: services
workloadRules:
  app: workload-rules
  wave: 34
  rules: workloads
# Needs the AlertmanagerConfig CRD and the Alertmanager
alertmanagerConfig:
  app: alertmanager-config
  wave: 32
  files: [alertmanager-slack.yaml]
grafanaDatasources:
  app: grafana-datasources
  wave: 51
  files: [grafana-datasource-loki.yaml, grafana-datasource-tempo.yaml]
grafanaDatasourcesLegacy:
  app: grafana-datasources-legacy
  wave: 51
  files: [grafana-datasource-loki-legacy.yaml, grafana-datasource-tempo-legacy.yaml]
# Needs the operator's CRD and webhook
instrumentation:
  app: instrumentation
  wave: 62
  files: [instrumentation.yaml]
{{- end -}}

{{/* Settings this chart derives from the top-level values, per component: (list $ key) */}}
{{- define "lgtm-stack.generated" -}}
{{- $ := index . 0 -}}
{{- $key := index . 1 -}}
{{- $v := $.Values -}}
{{- $mapping := include "lgtm-stack.orgMapping" $ -}}
{{- if and (eq $key "loki") $v.logRules.enabled }}
{{- $containers := list }}
{{- $volumes := list (dict "name" "rules-platform" "configMap" (dict "name" "loki-rules-platform")) }}
{{- $mounts := list (dict "name" "rules-platform" "mountPath" "/rules/platform" "readOnly" true) }}
{{- $overrides := dict }}
{{- $alertmanager := "http://kube-prometheus-stack-alertmanager.monitoring.svc.cluster.local:9093" }}
{{- $index := 0 }}
{{- /* Sidecars share the pod network, so the default health port 8080 collides for a second tenant. */}}
{{- range $tenant := $v.tenants }}
{{- if $tenant.namespaces }}
{{- $healthPort := add 8080 $index }}
{{- $volume := printf "rules-%d" $index }}
{{- $path := printf "/rules/%s" $tenant.id }}
{{- $ruleNamespaces := $tenant.namespaces }}
{{- if hasKey $tenant "ruleNamespaces" }}{{ $ruleNamespaces = $tenant.ruleNamespaces }}{{ end }}
{{- $volumes = append $volumes (dict "name" $volume "emptyDir" dict) }}
{{- $mounts = append $mounts (dict "name" $volume "mountPath" $path "readOnly" true) }}
{{- $env := list }}
{{- range $name, $value := dict "LABEL" "loki_rule" "FOLDER" $path "NAMESPACE" (join "," $ruleNamespaces) "RESOURCE" "configmap" "METHOD" "WATCH" "UNIQUE_FILENAMES" "true" "HEALTH_PORT" (toString $healthPort) "WATCH_SERVER_TIMEOUT" "60" "WATCH_CLIENT_TIMEOUT" "60" }}
{{- $env = append $env (dict "name" $name "value" $value) }}
{{- end }}
{{- $security := dict "readOnlyRootFilesystem" true "allowPrivilegeEscalation" false "capabilities" (dict "drop" (list "ALL")) "seccompProfile" (dict "type" "RuntimeDefault") }}
{{- /* Isolate writable volumes because k8s-sidecar-target-directory can override FOLDER. */}}
{{- $containers = append $containers (dict "name" (printf "rules-%s" $tenant.id) "image" $v.logRules.sidecar.image "env" $env "ports" (list (dict "name" (printf "http-rules-%d" $index) "containerPort" $healthPort)) "resources" $v.logRules.sidecar.resources "securityContext" $security "volumeMounts" (list (dict "name" $volume "mountPath" $path))) }}
{{- $index = int (add1 $index) }}
{{- /* Loki has no enforcedNamespaceLabel, so keep tenant namespaces to prevent routing forged alerts to the shared channel. */}}
{{- $relabels := list (dict "action" "keep" "source_labels" (list "namespace") "regex" (printf "^(%s)$" (join "|" $tenant.namespaces))) (dict "action" "replace" "target_label" "tenant" "replacement" $tenant.id) }}
{{- $_ := set $overrides $tenant.id (dict "ruler_max_rule_groups_per_tenant" $v.logRules.limits.maxRuleGroupsPerTenant "ruler_max_rules_per_rule_group" $v.logRules.limits.maxRulesPerRuleGroup "ruler_alertmanager_config" (dict "alertmanager_url" $alertmanager "enable_alertmanager_v2" true "alert_relabel_configs" $relabels)) }}
{{- end }}
{{- end }}
loki:
  rulerConfig:
    wal:
      dir: /var/loki/ruler-wal
    storage:
      type: local
      local:
        directory: /rules
    rule_path: /var/loki/rules-tmp
    alertmanager_url: {{ $alertmanager }}
    enable_alertmanager_v2: true
    enable_api: true
    ring:
      kvstore:
        store: inmemory
  runtimeConfig:
    overrides: {{ toYaml $overrides | nindent 6 }}
singleBinary:
  extraVolumes: {{ toYaml $volumes | nindent 4 }}
  extraVolumeMounts: {{ toYaml $mounts | nindent 4 }}
  extraContainers: {{ toYaml $containers | nindent 4 }}
{{- else if eq $key "kubePrometheusStack" }}
{{- with $v.placement.tolerations }}
prometheus-node-exporter:
  tolerations: {{- toYaml . | nindent 4 }}
{{- end }}
prometheus:
  prometheusSpec:
    externalLabels:
      cluster: {{ $v.cluster.name | quote }}
alertmanager:
  alertmanagerSpec:
    alertmanagerConfigMatcherStrategy:
      type: OnNamespace
{{- if $v.alerting.slack.enabled }}
    # The platform route must receive alerts from every namespace.
    alertmanagerConfiguration:
      name: slack
{{- end }}
{{- else if eq $key "grafana" }}
{{- if include "lgtm-stack.hasTenantDashboards" $ }}
{{- $platform := $v.grafana.tenantDashboards.platformNamespaces }}
{{- if empty $platform }}{{ fail "grafana.tenantDashboards.platformNamespaces must not be empty" }}{{ end }}
{{- range $key := list "extraContainers" "extraVolumes" "extraVolumeMounts" "extraObjects" }}
{{- if hasKey $v.components.grafana.values $key }}{{ fail (printf "grafana.tenantDashboards cannot be combined with components.grafana.values.%s" $key) }}{{ end }}
{{- end }}
{{- if hasKey (dig "sidecar" "dashboards" dict $v.components.grafana.values) "searchNamespace" }}{{ fail "grafana.tenantDashboards cannot be combined with components.grafana.values.sidecar.dashboards.searchNamespace" }}{{ end }}
{{- if hasKey (dig "dashboardProviders" dict $v.components.grafana.values) "tenant-dashboardproviders.yaml" }}{{ fail "grafana.tenantDashboards cannot be combined with components.grafana.values.dashboardProviders.tenant-dashboardproviders.yaml" }}{{ end }}
{{- range $platform }}
{{- if eq (upper (toString .)) "ALL" }}{{ fail "grafana.tenantDashboards.platformNamespaces must not contain ALL" }}{{ end }}
{{- if or (not (kindIs "string" .)) (not (regexMatch "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$" (toString .))) (gt (len (toString .)) 63) }}{{ fail "grafana.tenantDashboards.platformNamespaces must contain DNS-1123 labels" }}{{ end }}
{{- end }}
{{- $namespaces := dict }}
{{- $orgIds := dict }}
{{- $volumeNames := dict "sc-dashboard" true "sc-dashboard-volume" true }}
{{- $providerNames := dict (dig "sidecar" "dashboards" "provider" "name" "sidecarProvider" $v.components.grafana.values) true }}
{{- range $providerFile := (dig "dashboardProviders" dict $v.components.grafana.values) }}
{{- range $providerFile.providers }}
{{- $_ := set $providerNames .name true }}
{{- end }}
{{- end }}
{{- $healthPort := 8085 }}
{{- $volumes := list }}
{{- $mounts := list }}
{{- $containers := list }}
{{- $providers := list }}
{{- $objects := list }}
{{- range $tenant := $v.tenants }}
{{- if has $tenant.id (list "general" "volume") }}{{ fail "tenant dashboard id must not be general or volume" }}{{ end }}
{{- range $tenant.namespaces }}
{{- if eq (upper (toString .)) "ALL" }}{{ fail "tenants[].namespaces must not contain ALL" }}{{ end }}
{{- if or (not (kindIs "string" .)) (not (regexMatch "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$" (toString .))) (gt (len (toString .)) 63) }}{{ fail "tenants[].namespaces must contain DNS-1123 labels" }}{{ end }}
{{- if and (hasKey $namespaces .) (ne (index $namespaces .) $tenant.id) }}{{ fail "tenants[].namespaces must be unique across tenants" }}{{ end }}
{{- $_ := set $namespaces . $tenant.id }}
{{- if has . $platform }}{{ fail "tenant namespace must not be in grafana.tenantDashboards.platformNamespaces" }}{{ end }}
{{- end }}
{{- with $tenant.grafana }}
{{- if hasKey . "orgId" }}
{{- if or (kindIs "string" .orgId) (not (regexMatch "^[1-9][0-9]*$" (toString .orgId))) }}{{ fail "tenants[].grafana.orgId must be a positive integer" }}{{ end }}
{{- if eq (toString .orgId) "1" }}{{ fail "tenants[].grafana.orgId must not be 1" }}{{ end }}
{{- if hasKey $orgIds (toString .orgId) }}{{ fail "tenants[].grafana.orgId must be unique across tenants" }}{{ end }}
{{- $_ := set $orgIds (toString .orgId) true }}
{{- if empty $tenant.namespaces }}{{ fail "tenants[].namespaces must be set when tenants[].grafana.orgId is set; an empty sidecar NAMESPACE watches the Grafana namespace" }}{{ end }}
{{- $id := $tenant.id }}
{{- $volume := printf "tenant-dash-%s" $id }}
{{- $home := printf "tenant-home-%s" $id }}
{{- range $name := list $volume $home }}
{{- if or (hasKey $volumeNames $name) (gt (len $name) 63) }}{{ fail "tenant dashboard volume names must be unique and at most 63 characters" }}{{ end }}
{{- $_ := set $volumeNames $name true }}
{{- end }}
{{- range $name := list (printf "tenant-%s" $id) (printf "home-%s" $id) }}
{{- if hasKey $providerNames $name }}{{ fail "tenant dashboard provider names must be unique" }}{{ end }}
{{- $_ := set $providerNames $name true }}
{{- end }}
{{- $path := printf "/var/lib/grafana-tenant-dashboards/%s" $id }}
{{- $homePath := printf "/etc/grafana/tenant-home/%s" $id }}
{{- $volumes = append $volumes (dict "name" $volume "emptyDir" dict) }}
{{- $volumes = append $volumes (dict "name" $home "configMap" (dict "name" (printf "grafana-tenant-home-%s" $id))) }}
{{- $mounts = append $mounts (dict "name" $volume "mountPath" $path "readOnly" true) }}
{{- $mounts = append $mounts (dict "name" $home "mountPath" $homePath "readOnly" true) }}
{{- $env := list }}
{{- $env = append $env (dict "name" "HEALTH_PORT" "value" (toString $healthPort)) }}
{{- $healthPort = add1 $healthPort }}
{{- range $name, $value := dict "METHOD" "WATCH" "LABEL" "grafana_dashboard" "LABEL_VALUE" "1" "NAMESPACE" (join "," $tenant.namespaces) "RESOURCE" "configmap" "FOLDER" $path "UNIQUE_FILENAMES" "true" }}
{{- $env = append $env (dict "name" $name "value" $value) }}
{{- end }}
{{- $security := dict "readOnlyRootFilesystem" true "allowPrivilegeEscalation" false "capabilities" (dict "drop" (list "ALL")) "seccompProfile" (dict "type" "RuntimeDefault") }}
{{- $containers = append $containers (dict "name" (printf "grafana-sc-dashboard-%s" $id) "image" "quay.io/kiwigrid/k8s-sidecar:2.11.2" "env" $env "securityContext" $security "volumeMounts" (list (dict "name" $volume "mountPath" $path "readOnly" false))) }}
{{- range $isHome := list false true }}
{{- $providers = append $providers (dict "name" (printf "%s-%s" (ternary "home" "tenant" $isHome) $id) "orgId" $tenant.grafana.orgId "folder" $id "folderUid" $id "type" "file" "updateIntervalSeconds" 30 "allowUiUpdates" false "disableDeletion" $isHome "options" (dict "path" (ternary $homePath $path $isHome) "foldersFromFilesStructure" false)) }}
{{- end }}
{{- $dashboard := dict "uid" (printf "%s-home" $id) "title" (printf "%s home" $id) "schemaVersion" 39 "panels" (list (dict "id" 1 "type" "text" "title" "Your dashboards" "gridPos" (dict "h" 6 "w" 24 "x" 0 "y" 0) "options" (dict "mode" "markdown" "content" (printf "Save dashboards and sub-folders inside the %s folder. Copy Git-managed dashboards to edit them." $id)))) }}
{{- $objects = append $objects (dict "apiVersion" "v1" "kind" "ConfigMap" "metadata" (dict "name" (printf "grafana-tenant-home-%s" $id) "namespace" $v.namespace) "data" (dict (printf "%s-home.json" $id) (toJson $dashboard))) }}
{{- end }}
{{- end }}
{{- end }}
sidecar:
  dashboards:
    searchNamespace: {{ toYaml $platform | nindent 6 }}
{{- if $containers }}
extraVolumes: {{ toYaml $volumes | nindent 2 }}
extraVolumeMounts: {{ toYaml $mounts | nindent 2 }}
extraContainers: {{ toYaml $containers | quote }}
dashboardProviders:
  tenant-dashboardproviders.yaml:
    apiVersion: 1
    providers: {{ toYaml $providers | nindent 6 }}
extraObjects: {{ toYaml $objects | nindent 2 }}
{{- end }}
{{- end }}
{{- $orgMapping := list }}
{{- if $mapping }}
{{- if ne $v.grafana.sso.provider "keycloak" }}{{ fail "grafana.orgMapping requires grafana.sso.provider keycloak" }}{{ end }}
{{- $admins := $v.grafana.sso.keycloak.admin | default list }}
{{- range $admins }}
{{- if or (not (kindIs "string" .)) (eq . "") }}{{ fail "grafana.sso.keycloak.admin group must not contain : , whitespace or braces" }}{{ end }}
{{- if regexMatch "[:,[:space:]{}]" . }}{{ fail "grafana.sso.keycloak.admin group must not contain : , whitespace or braces" }}{{ end }}
{{- $orgMapping = append $orgMapping (printf "%s:*:Admin" .) }}
{{- end }}
{{- range $tenant := $v.tenants }}
{{- with $tenant.grafana }}
{{- range $role := list "Viewer" "Editor" }}
{{- $groups := list }}
{{- if eq $role "Viewer" }}{{ $groups = $tenant.grafana.viewers | default list }}{{ else }}{{ $groups = $tenant.grafana.editors | default list }}{{ end }}
{{- range $group := $groups }}
{{- if or (not (kindIs "string" $group)) (eq $group "") }}{{ fail "tenant grafana group must not be empty" }}{{ end }}
{{- if or (eq $group "sre") (has $group $admins) }}{{ fail "tenant grafana group must not be sre or an SSO admin group" }}{{ end }}
{{- if regexMatch "[:,[:space:]{}]" $group }}{{ fail "tenant grafana group must not contain : , whitespace or braces" }}{{ end }}
{{- $orgMapping = append $orgMapping (printf "%s:%s:Viewer" $group $tenant.id) }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- if or $v.grafana.domain $mapping }}
grafana.ini:
{{- with $v.grafana.domain }}
  server:
    root_url: https://{{ . }}
{{- end }}
{{- if $mapping }}
  auth.generic_oauth:
    org_attribute_path: groups
    org_mapping: {{ join " " $orgMapping | quote }}
{{- end }}
{{- end }}
{{- if $v.grafana.ingress.enabled }}
ingress:
  enabled: true
  ingressClassName: {{ $v.grafana.ingress.className }}
  {{- with $v.grafana.ingress.annotations }}
  annotations: {{- toYaml . | nindent 4 }}
  {{- end }}
  hosts: [{{ required "grafana.domain is required with grafana.ingress.enabled" $v.grafana.domain | quote }}]
{{- end }}
{{- $p := $v.grafana.sso.provider }}
{{- if not (has $p (list "none" "keycloak" "github")) }}{{ fail "grafana.sso.provider must be none, keycloak or github" }}{{ end }}
{{- if eq $p "keycloak" }}
{{- $_ := required "grafana.sso.keycloak.url is required" $v.grafana.sso.keycloak.url }}
{{- $_ := required "grafana.sso.keycloak.realm is required" $v.grafana.sso.keycloak.realm }}
{{- else if eq $p "github" }}
{{- $_ := required "grafana.sso.github.organization is required" $v.grafana.sso.github.organization }}
{{- $_ := required "grafana.sso.github.clientId is required" $v.grafana.sso.github.clientId }}
{{- end }}
{{- if ne $p "none" }}
sso:
  {{ $p }}: {{- toYaml (index $v.grafana.sso $p) | nindent 4 }}
{{- end }}
{{- else if eq $key "opentelemetryOperator" }}
admissionWebhooks:
  # Render the webhook cert as a plain resource, not a pre-upgrade hook, so ArgoCD keeps the first one
  secretAnnotations:
    helm.sh/hook: null
    helm.sh/hook-delete-policy: null
{{- else if eq $key "alloy" }}
{{- with $v.placement.tolerations }}
controller:
  tolerations: {{- toYaml . | nindent 4 }}
{{- end }}
{{- if $v.placement.nodeSelector }}
service:
  # Clusters that pin the stack usually run Fargate too, and a Fargate pod has no Alloy on its node
  internalTrafficPolicy: Cluster
{{- end }}
{{- end }}
{{- end -}}

{{/* Final Helm values for a component: presets, then placement, then generated settings, then components.<key>.values */}}
{{- define "lgtm-stack.values" -}}
{{- $ := index . 0 -}}
{{- $key := index . 1 -}}
{{- $c := index . 2 -}}
{{- $out := dict -}}
{{- $presets := $c.presets -}}
{{- if and (eq $key "grafana") (ne $.Values.grafana.sso.provider "none") -}}
{{- $presets = append $presets (printf "grafana-sso-%s.yaml" $.Values.grafana.sso.provider) -}}
{{- end -}}
{{- range $presets -}}
{{- $file := $.Files.Get (printf "presets/%s" .) -}}
{{- if has . (list "alloy.yaml" "alloy-gateway.yaml") -}}
{{- $file = tpl $file $ -}}
{{- end -}}
{{- if not $file -}}{{- fail (printf "unknown preset %s" .) -}}{{- end -}}
{{- include "lgtm-stack.merge" (list $out (fromYaml $file)) -}}
{{- end -}}
{{- $placement := dict -}}
{{- with $.Values.placement.nodeSelector -}}{{- $_ := set $placement "nodeSelector" . -}}{{- end -}}
{{- with $.Values.placement.tolerations -}}{{- $_ := set $placement "tolerations" . -}}{{- end -}}
{{- if $placement -}}
{{- range $c.placement -}}
{{- include "lgtm-stack.merge" (list $out (fromYaml (include "lgtm-stack.atPath" (list . $placement)))) -}}
{{- end -}}
{{- end -}}
{{- include "lgtm-stack.merge" (list $out (fromYaml (include "lgtm-stack.generated" (list $ $key)) | default dict)) -}}
{{- include "lgtm-stack.merge" (list $out (index $.Values.components $key).values) -}}
{{- if eq $key "kubePrometheusStack" -}}
{{- $tenantRules := list -}}
{{- range $.Values.tenants -}}
{{- if .namespaces -}}
{{- $tenantRules = append $tenantRules (dict "action" "replace" "sourceLabels" (list "namespace") "regex" (printf "^(%s)$" (join "|" .namespaces)) "targetLabel" "tenant" "replacement" .id) -}}
{{- end -}}
{{- end -}}
{{- if $tenantRules -}}
{{/* Tenant rulers need namespace series stamped before consumer filters, without losing consumer relabel lists to merge replacement. */}}
{{- range $path := list "kube-state-metrics.prometheus.monitor.metricRelabelings" "kubelet.serviceMonitor.metricRelabelings" "kubelet.serviceMonitor.cAdvisorMetricRelabelings" -}}
{{- $parent := $out -}}
{{- $parts := splitList "." $path -}}
{{- range initial $parts -}}
{{- if not (index $parent .) -}}{{- $_ := set $parent . (dict) -}}{{- end -}}
{{- $parent = index $parent . -}}
{{- end -}}
{{- $leaf := last $parts -}}
{{- $_ := set $parent $leaf (concat $tenantRules (index $parent $leaf | default list)) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- toYaml $out -}}
{{- end -}}

{{/* Fields every Application shares: (list $ appName wave) */}}
{{- define "lgtm-stack.applicationHeader" -}}
{{- $ := index . 0 -}}
{{- $annotations := dict "argocd.argoproj.io/sync-wave" (index . 2) -}}
{{- if gt (len .) 3 -}}
{{- $_ := mergeOverwrite $annotations (index . 3 | default dict) -}}
{{- end -}}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ printf "%s%s" $.Values.argocd.namePrefix (index . 1) }}
  namespace: {{ $.Values.argocd.namespace }}
  annotations:
    argocd.argoproj.io/sync-wave: {{ index $annotations "argocd.argoproj.io/sync-wave" | quote }}
    {{- range $key, $value := omit $annotations "argocd.argoproj.io/sync-wave" }}
    {{ $key }}: {{ $value | quote }}
    {{- end }}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
{{- end -}}

{{- define "lgtm-stack.destination" -}}
{{- $d := .Values.argocd.destination -}}
{{- if not (or $d.name $d.server) -}}{{- fail "argocd.destination.name or argocd.destination.server is required" -}}{{- end -}}
destination:
  {{- with $d.name }}
  name: {{ . }}
  {{- end }}
  {{- with $d.server }}
  server: {{ . }}
  {{- end }}
  namespace: {{ .Values.namespace }}
{{- end -}}

{{/* syncPolicy, with RespectIgnoreDifferences added when the Application ignores diffs: (list $ hasIgnores) */}}
{{- define "lgtm-stack.syncPolicy" -}}
{{- $policy := deepCopy (index . 0).Values.argocd.syncPolicy -}}
{{- if index . 1 -}}
{{- $_ := set $policy "syncOptions" (append ($policy.syncOptions | default list) "RespectIgnoreDifferences=true") -}}
{{- end -}}
syncPolicy: {{- toYaml $policy | nindent 2 }}
{{- end -}}
