#!/usr/bin/env bash
# upload-cidata.sh — Upload cloud-init ISOs to ESXi and attach to VMs
# Usage: source .env && bash scripts/upload-cidata.sh
set -euo pipefail

: "${ESXI_HOST:?}" "${ESXI_USER:?}" "${ESXI_PASS:?}"
: "${ESXI_DATASTORE_SSD:?}" "${ESXI_DATASTORE_HDD:?}"

# ── Python helper for SSH (no sshpass needed) ─────────────────────────────────
ssh_cmd() {
  python3 - "$@" << 'PYEOF'
import paramiko, sys, time

HOST = sys.argv[1]
USER = sys.argv[2]
PASS = sys.argv[3]
CMD  = " ".join(sys.argv[4:])

transport = paramiko.Transport((HOST, 22))
transport.connect()
def handler(title, instructions, prompts):
    return [PASS for _ in prompts]
transport.auth_interactive(USER, handler)

chan = transport.open_session()
chan.exec_command(CMD)
out = ""
while True:
    if chan.recv_ready(): out += chan.recv(65535).decode()
    if chan.exit_status_ready(): break
    time.sleep(0.3)
while chan.recv_ready(): out += chan.recv(65535).decode()
transport.close()
print(out.strip())
PYEOF
}

scp_to_esxi() {
  local LOCAL=$1
  local REMOTE=$2
  python3 << PYEOF
import paramiko
HOST = "${ESXI_HOST}"
USER = "${ESXI_USER}"
PASS = "${ESXI_PASS}"

transport = paramiko.Transport((HOST, 22))
transport.connect()
def handler(title, instructions, prompts):
    return [PASS for _ in prompts]
transport.auth_interactive(USER, handler)

sftp = paramiko.SFTPClient.from_transport(transport)
print(f"  Uploading ${LOCAL} -> {REMOTE}...")
sftp.put("${LOCAL}", "${REMOTE}")
sftp.close()
transport.close()
print("  Done.")
PYEOF
}

echo "=== Uploading cloud-init ISOs to ESXi ==="

# Upload ISOs to datastores
echo "→ Uploading k3s-master cidata ISO..."
python3 -c "
import paramiko
transport = paramiko.Transport(('${ESXI_HOST}', 22))
transport.connect()
transport.auth_interactive('${ESXI_USER}', lambda t,i,p: ['${ESXI_PASS}' for _ in p])
sftp = paramiko.SFTPClient.from_transport(transport)
sftp.put('/tmp/cidata-k3s-master.iso', '/vmfs/volumes/${ESXI_DATASTORE_SSD}/k3s-master/cidata.iso')
sftp.close(); transport.close()
print('  ✅ master ISO uploaded')
"

echo "→ Uploading k3s-worker-1 cidata ISO..."
python3 -c "
import paramiko
transport = paramiko.Transport(('${ESXI_HOST}', 22))
transport.connect()
transport.auth_interactive('${ESXI_USER}', lambda t,i,p: ['${ESXI_PASS}' for _ in p])
sftp = paramiko.SFTPClient.from_transport(transport)
sftp.put('/tmp/cidata-k3s-worker-1.iso', '/vmfs/volumes/${ESXI_DATASTORE_HDD}/k3s-worker-1/cidata.iso')
sftp.close(); transport.close()
print('  ✅ worker-1 ISO uploaded')
"

echo "→ Uploading k3s-worker-2 cidata ISO..."
python3 -c "
import paramiko
transport = paramiko.Transport(('${ESXI_HOST}', 22))
transport.connect()
transport.auth_interactive('${ESXI_USER}', lambda t,i,p: ['${ESXI_PASS}' for _ in p])
sftp = paramiko.SFTPClient.from_transport(transport)
sftp.put('/tmp/cidata-k3s-worker-2.iso', '/vmfs/volumes/${ESXI_DATASTORE_HDD}/k3s-worker-2/cidata.iso')
sftp.close(); transport.close()
print('  ✅ worker-2 ISO uploaded')
"

echo ""
echo "=== Attaching cidata ISOs to VMs ==="

# Attach as sata0:2 (second CD-ROM)
for VM_NAME in k3s-master k3s-worker-1 k3s-worker-2; do
  if [[ "$VM_NAME" == "k3s-master" ]]; then
    DS="${ESXI_DATASTORE_SSD}"
  else
    DS="${ESXI_DATASTORE_HDD}"
  fi
  python3 -c "
import paramiko, time
transport = paramiko.Transport(('${ESXI_HOST}', 22))
transport.connect()
transport.auth_interactive('${ESXI_USER}', lambda t,i,p: ['${ESXI_PASS}' for _ in p])

def run(cmd):
    chan = transport.open_session()
    chan.exec_command(cmd)
    out = ''
    while True:
        if chan.recv_ready(): out += chan.recv(65535).decode()
        if chan.exit_status_ready(): break
        time.sleep(0.2)
    return out.strip()

# Add cidata ISO as sata0:2
vmx_path = '/vmfs/volumes/${DS}/${VM_NAME}/${VM_NAME}.vmx'
cidata_path = '[${DS}] ${VM_NAME}/cidata.iso'
lines = run(f'cat {vmx_path}').splitlines()

# Remove any existing sata0:2 entries
lines = [l for l in lines if not l.startswith('sata0:2')]

# Add cidata entries
lines += [
    'sata0:2.present = \"TRUE\"',
    'sata0:2.deviceType = \"cdrom-image\"',
    f'sata0:2.fileName = \"{cidata_path}\"',
    'sata0:2.startConnected = \"TRUE\"',
]

new_vmx = '\n'.join(lines) + '\n'
run(f'cat > {vmx_path} << ENDVMX\n{new_vmx}\nENDVMX')
print(f'  ✅ ${VM_NAME} cidata ISO attached')
transport.close()
"
done

echo ""
echo "=== Powering on VMs ==="
python3 -c "
import paramiko, time
transport = paramiko.Transport(('${ESXI_HOST}', 22))
transport.connect()
transport.auth_interactive('${ESXI_USER}', lambda t,i,p: ['${ESXI_PASS}' for _ in p])

def run(cmd):
    chan = transport.open_session()
    chan.exec_command(cmd)
    out = ''
    while True:
        if chan.recv_ready(): out += chan.recv(65535).decode()
        if chan.exit_status_ready(): break
        time.sleep(0.2)
    return out.strip()

for vmid in ['1', '2', '3']:
    r = run(f'vim-cmd vmsvc/power.on {vmid}')
    print(f'  Powered on VMID {vmid}: {r[:50] if r else \"OK\"}')

transport.close()
"

echo ""
echo "✅ VMs powered on! Ubuntu autoinstall is running."
echo ""
echo "Monitor progress in ESXi Web UI → Virtual Machines → Console"
echo "Installation takes ~5-10 minutes per VM."
echo ""
echo "After all 3 VMs complete, run:"
echo "  source .env && bash scripts/install-k3s-master.sh"
