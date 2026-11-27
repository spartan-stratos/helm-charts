{{/* Application-mode namespace checks. Scope: root, original tenant and receiver. */}}
{{- define "lgtm-stack.gateway.kubernetes.validateNamespaces" -}}
{{- $tenant := .tenant -}}
{{- $receiver := .receiver -}}
{{- if empty $receiver.namespaces }}{{ fail "receiver namespaces must be non-empty" }}{{ end }}
{{- range $receiver.namespaces }}
{{- if not (has . ($tenant.namespaces | default list)) }}{{ fail "receiver namespaces must be a subset of tenant namespaces" }}{{ end }}
{{- end }}
{{- end -}}

{{/* Complete Kubernetes pipeline. Scope: root, lane and index. */}}
{{- define "lgtm-stack.gateway.kubernetes.pipeline" -}}
{{- $root := .root -}}
{{- $tenant := .lane -}}
{{- $index := .index -}}
{{ include "lgtm-stack.gateway.receiverPrefix" (dict "index" $index "lane" $tenant "isolation" $root.Values.tenantIsolation.enabled "filterInput" (printf "otelcol.processor.filter.tenant_%d.input" $index)) | indent 6 }}
{{ include "lgtm-stack.gateway.kubernetes.filter" (dict "index" $index "lane" $tenant "isolation" $root.Values.tenantIsolation.enabled "attributesInput" (printf "otelcol.processor.attributes.tenant_%d.input" $index)) | indent 6 }}
      otelcol.processor.attributes "tenant_{{ $index }}" {
        action {
          key = "tenant"
          value = {{ $tenant.id | quote }}
          action = "upsert"
        }
        output {
{{- if $root.Values.tenantIsolation.enabled }}
          logs = [otelcol.processor.transform.tenant_{{ $index }}.input]
{{- end }}
          metrics = [otelcol.processor.transform.tenant_{{ $index }}.input]
{{- if $root.Values.tenantIsolation.enabled }}
          traces = [otelcol.processor.transform.tenant_{{ $index }}.input]
{{- end }}
        }
      }
      // Prometheus promotes resource attributes, so stamp the resource too.
      otelcol.processor.transform "tenant_{{ $index }}" {
{{ include "lgtm-stack.gateway.kubernetes.normalization" (dict "lane" $tenant "isolation" $root.Values.tenantIsolation.enabled) | trimPrefix "\n" | indent 8 }}
        output {
{{- if $root.Values.tenantIsolation.enabled }}
          logs = [otelcol.exporter.otlphttp.loki_{{ $index }}.input]
{{- end }}
          metrics = [otelcol.exporter.otlphttp.prometheus_{{ $index }}.input]
{{- if $root.Values.tenantIsolation.enabled }}
          traces = [otelcol.exporter.otlp.tempo_{{ $index }}.input]
{{- end }}
        }
      }
{{- if $root.Values.tenantIsolation.enabled }}
{{ include "lgtm-stack.gateway.lokiTransport" (dict "index" $index "tenantId" $tenant.id) | indent 6 }}
{{- end }}
      otelcol.exporter.otlphttp "prometheus_{{ $index }}" {
        client {
          endpoint = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090/api/v1/otlp"
          headers = { "X-Scope-OrgID" = {{ $tenant.id | quote }} }
        }
      }
{{- if $root.Values.tenantIsolation.enabled }}
{{ include "lgtm-stack.gateway.tempoTransport" (dict "index" $index "tenantId" $tenant.id) | indent 6 }}
{{- end }}
{{- end -}}

{{/* Profile receiver validation. Scope: root and receiver. */}}
{{- define "lgtm-stack.gateway.kubernetes.validateReceiver" -}}
{{- $root := .root -}}
{{- $receiver := .receiver -}}
{{- if or (hasKey $receiver "ecs") (hasKey $receiver "environment") -}}{{ fail "Kubernetes receivers must not set ecs or environment" }}{{- end -}}
{{- end -}}

