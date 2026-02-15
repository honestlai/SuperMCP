#!/bin/bash

# MCP Gateway Startup Script
# Starts enabled MCP servers via supergateway, then launches the Express gateway.
# Enable servers by setting ENABLE_<NAME>=true environment variables.

set -e

echo "============================================"
echo "  MCP Gateway - Starting up"
echo "============================================"

mkdir -p /var/log/mcp /var/run

# ── Helper: start an MCP server wrapped in supergateway ───────────────────────
start_mcp() {
    local name=$1
    local port=$2
    local command=$3
    local log_file="/var/log/mcp/${name}.log"

    echo "[+] Starting ${name} on internal port ${port}..."
    echo "$(date '+%Y-%m-%d %H:%M:%S'): Starting ${name}" >> "$log_file"
    echo "    Command: ${command}" >> "$log_file"

    npx -y supergateway \
        --stdio "${command}" \
        --outputTransport streamableHttp \
        --port "${port}" \
        --streamableHttpPath /mcp \
        >> "$log_file" 2>&1 &

    local pid=$!
    echo $pid > "/var/run/${name}.pid"
    echo "    PID: ${pid}"
}

STARTED=0

# ── Playwright MCP ────────────────────────────────────────────────────────────
if [ "${ENABLE_PLAYWRIGHT}" = "true" ]; then
    start_mcp "playwright" 8081 \
        "npx -y @playwright/mcp@latest --headless --isolated --no-sandbox --browser chrome"
    STARTED=$((STARTED + 1))
fi

# ── Filesystem MCP ────────────────────────────────────────────────────────────
if [ "${ENABLE_FILESYSTEM}" = "true" ]; then
    start_mcp "filesystem" 8082 \
        "npx -y @modelcontextprotocol/server-filesystem /workspace"
    STARTED=$((STARTED + 1))
fi

# ── Sequential Thinking MCP ──────────────────────────────────────────────────
if [ "${ENABLE_SEQUENTIAL_THINKING}" = "true" ]; then
    start_mcp "sequential-thinking" 8083 \
        "npx -y @modelcontextprotocol/server-sequential-thinking"
    STARTED=$((STARTED + 1))
fi

# ── Memory MCP ────────────────────────────────────────────────────────────────
if [ "${ENABLE_MEMORY}" = "true" ]; then
    export MEMORY_FILE_PATH="${MEMORY_FILE_PATH:-/data/memory.jsonl}"
    start_mcp "memory" 8084 \
        "npx -y @modelcontextprotocol/server-memory"
    STARTED=$((STARTED + 1))
fi

# ── GitHub MCP ────────────────────────────────────────────────────────────────
if [ "${ENABLE_GITHUB}" = "true" ]; then
    if [ -z "${GITHUB_PERSONAL_ACCESS_TOKEN}" ]; then
        echo "[!] WARNING: ENABLE_GITHUB=true but GITHUB_PERSONAL_ACCESS_TOKEN is not set. Skipping."
    else
        start_mcp "github" 8085 \
            "npx -y @modelcontextprotocol/server-github"
        STARTED=$((STARTED + 1))
    fi
fi

# ── SearXNG MCP ──────────────────────────────────────────────────────────────
if [ "${ENABLE_SEARXNG}" = "true" ]; then
    if [ -z "${SEARXNG_SERVER_URL}" ]; then
        echo "[!] WARNING: ENABLE_SEARXNG=true but SEARXNG_SERVER_URL is not set. Skipping."
    else
        start_mcp "searxng" 8086 \
            "npx -y mcp-searxng"
        STARTED=$((STARTED + 1))
    fi
fi

# ── Context7 MCP ─────────────────────────────────────────────────────────────
if [ "${ENABLE_CONTEXT7}" = "true" ]; then
    start_mcp "context7" 8087 \
        "npx -y @upstash/context7-mcp"
    STARTED=$((STARTED + 1))
fi

# ── Python Interpreter MCP ───────────────────────────────────────────────────
if [ "${ENABLE_PYTHON_INTERPRETER}" = "true" ]; then
    start_mcp "python-interpreter" 8088 \
        "node /app/python-interpreter.mjs"
    STARTED=$((STARTED + 1))
fi

# ── YouTube Transcriber MCP (requires an API key for a Whisper-compatible provider)
if [ "${ENABLE_YOUTUBE_TRANSCRIBER}" = "true" ]; then
    if [ -z "${TRANSCRIBER_API_KEY}" ] && [ -z "${FIREWORKS_API_KEY}" ]; then
        echo "[!] WARNING: ENABLE_YOUTUBE_TRANSCRIBER=true but no API key is set."
        echo "    Set TRANSCRIBER_API_KEY (and optionally TRANSCRIBER_PROVIDER) or legacy FIREWORKS_API_KEY."
        echo "    Skipping."
    else
        start_mcp "youtube-transcriber" 8089 \
            "python3 /app/youtube_transcriber.py"
        STARTED=$((STARTED + 1))
    fi
fi

# ── Fetch MCP ────────────────────────────────────────────────────────────────
if [ "${ENABLE_FETCH}" = "true" ]; then
    start_mcp "fetch" 8090 \
        "python3 -m mcp_server_fetch"
    STARTED=$((STARTED + 1))
fi

# ── Git MCP ──────────────────────────────────────────────────────────────────
if [ "${ENABLE_GIT}" = "true" ]; then
    start_mcp "git" 8091 \
        "python3 -m mcp_server_git --repository /workspace"
    STARTED=$((STARTED + 1))
fi

echo ""
echo "--------------------------------------------"
echo "  ${STARTED} MCP server(s) enabled"
echo "--------------------------------------------"

# Give backends a moment to initialize
if [ $STARTED -gt 0 ]; then
    echo "Waiting for backends to initialize..."
    sleep 3
fi

# ── Start the gateway in the foreground ───────────────────────────────────────
echo "Starting MCP Gateway on port 8080..."
cd /app && node gateway.js &
GATEWAY_PID=$!

# Graceful shutdown: kill all child processes on SIGTERM/SIGINT
shutdown() {
    echo ""
    echo "Shutting down MCP Gateway..."
    # Kill all supergateway processes
    for pidfile in /var/run/*.pid; do
        if [ -f "$pidfile" ]; then
            kill "$(cat "$pidfile")" 2>/dev/null || true
        fi
    done
    # Kill gateway
    kill $GATEWAY_PID 2>/dev/null || true
    exit 0
}
trap shutdown INT TERM

# Keep the container running
wait $GATEWAY_PID
