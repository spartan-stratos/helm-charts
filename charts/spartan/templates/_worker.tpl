{{ define "spartan.worker" }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "spartan.fullname" $ }}-worker-{{ .worker.name }}
  labels:
    {{- include "spartan.labels" $ | nindent 4 }}
    tier: "worker"
spec:
  replicas: {{ .worker.replicaCount | default 1 }}
  selector:
    matchLabels:
      {{- include "spartan.workerLabels" $ | nindent 6 }}
      tier: "worker"
  template:
    metadata:
      {{- if .worker.podAnnotations }}
      {{- with .worker.podAnnotations }}
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
        {{- include "spartan.workerLabels" $ | nindent 8 }}
        tier: "worker"
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      serviceAccountName: {{ include "spartan.serviceAccountName" $ }}
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      terminationGracePeriodSeconds: {{ .worker.terminationGracePeriodSeconds | default 180 }}
      {{- if .Values.datadog.enabled }}
      shareProcessNamespace: true
      {{- end }}
      containers:
        - name: {{ include "spartan.containerName" . }}
          {{- if .worker.command }}
          command:
            - {{ default "/bin/sh" .worker.shell }}
            - -c
            - {{ .worker.command }}
          {{- end }}
          securityContext:
            {{- toYaml .Values.securityContext | nindent 12 }}
          {{- if and (.worker.customImage) (.worker.customImage.enabled) }}
          image: {{ .worker.customImage.image }}
          {{- else }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default "latest" }}"
          {{- end }}
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          resources:
            {{- toYaml .worker.resources | nindent 12 }}
          envFrom:
            {{- if .Values.secret.asEnv.enabled }}
            - secretRef:
                name: {{ include "spartan.secretAsEnv" $ }}
            {{- end }}
            {{- if .Values.secret.externalSecretEnv.enabled }}
            - secretRef:
                name: {{ .Values.secret.externalSecretEnv.name }}
            {{- end }}
            {{- if .Values.configMap.asEnv.enabled }}
            - configMapRef:
                name: {{ include "spartan.configMapAsEnv" $ }}
            {{- end }}
            {{- if .Values.configMap.externalConfigMapEnv.enabled }}
            - configMapRef:
                name: {{ .Values.configMap.externalConfigMapEnv.name }}
            {{- end }}
          env:
          {{- if .Values.datadog.enabled }}
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
          {{- include "spartan.extraEnvs" (dict "lists" (list .Values.extraEnvs .worker.extraEnvs)) | nindent 12 }}
          volumeMounts:
          {{- if .Values.secret.asFile.enabled }}
            - name: {{ include "spartan.secretAsFile" $ }}
              readOnly: true
              mountPath: {{ .Values.secret.asFile.mountPath | quote }}
          {{- end }}
          {{- if .Values.secret.externalSecretFile.enabled }}
            - name: {{ .Values.secret.externalSecretFile.name }}
              readOnly: true
              mountPath: {{ .Values.secret.externalSecretFile.mountPath | quote }}
          {{- end }}
          {{- if .Values.configMap.asFile.enabled }}
            - name: {{ include "spartan.configMapAsFile" $ }}
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

        {{- range $sidecar := .Values.sidecars }}
        {{ include "sidecar.template" (dict "sidecar" $sidecar "Values" $.Values "Chart" $.Chart "Release" $.Release) | indent 8 }}
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
        - name: {{ include "spartan.secretAsFile" $ }}
          secret:
            secretName: {{ include "spartan.secretAsFile" $ }}
      {{- end }}
      {{- if .Values.secret.externalSecretFile.enabled }}
        - name: {{ .Values.secret.externalSecretFile.name }}
          secret:
            secretName: {{ .Values.secret.externalSecretFile.name }}
      {{- end }}
      {{- if .Values.configMap.asFile.enabled }}
        - name: {{ include "spartan.configMapAsFile" $ }}
          configMap:
            name: {{ include "spartan.configMapAsFile" $ }}
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
{{ end }}
