{{/* Application-mode receiver checks retain the original parent tenant. Scope: root, tenant, receiver. */}}
{{- define "lgtm-stack.gateway.validateApplicationReceiver" -}}
{{- $mode := include "lgtm-stack.receiverMode" (list .root .receiver) }}
{{- if eq $mode "kubernetes" }}
{{- include "lgtm-stack.gateway.kubernetes.validateNamespaces" . }}
{{- end }}
{{- end -}}

{{/* Preserve global lane order and dispatch once at the platform boundary. Scope: root. */}}
{{- define "lgtm-stack.gateway.config" -}}
{{- $root := . -}}
{{- range $index, $lane := (include "lgtm-stack.gatewayLanes" $root | fromYamlArray) -}}
{{- if $index }}{{ "\n" }}{{- end -}}
{{- if and (hasKey $lane "mode") (eq $lane.mode "ecs") }}
{{- include "lgtm-stack.gateway.ecs.pipeline" (dict "root" $root "lane" $lane "index" $index) }}
{{- else }}
{{- include "lgtm-stack.gateway.kubernetes.pipeline" (dict "root" $root "lane" $lane "index" $index) }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "lgtm-stack.receiverMode" -}}
{{- $root := index . 0 -}}
{{- $receiver := index . 1 -}}
{{- $mode := "kubernetes" -}}
{{- if hasKey $receiver "mode" -}}
{{- if not (kindIs "string" $receiver.mode) -}}{{ fail "receiver mode must be kubernetes or ecs" }}{{- end -}}
{{- if not (has $receiver.mode (list "kubernetes" "ecs")) -}}{{ fail "receiver mode must be kubernetes or ecs" }}{{- end -}}
{{- $mode = $receiver.mode -}}
{{- end -}}
{{- if eq $mode "kubernetes" -}}
{{- include "lgtm-stack.gateway.kubernetes.validateReceiver" (dict "root" $root "receiver" $receiver) -}}
{{- else -}}
{{- include "lgtm-stack.gateway.ecs.validateReceiver" (dict "root" $root "receiver" $receiver) -}}
{{- end -}}
{{- $mode -}}
{{- end -}}

{{/* Flatten receivers so legacy tenants retain their lane index and rendered names. */}}
{{- define "lgtm-stack.gatewayLanes" -}}
{{- $root := . -}}
{{- $lanes := list -}}
{{- range .Values.tenants -}}
{{- $tenant := . -}}
{{- range $key := list "mode" "environment" "ecs" -}}
{{- if hasKey $tenant $key -}}{{ fail (printf "legacy tenant-level %s is unsupported; use nested receivers" $key) }}{{- end -}}
{{- end -}}
{{- if hasKey . "receivers" -}}
{{- range .receivers -}}
{{- $mode := include "lgtm-stack.receiverMode" (list $root .) -}}
{{- $ingress := true -}}
{{- if hasKey . "ingress" -}}{{- $ingress = .ingress -}}{{- end -}}
{{- if eq $mode "ecs" -}}
{{- $lanes = append $lanes (dict "id" $tenant.id "name" .name "port" .port "path" (.path | default (printf "/%s/%s" $tenant.id .name)) "ingress" $ingress "mode" $mode "environment" .environment "ecs" .ecs "htpasswdSecret" .htpasswdSecret) -}}
{{- else -}}
{{- $lanes = append $lanes (dict "id" $tenant.id "name" .name "port" .port "path" (.path | default (printf "/%s/%s" $tenant.id .name)) "ingress" $ingress "namespaces" .namespaces "stampNamespace" (.stampNamespace | default "") "htpasswdSecret" (.htpasswdSecret | default dict)) -}}
{{- end -}}
{{- end -}}
{{- else -}}
{{- $lanes = append $lanes (dict "id" .id "name" .id "port" .port "path" (printf "/%s" .id) "ingress" true "namespaces" .namespaces "htpasswdSecret" (.htpasswdSecret | default dict)) -}}
{{- end -}}
{{- end -}}
{{- toYaml $lanes -}}
{{- end -}}
