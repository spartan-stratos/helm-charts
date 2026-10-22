{{/*
observability.logs.fileSidecar: an Alloy native sidecar that tails the app's log files and pushes them to Loki, for pods
no node log agent reaches (Fargate). Callers pass (list $ serviceName isWorker).
*/}}

{{/* The sidecars[] entry whose sharedVolume is mounted at fileSidecar.path; the sidecar reads that subPath. "" when none */}}
{{- define "spartan.logSidecar.sharedFrom" -}}
{{- $args := . -}}
{{- $ := index . 0 -}}
{{- $path := trimSuffix "/" $.Values.observability.logs.fileSidecar.path -}}
{{- $found := "" -}}
{{- range $.Values.sidecars -}}
{{- /* A worker mounts every shared volume; the Deployment skips skipDeployment entries */ -}}
{{- if and (not $found) .sharedVolume (or (index $args 2) (not .skipDeployment)) -}}
{{- if eq (trimSuffix "/" .sharedVolume.mountPath) $path -}}
{{- $found = .name -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $found -}}
{{- end -}}

{{- define "spartan.logSidecar.name" -}}
{{ include "spartan.fullname" . }}-log-sidecar
{{- end -}}

{{/* initContainers entry */}}
{{- define "spartan.logSidecar.container" -}}
{{- $ := index . 0 -}}
{{- $fs := $.Values.observability.logs.fileSidecar -}}
{{- $from := include "spartan.logSidecar.sharedFrom" . -}}
- name: log-sidecar
  image: {{ $fs.image }}
  # Native sidecar: starts before the app, stops after it, never blocks it
  restartPolicy: Always
  args: [run, /etc/alloy/config.alloy, --storage.path=/var/lib/alloy, --server.http.listen-addr=127.0.0.1:12345]
  env:
    - name: CLUSTER_NAME
      value: {{ required "observability.logs.fileSidecar.cluster is required" $fs.cluster | quote }}
    - name: SERVICE_NAME
      value: {{ index . 1 | quote }}
    - name: CONTAINER_NAME
      value: {{ include "spartan.containerName" $ | quote }}
    - name: LOKI_URL
      value: {{ $fs.lokiUrl | quote }}
    - name: POD_NAMESPACE
      valueFrom:
        fieldRef:
          fieldPath: metadata.namespace
  {{- with $fs.resources }}
  resources: {{- toYaml . | nindent 4 }}
  {{- end }}
  volumeMounts:
    {{- if $from }}
    - name: sidecar-volume
      mountPath: {{ $fs.path | quote }}
      subPath: {{ $from }}
      readOnly: true
    {{- else }}
    - name: log-sidecar-logs
      mountPath: {{ $fs.path | quote }}
      readOnly: true
    {{- end }}
    - name: log-sidecar-config
      mountPath: /etc/alloy
    # Read positions survive a sidecar restart, so it carries on where it stopped
    - name: log-sidecar-data
      mountPath: /var/lib/alloy
{{- end -}}

{{/* The app's mount, only when no sidecars[] entry already shares the directory */}}
{{- define "spartan.logSidecar.appMount" -}}
{{- $ := index . 0 -}}
{{- if not (include "spartan.logSidecar.sharedFrom" .) }}
- name: log-sidecar-logs
  mountPath: {{ $.Values.observability.logs.fileSidecar.path | quote }}
{{- end }}
{{- end -}}

{{- define "spartan.logSidecar.volumes" -}}
{{- $ := index . 0 -}}
- name: log-sidecar-config
  configMap:
    name: {{ include "spartan.logSidecar.name" $ }}
- name: log-sidecar-data
  emptyDir: {}
{{- if not (include "spartan.logSidecar.sharedFrom" .) }}
- name: log-sidecar-logs
  {{- with $.Values.observability.logs.fileSidecar.sizeLimit }}
  emptyDir:
    sizeLimit: {{ . }}
  {{- else }}
  emptyDir: {}
  {{- end }}
{{- end }}
{{- end -}}
