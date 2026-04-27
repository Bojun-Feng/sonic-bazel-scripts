#!/bin/bash
# 01_install_bazel.sh — Install bazelisk and build dependencies (idempotent)
# For: sonic-buildimage Bazel build on fresh Ubuntu 24.04 (x86_64)
#
# Installs bazelisk to /usr/bin/bazel — already on PATH for all users,
# no bashrc/profile.d hacks needed.
[ "$(id -u)" -ne 0 ] && exec sudo "$0" "$@"
set -euo pipefail

BAZELISK_VERSION="v1.27.0"
BAZELISK_URL="https://github.com/bazelbuild/bazelisk/releases/download/${BAZELISK_VERSION}/bazelisk-linux-amd64"
# /usr/bin is on PATH by default on every Linux distro. No PATH games.
BAZEL_BIN="/usr/bin/bazel"

# Helper: format seconds as "Xm Ys" or "Zs"
_fmt_time() {
 local s=$1
 if [ "$s" -ge 60 ]; then
  echo "$((s/60))m $((s%60))s"
 else
  echo "${s}s"
 fi
}

echo "============================================"
echo "[01] Installing Bazelisk and build deps"
echo "============================================"

# --- Install bazelisk (idempotent: skip if correct version already installed) ---
NEED_INSTALL=true
if [ -x "$BAZEL_BIN" ]; then
 EXISTING_VER=$("$BAZEL_BIN" --version 2>&1 || true)
 if echo "$EXISTING_VER" | grep -q "Bazelisk version ${BAZELISK_VERSION}"; then
 echo "[01] bazelisk ${BAZELISK_VERSION} already installed, skipping download."
 NEED_INSTALL=false
 else
 echo "[01] Different version found (${EXISTING_VER}), upgrading..."
 fi
fi

if [ "$NEED_INSTALL" = true ]; then
 echo "[01] Installing bazelisk ${BAZELISK_VERSION} -> ${BAZEL_BIN}"
 # Download to temp file, then atomic mv (can't overwrite running binary)
 _t0=$(date +%s)
 TMPFILE=$(mktemp /tmp/bazel-install.XXXXXX)
 curl -fsSL "${BAZELISK_URL}" -o "$TMPFILE"
 chmod +x "$TMPFILE"
 mv -f "$TMPFILE" "$BAZEL_BIN"
 echo "[01] Downloaded bazelisk in $(_fmt_time $(( $(date +%s) - _t0 )))"
fi

# --- Install Docker (idempotent) ---
if command -v docker &>/dev/null; then
 echo "[01] Docker already installed: $(docker --version)"
else
 echo "[01] Installing Docker..."
 _t0=$(date +%s)
 # Install prerequisites for Docker's apt repo
 apt-get update -qq
 apt-get install -y -qq ca-certificates curl gnupg
 # Add Docker's official GPG key
 install -m 0755 -d /etc/apt/keyrings
 curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
 chmod a+r /etc/apt/keyrings/docker.asc
 # Add Docker apt repository
 echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
 apt-get update -qq
 # Install Docker Engine
 apt-get install -y -qq \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin
 echo "[01] Installed Docker in $(_fmt_time $(( $(date +%s) - _t0 )))"
fi

# Ensure docker daemon is running
if ! systemctl is-active --quiet docker 2>/dev/null; then
 echo "[01] Starting Docker daemon..."
 systemctl start docker || dockerd &>/dev/null &
fi

# Add the invoking user to the docker group so they can run docker without sudo
if [ -n "${SUDO_USER:-}" ]; then
 if ! id -nG "$SUDO_USER" | grep -qw docker; then
  usermod -aG docker "$SUDO_USER"
  echo "[01] Added $SUDO_USER to docker group"
 fi
fi

# --- Install build dependencies (idempotent) ---
echo "[01] Installing build dependencies..."
_t0=$(date +%s)
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
 git \
 build-essential \
 python3 \
 python3-pip \
 python3-yaml \
 zip \
 unzip \
 xz-utils \
 patch \
 clang \
 llvm-18 \
 llvm-18-dev \
 flex \
 bison \
 libicu-dev \
 libncurses-dev \
 libpcre2-dev \
 libxml2-dev \
 openjdk-21-jdk-headless \
 aspell
echo "[01] Installed build dependencies in $(_fmt_time $(( $(date +%s) - _t0 )))"

# --- Verify everything works ---
echo ""
echo "============================================"
echo "[01] Verification"
echo "============================================"

if [ ! -x "$BAZEL_BIN" ]; then
 echo "[01] FATAL: ${BAZEL_BIN} not found or not executable!"
 exit 1
fi

BAZEL_VER=$(bazel --version 2>&1) || {
 echo "[01] FATAL: 'bazel --version' failed!"
 exit 1
}

echo "[01] ✅ bazel binary: $(which bazel)"
echo "[01] ✅ bazel version: ${BAZEL_VER}"
echo "[01] ✅ Build dependencies installed"

DOCKER_VER=$(docker --version 2>&1) || {
 echo "[01] FATAL: 'docker --version' failed!"
 exit 1
}
echo "[01] ✅ docker: ${DOCKER_VER}"

# Re-exec a fresh login shell for the invoking user so the docker group takes effect
if [ -n "${SUDO_USER:-}" ]; then
 echo ""
 echo "[01] Spawning a new shell for $SUDO_USER with docker group active..."
 exec su - "$SUDO_USER"
fi
