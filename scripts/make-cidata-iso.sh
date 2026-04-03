#!/usr/bin/env bash
# make-cidata-iso.sh — Generate cloud-init autoinstall ISOs for k3s nodes
# Requires: cloud-image-utils (cloud-localds) or genisoimage/mkisofs
# Usage: source .env && bash scripts/make-cidata-iso.sh
#
# Output: /tmp/cidata-{master,worker-1,worker-2}.iso
# These ISOs are then uploaded to ESXi and attached to VMs as a second CD-ROM.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CIDATA_DIR="${SCRIPT_DIR}/cloud-init"

# ── Check dependencies ────────────────────────────────────────────────────────
if command -v cloud-localds &>/dev/null; then
  ISO_TOOL="cloud-localds"
elif command -v genisoimage &>/dev/null; then
  ISO_TOOL="genisoimage"
elif command -v mkisofs &>/dev/null; then
  ISO_TOOL="mkisofs"
else
  echo "❌ Need cloud-image-utils, genisoimage, or mkisofs"
  echo "   sudo apt install cloud-image-utils"
  exit 1
fi

echo "Using ISO tool: ${ISO_TOOL}"

# ── Required env vars ─────────────────────────────────────────────────────────
: "${MASTER_IP:?}" "${WORKER1_IP:?}" "${WORKER2_IP:?}"
: "${SUBNET_PREFIX:?}" "${GATEWAY:?}" "${DNS:?}"
: "${VM_USER:?}" "${VM_SSH_KEY_PUB:?}"

# Password hash (default: "ubuntu")
if [[ -z "${VM_PASSWORD_HASH:-}" ]]; then
  if command -v openssl &>/dev/null; then
    VM_PASSWORD_HASH=$(echo "ubuntu" | openssl passwd -6 -stdin)
    echo "⚠️  VM_PASSWORD_HASH not set, using default password 'ubuntu'"
  else
    echo "❌ Set VM_PASSWORD_HASH in .env (openssl passwd -6)"
    exit 1
  fi
fi

# Read SSH public key
VM_SSH_PUBKEY=$(cat "${VM_SSH_KEY_PUB/#\~/$HOME}")

make_iso() {
  local NAME=$1
  local USER_DATA_TPL=$2
  local OUTPUT=/tmp/cidata-${NAME}.iso
  local TMPDIR
  TMPDIR=$(mktemp -d)

  echo "→ Building cloud-init ISO for ${NAME}..."

  # Substitute variables in user-data template
  sed \
    -e "s|\${MASTER_IP}|${MASTER_IP}|g" \
    -e "s|\${WORKER1_IP}|${WORKER1_IP}|g" \
    -e "s|\${WORKER2_IP}|${WORKER2_IP}|g" \
    -e "s|\${WORKER_IP}|${WORKER_IP:-}|g" \
    -e "s|\${WORKER_HOSTNAME}|${WORKER_HOSTNAME:-}|g" \
    -e "s|\${SUBNET_PREFIX}|${SUBNET_PREFIX}|g" \
    -e "s|\${GATEWAY}|${GATEWAY}|g" \
    -e "s|\${DNS}|${DNS}|g" \
    -e "s|\${VM_USER}|${VM_USER}|g" \
    -e "s|\${VM_PASSWORD_HASH}|${VM_PASSWORD_HASH}|g" \
    -e "s|\${VM_SSH_PUBKEY}|${VM_SSH_PUBKEY}|g" \
    "${USER_DATA_TPL}" > "${TMPDIR}/user-data"

  # meta-data with correct hostname
  sed "s/k3s-node/${NAME}/g" "${CIDATA_DIR}/meta-data" > "${TMPDIR}/meta-data"

  if [[ "${ISO_TOOL}" == "cloud-localds" ]]; then
    cloud-localds "${OUTPUT}" "${TMPDIR}/user-data" "${TMPDIR}/meta-data"
  else
    # genisoimage / mkisofs
    ${ISO_TOOL} \
      -output "${OUTPUT}" \
      -volid cidata \
      -joliet -rock \
      "${TMPDIR}/user-data" \
      "${TMPDIR}/meta-data"
  fi

  rm -rf "${TMPDIR}"
  echo "  ✅ ${OUTPUT} ($(du -sh ${OUTPUT} | cut -f1))"
}

echo "=== Generating cloud-init ISOs ==="

# Master
make_iso "k3s-master" "${CIDATA_DIR}/user-data.master.yaml"

# Worker-1
WORKER_IP="${WORKER1_IP}" WORKER_HOSTNAME="k3s-worker-1" \
  make_iso "k3s-worker-1" "${CIDATA_DIR}/user-data.worker.yaml"

# Worker-2
WORKER_IP="${WORKER2_IP}" WORKER_HOSTNAME="k3s-worker-2" \
  make_iso "k3s-worker-2" "${CIDATA_DIR}/user-data.worker.yaml"

echo ""
echo "✅ ISOs ready:"
ls -lh /tmp/cidata-*.iso

echo ""
echo "Next: run upload-cidata.sh to push ISOs to ESXi and attach to VMs"
