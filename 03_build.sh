#!/bin/bash
# 03_build.sh — Run the sonic-buildimage Bazel build validation
# Mirrors tools/bazel/test_working_targets.sh but continues past failures.
set -uo pipefail

SONIC_DIR="$HOME/bazel/sonic-buildimage"
LOG_DIR="$HOME/bazel/logs"
FAILURES=()
SUCCESSES=()
LOG_FILES=()
_STEP_TIMES=()
_SCRIPT_START=$(date +%s)

mkdir -p "${LOG_DIR}"

# --- Argument parsing ---
# With no arguments, run everything. Otherwise run only the specified targets.
# Repo arguments match directory basenames (e.g. sonic-swss, sonic-sairedis).
# Flags: --local-tests, --docker, --help

RUN_LOCAL_TESTS=false
RUN_DOCKER=false
RUN_ALL=true
RUN_REPOS=""

usage() {
  cat <<EOF
Usage: $0 [OPTIONS] [REPO ...]

With no arguments, run all build validation steps.

Options:
  --local-tests   Run only the local tests step
  --docker        Run only the docker images step
  --help          Show this help message

Repos (specify one or more):
  sonic-build-infra   sonic-utilities   sonic-host-services
  sonic-sairedis      sonic-dash-api    sonic-swss-common
  sonic-swss          sonic-p4rt        sonic-mgmt-common
  sonic-gnmi

Examples:
  $0                              # run everything
  $0 sonic-swss sonic-utilities   # build only those repos
  $0 --local-tests                # run only local tests
  $0 --docker sonic-swss          # run docker step and sonic-swss repo
EOF
  exit 0
}

for arg in "$@"; do
  case "${arg}" in
    --help) usage ;;
    --local-tests) RUN_LOCAL_TESTS=true; RUN_ALL=false ;;
    --docker)      RUN_DOCKER=true;      RUN_ALL=false ;;
    -*)            echo "Unknown option: ${arg}"; exit 1 ;;
    *)             RUN_REPOS="${RUN_REPOS} ${arg} "; RUN_ALL=false ;;
  esac
done

# Helper: should we run this repo?
should_run_repo() {
  ${RUN_ALL} && return 0
  case "${RUN_REPOS}" in *" $1 "*) return 0 ;; esac
  return 1
}

should_run_local_tests() { ${RUN_ALL} || ${RUN_LOCAL_TESTS}; }
should_run_docker()      { ${RUN_ALL} || ${RUN_DOCKER}; }

# --- End argument parsing ---

# Helper: format seconds as "Xm Ys" or "Zs"
_fmt_time() {
 local s=$1
 if [ "$s" -ge 60 ]; then
  echo "$((s/60))m $((s%60))s"
 else
  echo "${s}s"
 fi
}

# Sanitize a description into a filename-safe component name
sanitize() {
 echo "$1" | sed 's|[/ :]|_|g; s|__*|_|g; s|^_||; s|_$||' | tr '[:upper:]' '[:lower:]'
}

run_step() {
 local desc="$1"
 shift
 local ts
 ts=$(date +%Y%m%d_%H%M%S)
 local comp
 comp=$(sanitize "${desc}")
 local logfile="${LOG_DIR}/bazel_${ts}_${comp}.log"
 local _st0
 _st0=$(date +%s)

 echo ""
 echo "[build] ${desc}"
 echo "[build] log → ${logfile}"

 {
 echo "========================================"
 echo "Step: ${desc}"
 echo "Started: $(date)"
 echo "Command: $*"
 echo "========================================"
 echo ""
 "$@" 2>&1
 local rc=$?
 echo ""
 echo "========================================"
 if [ ${rc} -eq 0 ]; then
 echo "RESULT: SUCCESS"
 else
 echo "RESULT: FAILURE (exit code ${rc})"
 fi
 echo "Finished: $(date)"
 echo "========================================"
 return ${rc}
 } 2>&1 | tee "${logfile}"

 # Recover the exit code from the subshell (PIPESTATUS[0] captures the left side of the pipe)
 local rc=${PIPESTATUS[0]}
 local _elapsed=$(( $(date +%s) - _st0 ))

 LOG_FILES+=("${logfile}")
 _STEP_TIMES+=("${desc}: $(_fmt_time ${_elapsed})")
 if [ ${rc} -eq 0 ]; then
 echo "[build] OK: ${desc} in $(_fmt_time ${_elapsed})"
 SUCCESSES+=("${desc}")
 else
 echo "[build] FAILED: ${desc} in $(_fmt_time ${_elapsed})"
 FAILURES+=("${desc}")
 fi
}

