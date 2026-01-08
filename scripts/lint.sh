#!/usr/bin/env bash
# Lint an OpenAPI spec using Redocly CLI
#
# Required environment variables:
#   SPEC_PATH       - Path to the OpenAPI spec (relative to workspace)
#   REPORTS_DIR     - Directory to write reports to
#   STATUS_FILE     - Path to the status TSV file
#   REDOCLY_IMAGE   - Docker image for Redocly CLI
#   WORKSPACE       - Root workspace directory
#   MATRIX_PATH     - Path to the matrix repo (relative to workspace)
#
# Optional environment variables:
#   REDOCLY_CONFIG  - Path to Redocly config (relative to workspace)

set -euo pipefail

: "${SPEC_PATH:?SPEC_PATH is required}"
: "${REPORTS_DIR:?REPORTS_DIR is required}"
: "${STATUS_FILE:?STATUS_FILE is required}"
: "${REDOCLY_IMAGE:?REDOCLY_IMAGE is required}"
: "${WORKSPACE:?WORKSPACE is required}"
: "${MATRIX_PATH:?MATRIX_PATH is required}"

log="${REPORTS_DIR}/lint/redocly.log"

config_arg=()
if [[ -n "${REDOCLY_CONFIG:-}" ]]; then
  config_arg=(--config "/work/${REDOCLY_CONFIG}")
fi

matrix_root="/work/${MATRIX_PATH}"

echo "::group::redocly lint"

# Log the command being run for debugging
{
  echo "$ docker run --rm -v \${WORKSPACE}:/work -w ${matrix_root} ${REDOCLY_IMAGE} lint /work/${SPEC_PATH} ${config_arg[*]:-}"
  echo ""
} > "${log}"

set +e
docker run --rm \
  -v "${WORKSPACE}:/work" \
  -w "${matrix_root}" \
  "${REDOCLY_IMAGE}" \
  lint "/work/${SPEC_PATH}" \
  ${config_arg[@]+"${config_arg[@]}"} 2>&1 | tee -a "${log}"
exit_code=${PIPESTATUS[0]}
set -e
echo "::endgroup::"

if [[ "${exit_code}" -eq 0 ]]; then
  printf 'lint\tspec\tredocly\tok\t%s\n' "${log}" >> "${STATUS_FILE}"
else
  printf 'lint\tspec\tredocly\tfail\t%s\n' "${log}" >> "${STATUS_FILE}"
fi

exit "${exit_code}"
