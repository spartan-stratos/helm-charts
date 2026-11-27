{{/* Complete ECS pipeline. Scope: root, lane and index. */}}
{{- define "lgtm-stack.gateway.ecs.pipeline" -}}
{{- $root := .root -}}
{{- $tenant := .lane -}}
{{- $index := .index -}}
{{ include "lgtm-stack.gateway.receiverPrefix" (dict "index" $index "lane" $tenant "isolation" $root.Values.tenantIsolation.enabled "filterInput" (printf "otelcol.processor.filter.tenant_%d.input" $index)) | indent 6 }}
{{ include "lgtm-stack.gateway.ecs.filter" (dict "root" $root "lane" $tenant "index" $index "attributesInput" (printf "otelcol.processor.attributes.tenant_%d.input" $index)) | trimPrefix "\n" | indent 6 }}
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
{{ include "lgtm-stack.gateway.ecs.normalization" (dict "root" $root "lane" $tenant "index" $index) | indent 8 }}
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
{{ include "lgtm-stack.gateway.ecs.metricsExporter" (dict "root" $root "lane" $tenant "index" $index) | indent 6 }}
{{- if $root.Values.tenantIsolation.enabled }}
{{ include "lgtm-stack.gateway.tempoTransport" (dict "index" $index "tenantId" $tenant.id) | indent 6 }}
{{- end }}
{{- end -}}

