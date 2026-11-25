{{/*
Rule bundles rendered in addon mode from alerting.rules. $o and $c print the braces of Prometheus templates.
*/}}

{{- define "lgtm-stack.retentionSeconds" -}}
{{- $value := toString . -}}
{{- if eq $value "0" -}}
0
{{- else -}}
{{- if not (regexMatch "^([0-9]+(ms|s|m|h|d|w|y))+$" $value) -}}
{{- fail (printf "invalid retention duration %q" $value) -}}
{{- end -}}
{{- $milliseconds := int64 0 -}}
{{- $units := dict "ms" 1 "s" 1000 "m" 60000 "h" 3600000 "d" 86400000 "w" 604800000 "y" 31536000000 -}}
{{- range regexFindAll "[0-9]+(ms|s|m|h|d|w|y)" $value -1 -}}
{{- $unit := regexFind "ms|s|m|h|d|w|y" . -}}
{{- $milliseconds = add $milliseconds (mul (int64 (trimSuffix $unit .)) (index $units $unit)) -}}
{{- end -}}
{{- div $milliseconds 1000 -}}
{{- end -}}
{{- end -}}

{{- define "lgtm-stack.rules.retention" -}}
{{- $retention := .Values.retention | default dict -}}
{{- if or (ne (index $retention "loki") nil) (ne (index $retention "tempo") nil) }}
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: lgtm-retention
  namespace: {{ .Values.namespace }}
spec:
  groups:
    - name: lgtm-retention
      rules:
{{- range $component := list "loki" "tempo" }}
{{- $seconds := index $retention $component }}
{{- if ne $seconds nil }}
        - record: lgtm_retention_seconds
          expr: vector({{ $seconds | int64 }})
          labels:
            component: {{ $component }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{/* RED alerts per service from Tempo span metrics (server spans), with per-service overrides */}}
{{- define "lgtm-stack.rules.services" -}}
{{- $o := "{{" }}{{ $c := "}}" -}}
{{- $cfg := .Values.alerting.rules.services -}}
{{- $sel := `span_kind="SPAN_KIND_SERVER"` -}}
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: lgtm-service-red
  namespace: {{ .Values.namespace }}
