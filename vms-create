#!/usr/bin/env bash
set -euo pipefail

# ====== RESOLVE REAL HOME ======
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

# ====== ARG PARSE (support BOTH call styles) ======
# Style A (your original): make-seed.sh <vm> <node_id> <pubkey> <seed_out>
# Style B (your current):  make-seed.sh <vm> <pubkey> <seed_out> <node_id>
VM_NAME="${1:-bootstrap}"

if [[ "${2:-}" =~ ^[0-9]+$ ]] && [[ -n "${3:-}" ]] && [[ -f "${3:-/dev/null}" ]]; then
  # Style A
  NODE_ID="$2"
  PUBKEY_FILE="$3"
  SEED_OUT="${4:-/var/lib/libvirt/images/${VM_NAME}-seed.iso}"
else
  # Style B
  PUBKEY_FILE="${2:-$REAL_HOME/.ssh/urissh.pub}"
  SEED_OUT="${3:-/var/lib/libvirt/images/${VM_NAME}-seed.iso}"
  NODE_ID="${4:-11}"
fi

# ====== PRECHECK ======
if ! [[ "$NODE_ID" =~ ^[0-9]+$ ]] || (( NODE_ID < 1 || NODE_ID > 254 )); then
  echo "ERROR: NODE_ID must be 1..254 (got: $NODE_ID)" >&2
  exit 1
fi

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

# ====== DEPENDENCIES (on host) ======
sudo apt-get update -y
sudo apt-get install -y cloud-image-utils

# ====== DERIVE UNIQUE MACs FROM NODE_ID ======
NODE_HEX="$(printf '%02x' "$NODE_ID")"
LAN_MAC="52:54:00:0b:${NODE_HEX}:01"
MGMT_MAC="52:54:00:0b:${NODE_HEX}:02"
API_MAC="52:54:00:0b:${NODE_HEX}:03"
TUN_MAC="52:54:00:0b:${NODE_HEX}:04"
STOR_MAC="52:54:00:0b:${NODE_HEX}:05"
EXT_MAC="52:54:00:0b:${NODE_HEX}:06"

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

# ====== NETWORK-CONFIG (match by MAC => never lech) ======
cat > "${WORKDIR}/network-config" <<EOF
version: 2
ethernets:
  lan0:
    match: {macaddress: "${LAN_MAC}"}
    set-name: lan0
    dhcp4: true
    optional: true

  mgmt0:
    match: {macaddress: "${MGMT_MAC}"}
    set-name: mgmt0
    dhcp4: false
    addresses: [10.10.10.${NODE_ID}/24]
    optional: true

  api0:
    match: {macaddress: "${API_MAC}"}
    set-name: api0
    dhcp4: false
    addresses: [10.10.20.${NODE_ID}/24]
    optional: true

  tun0:
    match: {macaddress: "${TUN_MAC}"}
    set-name: tun0
    dhcp4: false
    addresses: [10.10.30.${NODE_ID}/24]
    optional: true

  stor0:
    match: {macaddress: "${STOR_MAC}"}
    set-name: stor0
    dhcp4: false
    addresses: [10.10.50.${NODE_ID}/24]
    optional: true

  ext0:
    match: {macaddress: "${EXT_MAC}"}
    set-name: ext0
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
echo "MACs:"
echo "  LAN : $LAN_MAC"
echo "  MGMT: $MGMT_MAC"
echo "  API : $API_MAC"
echo "  TUN : $TUN_MAC"
echo "  STOR: $STOR_MAC"
echo "  EXT : $EXT_MAC"
