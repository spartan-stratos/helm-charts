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
    - prometheus-node-exporter
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
alloy:
  app: alloy
  wave: 52
  presets: [alloy.yaml]
  placement: [controller]
tempo:
  app: tempo
  wave: 60
  presets: [tempo.yaml]
  placement: [""]
opentelemetryOperator:
  app: opentelemetry-operator
  wave: 61
  presets: [opentelemetry-operator.yaml]
  placement: [""]
  # The chart generates the webhook cert on every render; as a plain resource (hook annotations nulled below) ArgoCD
  # creates it once and keeps it with the matching caBundle
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

{{/* Addons: Application name, sync wave, manifest files */}}
{{- define "lgtm-stack.addons" -}}
clusterInfo:
  app: cluster-info
  wave: 10
  files: [cluster-info.yaml]
# Needs the PrometheusRule CRD
pvcFillRules:
  app: pvc-fill-rules
  wave: 31
  files: [pvc-fill-rules.yaml]
# Needs the AlertmanagerConfig CRD and the Alertmanager
alertmanagerConfig:
  app: alertmanager-config
  wave: 32
  files: [alertmanager-slack.yaml]
grafanaDatasources:
  app: grafana-datasources
  wave: 51
  files: [grafana-datasource-loki.yaml, grafana-datasource-tempo.yaml]
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
{{- if eq $key "kubePrometheusStack" }}
prometheus:
  prometheusSpec:
    externalLabels:
      cluster: {{ $v.cluster.name | quote }}
{{- if $v.alerting.slack.enabled }}
alertmanager:
  alertmanagerSpec:
    # AlertmanagerConfig routes match alerts from every namespace, not only the config's own
    alertmanagerConfigMatcherStrategy:
      type: None
{{- end }}
{{- else if eq $key "grafana" }}
{{- with $v.grafana.domain }}
grafana.ini:
  server:
    root_url: https://{{ . }}
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
{{- if $v.placement.nodeSelector }}
service:
  # Alloy runs only where placement allows, so OTLP from other nodes must route across nodes
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
{{- toYaml $out -}}
{{- end -}}

{{/* Fields every Application shares: (list $ appName wave) */}}
{{- define "lgtm-stack.applicationHeader" -}}
{{- $ := index . 0 -}}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ printf "%s%s" $.Values.argocd.namePrefix (index . 1) }}
  namespace: {{ $.Values.argocd.namespace }}
  annotations:
    argocd.argoproj.io/sync-wave: {{ index . 2 | quote }}
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
