{{- /*
Expand the name of the chart.
*/}}
{{- define "spartan.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- /*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "spartan.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- /*
Define a new container name based on spartan.fullname or spartan.name.
*/}}
{{- define "spartan.containerName" -}}
{{- if .Values.containerName }}
{{- .Values.containerName | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end }}
{{- end }}

{{- /*
Create chart name and version as used by the chart label.
*/}}
{{- define "spartan.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- /*
Common labels
*/}}
{{- define "spartan.labels" -}}
helm.sh/chart: {{ include "spartan.chart" . }}
{{ include "spartan.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- /*
Selector labels
*/}}
{{- define "spartan.selectorLabels" -}}
{{- if .Values.appNameLabel -}}
app.kubernetes.io/name: {{ .Values.appNameLabel }}
{{- else -}}
app.kubernetes.io/name: {{ include "spartan.name" . }}
{{- end }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- /*
Hook labels
*/}}
{{- define "spartan.hookLabels" -}}
{{- if .Values.appNameLabel -}}
app.kubernetes.io/name: {{ .Values.appNameLabel }}-hook
{{- else -}}
app.kubernetes.io/name: {{ include "spartan.name" . }}-hook
{{- end }}
app.kubernetes.io/instance: {{ .Release.Name }}-hook
{{- end }}

{{/*
Worker labels
*/}}
{{- define "spartan.workerLabels" -}}
{{- if .Values.appNameLabel -}}
app.kubernetes.io/name: {{ .Values.appNameLabel }}-{{ .worker.name }}
{{- else -}}
app.kubernetes.io/name: {{ include "spartan.name" . }}-{{ .worker.name }}
{{- end }}
app.kubernetes.io/instance: {{ .Release.Name }}-worker
{{- end }}

{{/*
Cronjob labels
*/}}
{{- define "spartan.cronjobLabels" -}}
{{- if .Values.appNameLabel -}}
app.kubernetes.io/name: {{ .Values.appNameLabel }}-{{ .cronjob.name }}
{{- else -}}
app.kubernetes.io/name: {{ include "spartan.name" . }}-{{ .cronjob.name }}
{{- end }}
app.kubernetes.io/instance: {{ .Release.Name }}-cronjob
{{- end }}

{{/*
Global pod labels
*/}}
{{- define "spartan.podLabels" -}}
{{- with .Values.podLabels }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{- /*
Create the name of the service account to use
*/}}
{{- define "spartan.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "spartan.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- /*
Secret as files
*/}}
{{- define "spartan.secretAsFile" -}}
{{- printf "%s-%s" (include "spartan.fullname" .) "secret-as-file" }}
{{- end }}

{{- /*
Secret as environment variables
*/}}
{{- define "spartan.secretAsEnv" -}}
{{- printf "%s-%s" (include "spartan.fullname" .) "secret-as-env" }}
{{- end }}

{{- /*
ConfigMap as files
*/}}
{{- define "spartan.configMapAsFile" -}}
{{- printf "%s-%s" (include "spartan.fullname" .) "cm-as-file" }}
{{- end }}

{{- /*
ConfigMap as files
*/}}
{{- define "spartan.configMapAsEnv" -}}
{{- printf "%s-%s" (include "spartan.fullname" .) "cm-as-env" }}
{{- end }}

{{- /*
Get lowest hook weight
*/}}
{{- define "spartan.lowestHookWeight" -}}
{{- $hookWeight := 1000 }}
{{- range $hook := .Values.hooks }}
    {{- if lt (int $hook.hookWeight) (int $hookWeight) }}
        {{- $hookWeight = $hook.hookWeight }}
    {{- end }}
{{- end }}
{{- sub (int $hookWeight) 1 }}
{{- end }}

{{- /*
Get combine hook types
*/}}
{{- define "spartan.combineHookTypes" -}}
{{- $hookTypes := list "" }}
{{- range $hook := .Values.hooks }}
    {{- $hookTypes = append $hookTypes $hook.hookTypes }}
{{- end }}
{{- $uniqueHookTypes := uniq $hookTypes }}
{{- join "," $uniqueHookTypes | trimPrefix "," }}
{{- end }}

{{- /*
Get list of resources type
*/}}
{{- define "spartan.resources" -}}
{{- $resources := list "" }}
{{- $resourceLimits := .Values.resources.limits }}
{{- if $resourceLimits.cpu }}
    {{- $resources = append $resources "cpu" }}
{{- end }}
{{- if $resourceLimits.memory }}
    {{- $resources = append $resources "memory" }}
{{- end }}
{{- $resourceRequests := .Values.resources.requests }}
{{- if $resourceRequests.cpu }}
    {{- $resources = append $resources "cpu" }}
{{- end }}
{{- if $resourceRequests.memory }}
    {{- $resources = append $resources "memory" }}
{{- end }}
{{- $resources = uniq $resources }}
{{- join "," $resources | trimPrefix "," }}
{{- end }}

{{- /*
Primary service port (first entry from service.ports, or legacy service.port)
*/}}
{{- define "spartan.servicePrimaryPort" -}}
{{- if .Values.service.ports -}}
{{- (index .Values.service.ports 0).port -}}
{{- else -}}
{{- .Values.service.port | default 80 -}}
{{- end -}}
{{- end -}}

