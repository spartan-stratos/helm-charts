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

