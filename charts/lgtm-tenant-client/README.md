# LGTM tenant client

The platform team owns this shared chart for sending tenant telemetry to an lgtm-stack receiver.
It creates four objects in the configured namespace: ServiceAccount `otlp-secrets`, SecretStore
`otlp-secrets`, ExternalSecret `otlp-basic-auth` and an OpenTelemetry Instrumentation.

Install the External Secrets Operator and OpenTelemetry Operator CRDs first. Create the application
namespace beforehand. The IAM role must trust the `otlp-secrets` service account in that namespace
and permit reading the configured AWS Secrets Manager entry with `username` and `password` properties.
The External Secrets Operator resolves credentials at runtime and produces the `otlp-headers` Secret key.
No plaintext credentials are stored in chart values or rendered manifests.

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

## Example

The account id below is a fake placeholder. Supply values matching the platform receiver:

```yaml
namespace: example-app
tenant: example
region: us-east-1
roleArn: arn:aws:iam::000000000000:role/example-otlp-secrets
secretName: example/otlp-basic-auth
receiverUrl: http://alloy-gateway.monitoring.svc.cluster.local:4320/example/dev
```

Install this chart with those values and configure the workload's operator injection annotation to
reference the Instrumentation. The chart does not annotate or restart application workloads.

## Receiver contract

See [Onboarding a tenant in the lgtm-stack README](../lgtm-stack/README.md#onboarding-a-tenant).
The platform configures the tenant and receiver separately. Each receiver has its own port, credentials
and namespace allowlist. The client credentials must match the receiver's htpasswd entry.

Receiver paths default to `/<id>/<name>`; legacy tenant receivers use `/<id>`. Use the configured
path when overridden. Direct signal endpoints have the form
`http://alloy-gateway.monitoring.svc.cluster.local:<port>/<id>/<name>/v1/{metrics,logs,traces}`.
Public receivers use the ingress host and the same signal suffixes. Set `receiverUrl` to the base
URL including the receiver path, without the signal suffix.

Logs and spans must carry resource attribute `k8s.namespace.name`; the gateway drops them otherwise.
With `tenantIsolation.enabled: false` on the stack, receivers forward only metrics and drop logs and traces.
This chart does not configure the receiver, backend isolation, namespace labels or receiver credentials.
