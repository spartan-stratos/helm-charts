{{- define "spartan-alerts.short" -}}
{{- default (trimPrefix "service-" .Values.service.name) .Values.service.short -}}
{{- end -}}

{{- define "spartan-alerts.tokens" -}}
{{- dict "${SERVICE_NAME}" .Values.service.name "${SERVICE_SHORT}" (include "spartan-alerts.short" .) "${ENV}" .Values.env "${NAMESPACE}" .Release.Namespace "${CLUSTER_NAME}" .Values.workloadCluster "${GRAFANA_URL}" .Values.grafanaUrl "${ALERT_SLACK_SECRET}" .Values.slack.secretName "${ALERT_SLACK_CHANNEL}" .Values.slack.channel | toJson -}}
{{- end -}}

{{- define "spartan-alerts.expand" -}}
{{- $text := .text | toString -}}
{{- range $token := regexFindAll `\$\{[A-Z_]+\}` $text -1 | uniq -}}
{{- if not (hasKey $.tokens $token) -}}{{- fail (printf "unknown group token: %s" $token) -}}{{- end -}}
{{- $value := index $.tokens $token -}}
{{- if empty $value -}}{{- fail (printf "empty group token: %s" $token) -}}{{- end -}}
{{- $text = replace $token $value $text -}}
{{- end -}}
{{- $text -}}
{{- end -}}
