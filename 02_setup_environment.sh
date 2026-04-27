#!/bin/bash
# 02_setup_environment.sh — Clone and set up sonic-buildimage Bazel build from scratch
# Post-PR version: PRs #1, #2, #3 are merged to bazel/master on Bojun-Feng/sonic-buildimage.
# No manual patching needed — all fixes are in the repo.
set -euo pipefail

BASE_DIR="$HOME/bazel"
_SCRIPT_START=$(date +%s)

# Helper: format seconds as "Xm Ys" or "Zs"
_fmt_time() {
 local s=$1
 if [ "$s" -ge 60 ]; then
  echo "$((s/60))m $((s%60))s"
 else
  echo "${s}s"
 fi
}

# -----------------------------------------------
# Source repository (Bojun-Feng fork with all PRs merged)
# Pin to a specific commit for reproducibility.
# -----------------------------------------------
BUILDIMAGE_REPO="https://github.com/Bojun-Feng/sonic-buildimage.git"
BUILDIMAGE_BRANCH="bazel/master"
BUILDIMAGE_COMMIT="ea3849470a67a1af276f3f2807d3b202bcbd7bfa"

# -----------------------------------------------
# Checkpoint commits for sibling dependency repos
# These MUST be pinned — HEAD may drift and break compatibility.
# Source: thesayyn's repos (the Bazel migration author).
# To find updated compatible commits, run:
# python3 tools/bazel/migration_manager.py --checkpoint /path/to/sonic-buildimage
# -----------------------------------------------
SIBLING_GITHUB="https://github.com/thesayyn"
P4RUNTIME_COMMIT="d6eb7f4"
P4CONSTRAINTS_COMMIT="e774995"
P4C_COMMIT="b89ed7c6c"
GUTIL_COMMIT="149b358"

echo "============================================"
echo "[02] Setting up sonic-buildimage Bazel build"
echo "============================================"
echo "[02] sonic-buildimage: ${BUILDIMAGE_REPO} @ ${BUILDIMAGE_COMMIT}"
echo "[02] Sibling repos: thesayyn @ pinned checkpoint commits"

# -----------------------------------------------
# 0. Pre-flight checks
# -----------------------------------------------
for cmd in git python3 bazel; do
 if ! command -v "${cmd}" &>/dev/null; then
 echo "[02] ERROR: '${cmd}' not found. Run 01_install_bazel.sh first."
 exit 1
 fi
done

# -----------------------------------------------
# 1. Clean everything
# -----------------------------------------------
echo "[02] Cleaning ${BASE_DIR} (except scripts)..."
_t0=$(date +%s)

TMPDIR=$(mktemp -d)
for s in 01_install_bazel.sh 02_setup_environment.sh 03_build.sh; do
 cp "${BASE_DIR}/${s}" "${TMPDIR}/" 2>/dev/null || true
done

rm -rf "${BASE_DIR}/sonic-buildimage"
rm -rf "${BASE_DIR}/p4runtime"
rm -rf "${BASE_DIR}/p4-constraints"
rm -rf "${BASE_DIR}/p4c"
rm -rf "${BASE_DIR}/gutil"
rm -rf "${BASE_DIR}/rules_distroless" # stale artifact from original setup script

cp "${TMPDIR}"/*.sh "${BASE_DIR}/" 2>/dev/null || true
rm -rf "${TMPDIR}"

echo "[02] Cleaning Bazel caches..."
sudo rm -rf ~/.cache/bazel/
sudo rm -rf ~/.cache/bazelisk/

echo "[02] Clean step completed in $(_fmt_time $(( $(date +%s) - _t0 )))"

# -----------------------------------------------
# 2. Clone sonic-buildimage at pinned commit
# -----------------------------------------------
echo "[02] Cloning sonic-buildimage (branch: ${BUILDIMAGE_BRANCH})..."
_t0=$(date +%s)
git clone --branch "${BUILDIMAGE_BRANCH}" "${BUILDIMAGE_REPO}" "${BASE_DIR}/sonic-buildimage"

echo "[02] Checking out pinned commit ${BUILDIMAGE_COMMIT}..."
git -C "${BASE_DIR}/sonic-buildimage" checkout "${BUILDIMAGE_COMMIT}"
echo "[02] Cloned sonic-buildimage in $(_fmt_time $(( $(date +%s) - _t0 )))"

# -----------------------------------------------
# 3. Initialize all submodules
# -----------------------------------------------
echo "[02] Initializing submodules (this takes a while)..."
_t0=$(date +%s)
git -C "${BASE_DIR}/sonic-buildimage" submodule update --init --recursive
echo "[02] Submodule init completed in $(_fmt_time $(( $(date +%s) - _t0 )))"

# -----------------------------------------------
# 4. Clone external sibling repos at pinned commits
# -----------------------------------------------
# These repos are required by MODULE.bazel's local_path_override directives:
# - path = "../p4runtime/proto"
# - path = "../p4-constraints"
# - path = "../p4c"
# - path = "../gutil"
# They must be siblings of sonic-buildimage/ in the filesystem.
# -----------------------------------------------
echo "[02] Cloning external sibling repos at pinned commits..."

clone_at_commit() {
 local repo="$1"
 local commit="$2"
 local branch="$3"
 local _ct0
 _ct0=$(date +%s)
 echo "[02] ${repo} @ ${commit} (branch ${branch})"
 git clone --branch "${branch}" "${SIBLING_GITHUB}/${repo}.git" "${BASE_DIR}/${repo}"
 git -C "${BASE_DIR}/${repo}" checkout "${commit}"
 echo "[02] Cloned ${repo} in $(_fmt_time $(( $(date +%s) - _ct0 )))"
}

clone_at_commit "p4runtime" "${P4RUNTIME_COMMIT}" "main"
clone_at_commit "p4-constraints" "${P4CONSTRAINTS_COMMIT}" "master"
clone_at_commit "p4c" "${P4C_COMMIT}" "main"
clone_at_commit "gutil" "${GUTIL_COMMIT}" "main"

echo ""
echo "============================================"
echo "[02] Setup complete!"
echo "============================================"
echo ""
echo "Directory layout:"
echo " ${BASE_DIR}/"
echo " sonic-buildimage/ @ ${BUILDIMAGE_COMMIT} (Bojun-Feng fork, ${BUILDIMAGE_BRANCH})"
echo " p4runtime/ @ ${P4RUNTIME_COMMIT}"
echo " p4-constraints/ @ ${P4CONSTRAINTS_COMMIT}"
echo " p4c/ @ ${P4C_COMMIT}"
echo " gutil/ @ ${GUTIL_COMMIT}"
echo ""
echo "Next: run 03_build.sh to validate the build."
echo ""
echo "[02] Total elapsed time: $(_fmt_time $(( $(date +%s) - _SCRIPT_START )))"
