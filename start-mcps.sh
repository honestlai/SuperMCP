#!/bin/bash

# MCP Gateway Startup Script
# Starts enabled MCP servers via supergateway, then launches the Express gateway.
# Enable servers by setting ENABLE_<NAME>=true environment variables.

set -e

echo "============================================"
echo "  MCP Gateway - Starting up"
echo "============================================"

mkdir -p /var/log/mcp /var/run

# Cap Node.js heap per process to prevent OOM kills (each supergateway + MCP = ~2 Node procs)
export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=256}"

# Tracks started ports for the wait-for-ready step
STARTED_PORTS=()

# Tracks name->command and name->port for the watchdog restarter
declare -A MCP_COMMANDS
declare -A MCP_PORTS

# ── Helper: launch one MCP server wrapped in supergateway ─────────────────────
start_mcp() {
    local name=$1
    local port=$2
    local command=$3
    local log_file="/var/log/mcp/${name}.log"

    echo "[+] Starting ${name} on internal port ${port}..."
    echo "$(date '+%Y-%m-%d %H:%M:%S'): Starting ${name}" >> "$log_file"

    npx supergateway \
        --stdio "${command}" \
        --outputTransport streamableHttp \
        --port "${port}" \
        --streamableHttpPath /mcp \
        >> "$log_file" 2>&1 &

    local pid=$!
    echo $pid > "/var/run/${name}.pid"
    echo "    PID: ${pid}"

    STARTED_PORTS+=( "${port}" )
    MCP_COMMANDS["${name}"]="${command}"
    MCP_PORTS["${name}"]="${port}"
}

# ── Wait for a port to accept HTTP connections ─────────────────────────────────
wait_for_port() {
    local port=$1
    local max_attempts=${2:-90}
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if curl -s -o /dev/null --connect-timeout 1 "http://127.0.0.1:${port}/" 2>/dev/null; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    return 1
}

# ── Watchdog: restart any backend that has died ────────────────────────────────
watchdog() {
    while true; do
        sleep 30
        for name in "${!MCP_COMMANDS[@]}"; do
            local port="${MCP_PORTS[$name]}"
            local pidfile="/var/run/${name}.pid"
            local alive=0
            if [ -f "$pidfile" ]; then
                local pid
                pid=$(cat "$pidfile")
                if kill -0 "$pid" 2>/dev/null; then
                    alive=1
                fi
            fi
            if [ $alive -eq 0 ]; then
                echo "[watchdog] ${name} (port ${port}) is down — restarting..."
                local log_file="/var/log/mcp/${name}.log"
                echo "$(date '+%Y-%m-%d %H:%M:%S'): [watchdog] Restarting ${name}" >> "$log_file"
                npx supergateway \
                    --stdio "${MCP_COMMANDS[$name]}" \
                    --outputTransport streamableHttp \
                    --port "${port}" \
                    --streamableHttpPath /mcp \
                    >> "$log_file" 2>&1 &
                local new_pid=$!
                echo $new_pid > "$pidfile"
                echo "[watchdog] ${name} restarted with PID ${new_pid}"
            fi
        done
    done
}

STARTED=0

# ── Virtual display (Xvfb) for headless browser support ───────────────────────
# Playwright's chromium works in --headless mode without a display, but some
# code paths (and the system Chrome) still check $DISPLAY. Xvfb satisfies that.
if command -v Xvfb >/dev/null 2>&1; then
    Xvfb :99 -screen 0 1280x960x24 -ac +extension GLX +render -noreset \
        >> /var/log/mcp/xvfb.log 2>&1 &
    export DISPLAY=:99
    sleep 1
    echo "[+] Started virtual display on :99"
fi

# ── Playwright MCP ────────────────────────────────────────────────────────────
# Uses Playwright's bundled Chromium (--browser chromium) which runs headless
# in Docker without a display server, unlike system Chrome (--browser chrome).
if [ "${ENABLE_PLAYWRIGHT}" = "true" ]; then
    start_mcp "playwright" 8081 \
        "npx @playwright/mcp@latest --headless --isolated --no-sandbox --browser chromium"
    STARTED=$((STARTED + 1))
fi

