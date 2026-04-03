#!/usr/bin/env bash
# create-vms.sh — Create k3s VMs on ESXi via SSH
# Usage: source .env && bash create-vms.sh
set -euo pipefail

: "${ESXI_HOST:?}" "${ESXI_USER:?}" "${ESXI_PASS:?}"
: "${ESXI_DATASTORE_SSD:?}" "${ESXI_DATASTORE_HDD:?}"
: "${UBUNTU_ISO_DATASTORE:?}" "${UBUNTU_ISO_NAME:?}"

MASTER_CPU=${MASTER_CPU:-2}
MASTER_MEM_MB=${MASTER_MEM_MB:-4096}
MASTER_DISK_GB=${MASTER_DISK_GB:-32}
WORKER_CPU=${WORKER_CPU:-3}
WORKER_MEM_MB=${WORKER_MEM_MB:-12288}
WORKER_DISK_GB=${WORKER_DISK_GB:-40}
WORKER_DATA_DISK_GB=${WORKER_DATA_DISK_GB:-200}
VM_NETWORK=${VM_NETWORK:-"VM Network"}

SSH="sshpass -p ${ESXI_PASS} ssh -o StrictHostKeyChecking=no ${ESXI_USER}@${ESXI_HOST}"

ISO_PATH="[${UBUNTU_ISO_DATASTORE}] ${UBUNTU_ISO_NAME}"

create_vm() {
  local NAME=$1 DS=$2 CPU=$3 MEM=$4 DISK=$5
  echo "→ Creating VM: $NAME on [$DS]"

  $SSH "mkdir -p /vmfs/volumes/${DS}/${NAME}"

  # Create VMX
  $SSH "cat > /vmfs/volumes/${DS}/${NAME}/${NAME}.vmx" <<VMX
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "19"
vmci0.present = "TRUE"
displayName = "${NAME}"
floppy0.present = "FALSE"
numvcpus = "${CPU}"
cpuid.coresPerSocket = "${CPU}"
memSize = "${MEM}"
guestOS = "ubuntu-64"
firmware = "efi"
sata0.present = "TRUE"
sata0:1.present = "TRUE"
sata0:1.deviceType = "cdrom-image"
sata0:1.fileName = "${ISO_PATH}"
sata0:1.startConnected = "TRUE"
ethernet0.present = "TRUE"
ethernet0.virtualDev = "vmxnet3"
ethernet0.networkName = "${VM_NETWORK}"
ethernet0.addressType = "generated"
scsi0.present = "TRUE"
scsi0.virtualDev = "pvscsi"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "${NAME}.vmdk"
scsi0:0.deviceType = "scsi-hardDisk"
tools.syncTime = "TRUE"
VMX

  # Create main disk
  $SSH "vmkfstools -c ${DISK}G -d thin /vmfs/volumes/${DS}/${NAME}/${NAME}.vmdk"

  # Register VM
  local VMID
  VMID=$($SSH "vim-cmd solo/registervm /vmfs/volumes/${DS}/${NAME}/${NAME}.vmx")
  echo "  Registered VMID: $VMID"
  echo "$NAME=$VMID" >> /tmp/k3s-vmids.txt
}

add_data_disk() {
  local NAME=$1 DS=$2 SIZE=$3
  echo "→ Adding data disk to $NAME (${SIZE}G)"
  $SSH "vmkfstools -c ${SIZE}G -d thin /vmfs/volumes/${DS}/${NAME}/${NAME}-data.vmdk"
  # Find VMID
  local VMID
  VMID=$($SSH "vim-cmd vmsvc/getallvms 2>/dev/null | grep ' ${NAME} ' | awk '{print \$1}'")
  $SSH "vim-cmd vmsvc/device.diskaddexisting $VMID /vmfs/volumes/${DS}/${NAME}/${NAME}-data.vmdk 0 1"
}

echo "=== Creating k3s VMs on ESXi ${ESXI_HOST} ==="
rm -f /tmp/k3s-vmids.txt

create_vm "k3s-master"   "$ESXI_DATASTORE_SSD" "$MASTER_CPU" "$MASTER_MEM_MB" "$MASTER_DISK_GB"
create_vm "k3s-worker-1" "$ESXI_DATASTORE_HDD" "$WORKER_CPU" "$WORKER_MEM_MB" "$WORKER_DISK_GB"
create_vm "k3s-worker-2" "$ESXI_DATASTORE_HDD" "$WORKER_CPU" "$WORKER_MEM_MB" "$WORKER_DISK_GB"

add_data_disk "k3s-worker-1" "$ESXI_DATASTORE_HDD" "$WORKER_DATA_DISK_GB"
add_data_disk "k3s-worker-2" "$ESXI_DATASTORE_HDD" "$WORKER_DATA_DISK_GB"

echo ""
echo "✅ VMs created. VM IDs saved to /tmp/k3s-vmids.txt"
echo "Next: boot VMs and install Ubuntu, then run install-k3s-master.sh"
echo ""
echo "To power on all VMs:"
cat /tmp/k3s-vmids.txt | while IFS='=' read NAME VMID; do
  echo "  sshpass -p ${ESXI_PASS} ssh ${ESXI_USER}@${ESXI_HOST} vim-cmd vmsvc/power.on $VMID"
done
