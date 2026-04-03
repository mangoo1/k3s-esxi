---
name: k3s-esxi
description: Install and configure a k3s Kubernetes cluster on VMware ESXi. Use when asked to set up k3s, create VMs on ESXi for Kubernetes, install k3s master/worker nodes, configure Longhorn storage, or deploy a k3s cluster from scratch on a VMware ESXi host. Requires ESXi credentials in a .env file.
---

# k3s-esxi Skill

Install a production-ready k3s cluster on VMware ESXi via SSH automation.

## Prerequisites

- ESXi host with SSH enabled
- Ubuntu 24.04 Server ISO uploaded to a datastore
- `.env` file with credentials (see `references/env-sample.md`)

## Workflow

1. Read `.env` file from the path provided by user
2. Validate connectivity: `ssh root@$ESXI_HOST vim-cmd vmsvc/getallvms`
3. Create VMs using `scripts/create-vms.sh`
4. Install Ubuntu on each VM (cloud-init via `scripts/cloud-init/`)
5. Install k3s on master: `scripts/install-k3s-master.sh`
6. Join workers: `scripts/install-k3s-worker.sh`
7. Install Longhorn storage: `scripts/install-longhorn.sh`
8. Verify cluster: `kubectl get nodes -o wide`

## VM Layout (default for N100 32G)

| VM | Role | vCPU | RAM | System Disk | Data Disk | Datastore |
|---|---|---|---|---|---|---|
| k3s-master | control plane | 2 | 3G | 80G | — | SSD |
| k3s-worker-1 | worker | 3 | 10G | 40G | 300G | SSD |
| k3s-worker-2 | worker | 3 | 10G | 40G | 300G | SSD |

Adjust via env vars: `MASTER_CPU`, `MASTER_MEM_MB`, `WORKER_CPU`, `WORKER_MEM_MB` etc.

## Network

- All VMs on same `VM Network` vSwitch
- Static IPs assigned via cloud-init
- k3s pod CIDR: `10.42.0.0/16`, service CIDR: `10.43.0.0/16`
- Flannel CNI (default)

## Storage

- Longhorn distributed storage on worker data disks
- Default replica count: 2
- StorageClass: `longhorn` (set as default)

## After Install

- kubeconfig saved to `~/.kube/config` on master
- Copy to local: `scp ubuntu@$MASTER_IP:~/.kube/config ~/.kube/k3s-config`
- Access dashboard: `kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80`

## Key Files

- `references/env-sample.md` — sample .env with all variables
- `scripts/create-vms.sh` — ESXi VM creation via SSH
- `scripts/cloud-init/` — per-VM cloud-init configs
- `scripts/install-k3s-master.sh` — master node setup
- `scripts/install-k3s-worker.sh` — worker join script
- `scripts/install-longhorn.sh` — Longhorn storage install

## Notes

- ESXi SSH must be enabled (Host → Actions → Services → Enable SSH)
- Ubuntu ISO path in env: `ESXI_DATASTORE/UBUNTU_ISO_NAME`
- Scripts use `govc` CLI where available, fallback to raw ESXi vim-cmd/esxcli
- All VMs use UEFI boot, VMXNET3 NIC, PVSCSI disk controller