{{/* Profile receiver validation. Scope: root and receiver. */}}
{{- define "lgtm-stack.gateway.ecs.validateReceiver" -}}
{{- $root := .root -}}
{{- $receiver := .receiver -}}
{{- range $key := list "namespaces" "stampNamespace" -}}
{{- if hasKey $receiver $key -}}{{ fail (printf "ECS receivers must not set %s" $key) }}{{- end -}}
{{- end -}}
{{- if not (and (kindIs "bool" $root.Values.tenantIsolation.enabled) (eq $root.Values.tenantIsolation.enabled true)) -}}{{ fail "ECS receivers require tenantIsolation.enabled true" }}{{- end -}}
{{- if not (kindIs "string" $receiver.environment) -}}{{ fail "ECS receiver environment must be dev or prod" }}{{- end -}}
{{- if not (has $receiver.environment (list "dev" "prod")) -}}{{ fail "ECS receiver environment must be dev or prod" }}{{- end -}}
{{- $secret := $receiver.htpasswdSecret -}}
{{- if not (kindIs "map" $secret) -}}{{ fail "ECS receiver htpasswdSecret must be an object with name and key" }}{{- end -}}
{{- if not (and (kindIs "string" $secret.name) (kindIs "string" $secret.key)) -}}{{ fail "ECS receiver htpasswdSecret requires string name and key" }}{{- end -}}
{{- if or (not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$" $secret.name)) (gt (len $secret.name) 253) (not (regexMatch "^[A-Za-z0-9._-]+$" $secret.key)) (gt (len $secret.key) 253) -}}{{ fail "ECS receiver htpasswdSecret requires valid nonempty name and key" }}{{- end -}}
{{- $ecs := $receiver.ecs -}}
{{- if not (kindIs "map" $ecs) -}}{{ fail "receiver ecs must be an object" }}{{- end -}}
{{- range $key, $_ := $ecs -}}
{{- if not (has $key (list "accountId" "clusterArn" "serviceNames")) -}}{{ fail (printf "unknown ecs identity key %s" $key) }}{{- end -}}
{{- end -}}
{{- if not (kindIs "string" $ecs.accountId) -}}{{ fail "ecs.accountId must be a twelve-digit string" }}{{- end -}}
{{- if not (regexMatch "^[0-9]{12}$" $ecs.accountId) -}}{{ fail "ecs.accountId must be a twelve-digit string" }}{{- end -}}
{{- if not (kindIs "string" $ecs.clusterArn) -}}{{ fail "ecs.clusterArn must be an ECS cluster ARN" }}{{- end -}}
{{- if or (gt (len $ecs.clusterArn) 512) (not (regexMatch "^arn:aws(-cn|-us-gov)?:ecs:[a-z]{2}(-[a-z]+)+-[0-9]+:[0-9]{12}:cluster/[A-Za-z0-9_-]{1,255}$" $ecs.clusterArn)) -}}{{ fail "ecs.clusterArn must be a bounded literal ECS cluster ARN" }}{{- end -}}
{{- if ne (index (splitList ":" $ecs.clusterArn) 4) $ecs.accountId -}}{{ fail "ecs.clusterArn account must equal ecs.accountId" }}{{- end -}}
{{- if not (kindIs "slice" $ecs.serviceNames) -}}{{ fail "ecs.serviceNames must be a list of one to sixteen unique literal names" }}{{- end -}}
{{- if or (lt (len $ecs.serviceNames) 1) (gt (len $ecs.serviceNames) 16) -}}{{ fail "ecs.serviceNames must contain one to sixteen names" }}{{- end -}}
{{- $services := dict -}}
{{- range $ecs.serviceNames -}}
{{- if not (kindIs "string" .) -}}{{ fail "ecs.serviceNames must contain only literal strings" }}{{- end -}}
{{- if not (regexMatch "^[A-Za-z0-9_-]{1,255}$" .) -}}{{ fail "ecs.serviceNames must contain bounded literal ECS service names" }}{{- end -}}
{{- if hasKey $services . -}}{{ fail "ecs.serviceNames must not contain duplicates" }}{{- end -}}
{{- $_ := set $services . true -}}
{{- end -}}
{{- end -}}

{{/* ECS admission only. Scope: root, lane, index and attributesInput. */}}
{{- define "lgtm-stack.gateway.ecs.filter" -}}
{{- $lane := .lane -}}
{{- $index := .index -}}
{{- $fixed := dict "tenant" $lane.id "env" $lane.environment "deployment.environment" $lane.environment "deployment.environment.name" $lane.environment }}
{{- $identity := dict "cloud.account.id" "cloud.account.id" "aws.ecs.cluster.arn" "aws.ecs.cluster.arn" "aws.ecs.task.arn" "aws.ecs.task.arn" "service.name" "service.name" "service.instance.id" "aws.ecs.task.arn" }}
{{- $drop := list }}
{{- range $key := list "cloud.account.id" "aws.ecs.cluster.arn" "aws.ecs.task.arn" "service.name" }}
{{- $drop = append $drop (printf "not IsString(resource.attributes[%s])" ($key | toJson)) }}
{{- end }}
{{- range $key, $value := dict "cloud.account.id" $lane.ecs.accountId "aws.ecs.cluster.arn" $lane.ecs.clusterArn }}
{{- $drop = append $drop (printf "resource.attributes[%s] != %s" ($key | toJson) ($value | toJson)) }}
{{- end }}
{{- $services := list }}
{{- range $lane.ecs.serviceNames }}
{{- $services = append $services (printf "resource.attributes[\"service.name\"] == %s" (. | toJson)) }}
{{- end }}
{{- $drop = append $drop (printf "not (%s)" (join " or " $services)) }}
{{- $taskPattern := printf "^%s/[0-9a-f]{32}$" (replace ":cluster/" ":task/" $lane.ecs.clusterArn) }}
{{- $drop = append $drop (printf "not IsMatch(resource.attributes[\"aws.ecs.task.arn\"], %s)" ($taskPattern | toJson)) }}
{{- range $key := list "namespace" "k8s.namespace.name" }}
{{- $drop = append $drop (printf "resource.attributes[%s] != nil" ($key | toJson)) }}
{{- end }}
{{- range $key, $value := $fixed }}
{{- $drop = append $drop (printf "resource.attributes[%s] != nil and (not IsString(resource.attributes[%s]) or resource.attributes[%s] != %s)" ($key | toJson) ($key | toJson) ($key | toJson) ($value | toJson)) }}
{{- end }}
{{- $drop = concat $drop (list "resource.attributes[\"service.instance.id\"] != nil and (not IsString(resource.attributes[\"service.instance.id\"]) or resource.attributes[\"service.instance.id\"] != resource.attributes[\"aws.ecs.task.arn\"])" "Len(resource.attributes) > 64" "Len(instrumentation_scope.attributes) > 64") }}
{{- $resourceDrop := $drop }}
{{- range $key := list "namespace" "k8s.namespace.name" }}
{{- $drop = append $drop (printf "attributes[%s] != nil" ($key | toJson)) }}
{{- end }}
{{- range $key, $value := $fixed }}
{{- $drop = append $drop (printf "attributes[%s] != nil and (not IsString(attributes[%s]) or attributes[%s] != %s)" ($key | toJson) ($key | toJson) ($key | toJson) ($value | toJson)) }}
{{- end }}
{{- range $key, $resourceKey := $identity }}
{{- $drop = append $drop (printf "attributes[%s] != nil and (not IsString(attributes[%s]) or attributes[%s] != resource.attributes[%s])" ($key | toJson) ($key | toJson) ($key | toJson) ($resourceKey | toJson)) }}
{{- end }}
{{- $drop = append $drop "Len(attributes) > 64" }}
// BasicAuth identifies the tenant; ECS attributes are matching constraints, not AWS attestation.
otelcol.processor.filter "tenant_{{ $index }}" {
  error_mode = "propagate"
  metrics {
    metric = [{{ range $i, $condition := $resourceDrop }}{{ if $i }}, {{ end }}{{ $condition | quote }}{{ end }}]
    datapoint = [{{ range $i, $condition := $drop }}{{ if $i }}, {{ end }}{{ $condition | quote }}{{ end }}]
  }
  logs {
    log_record = [{{ range $i, $condition := $drop }}{{ if $i }}, {{ end }}{{ $condition | quote }}{{ end }}]
  }
  traces {
    span = [{{ range $i, $condition := $drop }}{{ if $i }}, {{ end }}{{ $condition | quote }}{{ end }}]
  }
  output {
    logs = [{{ .attributesInput }}]
    metrics = [{{ .attributesInput }}]
    traces = [{{ .attributesInput }}]
  }
}
{{- end -}}

{{/* ECS canonical normalization only. Scope: root, lane and index. */}}
{{- define "lgtm-stack.gateway.ecs.normalization" -}}
{{- $lane := .lane -}}
error_mode = "propagate"
{{- $resourceStatements := list "keep_keys(attributes, [\"cloud.account.id\", \"aws.ecs.cluster.arn\", \"aws.ecs.task.arn\", \"service.name\"])" "set(attributes[\"service.instance.id\"], attributes[\"aws.ecs.task.arn\"])" }}
{{- $businessKeys := list "http.request.method" "http.response.status_code" "http.route" "url.scheme" "server.address" "server.port" "network.protocol.name" "network.protocol.version" "error.type" "jvm.memory.type" "jvm.memory.pool.name" "jvm.gc.name" "jvm.thread.state" "jvm.buffer.pool.name" "db.system.name" "db.operation.name" "db.client.connection.pool.name" "pool.name" "state" "type" }}
{{- $signalStatements := list "keep_keys(instrumentation_scope.attributes, [])" }}
{{- range $key, $value := dict "tenant" $lane.id "env" $lane.environment "deployment.environment" $lane.environment "deployment.environment.name" $lane.environment }}
{{- $statement := printf "set(attributes[%s], %s)" ($key | toJson) ($value | toJson) }}
{{- $resourceStatements = append $resourceStatements $statement }}
{{- $signalStatements = append $signalStatements $statement }}
{{- end }}
{{- range $block, $context := dict "log_statements" "log" "metric_statements" "datapoint" "trace_statements" "span" }}
{{- $contextKeys := $businessKeys }}
{{- if eq $context "span" }}{{- $contextKeys = concat $businessKeys (list "url.path") }}{{- end }}
{{- $contextStatements := concat (list (printf "keep_keys(attributes, %s)" ($contextKeys | toJson))) $signalStatements }}
{{ $block }} {
  context = "resource"
  statements = [{{ range $i, $statement := $resourceStatements }}{{ if $i }}, {{ end }}{{ $statement | quote }}{{ end }}]
}
{{ $block }} {
  context = {{ $context | quote }}
  statements = [{{ range $i, $statement := $contextStatements }}{{ if $i }}, {{ end }}{{ $statement | quote }}{{ end }}]
}
{{- end }}
{{- end -}}

{{/* ECS metrics preserve arrival order. Scope: root, lane and index. */}}
{{- define "lgtm-stack.gateway.ecs.metricsExporter" -}}
otelcol.exporter.otlphttp "prometheus_{{ .index }}" {
  sending_queue {
    num_consumers = 1
  }
  client {
    endpoint = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090/api/v1/otlp"
    headers = { "X-Scope-OrgID" = {{ .lane.id | quote }} }
  }
}
{{- end -}}
