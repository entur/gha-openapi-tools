#!/usr/bin/env bash
# Generate HTML dashboard for reports
#
# Required environment variables:
#   REPORTS_DIR     - Directory containing reports
#   STATUS_FILE     - Path to the status TSV file

set -euo pipefail

: "${REPORTS_DIR:?REPORTS_DIR is required}"
: "${STATUS_FILE:?STATUS_FILE is required}"

# HTML escape function
html_escape() {
  sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

output="${REPORTS_DIR}/dashboard.html"

# Count results
total=0 passed=0 failed=0
if [[ -f "${STATUS_FILE}" ]]; then
  total=$(wc -l < "${STATUS_FILE}" | tr -d ' ')
  passed=$(awk -F'\t' '$4=="ok"' "${STATUS_FILE}" | wc -l | tr -d ' ')
  failed=$(awk -F'\t' '$4=="fail"' "${STATUS_FILE}" | wc -l | tr -d ' ')
fi

cat > "${output}" << 'HTMLHEAD'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>OpenAPI Tools Report</title>
  <style>
    :root {
      --bg: #0d1117; --fg: #c9d1d9; --border: #30363d;
      --green: #238636; --red: #da3633; --yellow: #d29922;
      --link: #58a6ff; --code-bg: #161b22;
    }
    * { box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
           background: var(--bg); color: var(--fg); margin: 0; padding: 20px; line-height: 1.5; }
    h1, h2, h3 { margin-top: 0; font-weight: 600; }
    h1 { border-bottom: 1px solid var(--border); padding-bottom: 10px; }
    .summary { display: flex; gap: 20px; margin-bottom: 30px; flex-wrap: wrap; }
    .stat { background: var(--code-bg); border: 1px solid var(--border); border-radius: 6px;
            padding: 16px 24px; text-align: center; min-width: 120px; }
    .stat-value { font-size: 2em; font-weight: 600; }
    .stat-label { color: #8b949e; font-size: 0.9em; }
    .stat.pass .stat-value { color: var(--green); }
    .stat.fail .stat-value { color: var(--red); }
    .section { margin-bottom: 30px; }
    .result-table { width: 100%; border-collapse: collapse; background: var(--code-bg);
                   border: 1px solid var(--border); border-radius: 6px; overflow: hidden; }
    .result-table th, .result-table td { padding: 12px; text-align: left; border-bottom: 1px solid var(--border); }
    .result-table th { background: var(--bg); font-weight: 600; }
    .result-table tr:last-child td { border-bottom: none; }
    .badge { display: inline-block; padding: 2px 8px; border-radius: 12px; font-size: 0.85em; font-weight: 500; }
    .badge.ok { background: var(--green); color: #fff; }
    .badge.fail { background: var(--red); color: #fff; }
    details { background: var(--code-bg); border: 1px solid var(--border); border-radius: 6px; margin-top: 10px; }
    summary { padding: 12px; cursor: pointer; font-weight: 500; }
    summary:hover { background: var(--border); }
    pre { margin: 0; padding: 16px; overflow-x: auto; font-size: 0.85em;
          background: var(--bg); border-top: 1px solid var(--border); max-height: 500px; overflow-y: auto; }
    code { font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace; }
    a { color: var(--link); text-decoration: none; }
    a:hover { text-decoration: underline; }
    .empty { color: #8b949e; font-style: italic; }
  </style>
</head>
<body>
  <h1>OpenAPI Tools Report</h1>
  <div class="summary">
HTMLHEAD

# Summary stats
cat >> "${output}" << HTMLSTATS
    <div class="stat">
      <div class="stat-value">${total}</div>
      <div class="stat-label">Total</div>
    </div>
    <div class="stat pass">
      <div class="stat-value">${passed}</div>
      <div class="stat-label">Passed</div>
    </div>
    <div class="stat fail">
      <div class="stat-value">${failed}</div>
      <div class="stat-label">Failed</div>
    </div>
  </div>
HTMLSTATS

# Results by section
for section in lint generate compile; do
  case "${section}" in
    lint) section_title="Lint" ;;
    generate) section_title="Generate" ;;
    compile) section_title="Compile" ;;
  esac

  entries=""
  if [[ -f "${STATUS_FILE}" ]]; then
    entries=$(awk -F'\t' -v s="${section}" '$1==s' "${STATUS_FILE}" || true)
  fi

  if [[ -n "${entries}" ]]; then
    cat >> "${output}" << HTMLSECTION
  <div class="section">
    <h2>${section_title}</h2>
    <table class="result-table">
      <thead>
        <tr><th>Scope</th><th>Target</th><th>Status</th><th>Log</th></tr>
      </thead>
      <tbody>
HTMLSECTION

    while IFS=$'\t' read -r stage scope target status logpath; do
      badge_class="${status}"
      log_content=""
      log_basename=""

      if [[ -f "${logpath}" ]]; then
        log_basename=$(basename "${logpath}")
        log_content=$(head -c 100000 "${logpath}" | html_escape || echo "Could not read log")
      else
        log_content="Log file not found: ${logpath}"
      fi

      cat >> "${output}" << HTMLROW
        <tr>
          <td>${scope}</td>
          <td>${target}</td>
          <td><span class="badge ${badge_class}">${status}</span></td>
          <td>
            <details>
              <summary>${log_basename:-log}</summary>
              <pre><code>${log_content}</code></pre>
            </details>
          </td>
        </tr>
HTMLROW
    done <<< "${entries}"

    cat >> "${output}" << 'HTMLSECTIONEND'
      </tbody>
    </table>
  </div>
HTMLSECTIONEND
  fi
done

# Footer
cat >> "${output}" << 'HTMLFOOT'
  <footer style="margin-top: 40px; padding-top: 20px; border-top: 1px solid var(--border); color: #8b949e; font-size: 0.85em;">
    Generated by the reusable GHA workflow <a href="https://github.com/entur/gha-openapi-tools">OpenAPI Tools</a> from Entur.
  </footer>
</body>
</html>
HTMLFOOT

echo "Generated reports dashboard: ${output}"
