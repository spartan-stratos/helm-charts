#!/usr/bin/env bash
set -euo pipefail

mkdir -p generated
cp charts/spartan-alerts/files/tests/catalogue-values.yaml generated/alerts-values.yaml
yq -i '.service.name = "artifact-test"' generated/alerts-values.yaml
