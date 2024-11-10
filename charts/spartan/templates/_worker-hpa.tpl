{{ define "spartan.workerHpa" }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "spartan.fullname" $ }}-worker-{{ .worker.name}}
  labels:
    {{- include "spartan.labels" $ | nindent 4 }}
    tier: "worker"
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "spartan.fullname" $ }}-worker-{{ .worker.name}}
  minReplicas: {{ .worker.autoscaling.minReplicas }}
  maxReplicas: {{ .worker.autoscaling.maxReplicas }}
  metrics:
    {{- if .worker.autoscaling.targetCPUUtilizationPercentage }}
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .worker.autoscaling.targetCPUUtilizationPercentage }}
    {{- end }}
    {{- if .worker.autoscaling.targetMemoryUtilizationPercentage }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ .worker.autoscaling.targetMemoryUtilizationPercentage }}
    {{- end }}
{{ end }}
