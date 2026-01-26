#!/usr/bin/env bash
set -euo pipefail

# ====== CONFIG ======
VM_NAME="${1:-bootstap}"
PRIVKEY="${2:-$HOME/.ssh/urissh}"
SEED_OUT="${3:-/var/lib/libvirt/images/${VM_NAME}-seed.iso}"

# ====== PRECHECK ======
if [[ ! -f "$PRIVKEY" ]]; then
  echo "ERROR: Private key not found: $PRIVKEY" >&2
  exit 1
fi

# ssh sẽ từ chối nếu key permission quá mở
chmod 700 "$HOME/.ssh" || true
chmod 600 "$PRIVKEY"

# ====== DEPENDENCIES ======
sudo apt-get update -y
sudo apt-get install -y cloud-image-utils

# ====== BUILD PUBKEY ======
PUBKEY_FILE="${PRIVKEY}.pub"
ssh-keygen -y -f "$PRIVKEY" > "$PUBKEY_FILE"
PUBKEY="$(cat "$PUBKEY_FILE")"

# ====== WRITE CLOUD-INIT FILES ======
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

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

cat > "${WORKDIR}/meta-data" <<EOF
instance-id: ${VM_NAME}-$(date +%s)
local-hostname: ${VM_NAME}
EOF

# network-config KHÔNG rename NIC, KHÔNG gán static (để tránh map nhầm khi nhiều NIC)
# Mục tiêu: bảo đảm có DHCP để SSH vào (khuyến nghị VM boot lần đầu chỉ có 1 NIC br-lan)
cat > "${WORKDIR}/network-config" <<'EOF'
version: 2
ethernets:
  default:
    dhcp4: true
EOF

# ====== BUILD ISO ======
sudo mkdir -p "$(dirname "$SEED_OUT")"
sudo cloud-localds -v --network-config="${WORKDIR}/network-config" \
  "$SEED_OUT" "${WORKDIR}/user-data" "${WORKDIR}/meta-data"

sudo chown libvirt-qemu:kvm "$SEED_OUT"
sudo chmod 0640 "$SEED_OUT"

echo "OK: Seed ISO created: $SEED_OUT"
echo "Tip: Use virsh domifaddr --source agent after boot (qemu-guest-agent installed)."
