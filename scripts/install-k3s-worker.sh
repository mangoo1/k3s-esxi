#!/usr/bin/env bash
# install-k3s-worker.sh — Join worker nodes to k3s cluster
# Usage: source .env && bash install-k3s-worker.sh
set -euo pipefail

: "${MASTER_IP:?}" "${WORKER1_IP:?}" "${WORKER2_IP:?}" "${VM_USER:?}" "${K3S_TOKEN:?}"
K3S_VERSION=${K3S_VERSION:-""}

install_worker() {
  local WORKER_IP=$1 WORKER_NAME=$2
  echo "=== Joining ${WORKER_NAME} (${WORKER_IP}) to cluster ==="
  local SSH_VM="ssh -o StrictHostKeyChecking=no ${VM_USER}@${WORKER_IP}"

  echo "→ Waiting for SSH..."
  until $SSH_VM echo "SSH ready" 2>/dev/null; do sleep 5; done

  $SSH_VM "sudo apt-get update -q && sudo apt-get install -y -q curl open-iscsi nfs-common"
  $SSH_VM "sudo systemctl enable --now iscsid"

  # Format and mount data disk (second disk = /dev/sdb)
  $SSH_VM "sudo bash -c '
    if ! blkid /dev/sdb; then
      mkfs.ext4 -F /dev/sdb
      mkdir -p /var/lib/longhorn
      echo \"/dev/sdb /var/lib/longhorn ext4 defaults 0 0\" >> /etc/fstab
      mount -a
    fi
  '"

  if [[ -n "$K3S_VERSION" ]]; then
    $SSH_VM "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${K3S_VERSION} K3S_URL=https://${MASTER_IP}:6443 K3S_TOKEN=${K3S_TOKEN} sh -"
  else
    $SSH_VM "curl -sfL https://get.k3s.io | K3S_URL=https://${MASTER_IP}:6443 K3S_TOKEN=${K3S_TOKEN} sh -"
  fi

  echo "✅ ${WORKER_NAME} joined!"
}

install_worker "$WORKER1_IP" "k3s-worker-1"
install_worker "$WORKER2_IP" "k3s-worker-2"

echo ""
echo "=== Verifying cluster nodes ==="
ssh -o StrictHostKeyChecking=no ${VM_USER}@${MASTER_IP} "kubectl get nodes -o wide"
