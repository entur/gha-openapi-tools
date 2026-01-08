#!/usr/bin/env bash
# Generate code from an OpenAPI spec using OpenAPI Generator CLI
#
# Required environment variables:
#   SPEC_PATH           - Path to the OpenAPI spec (relative to workspace, prefixed with caller/)
#   REPORTS_DIR         - Directory to write reports to
#   STATUS_FILE         - Path to the status TSV file
#   GENERATOR_IMAGE     - Docker image for OpenAPI Generator CLI
#   WORKSPACE           - Root workspace directory
#   MATRIX_PATH         - Path to the matrix repo (relative to workspace)
#   MODE                - Generator mode: server, client, or both
#   SERVER_CONFIG_DIR   - Path to server generator configs (relative to config root)
#   CLIENT_CONFIG_DIR   - Path to client generator configs (relative to config root)
#
# Optional environment variables:
#   SERVER_GENERATORS   - Comma-separated list of server generators to run
#   CLIENT_GENERATORS   - Comma-separated list of client generators to run
#   USE_CALLER_CONFIGS  - If 'true', look for configs in caller repo instead of matrix repo

set -euo pipefail
shopt -s nullglob

: "${SPEC_PATH:?SPEC_PATH is required}"
: "${REPORTS_DIR:?REPORTS_DIR is required}"
: "${STATUS_FILE:?STATUS_FILE is required}"
: "${GENERATOR_IMAGE:?GENERATOR_IMAGE is required}"
: "${WORKSPACE:?WORKSPACE is required}"
: "${MATRIX_PATH:?MATRIX_PATH is required}"
: "${MODE:?MODE is required}"
: "${SERVER_CONFIG_DIR:?SERVER_CONFIG_DIR is required}"
: "${CLIENT_CONFIG_DIR:?CLIENT_CONFIG_DIR is required}"

spec="/work/${SPEC_PATH}"
host_matrix_root="${WORKSPACE}/${MATRIX_PATH}"
container_matrix_root="/work/${MATRIX_PATH}"

# Resolve config directories: caller repo if USE_CALLER_CONFIGS=true, otherwise matrix repo
if [[ "${USE_CALLER_CONFIGS:-false}" == "true" ]]; then
  config_host_root="${WORKSPACE}/caller"
  config_container_root="/work/caller"
else
  config_host_root="${host_matrix_root}"
  config_container_root="${container_matrix_root}"
fi

host_server_dir="${config_host_root}/${SERVER_CONFIG_DIR}"
host_client_dir="${config_host_root}/${CLIENT_CONFIG_DIR}"
container_server_dir="${config_container_root}/${SERVER_CONFIG_DIR}"
container_client_dir="${config_container_root}/${CLIENT_CONFIG_DIR}"

case "${MODE}" in
  server|client|both)
    ;;
  *)
    echo "Invalid mode: ${MODE} (expected server, client, or both)" | tee -a "${REPORTS_DIR}/generate/_errors.log"
    printf 'generate\tmode\tinvalid\tfail\t%s\n' "${REPORTS_DIR}/generate/_errors.log" >> "${STATUS_FILE}"
    exit 1
    ;;
esac

generate_from_dir() {
  local host_dir="$1"
  local container_dir="$2"
  local list="$3"
  local label="$4"
  local configs=()
  local failures=0
  local error_log="${REPORTS_DIR}/generate/${label}/_errors.log"

  if [[ ! -d "${host_dir}" ]]; then
    echo "Missing ${label} config dir: ${host_dir}" | tee -a "${error_log}"
    printf 'generate\t%s\t_config_\tfail\t%s\n' "${label}" "${error_log}" >> "${STATUS_FILE}"
    return 1
  fi

  if [[ -n "${list}" ]]; then
    IFS=',' read -r -a gens <<< "${list}"
    for raw in "${gens[@]}"; do
      gen="$(echo "${raw}" | xargs)"
      if [[ -z "${gen}" ]]; then
        continue
      fi
      config="${host_dir}/${gen}.yaml"
      if [[ ! -f "${config}" ]]; then
        echo "Missing ${label} generator config: ${config}" | tee -a "${error_log}"
        printf 'generate\t%s\t%s\tfail\t%s\n' "${label}" "${gen}" "${error_log}" >> "${STATUS_FILE}"
        return 1
      fi
      configs+=("${config}")
    done
  else
    configs=("${host_dir}"/*.yaml)
  fi

  if [[ "${#configs[@]}" -eq 0 ]]; then
    echo "No ${label} generator configs found under ${host_dir}" | tee -a "${error_log}"
    printf 'generate\t%s\t_config_\tfail\t%s\n' "${label}" "${error_log}" >> "${STATUS_FILE}"
    return 1
  fi

  for config in "${configs[@]}"; do
    name="$(basename "${config}" .yaml)"
    config_container="${config/${host_dir}/${container_dir}}"
    log="${REPORTS_DIR}/generate/${label}/${name}.log"
    echo "::group::generate ${label} ${name}"

    # Log the command being run for debugging
    {
      echo "$ docker run --rm --user $(id -u):$(id -g) -v \${WORKSPACE}:/work -w ${container_matrix_root} ${GENERATOR_IMAGE} generate -i ${spec} -c ${config_container}"
      echo ""
    } > "${log}"

    set +e
    docker run --rm \
      --user "$(id -u):$(id -g)" \
      -v "${WORKSPACE}:/work" \
      -w "${container_matrix_root}" \
      "${GENERATOR_IMAGE}" \
      generate -i "${spec}" -c "${config_container}" 2>&1 | tee -a "${log}"
    exit_code=${PIPESTATUS[0]}
    set -e
    echo "::endgroup::"
    if [[ "${exit_code}" -eq 0 ]]; then
      printf 'generate\t%s\t%s\tok\t%s\n' "${label}" "${name}" "${log}" >> "${STATUS_FILE}"
    else
      printf 'generate\t%s\t%s\tfail\t%s\n' "${label}" "${name}" "${log}" >> "${STATUS_FILE}"
      failures=1
    fi
  done
  return "${failures}"
}

failures=0
if [[ "${MODE}" == "server" ]] || [[ "${MODE}" == "both" ]]; then
  generate_from_dir "${host_server_dir}" "${container_server_dir}" "${SERVER_GENERATORS:-}" "server" || failures=1
fi
if [[ "${MODE}" == "client" ]] || [[ "${MODE}" == "both" ]]; then
  generate_from_dir "${host_client_dir}" "${container_client_dir}" "${CLIENT_GENERATORS:-}" "client" || failures=1
fi

# Fix permissions on generated directory (Docker creates files as root)
generated_dir="${host_matrix_root}/generated"
if [[ -d "${generated_dir}" ]]; then
  chmod -R a+rw "${generated_dir}" 2>/dev/null || true
fi

exit "${failures}"