{{- /*
Merge extraEnvs
*/}}
{{- define "spartan.extraEnvs" -}}
  {{- $lists := .lists -}}
  {{- $merged := list -}}
  {{- range $list := $lists -}}
    {{- range $item := $list -}}
      {{- $exists := false -}}
      {{- $updatedMerged := list -}}
      {{- range $existing := $merged -}}
        {{- if eq $item.name $existing.name -}}
          {{- $exists = true -}}
          {{- $updatedMerged = append $updatedMerged $item -}}
        {{- else -}}
          {{- $updatedMerged = append $updatedMerged $existing -}}
        {{- end -}}
      {{- end -}}
      {{- if not $exists -}}
        {{- $updatedMerged = append $updatedMerged $item -}}
      {{- end -}}
      {{- $merged = $updatedMerged -}}
    {{- end -}}
  {{- end -}}
  {{- toYaml $merged }}
{{- end -}}

{{- /* Fails on observability settings the chart or the OTel Operator would reject. */}}
{{- define "spartan.observability.validate" -}}
  {{- $o := .Values.observability -}}
  {{- if and $o.enabled .Values.datadog.enabled -}}
    {{- fail "spartan: datadog.enabled and observability.enabled are both true. A project picks one: the Datadog agent or OTel (LGTM). Disable one of them" -}}
  {{- end -}}
  {{- with $o.autoInstrumentation -}}
    {{- if not (has . (list "java" "python" "go")) -}}
      {{- fail (printf "spartan: observability.autoInstrumentation must be one of java, python, go or empty (got %q)" .) -}}
    {{- end -}}
    {{- if and (eq . "go") (not $o.goTargetExe) -}}
      {{- fail "spartan: observability.autoInstrumentation=go needs observability.goTargetExe (path of the binary in the image); the operator skips Go injection without it" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{- /* Base OTEL_SERVICE_NAME: observability.serviceName, else appNameLabel, else fullname. */}}
{{- define "spartan.observability.serviceName" -}}
{{- .Values.observability.serviceName | default .Values.appNameLabel | default (include "spartan.fullname" .) -}}
{{- end -}}

{{- /* Operator annotations as YAML, from dict "Values" "job". Go is skipped on Job pods: its sidecar never exits. */}}
{{- define "spartan.observability.podAnnotations" -}}
  {{- $o := .Values.observability -}}
  {{- if and $o.enabled $o.autoInstrumentation (not (and .job (eq $o.autoInstrumentation "go"))) }}
instrumentation.opentelemetry.io/inject-{{ $o.autoInstrumentation }}: {{ $o.instrumentationRef | quote }}
    {{- if eq $o.autoInstrumentation "go" }}
instrumentation.opentelemetry.io/otel-go-auto-target-exe: {{ $o.goTargetExe | quote }}
    {{- end }}
  {{- end }}
{{- end -}}

{{- /* Pod template annotations: user annotations win over the operator ones. Args: dict "Values" "job" "annotations". */}}
{{- define "spartan.observability.mergeAnnotations" -}}
{{- $otel := include "spartan.observability.podAnnotations" . | fromYaml | default dict -}}
{{- $merged := mergeOverwrite (dict) $otel (.annotations | default dict) -}}
{{- with $merged }}{{ toYaml . }}{{ end -}}
{{- end -}}

{{- /* OTEL_* env list as YAML, from the root context plus "serviceName". Downward API vars come first so $(VAR) resolves. */}}
{{- define "spartan.observability.env" -}}
  {{- $o := .Values.observability -}}
  {{- if $o.enabled -}}
    {{- include "spartan.observability.validate" . -}}
    {{- $attrs := dict "k8s.namespace.name" "$(OTEL_K8S_NAMESPACE_NAME)" "k8s.pod.name" "$(OTEL_K8S_POD_NAME)" -}}
    {{- with $o.environment }}{{ $_ := set $attrs "deployment.environment.name" (toString .) }}{{ end -}}
    {{- with .Values.image.tag }}{{ $_ := set $attrs "service.version" (toString .) }}{{ end -}}
    {{- range $k, $v := $o.resourceAttributes }}{{ $_ := set $attrs $k (toString $v) }}{{ end -}}
    {{- $pairs := list -}}
    {{- range $k := keys $attrs | sortAlpha }}{{ $pairs = append $pairs (printf "%s=%s" $k (get $attrs $k)) }}{{ end }}
- name: OTEL_K8S_NAMESPACE_NAME
  valueFrom:
    fieldRef:
      apiVersion: v1
      fieldPath: metadata.namespace
- name: OTEL_K8S_POD_NAME
  valueFrom:
    fieldRef:
      apiVersion: v1
      fieldPath: metadata.name
- name: OTEL_SERVICE_NAME
  value: {{ .serviceName | quote }}
- name: OTEL_RESOURCE_ATTRIBUTES
  value: {{ join "," $pairs | quote }}
    {{- if $o.otlp.enabled }}
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: {{ $o.otlp.endpoint | quote }}
- name: OTEL_EXPORTER_OTLP_PROTOCOL
  value: {{ $o.otlp.protocol | quote }}
- name: OTEL_TRACES_SAMPLER
  value: "parentbased_traceidratio"
- name: OTEL_TRACES_SAMPLER_ARG
  value: {{ $o.otlp.tracesSampleRatio | toString | quote }}
    {{- end }}
  {{- end -}}
{{- end -}}
