# OpenAPI Tools

A reusable GitHub Actions workflow for linting OpenAPI specs, generating server code across multiple generators, and optionally compiling the results in Docker. This repo is CI-only and designed for reuse across Entur repos.

## Supported Generators

### Server Generators (default)

| Generator | Language | Framework |
|-----------|----------|-----------|
| `aspnetcore` | C# | ASP.NET Core 8 |
| `go-server` | Go | Chi router |
| `kotlin-spring` | Kotlin | Spring Boot 3 |
| `python-fastapi` | Python | FastAPI |
| `spring` | Java | Spring Boot 3 |
| `typescript-nestjs` | TypeScript | NestJS |

### Client Generators

| Generator | Language | Notes |
|-----------|----------|-------|
| `typescript-axios` | TypeScript | Axios |
| `typescript-fetch` | TypeScript | Fetch API |
| `typescript-node` | TypeScript | Node HTTP client |
| `java` | Java | OkHttp/Gson (default) |
| `kotlin` | Kotlin | OkHttp4 |
| `python` | Python | urllib3 (default) |
| `go` | Go | net/http |
| `csharp` | C# | HttpClient |

## Usage (caller repo)

```yaml
name: OpenAPI Verify

on:
  push:
    paths:
      - openapi/**.yaml
      - openapi/**.yml
  pull_request:
    paths:
      - openapi/**.yaml
      - openapi/**.yml

jobs:
  matrix:
    uses: entur/gha-openapi-tools/.github/workflows/workflow.yml@v0
    with:
      spec_path: openapi/your-spec.yaml
      mode: server
      server_generators: aspnetcore,go-server,spring
      run_compile: true
```

For client or mixed runs, set `mode: client` or `mode: both` and choose `client_generators`.

Client-only example:

```yaml
jobs:
  matrix:
    uses: entur/gha-openapi-tools/.github/workflows/workflow.yml@v0
    with:
      spec_path: openapi/your-spec.yaml
      mode: client
      client_generators: typescript-axios,java
      run_lint: false
      run_compile: false
```

### Workflow Inputs

- `spec_path` (required): Path to the OpenAPI spec in the caller repo (relative path).
- `mode` (optional): `server`, `client`, or `both` (default `server`).
- `server_generators` (optional): Comma-separated server generator names (must match filenames in `generators/server/` without `.yaml`).
- `client_generators` (optional): Comma-separated client generator names (must match filenames in `generators/client/` without `.yaml`).
- `server_config_dir` (optional): Server config directory in this repo (default `generators/server`).
- `client_config_dir` (optional): Client config directory in this repo (default `generators/client`).
- `generator_image` (optional): OpenAPI Generator CLI image (default `openapitools/openapi-generator-cli:v7.17.0`).
- `redocly_image` (optional): Redocly CLI image (default `redocly/cli:1.25.5`).
- `redocly_config` (optional): Redocly config path in the caller repo (default uses Redocly recommended ruleset).
- `run_lint` (optional): Run Redocly linting (default `true`).
- `run_generate` (optional): Run OpenAPI Generator (default `true`).
- `run_compile` (optional): Compile generated code in Docker (default `true`, skipped when `run_generate=false`).
- `run_upload` (optional): Upload the `openapi-tools-reports` artifact (default `true`).
- `run_upload_generated` (optional): Upload the generated code as `openapi-generated-code` artifact (default `false`). Useful for inspecting generated output or debugging generator configurations.

## What It Does

- Lints the spec with Redocly CLI using the recommended ruleset.
- Generates code using OpenAPI Generator CLI with the configs in `generators/server/` and/or `generators/client/`.
- Optionally compiles generated targets using `docker-compose.yaml`.
- Outputs are written under `generated/server/` and `generated/client/`.
- Requires Docker on the runner (GitHub-hosted runners already include it).

## Reporting and Artifacts

- Each generator and compile target runs in its own log group in the Actions UI.
- Full logs are stored under `reports/` and uploaded as the `openapi-tools-reports` artifact.
- The workflow summary includes a table of results and log paths.
- When `run_upload_generated: true`, the generated code is uploaded as `openapi-generated-code` artifact, allowing you to download and inspect the output for all generators.

### HTML Dashboard

The reports artifact includes a `dashboard.html` dashboard for easy browsing:

- Summary with pass/fail counts
- Results table grouped by stage (lint, generate, compile)
- Expandable log viewers for each step

Download the artifact, unzip, and open `dashboard.html` in a browser.

## Repo Structure

```
.
├── generators/          # Generator configurations
│   ├── server/          # Server generators
│   └── client/          # Client generators
├── scripts/             # Reusable shell scripts
│   ├── lint.sh          # Redocly linting
│   ├── generate.sh      # OpenAPI code generation
│   ├── compile.sh       # Docker compilation
│   ├── summarize.sh     # GitHub step summary
│   └── dashboard.sh     # HTML dashboard generation
├── docker-compose.yaml  # Docker services for compilation
└── redocly.yaml         # Lint configuration (recommended rules)
```

## Customizing Generators

Each generator has a configuration file in `generators/server/` or `generators/client/`. Modify these to customize package names, output directories, type mappings, and generator-specific options.

See [OpenAPI Generator documentation](https://openapi-generator.tech/docs/generators) for options.
