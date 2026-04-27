#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
# lima-refresh.sh — Tear down and recreate a Lima VM with Ubuntu 24.04
#
# Usage:
#   ./lima-refresh.sh <vm-name>
#
# If a VM with that name already exists, it is force-stopped and
# deleted without confirmation, then a fresh Ubuntu 24.04 VM is
# created and started.
#
# VM config mirrors sonic-local-pipeline/vm-sonic-build.yaml but with
# Ubuntu 24.04 and no provisioning scripts.
# ──────────────────────────────────────────────────────────────────────
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <vm-name>"
  exit 1
fi

VM_NAME="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
YAML_FILE="${SCRIPT_DIR}/.lima-refresh-vm.yaml"

info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }

# ── Generate VM config (aligned with vm-sonic-build.yaml) ────────────
cat > "$YAML_FILE" <<'EOF'
vmType: "qemu"
arch: "x86_64"

images:
  - location: "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
    arch: "x86_64"

cpus: 4
memory: "16GiB"
disk: "250GiB"

ssh:
  localPort: 40853
  forwardAgent: true
  loadDotSSHPubKeys: true

containerd:
  system: false
  user: false

mounts:
  - location: "~"
    writable: false
EOF

# ── Tear down existing VM (force, no confirmation) ───────────────────
if limactl list -q 2>/dev/null | grep -qx "$VM_NAME"; then
  info "Stopping '${VM_NAME}'..."
  limactl stop "$VM_NAME" --force 2>/dev/null || true
  info "Deleting '${VM_NAME}'..."
  limactl delete "$VM_NAME" --force 2>/dev/null || true
  ok "Old VM removed."
else
  info "No existing VM named '${VM_NAME}'."
fi

# ── Create and start fresh Ubuntu 24.04 VM ──────────────────────────
info "Creating '${VM_NAME}' with Ubuntu 24.04..."
limactl create \
  --name="$VM_NAME" \
  --tty=false \
  "$YAML_FILE"

info "Starting '${VM_NAME}'..."
limactl start "$VM_NAME" --tty=false

ok "VM '${VM_NAME}' is ready. Connect with: limactl shell ${VM_NAME}"