spec:
  groups:
    - name: lgtm-service-red.recording
      rules:
        - record: service:traces_spanmetrics_calls:rate5m
          expr: sum by (service) (rate(traces_spanmetrics_calls_total{ {{- $sel -}} }[5m]))
        - record: service:traces_spanmetrics_errors:rate5m
          expr: sum by (service) (rate(traces_spanmetrics_calls_total{ {{- $sel -}} ,status_code="STATUS_CODE_ERROR"}[5m]))
        - record: service:traces_spanmetrics_error_ratio:rate5m
          expr: service:traces_spanmetrics_errors:rate5m / service:traces_spanmetrics_calls:rate5m
        - record: service:traces_spanmetrics_latency_p95:rate5m
          expr: histogram_quantile(0.95, sum by (service, le) (rate(traces_spanmetrics_latency_bucket{ {{- $sel -}} }[5m])))
    - name: lgtm-service-red
      rules:
{{- /* One default set excludes services with overrides or namespace mappings, then one per special service */}}
{{- $overrides := $cfg.overrides | default dict }}
{{- $namespaces := $cfg.namespaces | default dict }}
{{- range $service, $namespace := $namespaces }}
{{- if not (kindIs "string" $namespace) }}
{{- fail (printf "Invalid namespace for service %s: must be a non-empty DNS label string" $service) }}
{{- end }}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $namespace) }}
{{- fail (printf "Invalid namespace for service %s: must be a non-empty DNS label string" $service) }}
{{- end }}
{{- end }}
{{- $sets := list (dict "matcher" "" "t" $cfg "namespace" "") }}
{{- $names := concat (keys $overrides) (keys $namespaces) | uniq | sortAlpha }}
{{- if $names }}
{{- /* PromQL raw string, so the regex escapes from regexQuoteMeta stay as they are */}}
{{- $quoted := list }}
{{- range $names }}{{ $quoted = append $quoted (regexQuoteMeta .) }}{{ end }}
{{- $sets = list (dict "matcher" (printf ",service!~`%s`" (join "|" $quoted)) "t" $cfg "namespace" "") }}
{{- end }}
{{- range $names }}
{{- $t := deepCopy (omit $cfg "overrides" "namespaces") }}
{{- with index $overrides . }}
{{- include "lgtm-stack.merge" (list $t .) }}
{{- end }}
{{- $sets = append $sets (dict "matcher" (printf `,service="%s"` .) "t" $t "namespace" (index $namespaces . | default "")) }}
{{- end }}
{{- range $sets }}
{{- $m := .matcher }}
{{- $t := .t }}
{{- $namespace := .namespace }}
{{- if $t.enabled }}
{{- $traffic := printf "service:traces_spanmetrics_calls:rate5m{%s} > %v" (trimPrefix "," $m) $t.minRequestRate }}
{{- range $sev := list "warning" "critical" }}
{{- with index $t.errorRate $sev }}
        - alert: ServiceErrorRateHigh
          expr: |-
            service:traces_spanmetrics_error_ratio:rate5m{ {{- trimPrefix "," $m -}} } > {{ . }}
            and on (service) {{ $traffic }}
          for: {{ $t.errorRate.for }}
          labels:
            severity: {{ $sev }}
{{- if $namespace }}
            namespace: {{ $namespace | quote }}
{{- end }}
          annotations:
            summary: Service {{ $o }} $labels.service {{ $c }} is failing {{ $o }} $value | humanizePercentage {{ $c }} of requests
            description: >-
              Server spans with status ERROR are above {{ mulf . 100 | printf "%.4g" }}% for {{ $t.errorRate.for }}.
              Open the Service overview (RED) dashboard and the error traces for this service.
            runbook_url: https://github.com/spartan-stratos/helm-charts/blob/master/charts/lgtm-stack/README.md#service-alerts
            dashboard_url: /d/lgtm-service-red/service-overview-red?var-service={{ $o }} $labels.service {{ $c }}
{{- end }}
{{- with index $t.latencyP95 $sev }}
        - alert: ServiceLatencyHigh
          expr: |-
            service:traces_spanmetrics_latency_p95:rate5m{ {{- trimPrefix "," $m -}} } > {{ . }}
            and on (service) {{ $traffic }}
          for: {{ $t.latencyP95.for }}
          labels:
            severity: {{ $sev }}
{{- if $namespace }}
            namespace: {{ $namespace | quote }}
{{- end }}
          annotations:
            summary: Service {{ $o }} $labels.service {{ $c }} p95 latency is {{ $o }} $value | humanizeDuration {{ $c }}
            description: >-
              p95 of server spans is above {{ . }}s for {{ $t.latencyP95.for }}.
              Check the slowest routes on the Service overview (RED) dashboard.
            runbook_url: https://github.com/spartan-stratos/helm-charts/blob/master/charts/lgtm-stack/README.md#service-alerts
            dashboard_url: /d/lgtm-service-red/service-overview-red?var-service={{ $o }} $labels.service {{ $c }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{/* Workload alerts kube-prometheus-stack does not ship */}}
{{- define "lgtm-stack.rules.workloads" -}}
{{- $o := "{{" }}{{ $c := "}}" -}}
{{- $cfg := .Values.alerting.rules.workloads -}}
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: lgtm-workloads
  namespace: {{ .Values.namespace }}
