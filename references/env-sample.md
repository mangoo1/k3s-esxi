# k3s-esxi .env Sample

Copy this file, fill in your values, and pass the path to Dan.

```env
# ── ESXi Host ─────────────────────────────────────────────────────────────────
ESXI_HOST=192.168.1.10          # ESXi host IP or hostname
ESXI_USER=root                  # ESXi SSH user (usually root)
ESXI_PASS=your-esxi-password    # ESXi root password

# ── Datastores ────────────────────────────────────────────────────────────────
ESXI_DATASTORE_SSD=datastore1   # Datastore name for master (SSD preferred)
ESXI_DATASTORE_HDD=datastore2   # Datastore name for workers (HDD/large)

# ── Ubuntu ISO ────────────────────────────────────────────────────────────────
UBUNTU_ISO_DATASTORE=datastore1          # Which datastore has the ISO
UBUNTU_ISO_NAME=ubuntu-24.04-live-server-amd64.iso

# ── Network ───────────────────────────────────────────────────────────────────
VM_NETWORK=VM Network           # ESXi vSwitch port group name
GATEWAY=192.168.1.1             # Your router/gateway IP
DNS=1.1.1.1                     # DNS server

# ── VM IPs (static) ───────────────────────────────────────────────────────────
MASTER_IP=192.168.1.101
WORKER1_IP=192.168.1.102
WORKER2_IP=192.168.1.103
SUBNET_PREFIX=24                # e.g. 24 for /24 (255.255.255.0)

# ── VM Sizing (optional, defaults match N100 32G layout) ─────────────────────
MASTER_CPU=2
MASTER_MEM_MB=4096
MASTER_DISK_GB=32

WORKER_CPU=3
WORKER_MEM_MB=12288
WORKER_DISK_GB=40
WORKER_DATA_DISK_GB=200

# ── VM Credentials (for SSH into VMs after install) ───────────────────────────
VM_USER=ubuntu
VM_SSH_KEY_PUB=~/.ssh/id_rsa.pub   # Public key to inject into VMs

# ── k3s ───────────────────────────────────────────────────────────────────────
K3S_VERSION=v1.32.3+k3s1        # Leave blank for latest stable

# ── Longhorn ──────────────────────────────────────────────────────────────────
LONGHORN_VERSION=1.7.2           # Leave blank for latest stable
LONGHORN_REPLICA_COUNT=2
```

## ESXi SSH 开启方法

ESXi Web UI → Host → Actions → Services → Enable SSH
