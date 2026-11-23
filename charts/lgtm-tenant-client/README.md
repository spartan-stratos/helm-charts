# LGTM tenant client

The platform team owns this shared chart for sending tenant telemetry to an lgtm-stack receiver.
It creates four objects in the configured namespace: ServiceAccount `otlp-secrets`, SecretStore
`otlp-secrets`, ExternalSecret `otlp-basic-auth` and an OpenTelemetry Instrumentation.

Install the External Secrets Operator and OpenTelemetry Operator CRDs first. Create the application
namespace beforehand. Use one IAM role per consumer. Trust exactly
`system:serviceaccount:<namespace>:otlp-secrets`, with no wildcard. Allow only
`secretsmanager:GetSecretValue` and `secretsmanager:DescribeSecret` on the configured secret.
Use `lgtm/tenants/<tenant>-<env>/otlp-basic-auth` with JSON keys `username`, `password` and `htpasswd`.
The sender reads `username` and `password`; the gateway reads `htpasswd` from the same entry.
Cross-account: the role lives in the cluster account. The secret's resource policy and its KMS key
policy must both allow that role.
The External Secrets Operator resolves credentials at runtime and produces the `otlp-headers` Secret key.
No plaintext credentials are stored in chart values or rendered manifests.
The default refresh is `1h`. Apply a rotated value now with
`kubectl annotate externalsecret otlp-basic-auth -n <namespace> force-sync=<epoch> --overwrite`.

## Values

All defaults are empty strings. Every required value fails rendering with `<key> is required` when empty or missing.

| Key | Required | Meaning |
| --- | --- | --- |
| `namespace` | Yes | Existing application namespace for all four objects. |
| `tenant` | Yes | Tenant id; required even when the instrumentation name is overridden. |
| `region` | Yes | AWS region of the Secrets Manager entry. |
| `roleArn` | Yes | IAM role ARN used by the `otlp-secrets` service account. |
| `secretName` | Yes | Secrets Manager entry containing `username` and `password`. |
| `receiverUrl` | Yes | OTLP HTTP receiver base URL, including its configured receiver path. |
| `instrumentationName` | No | Instrumentation name; defaults to `tenant`. |

Dev uses in-cluster port `4320` and path `/<tenant>`. Prod uses its own port and path
`/<tenant>/<env>`, for example `:4321/example/prod`. Public receivers use the ingress host.

## Example

Replace `<account-id>` and `<region>`. Supply values matching the platform receiver:

```yaml
namespace: example-app
tenant: example
region: <region>
roleArn: arn:aws:iam::<account-id>:role/example-otlp-secrets
secretName: lgtm/tenants/example-dev/otlp-basic-auth
receiverUrl: http://alloy-gateway.monitoring.svc.cluster.local:4320/example
```

Install this chart with those values and configure the workload's operator injection annotation to
reference the Instrumentation:
`instrumentation.opentelemetry.io/inject-<lang>: "<namespace>/<instrumentationName>"`.
`instrumentationName` defaults to `tenant`. The chart does not annotate or restart application workloads.

## Receiver contract

See [Onboarding a tenant in the lgtm-stack README](../lgtm-stack/README.md#onboarding-a-tenant).
The platform configures the tenant and receiver separately. Each receiver has its own port, credentials
and namespace allowlist. The client credentials must match the receiver's htpasswd entry.

Receiver paths default to `/<id>/<name>`. A receiver may set `path`, for example `/<id>` for dev;
legacy tenant receivers also use `/<id>`. Use the configured path when overridden. Direct signal endpoints have the form
`http://alloy-gateway.monitoring.svc.cluster.local:<port>/<id>/<name>/v1/{metrics,logs,traces}`.
Public receivers use the ingress host and the same signal suffixes. Set `receiverUrl` to the base
URL including the receiver path, without the signal suffix.

Logs and spans must carry resource attribute `k8s.namespace.name`; the gateway drops them otherwise.
With `tenantIsolation.enabled: false` on the stack, receivers forward only metrics and drop logs and traces.
This chart does not configure the receiver, backend isolation, namespace labels or receiver credentials.
