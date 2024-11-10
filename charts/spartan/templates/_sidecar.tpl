{{- define "sidecar.template" }}
{{- if .sidecar }}
- name: {{ .sidecar.name }}
  image: {{ .sidecar.image }}
  imagePullPolicy: {{ .Values.image.pullPolicy | quote }}
  {{- if .sidecar.command }}
  command: 
  - {{ default "/bin/sh" .sidecar.shell }}
  - -c 
  - while ! [ -f /tmp/kill_me ]; do {{ .sidecar.command }}; done;
  {{- end }}
  envFrom:
    {{- if .Values.secret.asEnv.enabled }}
    - secretRef:
        name: {{ include "spartan.secretAsEnv" . }}
    {{- end }}
    {{- if .Values.secret.externalSecretEnv.enabled }}
    - secretRef:
        name: {{ .Values.secret.externalSecretEnv.name }}
    {{- end }}
    {{- if .Values.configMap.asEnv.enabled }}
    - configMapRef:
        name: {{ include "spartan.configMapAsEnv" . }}
    {{- end }}
    {{- if .Values.configMap.externalConfigMapEnv.enabled }}
    - configMapRef:
        name: {{ .Values.configMap.externalConfigMapEnv.name }}
    {{- end }}
  env:
  {{- if eq .sidecar.name "datadog-agent" }}
    - name: DD_KUBERNETES_KUBELET_NODENAME
      valueFrom:
        fieldRef:
          apiVersion: v1
          fieldPath: spec.nodeName
    - name: DD_LOGS_ENABLED
      value: "true"
    - name: DD_LOGS_INJECTION
      value: "true"
    - name: DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL
      value: "true"
    - name: DD_ORCHESTRATOR_EXPLORER_ENABLED
      value: "true"
    - name: DD_PROCESS_AGENT_ENABLED
      value: "true"
    - name: DD_CLUSTER_AGENT_ENABLED
      value: "true"
  {{- end }}
  {{- include "spartan.extraEnvs" (dict "lists" (list .Values.extraEnvs .sidecar.extraEnvs)) | nindent 4 }}
  {{- if .sidecar.ports}}
  ports: {{- toYaml .sidecar.ports | nindent 4 }}
  {{- end }}
  {{- if .sidecar.livenessProbe }}
  livenessProbe: {{- toYaml .sidecar.livenessProbe | nindent 4 }}
  {{- end }}
  {{- if .sidecar.readinessProbe }}
  readinessProbe: {{- toYaml .sidecar.readinessProbe | nindent 4 }}
  {{- end }} 
  {{- if .sidecar.resources }}
  resources: {{- toYaml .sidecar.resources | nindent 4 }}
  {{- end }}
  volumeMounts:
  {{- if .Values.secret.asFile.enabled }}
    - name: {{ include "spartan.secretAsFile" . }}
      readOnly: true
      mountPath: {{ .Values.secret.asFile.mountPath | quote }}
  {{- end }}
  {{- if .Values.secret.externalSecretFile.enabled }}
    - name: {{ .Values.secret.externalSecretFile.name }}
      readOnly: true
      mountPath: {{ .Values.secret.externalSecretFile.mountPath | quote }}
  {{- end }}
  {{- if .Values.configMap.asFile.enabled }}
    - name: {{ include "spartan.configMapAsFile" . }}
      readOnly: true
      mountPath: {{ .Values.configMap.asFile.mountPath | quote }}
  {{- end }}
  {{- if .Values.configMap.externalConfigMapFile.enabled }}
    - name: {{ .Values.configMap.externalConfigMapFile.name }}
      readOnly: true
      mountPath: {{ .Values.configMap.externalConfigMapFile.mountPath | quote }}
  {{- end }}
  {{- if .sidecar.sharedVolume }}
    - mountPath: {{ .sidecar.sharedVolume.mountPath | quote }}
      name: sidecar-volume
      subPath: {{ .sidecar.name | quote }}
  {{- end }}
{{- end }}
{{- end }}
