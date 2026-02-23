#!/usr/bin/env bash
# =============================================================================
# Entrypoint for CodeNomad + OpenCode container
# =============================================================================
# Starts the CodeNomad server which manages OpenCode sessions.
# All configuration is driven by environment variables.
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
CODENOMAD_HOST="${CODENOMAD_HOST:-0.0.0.0}"
CODENOMAD_HTTP_PORT="${CODENOMAD_HTTP_PORT:-9899}"
CODENOMAD_WORKSPACE_ROOT="${CODENOMAD_WORKSPACE_ROOT:-/workspaces}"

# Authentication
CODENOMAD_SERVER_USERNAME="${CODENOMAD_SERVER_USERNAME:-admin}"
CODENOMAD_SERVER_PASSWORD="${CODENOMAD_SERVER_PASSWORD:-}"
CODENOMAD_SKIP_AUTH="${CODENOMAD_SKIP_AUTH:-false}"

# OpenCode server auth (passed through to opencode processes)
OPENCODE_SERVER_PASSWORD="${OPENCODE_SERVER_PASSWORD:-}"
OPENCODE_SERVER_USERNAME="${OPENCODE_SERVER_USERNAME:-opencode}"

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
if [[ -z "${CODENOMAD_SERVER_PASSWORD}" && "${CODENOMAD_SKIP_AUTH}" != "true" ]]; then
    echo "=================================================================="
    echo "  WARNING: No CODENOMAD_SERVER_PASSWORD is set."
    echo "  The server will require authentication but has no password."
    echo "  Set CODENOMAD_SERVER_PASSWORD or CODENOMAD_SKIP_AUTH=true"
    echo "=================================================================="
fi

# Check that at least one LLM provider key is configured
if [[ -z "${ANTHROPIC_API_KEY:-}" && -z "${OPENAI_API_KEY:-}" && -z "${OPENCODE_API_KEY:-}" && -z "${OPENROUTER_API_KEY:-}" ]]; then
    echo "=================================================================="
    echo "  WARNING: No LLM provider API key detected."
    echo "  Set at least one of:"
    echo "    - ANTHROPIC_API_KEY"
    echo "    - OPENAI_API_KEY"
    echo "    - OPENCODE_API_KEY"
    echo "    - OPENROUTER_API_KEY"
    echo "=================================================================="
fi

# ---------------------------------------------------------------------------
# Ensure workspace directory exists
# ---------------------------------------------------------------------------
if [[ ! -d "${CODENOMAD_WORKSPACE_ROOT}" ]]; then
    echo "Creating workspace root: ${CODENOMAD_WORKSPACE_ROOT}"
    mkdir -p "${CODENOMAD_WORKSPACE_ROOT}"
fi

# ---------------------------------------------------------------------------
# Write OpenCode auth.json if API keys are provided via env vars
# ---------------------------------------------------------------------------
AUTH_DIR="/home/codeuser/.local/share/opencode"
AUTH_FILE="${AUTH_DIR}/auth.json"

mkdir -p "${AUTH_DIR}"

# Build auth.json from environment variables
AUTH_JSON="{}"
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    AUTH_JSON=$(echo "${AUTH_JSON}" | jq --arg key "${ANTHROPIC_API_KEY}" '. + {"anthropic": {"apiKey": $key}}')
fi
if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    AUTH_JSON=$(echo "${AUTH_JSON}" | jq --arg key "${OPENAI_API_KEY}" '. + {"openai": {"apiKey": $key}}')
fi
if [[ -n "${OPENCODE_API_KEY:-}" ]]; then
    AUTH_JSON=$(echo "${AUTH_JSON}" | jq --arg key "${OPENCODE_API_KEY}" '. + {"opencode": {"apiKey": $key}}')
fi
if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
    AUTH_JSON=$(echo "${AUTH_JSON}" | jq --arg key "${OPENROUTER_API_KEY}" '. + {"openrouter": {"apiKey": $key}}')
fi

echo "${AUTH_JSON}" > "${AUTH_FILE}"

# ---------------------------------------------------------------------------
# Build CodeNomad CLI arguments
# ---------------------------------------------------------------------------
CODENOMAD_ARGS=(
    "--host" "${CODENOMAD_HOST}"
    "--http" "true"
    "--https" "false"
    "--http-port" "${CODENOMAD_HTTP_PORT}"
    "--workspace-root" "${CODENOMAD_WORKSPACE_ROOT}"
    "--username" "${CODENOMAD_SERVER_USERNAME}"
    "--ui-auto-update" "true"
)

# Add password if set
if [[ -n "${CODENOMAD_SERVER_PASSWORD}" ]]; then
    CODENOMAD_ARGS+=("--password" "${CODENOMAD_SERVER_PASSWORD}")
fi

# # Skip auth if explicitly requested
# if [[ "${CODENOMAD_SKIP_AUTH}" == "true" ]]; then
#     CODENOMAD_ARGS+=("--dangerously-skip-auth")
# fi

# Allow unrestricted filesystem browsing if enabled
if [[ "${CODENOMAD_UNRESTRICTED_ROOT:-false}" == "true" ]]; then
    CODENOMAD_ARGS+=("--unrestricted-root")
fi

# ---------------------------------------------------------------------------
# Export OpenCode env vars so spawned processes inherit them
# ---------------------------------------------------------------------------
export OPENCODE_SERVER_PASSWORD="${OPENCODE_SERVER_PASSWORD}"
export OPENCODE_SERVER_USERNAME="${OPENCODE_SERVER_USERNAME}"

# ---------------------------------------------------------------------------
# Start CodeNomad server
# ---------------------------------------------------------------------------
echo "=================================================================="
echo "  CodeNomad Server starting..."
echo "  Host:      ${CODENOMAD_HOST}"
echo "  HTTP Port: ${CODENOMAD_HTTP_PORT}"
echo "  Workspace: ${CODENOMAD_WORKSPACE_ROOT}"
echo "  Auth:      $(if [[ "${CODENOMAD_SKIP_AUTH}" == "true" ]]; then echo "DISABLED"; elif [[ -n "${CODENOMAD_SERVER_PASSWORD}" ]]; then echo "ENABLED"; else echo "NO PASSWORD SET"; fi)"
echo "=================================================================="

exec codenomad "${CODENOMAD_ARGS[@]}"
