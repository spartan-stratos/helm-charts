{{ define "spartan.hook" }}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "spartan.fullname" $ }}-hook-{{ .hook.name}}
  labels:
    {{- include "spartan.labels" . | nindent 4 }}
    tier: "hook"
  annotations:
    "helm.sh/hook": {{ .hook.hookTypes | quote }}
    "helm.sh/hook-weight": "{{ .hook.hookWeight | default "0" }}"
    "helm.sh/resource-policy": keep
spec:
  backoffLimit: {{ .hook.backoffLimit | default 0 }}
  template:
    metadata:
      {{- if .hook.podAnnotations }}
      {{- with .hook.podAnnotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- else }}
      {{- with .Values.podAnnotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- end }}
      labels:
        {{- include "spartan.hookLabels" . | nindent 8 }}
        tier: "hook"
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
          {{- toYaml . | nindent 8 }}
      {{- end }}
      serviceAccountName: {{ include "spartan.serviceAccountName" . }}
      securityContext:
          {{- toYaml .Values.podSecurityContext | nindent 8 }}
      restartPolicy: {{ .hook.restartPolicy | default "Never" }}
      {{- if and (.Values.datadog.enabled) (.hook.collectLog) }}
      shareProcessNamespace: true
      {{- end }}
      containers:
        - name: {{ include "spartan.containerName" . }}
          securityContext:
              {{- toYaml .Values.securityContext | nindent 12 }}
          {{- if .hook.customImage.enabled }}
          image: {{ .hook.customImage.image }}
          {{- else }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default "latest" }}"
          {{- end }}
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          command:
            - {{ default "/bin/sh" .hook.shell }}
            - -c
            - |
            {{- if and (.Values.datadog.enabled) (.hook.collectLog) }}
              trap 'sleep 10 && pkill agent' EXIT
              set -o pipefail
              if [ ! `which curl` ]; then sleep 300; else while ! curl -Ns localhost:8126; do sleep 1 && echo "Waiting for datadog agent to start...."; done; fi
            {{- end }}
            {{- range .hook.commands }}
              {{ . }}
            {{- end }}
          resources:
              {{- toYaml .hook.resources | nindent 12 }}
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
          {{- if and (.Values.datadog.enabled) (.hook.collectLog) }}
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
          {{- if or .Values.extraEnvs .hook.extraEnvs }}
          {{- include "spartan.extraEnvs" (dict "lists" (list .Values.extraEnvs .hook.extraEnvs)) | nindent 12 }}
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
            {{- range .Values.sidecars }}
            {{- if .sharedVolume }}
            - name: sidecar-volume
              readOnly: false
              mountPath: {{ .sharedVolume.mountPath }}
              subPath: {{ .name }}
            {{- end }}
          {{- end }}
        {{- $hook := .hook }}
        {{- range $sidecar := .Values.sidecars }}
          {{- if and (eq $sidecar.name "datadog-agent") ($hook.collectLog) }}
            {{ include "sidecar.template" (dict "sidecar" $sidecar "Values" $.Values "Chart" $.Chart "Release" $.Release) | indent 8 }}
          {{- end }}
        {{- end }}
      {{- with .Values.nodeSelector }}
      nodeSelector:
          {{- toYaml . | nindent 8 }}
        {{- end }}
        {{- with .Values.affinity }}
      affinity:
          {{- toYaml . | nindent 8 }}
        {{- end }}
        {{- with .Values.tolerations }}
      tolerations:
          {{- toYaml . | nindent 8 }}
        {{- end }}
      volumes:
        {{- if .Values.secret.asFile.enabled }}
        - name: {{ include "spartan.secretAsFile" . }}
          secret:
            secretName: {{ include "spartan.secretAsFile" . }}
        {{- end }}
        {{- if .Values.secret.externalSecretFile.enabled }}
        - name: {{ .Values.secret.externalSecretFile.name }}
          secret:
            secretName: {{ .Values.secret.externalSecretFile.name }}
        {{- end }}
        {{- if .Values.configMap.asFile.enabled }}
        - name: {{ include "spartan.configMapAsFile" . }}
          configMap:
            name: {{ include "spartan.configMapAsFile" . }}
        {{- end }}
        {{- if .Values.configMap.externalConfigMapFile.enabled }}
        - name: {{ .Values.configMap.externalConfigMapFile.name }}
          configMap:
            name: {{ .Values.configMap.externalConfigMapFile.name }}
        {{- end }}
        {{- if .Values.sidecars }}
        - name: sidecar-volume
          emptyDir: {}
        {{- end }}
{{- end }}
