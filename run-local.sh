#!/usr/bin/env bash
# Run OpenAPI tools locally (same steps as the GitHub Actions workflow)
#
# Usage:
#   ./run-local.sh <spec-path> [options]
#
# Options:
#   --mode <server|client|both>     Generator mode (default: server)
#   --server-generators <list>      Comma-separated server generators (default: all)
#   --client-generators <list>      Comma-separated client generators (default: all)
#   --server-config-dir <path>      Path to server configs (default: generators/server)
#   --client-config-dir <path>      Path to client configs (default: generators/client)
#   --generator-image <image>       OpenAPI Generator image (default: openapitools/openapi-generator-cli:v7.17.0)
#   --redocly-image <image>         Redocly CLI image (default: redocly/cli:1.25.5)
#   --redocly-config <path>         Path to Redocly config file
#   --skip-lint                     Skip linting step
#   --skip-generate                 Skip generation step
#   --skip-compile                  Skip compilation step
#   --clean                         Remove generated/ and reports/ before running
#   -h, --help                      Show this help message
#
# Examples:
#   ./run-local.sh fixtures/petstore.yaml
#   ./run-local.sh api/openapi.yaml --mode both --skip-compile
#   ./run-local.sh spec.yaml --server-generators spring,kotlin-spring

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
MODE="server"
SERVER_GENERATORS=""
CLIENT_GENERATORS=""
SERVER_CONFIG_DIR="generators/server"
CLIENT_CONFIG_DIR="generators/client"
GENERATOR_IMAGE="openapitools/openapi-generator-cli:v7.17.0"
REDOCLY_IMAGE="redocly/cli:1.25.5"
REDOCLY_CONFIG=""
RUN_LINT=true
RUN_GENERATE=true
RUN_COMPILE=true
CLEAN=false
SPEC_PATH=""

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
  exit 0
}

die() {
  echo "Error: $1" >&2
  exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    --server-generators)
      SERVER_GENERATORS="$2"
      shift 2
      ;;
    --client-generators)
      CLIENT_GENERATORS="$2"
      shift 2
      ;;
    --server-config-dir)
      SERVER_CONFIG_DIR="$2"
      shift 2
      ;;
    --client-config-dir)
      CLIENT_CONFIG_DIR="$2"
      shift 2
      ;;
    --generator-image)
      GENERATOR_IMAGE="$2"
      shift 2
      ;;
    --redocly-image)
      REDOCLY_IMAGE="$2"
      shift 2
      ;;
    --redocly-config)
      REDOCLY_CONFIG="$2"
      shift 2
      ;;
    --skip-lint)
      RUN_LINT=false
      shift
      ;;
    --skip-generate)
      RUN_GENERATE=false
      shift
      ;;
    --skip-compile)
      RUN_COMPILE=false
      shift
      ;;
    --clean)
      CLEAN=true
      shift
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      if [[ -z "${SPEC_PATH}" ]]; then
        SPEC_PATH="$1"
      else
        die "Unexpected argument: $1"
      fi
      shift
      ;;
  esac
done

if [[ -z "${SPEC_PATH}" ]]; then
  die "Spec path is required. Usage: $0 <spec-path> [options]"
fi

if [[ ! -f "${SPEC_PATH}" ]]; then
  die "Spec file not found: ${SPEC_PATH}"
fi

case "${MODE}" in
  server|client|both) ;;
  *) die "Invalid mode: ${MODE} (expected: server, client, both)" ;;
esac

# Check Docker is available
if ! command -v docker &>/dev/null; then
  die "Docker is required but not found in PATH"
fi

# Set up environment for local execution
# Key difference from CI: no caller/matrix split, everything is in SCRIPT_DIR
export WORKSPACE="${SCRIPT_DIR}"
export MATRIX_PATH="."
export REPORTS_DIR="${SCRIPT_DIR}/reports"
export STATUS_FILE="${REPORTS_DIR}/status.tsv"

