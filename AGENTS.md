# Repository guide

## Layout

- `charts/spartan`: application chart.
- `charts/datadog`: monitoring integration chart.
- `charts/lgtm-stack`: observability stack chart.
- `charts/lgtm-tenant-client`: Kubernetes tenant telemetry client chart.
- `charts/spartan-alerts`: alert rules chart.
- `.github/workflows`: validation and release workflows.

## Validation

The Helm validation matrix in `.github/workflows/pull_request.yml` covers five charts:
spartan, datadog, lgtm-stack, spartan-alerts and lgtm-tenant-client.
Run `helm unittest charts/<chart>` for each changed chart.
Run `helm lint charts/<chart>` and `helm template charts/<chart>`.
For lgtm-stack, supply its required test values:

```sh
helm lint charts/lgtm-stack -f charts/lgtm-stack/ci/test-values.yaml
helm template charts/lgtm-stack -f charts/lgtm-stack/ci/test-values.yaml
```

CI uses helm-check for linting and rendering, then helm-unittest.
It also checks lgtm-stack rules and bundled dashboards.

### Gateway ownership and validation

- Helm manages the Kubernetes-hosted telemetry hub. ECS task collectors, Java helpers, FireLens, task roles and rollout belong to the sender's ECS infrastructure.
- Keep `presets/alloy-gateway.yaml` as the values shell. Chart-prefixed templates in `_gateway.tpl` dispatch to `_gateway-kubernetes.tpl` or `_gateway-ecs.tpl`; `_gateway-transport.tpl` owns shared transport fragments.
- Pass explicit context to named templates. Preserve receiver order, global indexes and rendered bytes during extraction. Profiles may reject incompatible identity claims, but must not stamp the other platform's workload identity.
- Helm lint/render/unit CI jobs run unconditionally. Receiver contracts are validated in applications mode and the gateway addon, including when ingress is disabled; unrelated addons validate only the inputs they consume.
- Heavy ECS runtime checks use explicit shared/ECS dependency paths, including gateway ingress and Prometheus backend settings. Dedicated Kubernetes profile or documentation changes alone skip that runtime check.
- Failed or missing path detection must run the runtime check and remain a failing check; fallback runtime success does not clear detector failure.

## Releases

- Bump `version` in the changed chart's `Chart.yaml`.
- Add a CHANGELOG entry describing the change.
- Release Charts publishes on merge to master when a chart's `Chart.yaml` changes.
- `.github/workflows/release.yaml` also allows manual releases.

## Pull requests

- Copy the template headings verbatim before writing.
- State the behaviour after the change, not the investigation.
- Prefer terse bullets over paragraphs; Summary has three bullets: Why, What and Effect of merging.
- Include a Mermaid diagram by default.
- Use `No diagram: reason` only for trivial or docs-only changes.
- Test Plan lists commands and results, or human-verifiable steps.
- Tick applicable Types of Changes; Jira Issues may be n/a.
- Never name another project, repo, company or client.
- No internal ticket ids, local file paths or internal tool names.
- No AI attribution or co-author trailers.
- No en or em dashes or horizontal bars; use plain hyphens.
- Stay under 300 prose words, excluding code, tables, checkboxes and comments.
- Posted review bodies carry the verdict and unanchored findings only, under 1200 characters; detail goes inline.
