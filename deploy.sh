#!/usr/bin/env bash
# Deploy VProfile to the cluster (run where kubectl is configured, e.g. master1)
set -euo pipefail

# 1) storage class (once per cluster)
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.31/deploy/local-path-storage.yaml
kubectl -n local-path-storage rollout status deploy/local-path-provisioner
kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# 2) app stack (order matters: ns -> secret -> backing services -> app)
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-secret.yaml
kubectl apply -f k8s/02-db.yaml
kubectl apply -f k8s/03-memcached.yaml
kubectl apply -f k8s/04-rabbitmq.yaml
kubectl apply -f k8s/05-app.yaml

# 3) watch it come up
kubectl -n vprofile get pods -w