# ── Filesystem MCP ────────────────────────────────────────────────────────────
if [ "${ENABLE_FILESYSTEM}" = "true" ]; then
    start_mcp "filesystem" 8082 \
        "npx @modelcontextprotocol/server-filesystem /workspace"
    STARTED=$((STARTED + 1))
fi

# ── Sequential Thinking MCP ──────────────────────────────────────────────────
if [ "${ENABLE_SEQUENTIAL_THINKING}" = "true" ]; then
    start_mcp "sequential-thinking" 8083 \
        "npx @modelcontextprotocol/server-sequential-thinking"
    STARTED=$((STARTED + 1))
fi

# ── Memory MCP ────────────────────────────────────────────────────────────────
if [ "${ENABLE_MEMORY}" = "true" ]; then
    export MEMORY_FILE_PATH="${MEMORY_FILE_PATH:-/data/memory.jsonl}"
    start_mcp "memory" 8084 \
        "npx @modelcontextprotocol/server-memory"
    STARTED=$((STARTED + 1))
fi

# ── GitHub MCP ────────────────────────────────────────────────────────────────
if [ "${ENABLE_GITHUB}" = "true" ]; then
    if [ -z "${GITHUB_PERSONAL_ACCESS_TOKEN}" ]; then
        echo "[!] WARNING: ENABLE_GITHUB=true but GITHUB_PERSONAL_ACCESS_TOKEN is not set. Skipping."
    else
        start_mcp "github" 8085 \
            "npx @modelcontextprotocol/server-github"
        STARTED=$((STARTED + 1))
    fi
fi

# ── SearXNG MCP ──────────────────────────────────────────────────────────────
if [ "${ENABLE_SEARXNG}" = "true" ]; then
    if [ -z "${SEARXNG_SERVER_URL}" ]; then
        echo "[!] WARNING: ENABLE_SEARXNG=true but SEARXNG_SERVER_URL is not set. Skipping."
    else
        export SEARXNG_URL="${SEARXNG_SERVER_URL}"
        start_mcp "searxng" 8086 \
            "npx mcp-searxng"
        STARTED=$((STARTED + 1))
    fi
fi

# ── Context7 MCP ─────────────────────────────────────────────────────────────
if [ "${ENABLE_CONTEXT7}" = "true" ]; then
    start_mcp "context7" 8087 \
        "npx @upstash/context7-mcp"
    STARTED=$((STARTED + 1))
fi

# ── Python Interpreter MCP ───────────────────────────────────────────────────
if [ "${ENABLE_PYTHON_INTERPRETER}" = "true" ]; then
    start_mcp "python-interpreter" 8088 \
        "node /app/python-interpreter.mjs"
    STARTED=$((STARTED + 1))
fi

# ── YouTube Transcriber MCP ──────────────────────────────────────────────────
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

# ── Video Doc MCP ─────────────────────────────────────────────────────────────
if [ "${ENABLE_VIDEO_DOC}" = "true" ]; then
    start_mcp "video-doc" 8092 \
        "python3 /app/video_doc_mcp.py"
    STARTED=$((STARTED + 1))
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

# Wait for each started backend to accept connections before starting the gateway.
# This prevents ECONNREFUSED errors during the startup race.
if [ ${#STARTED_PORTS[@]} -gt 0 ]; then
    echo "Waiting for backends to be ready..."
    for port in "${STARTED_PORTS[@]}"; do
        if wait_for_port "$port"; then
            echo "  Port ${port} ready."
        else
            echo "  WARNING: Port ${port} did not become ready within 90s — continuing anyway."
        fi
    done
fi

# Start watchdog in background so dead backends are auto-restarted
watchdog &
WATCHDOG_PID=$!

# ── Start the gateway ─────────────────────────────────────────────────────────
echo "Starting MCP Gateway on port 8080..."
cd /app && node gateway.js &
GATEWAY_PID=$!

# Graceful shutdown: kill all children on SIGTERM/SIGINT
shutdown() {
    echo ""
    echo "Shutting down MCP Gateway..."
    for pidfile in /var/run/*.pid; do
        if [ -f "$pidfile" ]; then
            kill "$(cat "$pidfile")" 2>/dev/null || true
        fi
    done
    kill $WATCHDOG_PID 2>/dev/null || true
    kill $GATEWAY_PID 2>/dev/null || true
    exit 0
}
trap shutdown INT TERM

# Keep the container alive
wait $GATEWAY_PID
