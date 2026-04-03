#!/usr/bin/env bash
# install-k3s-master.sh — Install k3s on master node
# Usage: source .env && bash install-k3s-master.sh
set -euo pipefail

: "${MASTER_IP:?}" "${VM_USER:?}"
K3S_VERSION=${K3S_VERSION:-""}
SSH_VM="ssh -o StrictHostKeyChecking=no ${VM_USER}@${MASTER_IP}"

echo "=== Installing k3s master on ${MASTER_IP} ==="

# Wait for SSH
echo "→ Waiting for SSH..."
until $SSH_VM echo "SSH ready" 2>/dev/null; do sleep 5; done

# Install dependencies
$SSH_VM "sudo apt-get update -q && sudo apt-get install -y -q curl open-iscsi nfs-common"
$SSH_VM "sudo systemctl enable --now iscsid"

# Install k3s
if [[ -n "$K3S_VERSION" ]]; then
  $SSH_VM "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${K3S_VERSION} sh -s - server \
    --write-kubeconfig-mode 644 \
    --disable traefik \
    --node-ip ${MASTER_IP}"
else
  $SSH_VM "curl -sfL https://get.k3s.io | sh -s - server \
    --write-kubeconfig-mode 644 \
    --disable traefik \
    --node-ip ${MASTER_IP}"
fi

# Wait for node ready
echo "→ Waiting for node ready..."
$SSH_VM "until kubectl get node | grep -q Ready; do sleep 5; done"

# Get join token
NODE_TOKEN=$($SSH_VM "sudo cat /var/lib/rancher/k3s/server/node-token")
echo ""
echo "✅ k3s master installed!"
echo ""
echo "Join token (save this):"
echo "  NODE_TOKEN=${NODE_TOKEN}"
echo ""
echo "Add to your .env:"
echo "  K3S_TOKEN=${NODE_TOKEN}"
echo ""
echo "kubeconfig:"
$SSH_VM "cat /etc/rancher/k3s/k3s.yaml" | sed "s/127.0.0.1/${MASTER_IP}/g"
