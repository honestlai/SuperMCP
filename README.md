# MCP Gateway

**One container. One port. Every MCP your AI coding agent needs.**

MCP Gateway is a self-hosted Docker container that bundles eleven of the most useful MCP (Model Context Protocol) servers behind a single HTTP endpoint. Nothing runs by default. You pick what you need, flip an environment variable, and your AI agent gets instant access to browser automation, file operations, web search, GitHub, persistent memory, and more -- all through clean, predictable URLs.

```
http://your-server:8080/playwright
http://your-server:8080/filesystem
http://your-server:8080/memory
http://your-server:8080/github
http://your-server:8080/context7
...
```

No juggling ports. No managing separate containers. No figuring out which MCP package supports HTTP and which one only speaks stdio. The gateway handles all of that for you.

---

## Why This Exists

If you've spent any time building with AI coding agents, you've probably hit the same wall: the agent is brilliant at writing code, but it can't browse the web, can't touch the filesystem, can't search documentation, can't look at your GitHub issues. Each of those capabilities lives in its own MCP server, each with its own setup, its own transport quirks, and its own container or process to manage.

This project started as a way to solve that problem for my own workflow. I wanted to sit down, open Cursor, and have everything available -- browser automation for testing, filesystem access for reading and writing code, memory for context that persists across sessions, web search for looking things up, and GitHub integration for managing repos. I didn't want to run five containers and remember five different port numbers.

The result is a single Docker image that pre-installs all eleven MCP servers at build time, but starts none of them. You control exactly what runs through environment variables in your `docker-compose.yml`. The internal gateway takes care of bridging each server to HTTP and exposing it on a clean URL path. Your AI agent just connects to `http://your-server:8080/playwright` and it works.

---

## What's Inside

| Server | Path | What It Does |
|--------|------|--------------|
| **Playwright** | `/playwright` | Full browser automation -- navigate pages, click buttons, fill forms, take screenshots, scrape content, test web apps |
| **Filesystem** | `/filesystem` | Read, write, move, and search files and directories within your mounted `/workspace` |
| **Sequential Thinking** | `/sequential-thinking` | Gives your agent a structured way to reason through complex, multi-step problems before acting |
| **Memory** | `/memory` | A persistent knowledge graph that survives across sessions -- your agent can remember things |
| **GitHub** | `/github` | Full GitHub API access -- create repos, manage issues and PRs, read code, search across repositories |
| **SearXNG** | `/searxng` | Privacy-respecting web search through your own SearXNG instance |
| **Context7** | `/context7` | Pulls up-to-date documentation for libraries and frameworks, so your agent isn't working from stale training data |
| **Python Interpreter** | `/python-interpreter` | Executes Python 3 code directly inside the container and returns the output |
| **YouTube Transcriber** | `/youtube-transcriber` | Downloads YouTube audio and transcribes it using any Whisper-compatible API (OpenAI, Groq, Fireworks, or custom) |
| **Fetch** | `/fetch` | Fetches any URL and returns the content as clean markdown -- great for reading docs, calling APIs, checking live pages |
| **Git** | `/git` | Local git operations on your `/workspace` repo -- status, diff, commit, branch, log, checkout, and more |
| **Video Doc** | `/video-doc` | Processes video recordings (Zoom, Loom, Google Drive, Vimeo, direct mp4) into structured markdown documents with transcript, AI summary, action items, and embedded screenshots |

Every server is an official or well-maintained community MCP package, pre-installed in the image and ready to go. You just decide which ones to turn on.

A SearXNG search engine instance is also bundled in the `docker-compose.yml` as a separate service, so web search works out of the box with no extra setup.

---

## How It Works

The architecture is straightforward. A single Express.js gateway listens on port 8080 and routes incoming requests to internal MCP backends based on the URL path.

