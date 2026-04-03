#!/usr/bin/env bash
# install-longhorn.sh — Install Longhorn distributed storage on k3s
# Usage: source .env && bash install-longhorn.sh
set -euo pipefail

: "${MASTER_IP:?}" "${VM_USER:?}"
LONGHORN_VERSION=${LONGHORN_VERSION:-"1.7.2"}
REPLICA_COUNT=${LONGHORN_REPLICA_COUNT:-2}

SSH_MASTER="ssh -o StrictHostKeyChecking=no ${VM_USER}@${MASTER_IP}"

echo "=== Installing Longhorn ${LONGHORN_VERSION} ==="

# Install Helm if not present
$SSH_MASTER "which helm || curl -sfL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"

# Add Longhorn repo
$SSH_MASTER "helm repo add longhorn https://charts.longhorn.io && helm repo update"

# Install Longhorn
$SSH_MASTER "helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --version ${LONGHORN_VERSION} \
  --set defaultSettings.defaultReplicaCount=${REPLICA_COUNT} \
  --set defaultSettings.storageMinimalAvailablePercentage=10 \
  --set persistence.defaultClassReplicaCount=${REPLICA_COUNT} \
  --wait --timeout 10m"

# Set as default StorageClass
$SSH_MASTER "kubectl patch storageclass longhorn -p '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}'"

echo ""
echo "✅ Longhorn installed!"
echo ""
$SSH_MASTER "kubectl get pods -n longhorn-system"
echo ""
echo "Access Longhorn UI:"
echo "  kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80"
echo "  → http://localhost:8080"
