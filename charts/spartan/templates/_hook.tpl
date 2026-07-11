{{ define "spartan.hook" }}
{{- $lc := .hook.logCollector | default dict }}
{{- $lcName := $lc.sidecarName | default "datadog-agent" }}
{{- $drain := $lc.drain | default dict }}
{{- if and .hook.collectLog .hook.logCollector }}
{{- $sidecarNames := list }}
{{- range .Values.sidecars }}{{- $sidecarNames = append $sidecarNames .name }}{{- end }}
{{- if not (has $lcName $sidecarNames) }}{{ fail (printf "spartan: hook %q log collector %q (logCollector.sidecarName, default \"datadog-agent\") does not match any configured sidecar (sidecars[].name: %v)" .hook.name $lcName $sidecarNames) }}{{- end }}
{{- if ne $lcName "datadog-agent" }}
{{- if not $lc.readyCommand }}{{ fail (printf "spartan: hook %q sets logCollector.sidecarName=%q but no logCollector.readyCommand; a non-datadog-agent collector would hang on the default :8126 wait" .hook.name $lcName) }}{{- end }}
{{- if and (not $lc.stopCommand) (not $drain.enabled) }}{{ fail (printf "spartan: hook %q sets logCollector.sidecarName=%q but no logCollector.stopCommand and logCollector.drain.enabled is not true; the default 'pkill agent' would never stop the collector and the Job would hang" .hook.name $lcName) }}{{- end }}
{{- end }}
{{- end }}
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
    {{- if .hook.deletePolicy }}
    "helm.sh/hook-delete-policy": {{ .hook.deletePolicy | quote }}
    {{- else }}
    "helm.sh/resource-policy": keep
    {{- end }}
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
        {{- include "spartan.podLabels" . | nindent 8 }}
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
          {{- toYaml . | nindent 8 }}
      {{- end }}
      serviceAccountName: {{ include "spartan.serviceAccountName" . }}
      securityContext:
          {{- toYaml .Values.podSecurityContext | nindent 8 }}
      restartPolicy: {{ .hook.restartPolicy | default "Never" }}
      {{- if and (.hook.collectLog) (or .Values.datadog.enabled .hook.logCollector) }}
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
            {{- if and (.hook.collectLog) (or .Values.datadog.enabled .hook.logCollector) }}
            {{- if $drain.enabled }}
              # Deterministic drain: on hook-container exit, wait until the log
              # collector has SHIPPED every record it read (output proc_records >=
              # input records) before stopping it - no fixed sleep to out-guess. The
              # collector must expose Fluent Bit's metrics API (default :2020); the
              # maxWaitSeconds cap is a bounded backstop, not the expected wait.
              # Assumes a SINGLE input and a SINGLE output (it sums records across
              # all inputs/outputs); a multi-output collector would satisfy the
              # condition before every output drained.
              __spartan_drain() {
                _url="{{ $drain.metricsUrl | default "http://localhost:2020/api/v1/metrics" }}"
                _i=0; _prev=-1
                while [ "$_i" -lt {{ $drain.maxWaitSeconds | default 60 }} ]; do
                  _m=$(curl -s --max-time 5 "$_url" 2>/dev/null)
                  _in=0; for _n in $(printf '%s' "$_m" | grep -oE '"records":[0-9]+' | grep -oE '[0-9]+'); do _in=$((_in+_n)); done
                  _out=0; for _n in $(printf '%s' "$_m" | grep -oE '"proc_records":[0-9]+' | grep -oE '[0-9]+'); do _out=$((_out+_n)); done
                  # break only when the input count is STABLE across two polls (tail has
                  # finished reading an incrementally-written log) AND output shipped it all
                  if [ "$_in" -gt 0 ] && [ "$_in" -eq "$_prev" ] && [ "$_out" -ge "$_in" ]; then break; fi
                  _prev="$_in"; _i=$((_i+1)); sleep 1
                done
                [ "$_i" -ge {{ $drain.maxWaitSeconds | default 60 }} ] && echo "spartan drain: cap reached (in=$_in out=$_out); collector logs may be incomplete" >&2
                pkill {{ $drain.signal | default "fluent-bit" }} || true
              }
              trap __spartan_drain EXIT
            {{- else }}
              trap '{{ $lc.stopCommand | default "sleep 10 && pkill agent" }}' EXIT
            {{- end }}
              set -o pipefail
            {{- if $lc.readyCommand }}
              {{ $lc.readyCommand }}
            {{- else }}
              if [ ! `which curl` ]; then sleep 300; else while ! curl -Ns localhost:8126; do sleep 1 && echo "Waiting for datadog agent to start...."; done; fi
            {{- end }}
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
          {{- if and (.hook.collectLog) (or .Values.datadog.enabled .hook.logCollector) (eq $lcName "datadog-agent") }}
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
              value: {{ .Values.datadog.orchestratorExplorerEnabled | quote }}
            - name: DD_PROCESS_AGENT_ENABLED
              value: "true"
            - name: DD_CLUSTER_AGENT_ENABLED
              value: {{ .Values.datadog.clusterAgentEnabled | quote }}
            {{- if not .Values.datadog.cloudProviderMetadataEnabled }}
            - name: DD_CLOUD_PROVIDER_METADATA
              value: ""
            {{- end }}
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
            {{- if and .sharedVolume (eq .name $lcName) }}
            - name: sidecar-volume
              readOnly: false
              mountPath: {{ .sharedVolume.mountPath }}
              subPath: {{ .name }}
            {{- end }}
          {{- end }}
        {{- $hook := .hook }}
        {{- range $sidecar := .Values.sidecars }}
          {{- if and (eq $sidecar.name $lcName) ($hook.collectLog) }}
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
