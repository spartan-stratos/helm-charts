{{ define "spartan.workerKeda" }}
{{- $fullName := .worker.name -}}
{{- range .worker.keda.authentication }}
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: {{ include "spartan.fullname" $ }}-worker-{{ $fullName }}-{{ .name }}
spec:
  podIdentity:
    provider: {{ .podIdentity.provider }}
    identityOwner: {{ .podIdentity.identityOwner | default "workload" }}
---
{{- end }}
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: {{ include "spartan.fullname" $ }}-worker-{{ $fullName }}
spec:
  minReplicaCount: {{ .worker.keda.minReplicas}}
  maxReplicaCount: {{ .worker.keda.maxReplicas}}
  pollingInterval: {{ .worker.keda.pollingInterval}}
  scaleTargetRef:
    name: {{ include "spartan.fullname" $ }}-worker-{{ .worker.name}}
  triggers:
    {{- range .worker.keda.triggers }}
    - type: {{ .type }}
      {{- if .metricType }}
      metricType: {{ .metricType }}
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
