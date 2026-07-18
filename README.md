# VProfile on Kubernetes — ALnaqib bundle

Companion files for the PDF guide. Deploy VProfile (Java multi-tier app) as 4
secure microservices on a kubeadm HA cluster (RHEL 9), fronted by HAProxy.

## Layout
```
images/
  app/Dockerfile        multi-stage Tomcat (build WAR -> minimal runtime, non-root)
  db/Dockerfile         MySQL 8 pre-seeded with the 'accounts' DB
  memcached/Dockerfile  hardened memcached
  rabbitmq/Dockerfile   rabbitmq + management
k8s/
  00-namespace.yaml  01-secret.yaml  02-db.yaml
  03-memcached.yaml  04-rabbitmq.yaml  05-app.yaml
haproxy/vprofile.cfg    frontend/backend to append on the HAProxy VM
build-and-push.sh       build + trivy scan + push to alnaqib/*
deploy.sh               install local-path SC + apply manifests in order
```

## Quick start
```bash
# 1) on your workstation (docker + trivy):
./build-and-push.sh

# 2) on master1 (kubectl configured):
./deploy.sh

# 3) on the HAProxy VM: append haproxy/vprofile.cfg (fix worker IPs), then
sudo haproxy -c -f /etc/haproxy/haproxy.cfg && sudo systemctl reload haproxy
```

## MUST edit before using
- k8s/01-secret.yaml         -> real passwords (NOT the demo defaults)
- images/app build args      -> MUST match the secret's db/rmq user+password
- haproxy/vprofile.cfg        -> real worker INTERNAL-IPs (kubectl get nodes -o wide)

The app image bakes db/rmq credentials into the WAR at build time, so the Secret
values and the app --build-arg values must be identical.
