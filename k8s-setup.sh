#!/bin/bash
# ============================================================
#  Kubernetes Node Bootstrap  —  RHEL 9 / kubeadm / CRI-O
#  Roles: master | control-plane | worker   (HA via HAProxy)
#
#  Interactive:  sudo ./k8s-setup.sh
#  Automated:    sudo ROLE=master HAPROXY_IP=10.0.0.100 ./k8s-setup.sh
#                sudo ROLE=worker JOIN_CMD="kubeadm join ..." ./k8s-setup.sh
# ============================================================
set -euo pipefail

# ------------------ Config (edit here only) ------------------
K8S_VERSION="v1.36"
CRIO_VERSION="v1.36"
POD_CIDR="192.168.0.0/16"
CALICO_VERSION="v3.32.1"
# -------------------------------------------------------------

[[ $EUID -eq 0 ]] || { echo "ERROR: run as root/sudo"; exit 1; }

# ==================== 1) Choose role ====================
if [[ -z "${ROLE:-}" ]]; then
  echo "=================================================="
  echo "  Choose this node's role:"
  echo "    master         ->  first control-plane (runs kubeadm init)"
  echo "    control-plane  ->  additional master (HA - joins via HAProxy)"
  echo "    worker         ->  regular worker (joins via HAProxy)"
  echo "=================================================="
  read -rp "Role [master/control-plane/worker]: " ROLE
fi
ROLE=$(echo "${ROLE}" | tr '[:upper:]' '[:lower:]' | xargs)
case "${ROLE}" in
  master|control-plane|worker) ;;
  *) echo "ERROR: unknown role: '${ROLE}'"; exit 1 ;;
esac
echo ">> Selected role: ${ROLE}"

# ==================== 2) Helper functions ====================
setup_kubeconfig() {
  mkdir -p "$HOME/.kube"
  cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
  chown "$(id -u):$(id -g)" "$HOME/.kube/config"
  export KUBECONFIG=/etc/kubernetes/admin.conf
}

run_prereqs() {
  echo "========== Disable Swap =========="
  swapoff -a
  sed -i '/ swap / s/^/#/' /etc/fstab

  echo "========== Disable SELinux =========="
  setenforce 0 || true
  sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

  echo "========== Disable Firewalld =========="
  if systemctl list-unit-files | grep -q "^firewalld.service"; then
    systemctl disable --now firewalld
  fi

  echo "========== Load Kernel Modules =========="
  cat >/etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
  modprobe overlay
  modprobe br_netfilter

  echo "========== Configure Sysctl =========="
  cat >/etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
EOF
  sysctl --system

  echo "========== Add Kubernetes Repository =========="
  cat >/etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/rpm/repodata/repomd.xml.key
EOF

  echo "========== Add CRI-O Repository =========="
  cat >/etc/yum.repos.d/cri-o.repo <<EOF
[cri-o]
name=CRI-O
baseurl=https://download.opensuse.org/repositories/isv:/cri-o:/stable:/${CRIO_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://download.opensuse.org/repositories/isv:/cri-o:/stable:/${CRIO_VERSION}/rpm/repodata/repomd.xml.key
EOF

  echo "========== Install Packages =========="
  dnf install -y container-selinux socat conntrack-tools
  dnf install -y cri-o kubelet kubeadm kubectl

  echo "========== Enable Services =========="
  systemctl enable --now crio
  systemctl enable --now kubelet
}

# ==================== 3) Prerequisites (all roles) ====================
run_prereqs

