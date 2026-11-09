{{ define "spartan.workerKeda" }}
{{- $fullName := .worker.name -}}
{{- $autoscaling := .worker.autoscaling | default dict }}
{{- $behavior := .worker.keda.behavior | default (and $autoscaling.enabled $autoscaling.behavior) }}
{{- range .worker.keda.authentication }}
{{- if not (or .podIdentity .secretTargetRef) }}
{{- fail (printf "workers %q keda.authentication %q needs podIdentity or secretTargetRef" $fullName .name) }}
{{- end }}
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: {{ include "spartan.fullname" $ }}-worker-{{ $fullName }}-{{ .name }}
spec:
  {{- if .podIdentity }}
  podIdentity:
    provider: {{ .podIdentity.provider }}
    identityOwner: {{ .podIdentity.identityOwner | default "workload" }}
  {{- end }}
  {{- with .secretTargetRef }}
  secretTargetRef:
    {{- toYaml . | nindent 4 }}
  {{- end }}
---
{{- end }}
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: {{ include "spartan.fullname" $ }}-worker-{{ $fullName }}
  {{- if $autoscaling.enabled }}
  annotations:
    scaledobject.keda.sh/transfer-hpa-ownership: "true"
  {{- end }}
spec:
  minReplicaCount: {{ .worker.keda.minReplicas }}
  maxReplicaCount: {{ .worker.keda.maxReplicas }}
  pollingInterval: {{ .worker.keda.pollingInterval }}
  scaleTargetRef:
    name: {{ include "spartan.fullname" $ }}-worker-{{ .worker.name }}
  {{- if or $autoscaling.enabled $behavior }}
  advanced:
    horizontalPodAutoscalerConfig:
      {{- if $autoscaling.enabled }}
      name: {{ include "spartan.fullname" $ }}-worker-{{ .worker.name }}
      {{- end }}
      {{- with $behavior }}
      behavior:
        {{- toYaml . | nindent 8 }}
      {{- end }}
  {{- end }}
  triggers:
    {{- range .worker.keda.triggers }}
    - type: {{ .type }}
      {{- if .metricType }}
      metricType: {{ .metricType }}
      {{- end }}
      {{- if .useCachedMetrics }}
      useCachedMetrics: true
      {{- end }}
      {{- if .authentication }}
      authenticationRef:
        name: {{ include "spartan.fullname" $ }}-worker-{{ $fullName }}-{{ .authentication.name }}
      {{- end }}
      metadata:
        {{- toYaml .metadata | nindent 8 }}
    {{- end }}
---
{{ end }}