echo "=== OpenAPI Tools (local) ==="
echo "Spec:       ${SPEC_PATH}"
echo "Mode:       ${MODE}"
echo "Lint:       ${RUN_LINT}"
echo "Generate:   ${RUN_GENERATE}"
echo "Compile:    ${RUN_COMPILE}"
echo ""

# Clean if requested
if [[ "${CLEAN}" == "true" ]]; then
  echo "Cleaning previous outputs..."
  rm -rf "${SCRIPT_DIR}/generated" "${REPORTS_DIR}"
fi

# Prepare reports directory
mkdir -p "${REPORTS_DIR}/lint" "${REPORTS_DIR}/generate/server" "${REPORTS_DIR}/generate/client" "${REPORTS_DIR}/compile"
: > "${STATUS_FILE}"

LINT_OUTCOME="skipped"
GENERATE_OUTCOME="skipped"
COMPILE_OUTCOME="skipped"

# Step 1: Lint
if [[ "${RUN_LINT}" == "true" ]]; then
  echo "=== Linting spec ==="
  export SPEC_PATH
  export REDOCLY_IMAGE
  export REDOCLY_CONFIG
  if "${SCRIPT_DIR}/scripts/lint.sh"; then
    LINT_OUTCOME="success"
  else
    LINT_OUTCOME="failure"
    echo "Lint failed (continuing...)"
  fi
  echo ""
fi

# Step 2: Generate
if [[ "${RUN_GENERATE}" == "true" ]]; then
  echo "=== Generating code ==="
  export SPEC_PATH
  export GENERATOR_IMAGE
  export MODE
  export SERVER_CONFIG_DIR
  export CLIENT_CONFIG_DIR
  export SERVER_GENERATORS
  export CLIENT_GENERATORS
  export USE_CALLER_CONFIGS="false"
  if "${SCRIPT_DIR}/scripts/generate.sh"; then
    GENERATE_OUTCOME="success"
  else
    GENERATE_OUTCOME="failure"
    echo "Generate failed (continuing...)"
  fi
  echo ""
fi

# Step 3: Compile
if [[ "${RUN_COMPILE}" == "true" ]] && [[ "${RUN_GENERATE}" == "true" ]]; then
  echo "=== Compiling generated code ==="
  export MODE
  export SERVER_GENERATORS
  export CLIENT_GENERATORS
  if "${SCRIPT_DIR}/scripts/compile.sh"; then
    COMPILE_OUTCOME="success"
  else
    COMPILE_OUTCOME="failure"
    echo "Compile failed (continuing...)"
  fi
  echo ""
fi

# Step 4: Generate dashboard
echo "=== Generating dashboard ==="
"${SCRIPT_DIR}/scripts/dashboard.sh"
echo ""

# Summary
echo "=== Results ==="
echo ""

if [[ -f "${STATUS_FILE}" ]]; then
  # Print status table
  printf "%-12s %-12s %-20s %-8s\n" "STEP" "SCOPE" "TARGET" "STATUS"
  printf "%-12s %-12s %-20s %-8s\n" "----" "-----" "------" "------"
  while IFS=$'\t' read -r step scope target status log; do
    printf "%-12s %-12s %-20s %-8s\n" "${step}" "${scope}" "${target}" "${status}"
  done < "${STATUS_FILE}"
  echo ""

  failures="$(awk -F '\t' '$4=="fail" {count++} END {print count+0}' "${STATUS_FILE}")"
  if [[ "${failures}" -gt 0 ]]; then
    echo "Failures: ${failures}"
    echo "See reports/ for detailed logs"
    echo "Open reports/dashboard.html for visual summary"
    exit 1
  fi
fi

echo "All steps completed successfully!"
echo ""
echo "Outputs:"
echo "  Generated code: generated/"
echo "  Reports:        reports/"
echo "  Dashboard:      reports/dashboard.html"
