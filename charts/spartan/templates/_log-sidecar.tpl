{{/*
observability.logs.fileSidecar: an Alloy native sidecar that tails the app's log file and pushes it to Loki, for pods
no node log agent reaches (Fargate). Callers pass (list $ isWorker from), from = spartan.logSidecar.sharedFrom.
*/}}

{{/* The sidecars[] entry whose sharedVolume is mounted at fileSidecar.path; the sidecar reads that subPath. "" when none */}}
{{- define "spartan.logSidecar.sharedFrom" -}}
{{- $isWorker := index . 1 -}}
{{- $ := index . 0 -}}
{{- $path := trimSuffix "/" $.Values.observability.logs.fileSidecar.path -}}
{{- $found := "" -}}
{{- range $.Values.sidecars -}}
{{- /* A worker mounts every shared volume; the Deployment skips skipDeployment entries */ -}}
{{- if and (not $found) .sharedVolume (or $isWorker (not .skipDeployment)) -}}
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
{{- $from := index . 2 -}}
{{- $fs := $.Values.observability.logs.fileSidecar -}}
{{- if semverCompare "<1.30-0" $.Capabilities.KubeVersion.Version -}}
{{- fail (printf "observability.logs.fileSidecar needs Kubernetes 1.30+ (native sidecar, preStop sleep), got %s; pass --kube-version to helm template" $.Capabilities.KubeVersion.Version) -}}
{{- end -}}
- name: log-sidecar
  image: {{ $fs.image }}
  # Native sidecar: starts before the app and stops after it. The app waits for it to start, so an image pull failure
  # keeps the pod in Init
  restartPolicy: Always
  args: [run, /etc/alloy/config.alloy, --storage.path=/var/lib/alloy, --server.http.listen-addr=127.0.0.1:12345]
  env:
    - name: CLUSTER_NAME
      value: {{ required "observability.logs.fileSidecar.cluster is required" $fs.cluster | quote }}
    # The pod label the node Alloy takes service_name from, so both collectors name the service alike
    - name: SERVICE_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.labels['app.kubernetes.io/name']
    - name: CONTAINER_NAME
      value: {{ include "spartan.containerName" $ | quote }}
    - name: LOKI_URL
      value: {{ $fs.lokiUrl | quote }}
    - name: POD_NAMESPACE
      valueFrom:
        fieldRef:
          fieldPath: metadata.namespace
    - name: POD_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
  {{- with $fs.resources }}
  resources: {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $fs.securityContext }}
  securityContext: {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- if $fs.drainSeconds }}
  # Alloy does not drain on SIGTERM: the delay lets it read and push the app's last lines (a crash) after the app exits
  lifecycle:
    preStop:
      sleep:
        seconds: {{ $fs.drainSeconds }}
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
{{- if not (index . 2) }}
{{- $v := $.Values -}}
{{- $path := trimSuffix "/" $v.observability.logs.fileSidecar.path }}
{{- $taken := list -}}
{{- range list $v.secret.asFile $v.secret.externalSecretFile $v.configMap.asFile $v.configMap.externalConfigMapFile }}
{{- if and . .enabled }}{{ $taken = append $taken .mountPath }}{{ end }}
{{- end }}
{{- /* Only the Deployment mounts volumeMounts and persistence */ -}}
{{- if not (index . 1) }}
{{- range concat ($v.volumeMounts | default list) ($v.persistence | default list) }}{{ $taken = append $taken .mountPath }}{{ end }}
{{- end }}
{{- range $taken }}
{{- if eq (trimSuffix "/" (toString .)) $path }}
{{- fail (printf "observability.logs.fileSidecar.path %s is already a mount of the app; share it through a sidecars[] sharedVolume or pick another path" $path) }}
{{- end }}
{{- end }}
- name: log-sidecar-logs
  mountPath: {{ $v.observability.logs.fileSidecar.path | quote }}
{{- end }}
{{- end -}}

{{- define "spartan.logSidecar.volumes" -}}
{{- $ := index . 0 -}}
- name: log-sidecar-config
  configMap:
    name: {{ include "spartan.logSidecar.name" $ }}
- name: log-sidecar-data
  emptyDir: {}
{{- if not (index . 2) }}
- name: log-sidecar-logs
  {{- with $.Values.observability.logs.fileSidecar.sizeLimit }}
  emptyDir:
    sizeLimit: {{ . }}
  {{- else }}
  emptyDir: {}
  {{- end }}
{{- end }}
{{- end -}}
