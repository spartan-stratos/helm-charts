# Spartan helm charts

## Overall

A comprehensive document that outlines conventions, standards, and best practices for developing and maintaining c0x12c Centralized Helm Charts.

The Centralized Helm Chart provides a comprehensive solution for deploying and managing **[Your Application]** on Kubernetes clusters. This Helm chart simplifies the deployment process by encapsulating all the necessary Kubernetes manifests and configuration into a single package.

## Structure

This section defines the folder structure standard for centralized helm chart only.

Additional files or folders not relating to helm chart, such as ArtifactHub metadata files, will not be included in this document but will be included in relative document if necessary.

### Overall Folder Structure

Following is overall folder structure to describe how Helm charts will be located:

```
helm-charts/       # Master folder of Helm charts using for the project.
  charts/          # Folder that will include all private charts, created and maintained by Infra team, following the structure mentioned in custom chart section.
  README.md        # Guidelines for working on this helm chart locally and from ArtifactHub and reference to *Helm Chart Standard and Convention* document.
```

### Custom Charts

Custom charts will follow the Helm official File Structure as below: (For example)

```
/spartan              # Chart folder.
  README.md           # Human-readable README file on chart configuration. Providing clear, step-by-step guides, input/output details, example configurations, and best practices for using the helm charts, making it easy for teams to onboard and implement.
  CHANGELOG.md        # Including changes made to chart.
  Chart.yaml          # Containing metadata about the chart (file name case-sensitive).
  values.yaml         # Default configuration values for this chart.
  templates/          # Directory of templates that, when combined with values, will generate valid Kubernetes manifest files.
    NOTES.txt         # OPTIONAL: A plain text file containing short usage notes
    tests/            # Folder consists of test files.
  hosting/            # Folder consists of packaged charts and a file index.yaml which contains an index of all of the charts in the repository.
```

## Standards and Conventions

### Chart naming and file naming

- **Naming:** must be lower case letters and numbers. Words may be separated with dashes `-`.

```
[CORRECT]   aws-cluster-autoscaler
[INCORRECT] awsClusterAutoScaler       # no camelcase
[INCORRECT] aws.cluster.autoscaler     # no dots
[INCORRECT] aws_cluster_auto_scaler    # no underscore
```

