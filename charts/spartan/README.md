# spartan chart

Provide a simple way to deploy applications base on our demand.

## Introduction

This chart bootstraps a deployment on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

## Prerequisites

- Kubernetes 1.14+
- Helm 3.x

## Get Repo Info

```bash
helm repo add spartan https://spartan-stratos.github.io/helm-charts/
helm repo update
```

See [helm repo](https://helm.sh/docs/helm/helm_repo/) for command documentation.

## Installing the Chart

To install the spartan chart using Helm.

```sh
helm install <release_name> spartan/spartan --version <version> -n <namespace> --create-namespace
```

`<release_name>`: The name assigned to a release when install a Helm chart.

## Upgrading the Chart

To upgrade the spartan chart using Helm.

```sh
helm upgrade <release_name> [--install] spartan/spartan --version <version> -n <namespace> -f /values.yaml
```

`/values.yaml`: Points to a specific values file (values.yaml) that contains configuration settings for the Helm chart.

`--install`: Tell Helm to install the chart if the specified release does not exist.

## Uninstalling the Chart

To uninstall/delete the `<release_name>` deployment from the `<namespace>`:

```console
helm delete <release_name> -n <namespace>
```
The command removes all the resources associated with the chart and deletes the release.

## Running helm check

To render templates with provided values:

```console
helm template --values ./test/values.yaml ./charts/spartan
```
The command allows to prevalidate helm chart template before its deployment and executes helm lint and helm template commands

## Validating helm template

To run lint check.

```
helm lint
```

To test rendering chart templates locally.
```
helm template --dry-run --debug ./charts/spartan --generate-name

```

```
helm template <version>.tgz --namespace <namespace> -f "values.yaml" > template-file.yaml
```

- Example:

```
cd /charts/spartan/
helm package .
helm template spartan-0.1.0.tgz --namespace dev -f "values.yaml" > template-file.yaml

This command will gen template-file.yaml file at /charts/spartan/
```

## Configuration

The following table lists the configurable parameters of the **spartan chart** and their default values.

| Parameter                                                                                                                                                         | Description                                                                                                                                        | Default      |
|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------|--------------|
| affinity                                                                                                                                                          | Affinity settings for pod assignment                                                                                                               | {}           |
| appNameLabel                                                                                                                                                      | Used for app.kubernetes.io/name k8s resources label                                                                                                | {}           |
| autoscaling.enabled                                                                                                                                               | Enables Autoscaling                                                                                                                                | false        |
| autoscaling.behaviour                                                                                                                                             | Specifies separate scaling policies upon scale-up and scale-down behaviors                                                                         | {}           |
| autoscaling.maxReplicas                                                                                                                                           | Maximum amount of Replicas                                                                                                                         | 100          |
| autoscaling.metrics                                                                                                                                               | Specifies resource metrics utilization threshold                                                                                                   | []           |
| autoscaling.minReplicas                                                                                                                                           | Minimum amount of Replicas                                                                                                                         | 1            |
| autoscaling.targetCPUUtilizationPercentage                                                                                                                        | Target CPU Utilization in percentage                                                                                                               | null         |
| autoscaling.targetMemoryUtilizationPercentage                                                                                                                     | Target Memory Utilization in percentage                                                                                                            | null         |
| configMap.asFile.enabled                                                                                                                                          | Determines if the ConfigMap should be created from files                                                                                           | false        |
| configMap.asFile.data                                                                                                                                             | Specifies the data for the ConfigMap created from files                                                                                            | {}           |
| configMap.asFile.mountPath                                                                                                                                        | Specifies the path to mount files for the ConfigMap                                                                                                | {}           |
| configMap.asEnv.enabled                                                                                                                                           | Enables creating a ConfigMap from environment variables                                                                                            | false        |
| configMap.asEnv.data                                                                                                                                              | Specifies the data for the ConfigMap created from environment variables                                                                            | {}           |
| configMap.externalConfigMapEnv.enabled                                                                                                                            | Enables mapping an existing ConfigMap to environment variables                                                                                     | false        |
| configMap.externalConfigMapEnv.name                                                                                                                               | Specifies the name for the existing ConfigMap                                                                                                      | {}           |
| configMap.externalConfigMapFile.enabled                                                                                                                           | Determines if the files can be used from an existing ConfigMap                                                                                     | false        |
| configMap.externalConfigMapFile.name                                                                                                                              | Specifies the name for the existing ConfigMap containing from files                                                                                | {}           |
| configMap.externalConfigMapFile.mountPath                                                                                                                         | Specifies the path to mount files for the existing ConfigMap                                                                                       | {}           |
| containerPort                                                                                                                                                     | Service target Port                                                                                                                                | 8080         |
| containerName                                                                                                                                                     | Service container name                                                                                                                             | ""           |
| cronjobs                                                                                                                                                          | Specifies list of cronjobs                                                                                                                         | []           |
| datadog.enabled                                                                                                                                                   | Add default global environment variables for Datadog configuration (this attribute does not support Datadog configuration through Pod annotations) | false        |
| extraEnvs                                                                                                                                                         | Mapping of additional raw environment variables                                                                                                    | []           |
| fullnameOverride                                                                                                                                                  | String to fully override spartan.fullname template                                                                                                 | null         |
| gatewayApi.enabled                                                                                                                                                | Enables or disables the Gateway API integration                                                                                                    | false        |
| gatewayApi.gatewayName                                                                                                                                            | Specifies the name of the Gateway resource to be used or created                                                                                   | null         |
| gatewayApi.healthCheckPolicy                                                                                                                                      | Defines the health check policy settings for the Gateway                                                                                           | null         |
| gatewayApi.healthCheckPolicy.checkIntervalSec                                                                                                                     | Sets the interval (in seconds) between each health check                                                                                           | 10           |
| gatewayApi.healthCheckPolicy.config                                                                                                                               | Configuration settings for the health check policy                                                                                                 | null         |
| gatewayApi.healthCheckPolicy.healthyThreshold                                                                                                                     | Number of consecutive successful checks needed to mark the service as healthy                                                                      | 1            |
| gatewayApi.healthCheckPolicy.unhealthyThreshold                                                                                                                   | Number of consecutive failed checks before marking the service as unhealthy                                                                        | 3            |
| gatewayApi.healthCheckPolicy.timeoutSec                                                                                                                           | Timeout duration (in seconds) for each health check attempt                                                                                        | 6            |
| gatewayApi.httpRoute.hostnames                                                                                                                                    | Specifies the list of hostnames for HTTP routing                                                                                                   | null         |
| gatewayApi.httpRoute.rules                                                                                                                                        | Defines routing rules for the HTTP route                                                                                                           | null         |
| gatewayApi.namespace                                                                                                                                              | Namespace in which the Gateway API resources are deployed                                                                                          | null         |
| gcp.enabled                                                                                                                                                       | Enables GCP configurations                                                                                                                         | false        |
| [gcp.backendConfig](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-configuration#configuring_ingress_features_through_backendconfig_parameters)   | Specifies the configuration for backend configuration of ALB of GKE ingress                                                                        | {}           |
| [gcp.frontendConfig](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-configuration#configuring_ingress_features_through_frontendconfig_parameters) | Specifies the configuration for frontend configuration of ALB of GKE ingress                                                                       | {}           |
| [gcp.managedCertificate](https://cloud.google.com/kubernetes-engine/docs/how-to/managed-certs)                                                                    | Enable the managed certificate for TLS/SSL for GKE ingress ALB                                                                                     | {}           |
| hooks                                                                                                                                                             | Allows customization of various aspects of the Job                                                                                                 | {}           |
| image.repository                                                                                                                                                  | Container image repository                                                                                                                         | nginx        |
| image.tag                                                                                                                                                         | Container image tag                                                                                                                                | null         |
| image.pullPolicy                                                                                                                                                  | Container image pull policy                                                                                                                        | IfNotPresent |
| imagePullSecrets                                                                                                                                                  | Global Docker registry secret names as an array                                                                                                    | []           |
| ingress.enabled                                                                                                                                                   | Enable ingress controller resource                                                                                                                 | false        |
| ingress.className                                                                                                                                                 | Ingress class name (Kubernetes 1.18+)                                                                                                              | null         |
| ingress.hosts                                                                                                                                                     | Ingress resource hostnames                                                                                                                         | {}           |
| ingress.annotations                                                                                                                                               | Ingress annotations configuration                                                                                                                  | {}           |
| ingress.tls                                                                                                                                                       | Ingress TLS configuration                                                                                                                          | []           |
| livenessProbe                                                                                                                                                     | Liveness Probe initial delay and timeout                                                                                                           | {}           |
| nameOverride                                                                                                                                                      | String to partially override common.names.fullname template (will maintain the release name)                                                       | null         |
| nodeSelector                                                                                                                                                      | Node labels for pod assignment                                                                                                                     | {}           |
| pdb.enabled                                                                                                                                                       | Enable/disable a Pod Disruption Budget creation                                                                                                    | false        |
| pdb.minAvailable                                                                                                                                                  | Minimum number/percentage of pods that should remain scheduled                                                                                     | 1            |
| pdb.maxUnavailable                                                                                                                                                | Maximum number/percentage of pods that may be made unavailable                                                                                     | ""           |
| podAnnotations                                                                                                                                                    | Pods annotations                                                                                                                                   | {}           |
| podSecurityContext                                                                                                                                                | Custom pod security context for spartan pod                                                                                                        | {}           |
| readinessProbe                                                                                                                                                    | Readiness Probe initial delay and timeout                                                                                                          | {}           |
| replicaCount                                                                                                                                                      | Number of replicas                                                                                                                                 | 1            |
| resources                                                                                                                                                         | Server resource requests and limits                                                                                                                | {}           |
| secret.asFile.enabled                                                                                                                                             | Determines if the Secret should be created from files                                                                                              | false        |
| secret.asFile.data                                                                                                                                                | Specifies the data for the Secret created from files                                                                                               | {}           |
| secret.asEnv.enabled                                                                                                                                              | Enables creating a Secret from environment variables                                                                                               | false        |
| secret.asEnv.data                                                                                                                                                 | Specifies the data for the Secret created from environment variables                                                                               | {}           |
| secret.externalSecretFile.enabled                                                                                                                                 | Determines if the files can be used from an existing Secret                                                                                        | false        |
| secret.externalSecretFile.name                                                                                                                                    | Specifies the name for the existing Secret containing from files                                                                                   | {}           |
| secret.externalSecretFile.mountPath                                                                                                                               | Specifies the path to mount files for the existing Secret                                                                                          | {}           |
| secret.externalSecretEnv.enabled                                                                                                                                  | Enables mapping an existing Secret to environment variables                                                                                        | false        |
| secret.externalSecretEnv.name                                                                                                                                     | Specifies the name of the existing Secret                                                                                                          | {}           |
| securityContext                                                                                                                                                   | Custom security context for spartan container                                                                                                      | {}           |
| service.annotations                                                                                                                                               | Specifies service annotations                                                                                                                      | {}           |
| service.port                                                                                                                                                      | Name for service port                                                                                                                              | 80           |
| service.type                                                                                                                                                      | ClusterIP, NodePort, or LoadBalancer                                                                                                               | ClusterIP    |
| service.name                                                                                                                                                      | Service name                                                                                                                                       | http         |
| service.protocol                                                                                                                                                  | Service protocol                                                                                                                                   | tcp          |
| serviceAccount.create                                                                                                                                             | Specifies whether a service account should be created                                                                                              | false        |
| serviceAccount.annotations                                                                                                                                        | Annotations to add to the service account                                                                                                          | {}           |
| serviceAccount.name                                                                                                                                               | The name of the service account to use                                                                                                             | null         |
| sidecars                                                                                                                                                          | Enables sidecars containers to run specific tasks and mounting shared volumes                                                                      | {}           |
| startupProbe                                                                                                                                                      | Startup Probe initial delay and timeout                                                                                                            | {}           |
| workers                                                                                                                                                           | Enables users to deploy scalable and customizable worker components                                                                                | []           |
| testConnections.enabled                                                                                                                                           | Enables test connections                                                                                                                           | false        |
| tolerations                                                                                                                                                       | Toleration labels for pod assignment                                                                                                               | []           |
| [updateStrategy](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#strategy)                                                                  | Specifies the configuration for deployment strategy                                                                                                | {}           |
| vpa.enabled                                                                                                                                                       | Specifies whether a vertical pod autoscaling should be created                                                                                     | false        |
| vpa.updateMode                                                                                                                                                    | Specifies whether recommended updates are applied when a Pod is started and whether                                                                | "Auto"       |
