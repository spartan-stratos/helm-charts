{{/*
Rule bundles rendered in addon mode from alerting.rules. $o and $c print the braces of Prometheus templates.
*/}}

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
{{- /* One set of rules for the defaults (minus overridden services), then one per override */}}
{{- $sets := list (dict "matcher" "" "t" $cfg) }}
{{- $names := keys ($cfg.overrides | default dict) | sortAlpha }}
{{- if $names }}
{{- /* PromQL raw string, so the regex escapes from regexQuoteMeta stay as they are */}}
{{- $quoted := list }}
{{- range $names }}{{ $quoted = append $quoted (regexQuoteMeta .) }}{{ end }}
{{- $sets = list (dict "matcher" (printf ",service!~`%s`" (join "|" $quoted)) "t" $cfg) }}
{{- end }}
{{- range $names }}
{{- $t := deepCopy (omit $cfg "overrides") }}
{{- include "lgtm-stack.merge" (list $t (index $cfg.overrides .)) }}
{{- $sets = append $sets (dict "matcher" (printf `,service="%s"` .) "t" $t) }}
{{- end }}
{{- range $sets }}
{{- $m := .matcher }}
{{- $t := .t }}
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
          annotations:
            summary: Service {{ $o }} $labels.service {{ $c }} is failing {{ $o }} $value | humanizePercentage {{ $c }} of requests
            description: >-
              Server spans with status ERROR are above {{ mulf . 100 | printf "%.4g" }}% for {{ $t.errorRate.for }}.
              Open the Service overview (RED) dashboard and the error traces for this service.
            runbook_url: https://github.com/spartan-stratos/helm-charts/blob/master/charts/lgtm-stack/README.md#service-alerts
{{- end }}
{{- with index $t.latencyP95 $sev }}
        - alert: ServiceLatencyHigh
          expr: |-
            service:traces_spanmetrics_latency_p95:rate5m{ {{- trimPrefix "," $m -}} } > {{ . }}
            and on (service) {{ $traffic }}
          for: {{ $t.latencyP95.for }}
          labels:
            severity: {{ $sev }}
          annotations:
            summary: Service {{ $o }} $labels.service {{ $c }} p95 latency is {{ $o }} $value | humanizeDuration {{ $c }}
            description: >-
              p95 of server spans is above {{ . }}s for {{ $t.latencyP95.for }}.
              Check the slowest routes on the Service overview (RED) dashboard.
            runbook_url: https://github.com/spartan-stratos/helm-charts/blob/master/charts/lgtm-stack/README.md#service-alerts
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
{{- end -}}