- **Chart version:** Use [SemVer 2](https://semver.org/) to represent version numbers: `MAJOR.MINOR.PATCH`.

### Templates

- Template files are located in `/templates` folder of a chart.
- Template files should have the extension `.yaml` if they produce YAML output. The extension `.tpl` may be used for template files that produce no formatted content.
- Template file names should reflect the resource kind in the name. e.g. `foo-pod.yaml`, `bar-svc.yaml`.
- All defined template names should be name-spaced to avoid conflicts among subcharts since templates are globally accessible by each other.

```
[CORRECT]
{{- define "spartan.fullname" }}
{{/* ... */}}
{{ end -}}

[INCORRECT]
{{- define "fullname" -}}
{{/* ... */}}
{{ end -}}
```

### Formatting

- YAML and template files should be indented using *two spaces* (and never tabs).
- Best to have no blank lines.
- Should have whitespace after the opening braces and before the closing braces; and chomp whitespace where possible.

```
[CORRECT]
{{ .foo }}
{{ print "foo" }}
{{- print "bar" -}}

[INCORRECT]
{{.foo}}
{{print "foo"}}
{{-print "bar"-}}
```

- Blocks (such as control structures) may be indented to indicate flow of the template code.

```
{{ if $foo -}}
  {{- with .Bar }}Hello{{ end -}}
{{- end -}}
```

### Comments

- For YAML:

```
*# This is a comment*
**type**: sprocket
```

- For Templates:

```
{{- /*
This is a comment.
*/}}
**type**: frobnitz
```

### Arguments and Values

- **Variable naming:** should begin with a lowercase letter, and words should be separated with camelcase.

```
[CORRECT]   chicken: true
[CORRECT]   chickenNoodleSoup: true
[INCORRECT] Chicken: true                # initial caps may conflict with built-ins
**[INCORRECT] chicken-noodle-soup: true    # do not use hyphens in the name
```

Note that all of Helm's built-in variables begin with an uppercase letter to easily distinguish them from user-defined values: `.Release.Name`, `.Capabilities.KubeVersion`.

- **Existence check:**

For optimal safety, a nested value must be checked at every level:

```
# nested
server:
  name: nginx
  port: 80
  
# flat
serverName: nginx
serverPort: 80
```

```
{{ if .Values.server }}
  {{ default "none" .Values.server.name }}
{{ end }}
```

- **Types clearance:**

To avoid type conversion errors is to be explicit about strings, and implicit about everything else. Or, in short, *quote all strings*.

To avoid the integer casting issues, store your integers as strings, and use `{{ int $value }}` in the template to convert from a string back to an integer.

### Chart manifests

- **Images:** A container image should use a fixed tag or the SHA of the image. It should not use the tags `latest`, `head`, `canary`, or other tags that are designed to be "floating".
- **ImagePullPolicy:** should be `IfNotPresent` by default.
- **PodTemplates Should Declare Selectors:** makes the relationship between the controller and the pod. Without this, Kubernetes will automatically try to match all labels and lose track of its pods, leading to mismatches or failures in rolling updates.

```
selector:
  matchLabels:
      app.kubernetes.io/name: spartan
template:
  metadata:
    labels:
      app.kubernetes.io/name: spartan
```

### Labels and Annotations

Labels that are recommended, and *should* be placed onto a chart for global consistency:

- Used by Kubernetes to identify this resource
- Useful to expose to operators for the purpose of querying the system.

The label list below is non-exhaustive and only includes recommended, not optional ones.

| Name | Description                                                                                                                                                                      |
| --- |----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `app.kubernetes.io/name` | This should be the app name, reflecting the entire app. Usually `{{ template "name" . }}` is used for this. This is used by many Kubernetes manifests, and is not Helm-specific. |
| `helm.sh/chart` | This should be the chart name and version: `{{ .Chart.Name }}-{{ .Chart.Version \| replace "+" "_" }}`.                                                                          |
| `app.kubernetes.io/managed-by` | This should always be set to `{{ .Release.Service }}`. It is for finding all things managed by Helm.                                                                             |
| `app.kubernetes.io/instance` | This should be the `{{ .Release.Name }}`. It aids in differentiating between different instances of the same application.                                                        |

If an item of metadata is not used for querying, it should be set as an annotation instead.

Helm hooks are always annotations.

## Tests

Reference: https://github.com/helm-unittest/helm-unittest

```
suite: "<Resource> template tests"

templates:
  - "templates/<resource_template>.yaml"

tests:
  - it: "test name"
    set:
      <property>: <expectedValue>
      ...
    asserts:
      - <condition>:                # E.g., isKind, equal, lengthEqual, matchRegex, ...
          of: <KubernetesResource>  # E.g., Deployment, Service, Ingress, ...
      - ...

  - ... 
```

## Documentation

We should provide comments and documents concisely and precisely for continuous developing and maintaining, quickly understanding the Centralized Helm Charts.

There are files considered for good documentation:

- `helm-charts/charts/chart-name/README.md`

```
# Chart name

## Introduction

Description of this chart.

## Prerequisites

- The following prerequisites are required for a successful and properly secured use of Helm.

## Get Repo Info

## Installing the Chart

## Upgrading the Chart

## Uninstalling the Chart

## Running helm check

## Validating helm template

## Configuration

The following table lists the configurable parameters of the chart and their default values.

| Parameter    | Description  | Default |
|--------------|--------------|---------|
| abc          | Used for xyz | {}      |

```

- `CHANGELOG.md`

```
# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0](https://github.com/repo/compare/v0.0.1...v1.0.0) (2024-01-01)

### ⚠ BREAKING CHANGES

* Bump version (#1)

### Features

* Add abc ([#1](https://pr-link) ([2517eb9](https://commit-link))

### Bug Fixes

* Fix abc ([#1](https://pr-link) ([2517eb9](https://commit-link))
```
