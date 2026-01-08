#!/usr/bin/env bash
# Summarize OpenAPI Tools results for GitHub Step Summary
#
# Required environment variables:
#   STATUS_FILE       - Path to the status TSV file
#   GITHUB_STEP_SUMMARY - Path to GitHub step summary file (set by GitHub Actions)
#
# Optional environment variables:
#   RUN_LINT          - Whether lint was enabled (true/false)
#   RUN_GENERATE      - Whether generate was enabled (true/false)
#   RUN_COMPILE       - Whether compile was enabled (true/false)
#   RUN_UPLOAD        - Whether upload was enabled (true/false)
#   LINT_OUTCOME      - Outcome of lint step (success/failure/skipped)
#   GENERATE_OUTCOME  - Outcome of generate step (success/failure/skipped)
#   COMPILE_OUTCOME   - Outcome of compile step (success/failure/skipped)

set -euo pipefail

: "${STATUS_FILE:?STATUS_FILE is required}"
: "${GITHUB_STEP_SUMMARY:?GITHUB_STEP_SUMMARY is required}"

summary="${GITHUB_STEP_SUMMARY}"

echo "## OpenAPI Tools Results" >> "${summary}"
echo "" >> "${summary}"

if [[ -f "${STATUS_FILE}" ]]; then
  # Lint section
  lint_line="$(awk -F '\t' '$1=="lint"' "${STATUS_FILE}" || true)"
  if [[ -n "${lint_line}" ]]; then
    lint_status="$(echo "${lint_line}" | awk -F '\t' '{print $4}')"
    lint_log="$(echo "${lint_line}" | awk -F '\t' '{print $5}')"
    echo "### Lint" >> "${summary}"
    echo "" >> "${summary}"
    echo "| Tool | Status | Log |" >> "${summary}"
    echo "|---|---|---|" >> "${summary}"
    echo "| Redocly | ${lint_status} | ${lint_log} |" >> "${summary}"
    echo "" >> "${summary}"
  fi

  if [[ "${RUN_LINT:-true}" != "true" ]]; then
    echo "### Lint" >> "${summary}"
    echo "" >> "${summary}"
    echo "Skipped (run_lint=false)" >> "${summary}"
    echo "" >> "${summary}"
  fi

  # Generate sections (server and client)
  for scope in server client; do
    entries="$(awk -F '\t' -v scope="${scope}" '$1=="generate" && $2==scope' "${STATUS_FILE}" || true)"
    if [[ -n "${entries}" ]]; then
      title="Generate (${scope})"
      echo "### ${title}" >> "${summary}"
      echo "" >> "${summary}"
      echo "| Generator | Status | Log |" >> "${summary}"
      echo "|---|---|---|" >> "${summary}"
      awk -F '\t' -v scope="${scope}" '$1=="generate" && $2==scope {printf("| %s | %s | %s |\n", $3, $4, $5)}' "${STATUS_FILE}" >> "${summary}"
      echo "" >> "${summary}"
    fi
  done

  if [[ "${RUN_GENERATE:-true}" != "true" ]]; then
    echo "### Generate" >> "${summary}"
    echo "" >> "${summary}"
    echo "Skipped (run_generate=false)" >> "${summary}"
    echo "" >> "${summary}"
  fi

  # Compile sections (server and client)
  for scope in server client; do
    entries="$(awk -F '\t' -v scope="${scope}" '$1=="compile" && $2==scope' "${STATUS_FILE}" || true)"
    if [[ -n "${entries}" ]]; then
      title="Compile (${scope})"
      echo "### ${title}" >> "${summary}"
      echo "" >> "${summary}"
      echo "| Target | Status | Log |" >> "${summary}"
      echo "|---|---|---|" >> "${summary}"
      awk -F '\t' -v scope="${scope}" '$1=="compile" && $2==scope {printf("| %s | %s | %s |\n", $3, $4, $5)}' "${STATUS_FILE}" >> "${summary}"
      echo "" >> "${summary}"
    fi
  done
else
  echo "No status file found." >> "${summary}"
fi

if [[ "${RUN_COMPILE:-true}" != "true" ]]; then
  echo "### Compile" >> "${summary}"
  echo "" >> "${summary}"
  echo "Skipped (run_compile=false)" >> "${summary}"
  echo "" >> "${summary}"
fi

if [[ "${RUN_UPLOAD:-true}" == "true" ]]; then
  echo "Reports artifact: \`openapi-tools-reports\`" >> "${summary}"
  echo "" >> "${summary}"
else
  echo "Reports artifact: skipped (run_upload=false)" >> "${summary}"
  echo "" >> "${summary}"
fi

# Count failures from status file
if [[ -f "${STATUS_FILE}" ]]; then
  failures="$(awk -F '\t' '$4=="fail" {count++} END {print count+0}' "${STATUS_FILE}")"
else
  failures=1
fi

# Check step outcomes
step_failures=0
if [[ "${RUN_LINT:-true}" == "true" ]] && [[ "${LINT_OUTCOME:-success}" == "failure" ]]; then
  step_failures=1
fi
if [[ "${RUN_GENERATE:-true}" == "true" ]] && [[ "${GENERATE_OUTCOME:-success}" == "failure" ]]; then
  step_failures=1
fi
if [[ "${RUN_COMPILE:-true}" == "true" ]] && [[ "${COMPILE_OUTCOME:-success}" == "failure" ]]; then
  step_failures=1
fi

if [[ "${failures}" -gt 0 ]]; then
  echo "Failures: ${failures}" >> "${summary}"
  exit 1
fi

if [[ "${step_failures}" -gt 0 ]]; then
  echo "Failures: at least one step failed before reporting status." >> "${summary}"
  exit 1
fi