spec:
  groups:
    - name: lgtm-workloads
      rules:
        - alert: ContainerImagePullFailing
          expr: max by (namespace, pod, container) (kube_pod_container_status_waiting_reason{reason=~"ErrImagePull|ImagePullBackOff|InvalidImageName"}) > 0
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: Image pull failing for {{ $o }} $labels.namespace {{ $c }}/{{ $o }} $labels.pod {{ $c }} ({{ $o }} $labels.container {{ $c }})
            description: The container has been waiting on its image for 5 minutes. Check the image tag and the registry credentials.
            runbook_url: https://github.com/spartan-stratos/helm-charts/blob/master/charts/lgtm-stack/README.md#workload-alerts
            dashboard_url: "/d/6581e46e4e5c7ba40a07646395ef7b23/kubernetes-compute-resources-pod?var-namespace={{ $o }} $labels.namespace {{ $c }}&var-pod={{ $o }} $labels.pod {{ $c }}"
        - alert: ContainerOOMKilled
          expr: |-
            max by (namespace, pod, container) (increase(kube_pod_container_status_restarts_total[15m])) > 0
            and on (namespace, pod, container) kube_pod_container_status_last_terminated_reason{reason="OOMKilled"} == 1
          labels:
            severity: warning
          annotations:
            summary: "{{ $o }} $labels.namespace {{ $c }}/{{ $o }} $labels.pod {{ $c }} ({{ $o }} $labels.container {{ $c }}) was OOM-killed"
            description: The container restarted after hitting its memory limit in the last 15 minutes. Raise the limit or find the leak.
            runbook_url: https://github.com/spartan-stratos/helm-charts/blob/master/charts/lgtm-stack/README.md#workload-alerts
            dashboard_url: "/d/6581e46e4e5c7ba40a07646395ef7b23/kubernetes-compute-resources-pod?var-namespace={{ $o }} $labels.namespace {{ $c }}&var-pod={{ $o }} $labels.pod {{ $c }}"
        - alert: ContainerMemoryNearLimit
          expr: |-
            max by (namespace, pod, container) (container_memory_working_set_bytes{container!="",container!="POD"})
            / on (namespace, pod, container) max by (namespace, pod, container) (kube_pod_container_resource_limits{resource="memory"})
            > {{ $cfg.memoryLimitRatio }}
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "{{ $o }} $labels.namespace {{ $c }}/{{ $o }} $labels.pod {{ $c }} ({{ $o }} $labels.container {{ $c }}) uses {{ $o }} $value | humanizePercentage {{ $c }} of its memory limit"
            description: Above {{ mulf $cfg.memoryLimitRatio 100 | printf "%.4g" }}% of the limit for 15 minutes; the next spike is an OOM kill.
            runbook_url: https://github.com/spartan-stratos/helm-charts/blob/master/charts/lgtm-stack/README.md#workload-alerts
            dashboard_url: "/d/6581e46e4e5c7ba40a07646395ef7b23/kubernetes-compute-resources-pod?var-namespace={{ $o }} $labels.namespace {{ $c }}&var-pod={{ $o }} $labels.pod {{ $c }}"
        # A pod annotated for auto-instrumentation that started while the OTel Operator was down runs without an agent
        - alert: PodMissingInstrumentation
          expr: |-
            max by (namespace, pod) (
              kube_pod_annotations{annotation_instrumentation_opentelemetry_io_inject_java!~"|false"}
              or kube_pod_annotations{annotation_instrumentation_opentelemetry_io_inject_python!~"|false"}
              or kube_pod_annotations{annotation_instrumentation_opentelemetry_io_inject_go!~"|false"}
              or kube_pod_annotations{annotation_instrumentation_opentelemetry_io_inject_nodejs!~"|false"}
              or kube_pod_annotations{annotation_instrumentation_opentelemetry_io_inject_dotnet!~"|false"}
            )
            unless on (namespace, pod) (
              kube_pod_init_container_info{container=~"opentelemetry-auto-instrumentation.*"}
              or kube_pod_container_info{container="opentelemetry-auto-instrumentation"}
            )
            and on (namespace, pod) (kube_pod_status_phase{phase="Running"} == 1)
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "{{ $o }} $labels.namespace {{ $c }}/{{ $o }} $labels.pod {{ $c }} runs without its OpenTelemetry agent"
            description: The pod asks for auto-instrumentation but has no agent, so it sends no traces. Restart it once the OTel Operator is up.
            runbook_url: https://github.com/spartan-stratos/helm-charts/blob/master/charts/lgtm-stack/README.md#workload-alerts
            dashboard_url: "/d/6581e46e4e5c7ba40a07646395ef7b23/kubernetes-compute-resources-pod?var-namespace={{ $o }} $labels.namespace {{ $c }}&var-pod={{ $o }} $labels.pod {{ $c }}"
{{- end -}}
