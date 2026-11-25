#!/usr/bin/env bash
set -euo pipefail
[[ "$(uname -s)-$(uname -m)" == Linux-x86_64 ]] || { echo 'Requires Linux amd64' >&2; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
curl -fsSLo helm.tar.gz https://get.helm.sh/helm-v3.17.3-linux-amd64.tar.gz
curl -fsSLo yq https://github.com/mikefarah/yq/releases/download/v4.45.1/yq_linux_amd64
curl -fsSLo prometheus.tar.gz https://github.com/prometheus/prometheus/releases/download/v3.5.0/prometheus-3.5.0.linux-amd64.tar.gz
sha256sum -c <<'SHA256'
ee88b3c851ae6466a3de507f7be73fe94d54cbf2987cbaa3d1a3832ea331f2cd  helm.tar.gz
654d2943ca1d3be2024089eb4f270f4070f491a0610481d128509b2834870049  yq
e811827af26d822afb09a4f28314f61b618b12cff5369835a67f674d8b46f39a  prometheus.tar.gz
SHA256
tar -xzf helm.tar.gz linux-amd64/helm
tar -xzf prometheus.tar.gz prometheus-3.5.0.linux-amd64/promtool
sudo install -m 0755 linux-amd64/helm yq prometheus-3.5.0.linux-amd64/promtool /usr/local/bin/
# The environment must survive this script for subsequent workflow steps.
python_env="$HOME/.spartan-alerts-python"
python3 -m venv "$python_env"
"$python_env/bin/python" -m pip install PyYAML==6.0.2
echo "$python_env/bin" >> "$GITHUB_PATH"
