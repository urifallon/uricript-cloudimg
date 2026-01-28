#!/usr/bin/env bash
set -euo pipefail

# ====== RESOLVE REAL HOME (robust even if user runs with sudo) ======
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

# ====== CONFIG ======
VM_NAME="${1:-bootstap}"
PUBKEY_FILE="${2:-$REAL_HOME/.ssh/urissh.pub}"
SEED_OUT="${3:-/var/lib/libvirt/images/${VM_NAME}-seed.iso}"
NODE_ID="${4:-11}"  # last octet for mgmt/api/tun/stor/ext

# ====== PRECHECK ======
if [[ ! -f "$PUBKEY_FILE" ]]; then
  echo "ERROR: Public key not found: $PUBKEY_FILE" >&2
  echo "Create it once with:" >&2
  echo "  ssh-keygen -y -f $REAL_HOME/.ssh/urissh > $REAL_HOME/.ssh/urissh.pub" >&2
  exit 1
fi

PUBKEY="$(tr -d '\n' < "$PUBKEY_FILE")"
if [[ -z "$PUBKEY" ]]; then
  echo "ERROR: Public key file is empty: $PUBKEY_FILE" >&2
  exit 1
fi

# ====== DEPENDENCIES ======
sudo apt-get update -y
sudo apt-get install -y cloud-image-utils

# ====== WORKDIR ======
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# ====== USER-DATA ======
cat > "${WORKDIR}/user-data" <<EOF
#cloud-config
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    ssh_authorized_keys:
      - ${PUBKEY}

ssh_pwauth: false
disable_root: true

packages:
  - openssh-server
  - qemu-guest-agent

runcmd:
  - systemctl enable --now ssh
  - systemctl enable --now qemu-guest-agent
EOF

# ====== META-DATA ======
cat > "${WORKDIR}/meta-data" <<EOF
instance-id: ${VM_NAME}-$(date +%s)
local-hostname: ${VM_NAME}
EOF

# ====== NETWORK-CONFIG (NO MAC) ======
# Assumption: NIC order in guest is stable:
# ens3=LAN(DHCP), ens4=MGMT, ens5=API, ens6=TUN, ens7=STOR, ens8=EXT
cat > "${WORKDIR}/network-config" <<EOF
version: 2
ethernets:
  ens3:
    dhcp4: true
    optional: true

  ens4:
    dhcp4: false
    addresses: [10.10.10.${NODE_ID}/24]
    optional: true

  ens5:
    dhcp4: false
    addresses: [10.10.20.${NODE_ID}/24]
    optional: true

  ens6:
    dhcp4: false
    addresses: [10.10.30.${NODE_ID}/24]
    optional: true

  ens7:
    dhcp4: false
    addresses: [10.10.50.${NODE_ID}/24]
    optional: true

  ens8:
    dhcp4: false
    addresses: [172.16.40.${NODE_ID}/24]
    optional: true
EOF

# ====== BUILD ISO ======
sudo mkdir -p "$(dirname "$SEED_OUT")"
sudo cloud-localds -v --network-config="${WORKDIR}/network-config" \
  "$SEED_OUT" "${WORKDIR}/user-data" "${WORKDIR}/meta-data"

sudo chown libvirt-qemu:kvm "$SEED_OUT"
sudo chmod 0640 "$SEED_OUT"

echo "OK: Seed ISO created: $SEED_OUT"
echo "NOTE: This assumes ens3..ens8 mapping follows NIC attach order."