test_repo() {
 local repo="$1"
 shift
 local desc="${repo}: $*"

 local ts
 ts=$(date +%Y%m%d_%H%M%S)
 local comp
 comp=$(sanitize "${desc}")
 local logfile="${LOG_DIR}/bazel_${ts}_${comp}.log"
 local _st0
 _st0=$(date +%s)

 echo ""
 echo "[build] ${desc}"
 echo "[build] log → ${logfile}"

 pushd "${SONIC_DIR}/${repo}" > /dev/null

 {
 echo "========================================"
 echo "Step: ${desc}"
 echo "Repo: ${repo}"
 echo "Started: $(date)"
 echo "Command: $*"
 echo "========================================"
 echo ""
 "$@" 2>&1
 local rc=$?
 echo ""
 echo "========================================"
 if [ ${rc} -eq 0 ]; then
 echo "RESULT: SUCCESS"
 else
 echo "RESULT: FAILURE (exit code ${rc})"
 fi
 echo "Finished: $(date)"
 echo "========================================"
 return ${rc}
 } 2>&1 | tee "${logfile}"

 local rc=${PIPESTATUS[0]}
 local _elapsed=$(( $(date +%s) - _st0 ))

 # Shut down this workspace's Bazel server to free memory
 bazel shutdown 2>/dev/null || true
 popd > /dev/null

 LOG_FILES+=("${logfile}")
 _STEP_TIMES+=("${desc}: $(_fmt_time ${_elapsed})")
 if [ ${rc} -eq 0 ]; then
 echo "[build] OK: ${desc} in $(_fmt_time ${_elapsed})"
 SUCCESSES+=("${desc}")
 else
 echo "[build] FAILED: ${desc} in $(_fmt_time ${_elapsed})"
 FAILURES+=("${desc}")
 fi
}

echo "============================================"
echo "[03] Bazel build validation"
echo "============================================"

pushd "${SONIC_DIR}" > /dev/null

echo "[03] Bazel version:"
bazel --version

if should_run_local_tests; then
echo ""
echo "[= Testing Local Tests =]"

run_step "local tests" bazel test \
 //dockers/docker-orchagent/tests:site-packages_assert \
 //dockers/docker-base-bookworm/tests:site-packages_assert \
 @libyang3_py3//... \
 @libyang//... \
 --keep_going --test_output=errors

# Shut down root workspace server before submodule builds to free memory
bazel shutdown 2>/dev/null || true
fi

echo ""
echo "[= Testing Dependent Repositories =]"

should_run_repo sonic-build-infra   && test_repo "src/sonic-build-infra" bazel build ...
should_run_repo sonic-utilities     && test_repo "src/sonic-utilities" bazel build :sonic-utilities :dist
should_run_repo sonic-utilities     && test_repo "src/sonic-utilities" bazel test //:all --test_output=errors
should_run_repo sonic-host-services && test_repo "src/sonic-host-services" bazel build :sonic-host-services :dist
should_run_repo sonic-host-services && test_repo "src/sonic-host-services" bazel test //:all --test_output=errors
should_run_repo sonic-sairedis      && test_repo "src/sonic-sairedis/SAI" bazel build ...
should_run_repo sonic-sairedis      && test_repo "src/sonic-sairedis" bazel build ...
should_run_repo sonic-dash-api      && test_repo "src/sonic-dash-api" bazel build ...
should_run_repo sonic-swss-common   && test_repo "src/sonic-swss-common" bazel build ...
should_run_repo sonic-swss          && test_repo "src/sonic-swss" bazel build ...
should_run_repo sonic-p4rt          && test_repo "src/sonic-p4rt/sonic-pins" bazel build ...
should_run_repo sonic-mgmt-common   && test_repo "src/sonic-mgmt-common" bazel build ...
should_run_repo sonic-gnmi          && test_repo "src/sonic-gnmi" bazel build ...

if should_run_docker; then
echo ""
echo "[= Testing Docker Images =]"

run_step "docker image query" bazel query 'kind(oci_load, ...)'

LOADS=$(bazel query 'kind(oci_load, ...) - //dockers/docker-sonic-p4rt:load' 2>/dev/null || true)
if [ -n "${LOADS}" ]; then
 for load in ${LOADS}; do
 run_step "docker load: ${load}" bazel run "${load}"
 done
else
 echo "[build] No OCI load targets found (or query failed)"
 FAILURES+=("docker image query returned empty")
fi
fi

popd > /dev/null

_TOTAL_ELAPSED=$(( $(date +%s) - _SCRIPT_START ))

echo ""
echo "============================================"
echo "[03] BUILD VALIDATION SUMMARY"
echo "============================================"
echo ""

if [ ${#SUCCESSES[@]} -gt 0 ]; then
 echo "✅ PASSED (${#SUCCESSES[@]}):"
 for s in "${SUCCESSES[@]}"; do
 echo " ✓ ${s}"
 done
 echo ""
fi

if [ ${#FAILURES[@]} -gt 0 ]; then
 echo "❌ FAILED (${#FAILURES[@]}):"
 for f in "${FAILURES[@]}"; do
 echo " ✗ ${f}"
 done
 echo ""
fi

echo "⏱ Step times:"
for st in "${_STEP_TIMES[@]}"; do
 echo " ${st}"
done
echo ""

echo "📁 Log files (${#LOG_FILES[@]}):"
for lf in "${LOG_FILES[@]}"; do
 # Grab the RESULT line from each log
 result=$(grep '^RESULT:' "${lf}" 2>/dev/null | tail -1 || echo "UNKNOWN")
 echo " ${lf} — ${result}"
done

echo ""
echo "⏱ Total elapsed time: $(_fmt_time ${_TOTAL_ELAPSED})"
echo ""
echo "============================================"
if [ ${#FAILURES[@]} -eq 0 ]; then
 echo "[= ALL ${#SUCCESSES[@]} STEPS PASSED =]"
 exit 0
else
 echo "[= ${#FAILURES[@]} FAILURE(S) / ${#SUCCESSES[@]} PASSED =]"
 echo "============================================"
 exit 1
fi
