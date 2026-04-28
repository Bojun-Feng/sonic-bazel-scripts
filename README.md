# sonic-bazel-scripts

Reproducible setup and build validation scripts for the SONiC Bazel migration. These scripts set up a clean environment from scratch, clone all required repositories at pinned commits, and run the full Bazel build validation suite.

Designed to be run inside a [Lima](https://lima-vm.io/) VM for isolation and reproducibility.

## Quick Start

```bash
# 1. Create a fresh Lima VM
./lima-refresh.sh sonic-bazel

# 2. Shell into the VM
limactl shell sonic-bazel

# 3. Port scripts over and chmod +x

# 4 Run scripts in order
./bash 01_install_bazel.sh >> log1.txt
# ⚠️ This script spawns a new shell at the end (for Docker group).
# You CANNOT chain it with other commands.
# E.g. `bash 01_install_bazel.sh && bash 02_setup_environment.sh` would not work

./02_setup_environment.sh >> log2.txt
./03_build.sh >> log3.txt
```

## Scripts

| Script | What it does | Approx time |
|---|---|---|
| `lima-refresh.sh <vm-name>` | Tears down and recreates a Lima VM (Ubuntu 24.04, x86_64, 4 CPU / 16 GiB RAM / 250 GiB disk) | ~2-5 min |
| `01_install_bazel.sh` | Installs Bazelisk v1.27.0, Docker, and all build dependencies (idempotent). **Spawns a new shell at the end** for Docker group — cannot be chained with subsequent scripts. | ~2-15 min |
| `02_setup_environment.sh` | Clones `sonic-buildimage` (Bojun-Feng fork, `bazel/master` branch) and all sibling dependency repos at pinned checkpoint commits. Initializes submodules. | ~2-15 min |
| `03_build.sh` | Runs the full Bazel build validation: local tests → all dependent repos → Docker image builds. Continues past failures and produces a summary. | ~3-8 h |

## Repository Layout After Setup

```
~/bazel/
├── sonic-buildimage/
├── p4runtime/
├── p4-constraints/
├── p4c/
├── gutil/
└── logs/
```

The sibling repos (`p4runtime`, `p4-constraints`, `p4c`, `gutil`) are required by `MODULE.bazel`'s `local_path_override` directives and must be siblings of `sonic-buildimage/` in the filesystem.

## Build Validation Results (April 21, 2026)

### Test Hardware
| Spec | Value |
|---|---|
| Machine | System76 Meerkat |
| CPU | Intel Core Ultra 5 225H (14 cores) |
| RAM | 96 GB DDR5 |
| Storage | 2 TB NVMe (Crucial P510) |
| OS | Ubuntu 24.04.3 LTS |

## Lima VM Specs

| Setting | Value |
|---|---|
| VM type | QEMU |
| Architecture | x86_64 |
| Base image | Ubuntu 24.04 Server (cloud image) |
| CPUs | 4 |
| Memory | 16 GiB |
| Disk | 250 GiB |

**22 passed / 5 failed** — total time ~160 minutes on a single x86_64 machine.

### ✅ Passed (22)

**Dependent repos (all build successfully):**
- sonic-build-infra, sonic-sairedis (SAI + main), sonic-dash-api, sonic-swss-common, sonic-swss, sonic-p4rt (sonic-pins), sonic-mgmt-common, sonic-gnmi

**Docker images (all build and load successfully):**
- docker-base-bookworm, docker-config-engine-bookworm, docker-database, docker-orchagent, docker-platform-monitor, docker-sflow, docker-sonic-gnmi, docker-swss-layer-bookworm, docker-sysmgr, docker-teamd, docker-syncd-brcm, docker-syncd-vs

### ❌ Failed (5)

| Target | Issue |
|---|---|
| Local tests (libyang pkg tests) | 4 libyang `rules_distroless` package assertion tests fail |
| sonic-utilities (build) | Build failure |
| sonic-utilities (test) | Test failure (depends on build) |
| sonic-host-services (build) | Build failure |
| sonic-host-services (test) | Test failure (depends on build) |

These failures are **pre-existing in the upstream fork** — they are not introduced by the patches in this repo.

## Logs

- `logs/log1.txt` — Full output from `01_install_bazel.sh`
- `logs/log2.txt` — Full output from `02_setup_environment.sh`
- `logs/log3.txt` — Full output from `03_build.sh`
- `logs/build_logs/` — Individual per-step build logs with timestamps

## `03_build.sh` Usage

```bash
# Run everything (default)
bash 03_build.sh

# Run only specific repos
bash 03_build.sh sonic-swss sonic-gnmi

# Run only Docker image builds
bash 03_build.sh --docker

# Run only local tests
bash 03_build.sh --local-tests
```

## Notes

- The `01_install_bazel.sh` script adds the current user to the `docker` group and spawns a new login shell at the end.
- All commits are pinned for reproducibility. To update to newer checkpoints, edit the commit variables in `02_setup_environment.sh`.
