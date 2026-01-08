#!/usr/bin/env bash
# Compile generated code using Docker Compose
#
# Required environment variables:
#   REPORTS_DIR       - Directory to write reports to
#   STATUS_FILE       - Path to the status TSV file
#   MATRIX_PATH       - Path to the matrix repo (relative to workspace)
#
# Optional environment variables:
#   MODE              - Which generator types to compile (server, client, both)
#                       Defaults to "server" for backward compatibility
#   SERVER_GENERATORS - Comma-separated list of server generators to compile
#                       If empty, compiles all supported server generators
#   CLIENT_GENERATORS - Comma-separated list of client generators to compile
#                       If empty, compiles all supported client generators

set -euo pipefail

: "${REPORTS_DIR:?REPORTS_DIR is required}"
: "${STATUS_FILE:?STATUS_FILE is required}"
: "${MATRIX_PATH:?MATRIX_PATH is required}"

MODE="${MODE:-server}"

error_log="${REPORTS_DIR}/compile/_errors.log"

# Supported generators for compilation
# These lists must match services in docker-compose.yaml
SUPPORTED_SERVER_GENERATORS=(
  aspnetcore
  go-server
  kotlin-spring
  python-fastapi
  spring
  typescript-nestjs
)

SUPPORTED_CLIENT_GENERATORS=(
  csharp
  go
  java
  kotlin
  python
  typescript-axios
  typescript-fetch
  typescript-node
)

is_supported_server() {
  local gen="$1"
  for supported in "${SUPPORTED_SERVER_GENERATORS[@]}"; do
    if [[ "${gen}" == "${supported}" ]]; then
      return 0
    fi
  done
  return 1
}

is_supported_client() {
  local gen="$1"
  for supported in "${SUPPORTED_CLIENT_GENERATORS[@]}"; do
    if [[ "${gen}" == "${supported}" ]]; then
      return 0
    fi
  done
  return 1
}

# Build list of services to compile
# Each entry is "type:service:name" where type is server/client
services=()

# Add server generators if mode includes server
if [[ "${MODE}" == "server" || "${MODE}" == "both" ]]; then
  if [[ -n "${SERVER_GENERATORS:-}" ]]; then
    IFS=',' read -r -a gens <<< "${SERVER_GENERATORS}"
    for raw in "${gens[@]}"; do
      gen="$(echo "${raw}" | xargs)"
      if [[ -z "${gen}" ]]; then
        continue
      fi
      if ! is_supported_server "${gen}"; then
        echo "Unsupported server generator for compile: ${gen}" | tee -a "${error_log}"
        printf 'compile\tserver\t%s\tfail\t%s\n' "${gen}" "${error_log}" >> "${STATUS_FILE}"
        exit 1
      fi
      services+=("server:build-${gen}:${gen}")
    done
  else
    for gen in "${SUPPORTED_SERVER_GENERATORS[@]}"; do
      services+=("server:build-${gen}:${gen}")
    done
  fi
fi

# Add client generators if mode includes client
if [[ "${MODE}" == "client" || "${MODE}" == "both" ]]; then
  if [[ -n "${CLIENT_GENERATORS:-}" ]]; then
    IFS=',' read -r -a gens <<< "${CLIENT_GENERATORS}"
    for raw in "${gens[@]}"; do
      gen="$(echo "${raw}" | xargs)"
      if [[ -z "${gen}" ]]; then
        continue
      fi
      if ! is_supported_client "${gen}"; then
        echo "Unsupported client generator for compile: ${gen}" | tee -a "${error_log}"
        printf 'compile\tclient\t%s\tfail\t%s\n' "${gen}" "${error_log}" >> "${STATUS_FILE}"
        exit 1
      fi
      services+=("client:build-client-${gen}:${gen}")
    done
  else
    for gen in "${SUPPORTED_CLIENT_GENERATORS[@]}"; do
      services+=("client:build-client-${gen}:${gen}")
    done
  fi
fi

failures=0
for entry in "${services[@]}"; do
  IFS=':' read -r type service name <<< "${entry}"
  mkdir -p "${REPORTS_DIR}/compile/${type}"
  log="${REPORTS_DIR}/compile/${type}/${service}.log"
  echo "::group::compile ${service}"

  # Log the command being run for debugging
  {
    echo "$ docker compose -f ${MATRIX_PATH}/docker-compose.yaml --project-directory ${MATRIX_PATH} run --rm ${service}"
    echo ""
  } > "${log}"

  set +e
  docker compose -f "${MATRIX_PATH}/docker-compose.yaml" --project-directory "${MATRIX_PATH}" run --rm "${service}" 2>&1 | tee -a "${log}"
  exit_code=${PIPESTATUS[0]}
  set -e
  echo "::endgroup::"
  if [[ "${exit_code}" -eq 0 ]]; then
    printf 'compile\t%s\t%s\tok\t%s\n' "${type}" "${name}" "${log}" >> "${STATUS_FILE}"
  else
    printf 'compile\t%s\t%s\tfail\t%s\n' "${type}" "${name}" "${log}" >> "${STATUS_FILE}"
    failures=1
  fi
done

if [[ "${failures}" -ne 0 ]]; then
  exit 1
fi
