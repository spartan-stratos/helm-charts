# Repository guide

## Layout

- `charts/spartan`: application chart.
- `charts/datadog`: monitoring integration chart.
- `charts/lgtm-stack`: observability stack chart.
- `charts/spartan-alerts`: alert rules chart.
- `.github/workflows`: validation and release workflows.

## Validation

CI covers all four charts in `.github/workflows/pull_request.yml`.
Run `helm unittest charts/<chart>` for each changed chart.
Run `helm lint charts/<chart>` and `helm template charts/<chart>`.
For lgtm-stack, supply its required test values:

```sh
helm lint charts/lgtm-stack -f charts/lgtm-stack/ci/test-values.yaml
helm template charts/lgtm-stack -f charts/lgtm-stack/ci/test-values.yaml
```

CI uses helm-check for linting and rendering, then helm-unittest.
It also checks lgtm-stack rules and bundled dashboards.

## Releases

- Bump `version` in the changed chart's `Chart.yaml`.
- Add a CHANGELOG entry describing the change.
- Release Charts publishes on merge to master when a chart's `Chart.yaml` changes.
- `.github/workflows/release.yaml` also allows manual releases.

## Pull requests

- Copy the template headings verbatim before writing.
- State the behaviour after the change, not the investigation.
- Prefer terse bullets over paragraphs; Summary has 1 to 3 bullets.
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