{{/* Kubernetes admission only. Scope: index, lane, isolation and attributesInput. */}}
{{- define "lgtm-stack.gateway.kubernetes.filter" -}}
{{- $lane := .lane -}}
// A credential may only write its own namespaces: drop any telemetry naming another namespace, in the resource or in
// the datapoint, log or span attributes, so one tenant cannot forge series that another tenant's or the platform's
// rules select by namespace.
otelcol.processor.filter "tenant_{{ .index }}" {
  error_mode = "ignore"
  metrics {
    datapoint = [{{ printf "resource.attributes[\"k8s.namespace.name\"] != nil and not IsMatch(resource.attributes[\"k8s.namespace.name\"], \"^(%s)$\")" (join "|" $lane.namespaces) | quote }}, {{ printf "attributes[\"namespace\"] != nil and not IsMatch(attributes[\"namespace\"], \"^(%s)$\")" (join "|" $lane.namespaces) | quote }}]
  }
{{- if .isolation }}
  logs {
    log_record = ["resource.attributes[\"k8s.namespace.name\"] == nil", {{ printf "resource.attributes[\"k8s.namespace.name\"] != nil and not IsMatch(resource.attributes[\"k8s.namespace.name\"], \"^(%s)$\")" (join "|" $lane.namespaces) | quote }}, {{ printf "attributes[\"namespace\"] != nil and not IsMatch(attributes[\"namespace\"], \"^(%s)$\")" (join "|" $lane.namespaces) | quote }}]
  }
  traces {
    span = ["resource.attributes[\"k8s.namespace.name\"] == nil", {{ printf "resource.attributes[\"k8s.namespace.name\"] != nil and not IsMatch(resource.attributes[\"k8s.namespace.name\"], \"^(%s)$\")" (join "|" $lane.namespaces) | quote }}, {{ printf "attributes[\"namespace\"] != nil and not IsMatch(attributes[\"namespace\"], \"^(%s)$\")" (join "|" $lane.namespaces) | quote }}]
  }
{{- end }}
  output {
{{- if .isolation }}
    logs = [{{ .attributesInput }}]
{{- end }}
    metrics = [{{ .attributesInput }}]
{{- if .isolation }}
    traces = [{{ .attributesInput }}]
{{- end }}
  }
}
{{- end -}}

{{/* Kubernetes namespace and tenant stamping. Scope: lane and isolation. */}}
{{- define "lgtm-stack.gateway.kubernetes.normalization" -}}
{{- $lane := .lane -}}
{{- if $lane.stampNamespace }}
// Overwrite after the filter, which already checked the original namespace: a sender cannot pick the stored one.
{{- if .isolation }}
log_statements {
  context = "resource"
  statements = [{{ printf "set(attributes[\"k8s.namespace.name\"], %s)" ($lane.stampNamespace | toJson) | quote }}]
}
// Only where the sender set a record-level namespace: adding one to every line or span would create a new field.
log_statements {
  context = "log"
  statements = [{{ printf "set(attributes[\"namespace\"], %s) where attributes[\"namespace\"] != nil" ($lane.stampNamespace | toJson) | quote }}]
}
{{- end }}
metric_statements {
  context = "resource"
  statements = [{{ printf "set(attributes[\"k8s.namespace.name\"], %s)" ($lane.stampNamespace | toJson) | quote }}]
}
metric_statements {
  context = "datapoint"
  statements = [{{ printf "set(attributes[\"namespace\"], %s)" ($lane.stampNamespace | toJson) | quote }}]
}
{{- if .isolation }}
trace_statements {
  context = "resource"
  statements = [{{ printf "set(attributes[\"k8s.namespace.name\"], %s)" ($lane.stampNamespace | toJson) | quote }}]
}
trace_statements {
  context = "span"
  statements = [{{ printf "set(attributes[\"namespace\"], %s) where attributes[\"namespace\"] != nil" ($lane.stampNamespace | toJson) | quote }}]
}
{{- end }}
{{- end }}
{{- if .isolation }}
log_statements {
  context = "resource"
  statements = [{{ printf "set(attributes[\"tenant\"], %s)" ($lane.id | toJson) | quote }}]
}
{{- end }}
metric_statements {
  context = "resource"
  statements = [{{ printf "set(attributes[\"tenant\"], %s)" ($lane.id | toJson) | quote }}]
}
metric_statements {
  context = "datapoint"
  statements = ["set(attributes[\"namespace\"], resource.attributes[\"k8s.namespace.name\"]) where attributes[\"namespace\"] == nil and resource.attributes[\"k8s.namespace.name\"] != nil"]
}
{{- if .isolation }}
trace_statements {
  context = "resource"
  statements = [{{ printf "set(attributes[\"tenant\"], %s)" ($lane.id | toJson) | quote }}]
}
{{- end }}
{{- end -}}
