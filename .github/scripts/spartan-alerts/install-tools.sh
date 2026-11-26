#!/usr/bin/env bash
set -euo pipefail
HELM_VERSION=3.17.3
YQ_VERSION=4.45.1
PROMETHEUS_VERSION=3.5.0
[[ "$(uname -s)" == Linux ]] || { echo 'Requires Linux' >&2; exit 1; }
case "$(uname -m)" in
  x86_64)
    arch=amd64
    helm_sha=ee88b3c851ae6466a3de507f7be73fe94d54cbf2987cbaa3d1a3832ea331f2cd
    yq_sha=654d2943ca1d3be2024089eb4f270f4070f491a0610481d128509b2834870049
    prometheus_sha=e811827af26d822afb09a4f28314f61b618b12cff5369835a67f674d8b46f39a
    ;;
  aarch64|arm64)
    arch=arm64
    helm_sha=7944e3defd386c76fd92d9e6fec5c2d65a323f6fadc19bfb5e704e3eee10348e
    yq_sha=ceea73d4c86f2e5c91926ee0639157121f5360da42beeb8357783d79c2cc6a1d
    prometheus_sha=173389cc42bf09c4e6e54cb53fa07a5a835d7c261e14775d2183181d6e385d1c
    ;;
  *) echo "Requires Linux amd64 or arm64, got $(uname -m)" >&2; exit 1 ;;
esac
# Tools and the Python environment must survive this script for subsequent workflow steps.
home="${RUNNER_TEMP:-$HOME}/spartan-alerts-tools"
bin="$home/bin"
mkdir -p "$bin"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
fetch() { # fetch <url> <sha256> <file>
  curl -fsSLo "$3" "$1"
  echo "$2  $3" | sha256sum -c -
}
# A tool already on PATH is kept only at the pinned version, so a runner image change cannot move the checks.
has() { command -v "$1" >/dev/null 2>&1 && "$@" 2>/dev/null | grep -qF "$PINNED"; }
if ! PINNED="v$HELM_VERSION" has helm version --short; then
  fetch "https://get.helm.sh/helm-v$HELM_VERSION-linux-$arch.tar.gz" "$helm_sha" helm.tar.gz
  tar -xzf helm.tar.gz "linux-$arch/helm"
  install -m 0755 "linux-$arch/helm" "$bin/helm"
fi
if ! PINNED="v$YQ_VERSION" has yq --version; then
  fetch "https://github.com/mikefarah/yq/releases/download/v$YQ_VERSION/yq_linux_$arch" "$yq_sha" yq
  install -m 0755 yq "$bin/yq"
fi
if ! PINNED="version $PROMETHEUS_VERSION " has promtool --version; then
  fetch "https://github.com/prometheus/prometheus/releases/download/v$PROMETHEUS_VERSION/prometheus-$PROMETHEUS_VERSION.linux-$arch.tar.gz" "$prometheus_sha" prometheus.tar.gz
  tar -xzf prometheus.tar.gz "prometheus-$PROMETHEUS_VERSION.linux-$arch/promtool"
  install -m 0755 "prometheus-$PROMETHEUS_VERSION.linux-$arch/promtool" "$bin/promtool"
fi
python3 -m venv "$home/python"
"$home/python/bin/python" -m pip install PyYAML==6.0.2
echo "$bin" >> "$GITHUB_PATH"
echo "$home/python/bin" >> "$GITHUB_PATH"