# ==================== 4) Branch by role ====================
case "${ROLE}" in

  master)
    if [[ -z "${HAPROXY_IP:-}" ]]; then
      read -rp "Enter the HAProxy IP (control-plane endpoint): " HAPROXY_IP
    fi

    echo "========== kubeadm init (first control-plane) =========="
    # --control-plane-endpoint + --upload-certs are required to add more masters later
    kubeadm init \
      --control-plane-endpoint "${HAPROXY_IP}:6443" \
      --upload-certs \
      --pod-network-cidr="${POD_CIDR}"

    echo "========== Configure kubectl =========="
    setup_kubeconfig

    echo "========== Install Calico (${CALICO_VERSION}) =========="
    kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"
    echo "Waiting for Calico Pods..."
    kubectl wait --for=condition=Ready pod \
      -n kube-system \
      -l k8s-app=calico-node \
      --timeout=300s || true

    echo "========== Generate Join Commands =========="
    # worker join -> automatically uses the HAProxy endpoint
    WORKER_JOIN="$(kubeadm token create --print-join-command)"
    # fresh certificate-key for control-plane join (valid for 2 hours only)
    CERT_KEY="$(kubeadm init phase upload-certs --upload-certs | tail -1)"
    CP_JOIN="${WORKER_JOIN} --control-plane --certificate-key ${CERT_KEY}"

    printf '%s\n' "${WORKER_JOIN}" > /root/join-worker.command
    printf '%s\n' "${CP_JOIN}"     > /root/join-control-plane.command
    chmod 600 /root/join-*.command

    echo
    echo "=============================================="
    echo " First control-plane is ready."
    echo "----------------------------------------------"
    echo " WORKER join command (saved to /root/join-worker.command):"
    echo "   ${WORKER_JOIN}"
    echo
    echo " CONTROL-PLANE join command (saved to /root/join-control-plane.command):"
    echo "   ${CP_JOIN}"
    echo "----------------------------------------------"
    echo " NOTE: token is valid for 24h, certificate-key for 2h only."
    echo "       If they expire, re-run these on the master:"
    echo "         kubeadm token create --print-join-command"
    echo "         kubeadm init phase upload-certs --upload-certs"
    echo "=============================================="
    kubectl get nodes -o wide
    ;;

  control-plane|worker)
    if [[ -z "${JOIN_CMD:-}" ]]; then
      echo
      echo "=================================================================="
      echo "  A join command is needed. Get it from the FIRST master"
      echo "  (the first node where 'kubeadm init' created the cluster)."
      echo "=================================================================="
      if [[ "${ROLE}" == "control-plane" ]]; then
        echo "  On the first master, run this single command. It generates the"
        echo "  token and certificate-key and prints one complete join command:"
        echo
        echo '    echo "$(kubeadm token create --print-join-command) --control-plane --certificate-key $(kubeadm init phase upload-certs --upload-certs | tail -1)"'
        echo
        echo "  (To see each part separately:"
        echo "     kubeadm token create --print-join-command      <- base join command"
        echo "     kubeadm init phase upload-certs --upload-certs  <- last line = certificate-key)"
        echo
        echo "  Copy the resulting line in full and paste it here:"
      else
        echo "  On the first master, run this command. It prints a complete"
        echo "  worker join command on a single line:"
        echo
        echo "    kubeadm token create --print-join-command"
        echo
        echo "  Copy the resulting line in full and paste it here:"
      fi
      echo "------------------------------------------------------------------"
      read -r JOIN_CMD
    fi

    # Ensure the CRI-O socket is set (only CRI-O is installed here)
    if [[ "${JOIN_CMD}" != *"--cri-socket"* ]]; then
      JOIN_CMD="${JOIN_CMD} --cri-socket unix:///var/run/crio/crio.sock"
    fi

    echo "========== Joining Cluster (${ROLE}) =========="
    eval "${JOIN_CMD}"

    # If control-plane -> configure kubectl on this node too
    if [[ "${ROLE}" == "control-plane" ]]; then
      echo "========== Configure kubectl =========="
      setup_kubeconfig
    fi

    echo
    echo "=============================================="
    echo " Node joined as ${ROLE}."
    echo " Verify from the master:  kubectl get nodes -o wide"
    echo "=============================================="
    ;;
esac
