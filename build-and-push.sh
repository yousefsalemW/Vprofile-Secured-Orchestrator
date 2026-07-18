#!/usr/bin/env bash
# Build, scan and push the 4 VProfile images to Docker Hub (alnaqib/*)
# Run from a workstation that has: git, docker (or podman), trivy
set -euo pipefail

DHUB="alnaqib"        # your Docker Hub username
TAG="1.0"
PLATFORM="linux/amd64"   # RHEL 9 nodes are amd64

# 0) get the source repo (app + db images build FROM it)
[ -d src ] || git clone -b Master https://github.com/abdelrahmanonline4/sourcecodeseniorwr.git src

# 1) build
docker build --platform "$PLATFORM" -t "$DHUB/vprofile-app:$TAG" -f images/app/Dockerfile       src/
docker build --platform "$PLATFORM" -t "$DHUB/vprofile-db:$TAG"  -f images/db/Dockerfile        src/
docker build --platform "$PLATFORM" -t "$DHUB/vprofile-mc:$TAG"  -f images/memcached/Dockerfile images/memcached/
docker build --platform "$PLATFORM" -t "$DHUB/vprofile-rmq:$TAG" -f images/rabbitmq/Dockerfile  images/rabbitmq/

# 2) scan (fail the build on HIGH/CRITICAL if you drop '|| true')
for s in app db mc rmq; do
  echo "== scanning $s =="
  trivy image --severity HIGH,CRITICAL --ignore-unfixed "$DHUB/vprofile-$s:$TAG" || true
done

# 3) push
docker login -u "$DHUB"
for s in app db mc rmq; do docker push "$DHUB/vprofile-$s:$TAG"; done
echo "done."