Most MCP servers only support stdio transport (they read from stdin and write to stdout). The gateway uses [supergateway](https://www.npmjs.com/package/supergateway) to bridge each one into an HTTP endpoint using the MCP Streamable HTTP transport. The result is that every server, regardless of its native transport, is accessible over plain HTTP.

```
Your AI Agent
     |
     |  POST http://server:8080/filesystem
     |
     v
 ┌────────────────────────────────────────────────────┐
 │  Docker Container                                  │
 │                                                    │
 │  Express Gateway (:8080)                           │
 │     |                                              │
 │     |  path-based routing                          │
 │     |                                              │
 │     ├── /playwright ──> supergateway (:8081)       │
 │     ├── /filesystem ──> supergateway (:8082)       │
 │     ├── /sequential-thinking ──> supergateway (:8083)│
 │     ├── /memory ──────> supergateway (:8084)       │
 │     ├── /github ──────> supergateway (:8085)       │
 │     ├── /searxng ─────> supergateway (:8086)       │
 │     ├── /context7 ────> supergateway (:8087)       │
 │     ├── /python-interpreter ──> supergateway (:8088)│
 │     ├── /youtube-transcriber ──> supergateway (:8089)│
 │     ├── /fetch ─────────────> supergateway (:8090)│
 │     ├── /git ────────────────> supergateway (:8091)│
 │     └── /video-doc ─────────> supergateway (:8092)│
 │                                                    │
 └────────────────────────────────────────────────────┘
```

On startup, the container reads your environment variables, launches only the servers you've enabled, and waits until every backend is actually accepting connections before starting the gateway. This prevents the proxy errors that would otherwise occur if the gateway raced ahead of a slow-starting MCP server. A background watchdog then monitors each backend and automatically restarts any that die, so a single crashed server doesn't leave its endpoint permanently broken.

Each Node.js process is capped at a 256 MB heap (`NODE_OPTIONS=--max-old-space-size=256`) to reduce memory pressure when many servers are running simultaneously.

If you haven't enabled anything, the gateway still runs -- it just serves a helpful index page telling you how to turn things on.

---

## Getting Started

### Prerequisites

- Docker and Docker Compose
- A Docker network for the container (create it once: `docker network create Network-Bridge`)

### 1. Clone the repo

```bash
git clone https://github.com/honestlai/SuperMCP.git
cd SuperMCP
```

### 2. Choose your servers

Open `docker-compose.yml` and uncomment the servers you want. For example, to enable Playwright, Filesystem, and Memory:

```yaml
environment:
  - PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
  - ENABLE_PLAYWRIGHT=true
  - ENABLE_FILESYSTEM=true
  - ENABLE_MEMORY=true
```

That's it. Those three servers will start when the container comes up. Everything else stays off.

### 3. Build and start

```bash
docker compose up -d --build
```

The first build takes a few minutes (it's installing browsers, npm packages, and Python). Subsequent starts are fast.

### 4. Verify it's running

```bash
curl http://localhost:8080/health
```

You should get back something like:

```json
{
  "status": "healthy",
  "service": "MCP Gateway",
  "activeMcps": ["playwright", "filesystem", "memory"],
  "endpoints": ["/playwright", "/filesystem", "/memory"]
}
```

### 5. Point your AI agent at it

In Cursor, VS Code, or whatever MCP-compatible client you use, add the servers:

```json
{
  "mcpServers": {
    "SuperMCP_Playwright": {
      "url": "http://localhost:8080/playwright"
    },
    "SuperMCP_Filesystem": {
      "url": "http://localhost:8080/filesystem"
    },
    "SuperMCP_Memory": {
      "url": "http://localhost:8080/memory"
    }
  }
}
```

**Important:** Use unique names like `SuperMCP_Playwright` instead of generic names like `playwright` or `filesystem`. Some MCP clients (including Cursor) may recognize generic names and attempt to run the server locally via stdio instead of connecting to your remote URL. Prefixing with `SuperMCP_` avoids this.

Replace `localhost` with your server's IP address if you're connecting remotely. Do **not** add trailing slashes to the URLs. A full example with all eleven servers is in `cursor-mcp-config.json`.

### Claude Desktop (Claude App)

Claude Desktop does not support remote HTTP MCP servers directly; it expects stdio-based servers. Use a local bridge (mcp-proxy or an npm adapter) so Claude talks stdio and the bridge talks Streamable HTTP to your gateway.

**Config file location:** [MCP Debugging guide](https://modelcontextprotocol.io/legacy/tools/debugging) recommends using **absolute paths** for `command`, because Claude may be started from anywhere and the working directory can be undefined.

- **macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Linux:** `~/.config/Claude/claude_desktop_config.json`

You can also open it from Claude Desktop: **Settings → Developer → Edit Config**.

---

**Option A: Python 3 + pip (no uv/uvx)** — works on any system with Python 3.

1. Install the bridge once:

   ```bash
   pip install mcp-proxy
   # or: pip3 install mcp-proxy
   ```

2. Find the full path to `python3` (use this in config so Claude finds it even with a minimal PATH):

   ```bash
   which python3
   # e.g. /opt/homebrew/bin/python3 or /usr/bin/python3
   ```

3. In `claude_desktop_config.json`, use that path as `command` and run mcp-proxy as a module:

   **Without API key:**

   ```json
   {
     "mcpServers": {
       "SuperMCP_Memory": {
         "command": "/opt/homebrew/bin/python3",
         "args": [
           "-m", "mcp_proxy",
           "--transport", "streamablehttp",
           "https://your-gateway.example.com/memory"
         ]
       }
     }
   }
   ```

   **With API key** (when `GATEWAY_API_KEY` is set on the gateway), add `env` with `API_ACCESS_TOKEN` (mcp-proxy sends it as `Authorization: Bearer <token>`):

   ```json
   {
     "mcpServers": {
       "SuperMCP_Memory": {
         "command": "/opt/homebrew/bin/python3",
         "args": [
           "-m", "mcp_proxy",
           "--transport", "streamablehttp",
           "https://your-gateway.example.com/memory"
         ],
         "env": {
           "API_ACCESS_TOKEN": "your-gateway-api-key-here"
         }
       }
     }
   }
   ```

   Use your actual `python3` path (e.g. `/usr/bin/python3` on Linux) and replace `https://your-gateway.example.com` with your SuperMCP base URL. Use the same value for `API_ACCESS_TOKEN` as `GATEWAY_API_KEY` in docker-compose.

---

**Option B: uvx** (if you already use [uv](https://github.com/astral-sh/uv)):

Use the **full path** to `uvx` so Claude can spawn it (e.g. `/opt/homebrew/bin/uvx` on macOS):

```json
{
  "mcpServers": {
    "SuperMCP_Memory": {
      "command": "/opt/homebrew/bin/uvx",
      "args": ["mcp-proxy", "--transport", "streamablehttp", "https://your-gateway.example.com/memory"],
      "env": { "API_ACCESS_TOKEN": "your-gateway-api-key-here" }
    }
  }
}
```

---

**Option C: Node.js (npx)** — alternative bridge that uses env vars for URL and token.

Install not required; npx runs it on demand. Prefer a **full path** to `npx` (e.g. `/opt/homebrew/bin/npx`) if you see “No such file or directory” when Claude starts the server.

- **URI** (required): your SuperMCP endpoint URL  
- **BEARER_TOKEN** (optional): same as your gateway `GATEWAY_API_KEY`

```json
{
  "mcpServers": {
    "SuperMCP_Memory": {
      "command": "/opt/homebrew/bin/npx",
      "args": ["-y", "@pyroprompts/mcp-stdio-to-streamable-http-adapter"],
      "env": {
        "URI": "https://your-gateway.example.com/memory",
        "BEARER_TOKEN": "your-gateway-api-key-here"
      }
    }
  }
}
```

---

**Troubleshooting:** If logs show `Failed to spawn process: No such file or directory`, Claude is not finding the executable. Use the **absolute path** for `command` (e.g. `/opt/homebrew/bin/python3`, `/usr/bin/python3`, or `/opt/homebrew/bin/npx`) instead of `python3` or `uvx`. See the [MCP Debugging guide](https://modelcontextprotocol.io/legacy/tools/debugging) for more. After config changes, fully quit and reopen Claude Desktop.

---

## Configuration Reference

### API key authentication

If you're exposing the gateway to a network (especially the internet), you should protect it with an API key. Set `GATEWAY_API_KEY` in your `docker-compose.yml`:

```yaml
environment:
  - GATEWAY_API_KEY=my-secret-key-here
```

When set, every request to an MCP endpoint must include a Bearer token:

```
Authorization: Bearer my-secret-key-here
```

In your Cursor / VS Code MCP config, add a `headers` block to each server:

```json
{
  "mcpServers": {
    "SuperMCP_Playwright": {
      "url": "http://your-server:8080/playwright",
      "headers": {
        "Authorization": "Bearer my-secret-key-here"
      }
    }
  }
}
```

Requests without a valid token receive a `401 Unauthorized` response. The `/health` endpoint remains open so Docker healthchecks continue to work. If `GATEWAY_API_KEY` is not set, the gateway runs open with no authentication (fine for local-only use).

- **Cursor / VS Code:** use the `headers` block with `Authorization: Bearer <key>` as in the example above.
- **Claude Desktop:** use mcp-proxy and set `API_ACCESS_TOKEN` in the `env` block for each server (see [Claude Desktop (Claude App)](#claude-desktop-claude-app)).

### Enabling servers

Every server is controlled by a single environment variable. Some servers need additional configuration (API keys, URLs). Set these in the `environment` section of your `docker-compose.yml`:

| Server | Enable With | Additional Config |
|--------|------------|-------------------|
| Playwright | `ENABLE_PLAYWRIGHT=true` | -- |
| Filesystem | `ENABLE_FILESYSTEM=true` | -- |
| Sequential Thinking | `ENABLE_SEQUENTIAL_THINKING=true` | -- |
| Memory | `ENABLE_MEMORY=true` | `MEMORY_FILE_PATH` (optional, defaults to `/data/memory.jsonl`) |
| GitHub | `ENABLE_GITHUB=true` | `GITHUB_PERSONAL_ACCESS_TOKEN` (required) |
| SearXNG | `ENABLE_SEARXNG=true` | `SEARXNG_SERVER_URL` (required, e.g. `http://searxng:8080`) |
| Context7 | `ENABLE_CONTEXT7=true` | `CONTEXT7_API_KEY` (optional, for higher rate limits) |
| Python Interpreter | `ENABLE_PYTHON_INTERPRETER=true` | -- |
| YouTube Transcriber | `ENABLE_YOUTUBE_TRANSCRIBER=true` | `TRANSCRIBER_API_KEY` + `TRANSCRIBER_PROVIDER` (see [YouTube Transcriber config](#youtube-transcriber-configuration)) |
| Fetch | `ENABLE_FETCH=true` | -- |
| Git | `ENABLE_GIT=true` | Requires `/workspace` to be a git repository |
| Video Doc | `ENABLE_VIDEO_DOC=true` | `VISION_API_KEY` + `VISION_BASE_URL` + `VISION_MODEL` (see [Video Doc configuration](#video-doc-configuration)); shares `TRANSCRIBER_API_KEY` with YouTube Transcriber |

If you enable a server that requires an API key but don't provide one, the startup script will log a warning and skip that server. Nothing crashes.

**Note on SearXNG:** The `docker-compose.yml` includes a bundled SearXNG instance with a Valkey cache as companion services. They start automatically alongside the gateway on the same Docker network. When you enable SearXNG, set `SEARXNG_SERVER_URL=http://searxng:8080` and it will connect to the bundled instance. If you already run your own SearXNG elsewhere, point the URL there instead and remove the `searxng` and `valkey` services from the compose file.

**Note on Context7:** Context7 works without an API key, but with lower rate limits. The MCP server runs locally but connects to Context7's hosted backend for documentation data. You can get a free API key at [context7.com](https://context7.com) for higher rate limits -- the backend itself is not self-hostable.

**Note on Git:** The Git MCP requires `/workspace` to contain an initialized git repository. If the workspace volume is empty or doesn't contain a `.git` directory, the Git MCP will fail to respond. Clone or init a repo in the workspace first, or skip enabling this server if you don't need it.

### YouTube Transcriber configuration

The YouTube Transcriber downloads audio from a YouTube URL with `yt-dlp` and transcribes it using a Whisper-compatible speech-to-text API. It works with any provider that offers an OpenAI-compatible `/audio/transcriptions` endpoint.

#### Environment variables

| Variable | Required | Description |
|----------|----------|-------------|
| `TRANSCRIBER_API_KEY` | **Yes** | API key for your chosen provider |
| `TRANSCRIBER_PROVIDER` | No | Provider preset: `openai`, `fireworks`, or `groq`. Auto-configures the base URL and model. |
| `TRANSCRIBER_BASE_URL` | No | Override the API base URL (for custom/self-hosted endpoints) |
| `TRANSCRIBER_MODEL` | No | Override the default Whisper model name |

If you set `TRANSCRIBER_PROVIDER`, the base URL and model are filled in automatically. You can still override either one individually. If you don't set a provider, the base URL and model must be supplied explicitly (or they default to OpenAI).

The legacy `FIREWORKS_API_KEY` variable still works -- if set without any `TRANSCRIBER_*` variables, it auto-selects the Fireworks provider.

#### Built-in provider presets

| Provider | `TRANSCRIBER_PROVIDER` | Default Model | API Base URL |
|----------|----------------------|---------------|--------------|
| OpenAI | `openai` | `whisper-1` | `https://api.openai.com/v1` |
| Fireworks AI | `fireworks` | `whisper-v3` | `https://api.fireworks.ai/inference/v1` |
| Groq | `groq` | `whisper-large-v3-turbo` | `https://api.groq.com/openai/v1` |

#### Examples

**Groq** (fast and free tier available):

```yaml
- ENABLE_YOUTUBE_TRANSCRIBER=true
- TRANSCRIBER_PROVIDER=groq
- TRANSCRIBER_API_KEY=gsk_your_groq_key_here
```

**OpenAI**:

```yaml
- ENABLE_YOUTUBE_TRANSCRIBER=true
- TRANSCRIBER_PROVIDER=openai
- TRANSCRIBER_API_KEY=sk-your_openai_key_here
```

**Fireworks AI**:

```yaml
- ENABLE_YOUTUBE_TRANSCRIBER=true
- TRANSCRIBER_PROVIDER=fireworks
- TRANSCRIBER_API_KEY=fw_your_fireworks_key_here
```

**Custom / self-hosted endpoint** (e.g. a local Whisper server):

```yaml
- ENABLE_YOUTUBE_TRANSCRIBER=true
- TRANSCRIBER_API_KEY=any-value
- TRANSCRIBER_BASE_URL=http://my-whisper-server:8000/v1
- TRANSCRIBER_MODEL=whisper-large-v3
```

**Groq with a specific model override**:

```yaml
- ENABLE_YOUTUBE_TRANSCRIBER=true
- TRANSCRIBER_PROVIDER=groq
- TRANSCRIBER_API_KEY=gsk_your_groq_key_here
- TRANSCRIBER_MODEL=whisper-large-v3
```

### Video Doc configuration

The Video Doc MCP downloads a video from a URL (or reads a local file), transcribes the audio, samples keyframes with scene-change detection, analyzes each frame with a vision model, and produces a structured markdown document with summary, action items, and embedded screenshots.

**Input:** any URL supported by yt-dlp (Zoom cloud recordings, Loom shares, Google Drive, Vimeo, direct `.mp4` links, 500+ platforms), or a local file path under `/workspace`.

**Output:** a markdown file written to `/workspace/outputs/`.

Every model endpoint uses the standard OpenAI-compatible API — you can swap providers without any code changes.

#### Configuration — unified provider (recommended)

Set `LLM_API_KEY` and `LLM_BASE_URL` once and all three AI tasks (vision, summary, transcription) use that provider automatically. Then set only the model names per task — no separate API keys needed.

```yaml
# One provider for everything
- LLM_API_KEY=your_api_key_here
- LLM_BASE_URL=https://api.fireworks.ai/inference/v1

# Model per task (all on the same provider)
- VISION_MODEL=accounts/fireworks/models/qwen2-vl-72b-instruct
- SUMMARY_MODEL=accounts/fireworks/models/llama4-scout-instruct-basic
- TRANSCRIBER_MODEL=whisper-v3
```

#### Provider and model recommendations

| Provider | `LLM_BASE_URL` | `VISION_MODEL` (best) | `VISION_MODEL` (budget) | `SUMMARY_MODEL` (budget) | `TRANSCRIBER_MODEL` |
|----------|---------------|----------------------|------------------------|--------------------------|---------------------|
| **Fireworks AI** | `https://api.fireworks.ai/inference/v1` | `accounts/fireworks/models/qwen2-vl-72b-instruct` | `accounts/fireworks/models/qwen2-vl-7b-instruct` | `accounts/fireworks/models/llama4-scout-instruct-basic` | `whisper-v3` |
| **OpenAI** | `https://api.openai.com/v1` | `gpt-4o` | `gpt-4o-mini` | `gpt-4o-mini` | `whisper-1` |
| **Together AI** | `https://api.together.xyz/v1` | `Qwen/Qwen2-VL-72B-Instruct` | `Qwen/Qwen2-VL-7B-Instruct` | `meta-llama/Llama-3.1-8B-Instruct-Turbo` | *(no Whisper — use Groq)* |
| **Ollama (local)** | `http://ollama:11434/v1` | `qwen2-vl:32b` | `qwen2-vl:7b` | `qwen3:4b` | *(no Whisper — use Groq)* |

> **Cost tip:** `VISION_MODEL` is called once per sampled frame (up to `max_frames`). `SUMMARY_MODEL` is called once per video. Always set `SUMMARY_MODEL` to a fast cheap text model — it dramatically cuts cost with no quality impact on the summary.

> **Transcription:** If your vision provider has no Whisper endpoint (Together AI, Ollama), set `TRANSCRIBER_API_KEY` and `TRANSCRIBER_BASE_URL` explicitly to Groq or OpenAI. Groq's `whisper-large-v3-turbo` is the fastest and cheapest option.

#### Advanced: per-service provider overrides

If you want different providers for different tasks, set the service-specific vars — they take priority over the unified `LLM_*` vars:

| Variable | Overrides | Description |
|----------|-----------|-------------|
| `VISION_API_KEY` | `LLM_API_KEY` | API key for frame analysis only |
| `VISION_BASE_URL` | `LLM_BASE_URL` | Base URL for frame analysis only |
| `VISION_MODEL` | — | Vision model name (always required) |
| `SUMMARY_API_KEY` | `VISION_API_KEY` → `LLM_API_KEY` | API key for summarization only |
| `SUMMARY_BASE_URL` | `VISION_BASE_URL` → `LLM_BASE_URL` | Base URL for summarization only |
| `SUMMARY_MODEL` | `VISION_MODEL` | Summary model name |
| `TRANSCRIBER_API_KEY` | `LLM_API_KEY` | API key for transcription only |
| `TRANSCRIBER_BASE_URL` | `LLM_BASE_URL` → Groq default | Base URL for transcription only |
| `TRANSCRIBER_MODEL` | — | Whisper model name |

Example — Fireworks AI for vision, Groq for transcription (cheapest combo):
```yaml
- LLM_API_KEY=fw_your_fireworks_key
- LLM_BASE_URL=https://api.fireworks.ai/inference/v1
- VISION_MODEL=accounts/fireworks/models/qwen2-vl-72b-instruct
- SUMMARY_MODEL=accounts/fireworks/models/llama4-scout-instruct-basic
- TRANSCRIBER_API_KEY=gsk_your_groq_key
- TRANSCRIBER_BASE_URL=https://api.groq.com/openai/v1
- TRANSCRIBER_MODEL=whisper-large-v3-turbo
```

#### Example usage (after enabling)

```
# Zoom cloud recording
process_video("https://zoom.us/rec/share/xxxx", "meeting")

# Loom recording
process_video("https://www.loom.com/share/xxxx", "discovery")

# Google Drive video share
process_video("https://drive.google.com/file/d/xxxx/view", "howto")

# Local file (mount it into the workspace volume first)
process_video("/workspace/call-recording.mp4", "meeting")
```

`doc_type` options: `meeting`, `discovery`, `howto`, `general`.

**Private links:** if the URL requires a login, mount a Netscape-format cookies file into the container and set `YTDLP_COOKIES_FILE` to its path.

---

### Full configuration example

Here's what it looks like with everything turned on:

```yaml
environment:
  - PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
  # Core servers
  - ENABLE_PLAYWRIGHT=true
  - ENABLE_FILESYSTEM=true
  - ENABLE_SEQUENTIAL_THINKING=true
  - ENABLE_MEMORY=true
  - ENABLE_PYTHON_INTERPRETER=true
  # GitHub
  - ENABLE_GITHUB=true
  - GITHUB_PERSONAL_ACCESS_TOKEN=ghp_your_token_here
  # Web search
  - ENABLE_SEARXNG=true
  - SEARXNG_SERVER_URL=http://searxng:8080
  # Documentation lookup
  - ENABLE_CONTEXT7=true
  - CONTEXT7_API_KEY=your_key_here
  # YouTube transcription (pick your provider -- see YouTube Transcriber section above)
  - ENABLE_YOUTUBE_TRANSCRIBER=true
  - TRANSCRIBER_PROVIDER=groq
  - TRANSCRIBER_API_KEY=your_api_key_here
  # Web fetching and local git
  - ENABLE_FETCH=true
  - ENABLE_GIT=true
  # Video Doc — set LLM_API_KEY + LLM_BASE_URL once, all tasks use that provider
  - ENABLE_VIDEO_DOC=true
  - LLM_API_KEY=your_api_key_here
  - LLM_BASE_URL=https://api.fireworks.ai/inference/v1
  - VISION_MODEL=accounts/fireworks/models/qwen2-vl-72b-instruct
  - SUMMARY_MODEL=accounts/fireworks/models/llama4-scout-instruct-basic
  - TRANSCRIBER_MODEL=whisper-v3
```

### Volumes

```yaml
volumes:
  - workspace:/workspace:rw    # Your project files (used by Filesystem MCP)
  - data:/data:rw              # Persistent storage (Memory MCP stores data here)
```

### Ports

Only one port is exposed:

```yaml
ports:
  - "8080:8080"
```

If port 8080 is taken on your host, change the left side: `"9090:8080"` will make the gateway available at port 9090.

---

## Gateway Endpoints

| URL | What It Does |
|-----|--------------|
| `GET /` | Index page listing all active servers and their URLs |
| `GET /health` | JSON health check with the list of active servers |
| `/<server-name>` | MCP Streamable HTTP endpoint for that server |

The server names match exactly what you see in the table above: `playwright`, `filesystem`, `sequential-thinking`, `memory`, `github`, `searxng`, `context7`, `python-interpreter`, `youtube-transcriber`, `fetch`, `git`.

---

## Alternative: Docker Exec Mode

Every MCP package is installed globally in the container, so you can also connect to them directly via `docker exec` using stdio transport. This is useful for debugging or if your MCP client prefers stdio over HTTP:

```bash
docker exec -i SuperMCP npx @playwright/mcp@latest --headless --isolated --no-sandbox --browser chromium
docker exec -i SuperMCP npx @modelcontextprotocol/server-filesystem /workspace
docker exec -i SuperMCP npx @modelcontextprotocol/server-memory
docker exec -i SuperMCP npx @modelcontextprotocol/server-sequential-thinking
docker exec -i SuperMCP npx @modelcontextprotocol/server-github
docker exec -i SuperMCP python3 -m mcp_server_fetch
docker exec -i SuperMCP python3 -m mcp_server_git --repository /workspace
```

This works regardless of which servers are enabled via environment variables -- the packages are always there.

---

## Troubleshooting

**The health check says no servers are active**
You haven't uncommented any `ENABLE_*` lines in `docker-compose.yml`. Uncomment the ones you want, then restart: `docker compose up -d`.

**A specific server returns 502**
The backend crashed or is restarting. The watchdog will restart it automatically within 30 seconds. Check that server's log for the underlying error:

```bash
docker exec SuperMCP cat /var/log/mcp/playwright.log
docker exec SuperMCP cat /var/log/mcp/memory.log
```

**GitHub or SearXNG won't start**
These require additional environment variables. Make sure you've set both the `ENABLE_*` flag and the required key/URL. The container logs will show a warning if a required variable is missing:

```bash
docker logs SuperMCP | head -30
```

**Container won't start at all**
Check that port 8080 is free and the Docker network exists:

```bash
docker network create Network-Bridge    # if it doesn't exist
docker compose down
docker compose build --no-cache
docker compose up -d
```

**General debugging**

```bash
docker ps | grep SuperMCP                                             # is it running?
docker inspect --format='{{.State.Health.Status}}' SuperMCP           # is it healthy?
docker logs SuperMCP                                                   # what happened on startup?
curl http://localhost:8080/health                                     # what does the gateway say?
```

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

Adding a new MCP server involves four files: `Dockerfile` (install the package), `start-mcps.sh` (add the launch block), `gateway.js` (add to the registry), and `docker-compose.yml` (add the env var). The pattern is the same for every server.

## License

MIT License -- see the LICENSE file for details.

## Acknowledgments

- [Model Context Protocol](https://modelcontextprotocol.io/) for the specification that makes all of this possible
- [supergateway](https://www.npmjs.com/package/supergateway) for the stdio-to-HTTP bridge that ties everything together
- [Playwright](https://playwright.dev/) for browser automation
- The MCP community for building and maintaining these server packages
