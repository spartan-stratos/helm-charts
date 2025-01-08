{{ define "spartan.pvc"}}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ .pvc.name }}
  {{- with .pvc.labels }}
  labels:
    {{ toYaml . | indent 4 }}
  {{- end }}
  {{- with .pvc.annotations }}
  annotations:
    {{ toYaml . | indent 4 }}
  {{- end }}
  {{- with .finalizers  }}
  finalizers:
    {{ toYaml . | indent 4 }}
  {{- end }}
spec:
  accessModes:
    {{- range .pvc.accessModes }}
    - {{ . | quote }}
    {{- end }}
  resources:
    requests:
      storage: {{ .pvc.storageSize | quote }}
  {{- if .pvc.storageClassName }}
  storageClassName: {{ .pvc.storageClassName }}
  {{- end }}
  {{- with .pvc.selectorLabels }}
  selector:
    matchLabels:
      {{ toYaml . | indent 6 }}
  {{- end }}
{{- end }}
