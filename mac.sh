#!/usr/bin/env bash
set -euo pipefail
NODE_ID="${1:?node_id required (1..254)}"

NODE_HEX="$(printf '%02x' "$NODE_ID")"
LAN="52:54:00:0b:${NODE_HEX}:01"
MGMT="52:54:00:0b:${NODE_HEX}:02"
API="52:54:00:0b:${NODE_HEX}:03"
TUN="52:54:00:0b:${NODE_HEX}:04"
STOR="52:54:00:0b:${NODE_HEX}:05"
EXT="52:54:00:0b:${NODE_HEX}:06"

echo "LAN=$LAN"
echo "MGMT=$MGMT"
echo "API=$API"
echo "TUN=$TUN"
echo "STOR=$STOR"
echo "EXT=$EXT"
