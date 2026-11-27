{{/* Shared transport only. Scope: index, lane, isolation and filterInput. */}}
{{- define "lgtm-stack.gateway.receiverPrefix" -}}
otelcol.auth.basic "tenant_{{ .index }}" {
  htpasswd {
    file = "/etc/alloy/tenants/{{ .index }}/htpasswd"
  }
}
otelcol.receiver.otlp "tenant_{{ .index }}" {
  http {
    endpoint = "0.0.0.0:{{ .lane.port }}"
    auth = otelcol.auth.basic.tenant_{{ .index }}.handler
    max_request_body_size = "4MiB"
    traces_url_path = "{{ .lane.path }}/v1/traces"
    metrics_url_path = "{{ .lane.path }}/v1/metrics"
    logs_url_path = "{{ .lane.path }}/v1/logs"
  }
  output {
{{- if .isolation }}
    logs = [{{ .filterInput }}]
{{- end }}
    metrics = [{{ .filterInput }}]
{{- if .isolation }}
    traces = [{{ .filterInput }}]
{{- end }}
  }
}
{{- end -}}

{{/* Scope: index and tenantId. The caller retains the isolation gate and position. */}}
{{- define "lgtm-stack.gateway.lokiTransport" -}}
otelcol.exporter.otlphttp "loki_{{ .index }}" {
  client {
    endpoint = "http://loki.monitoring.svc.cluster.local:3100/otlp"
    headers = { "X-Scope-OrgID" = {{ .tenantId | quote }} }
  }
}
{{- end -}}

{{/* Scope: index and tenantId. Metrics-exporter policy belongs to each profile. */}}
{{- define "lgtm-stack.gateway.tempoTransport" -}}
otelcol.exporter.otlp "tempo_{{ .index }}" {
  client {
    endpoint = "tempo.monitoring.svc.cluster.local:4317"
    headers = { "X-Scope-OrgID" = {{ .tenantId | quote }} }
    tls {
      insecure = true
    }
  }
}
{{- end -}}
