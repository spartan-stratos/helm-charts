#!/bin/bash

SEMTAG='./tools/semtag'
ACTION=${1:-patch}

git fetch origin --tags

RELEASE_VERSION="$($SEMTAG final -s $ACTION -o)"

echo "Next release version: $RELEASE_VERSION"

sed -i "/^version:/c version: $RELEASE_VERSION" charts/spartan/Chart.yaml
sed -i "/^appVersion:/c appVersion: $RELEASE_VERSION" charts/spartan/Chart.yaml

mkdir -p ./charts/spartan/hosting

helm package charts/spartan -d ./charts/spartan/hosting
helm repo index ./charts/spartan/hosting --merge ./charts/spartan/hosting/index.yaml

git add ./charts/spartan/hosting
git add spartan/Chart.yaml

git commit -m "chore: bump version to $RELEASE_VERSION" -a
git push origin master

$SEMTAG final -s $ACTION -v "$RELEASE_VERSION"
