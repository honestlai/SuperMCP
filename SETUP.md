# MCP Gateway Setup Guide

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/honestlai/SuperMCP.git
cd SuperMCP
```

### 2. Create the Docker Network (if it doesn't exist)

```bash
docker network create Network-Bridge
```

### 3. Enable Your MCP Servers

Edit `docker-compose.yml` and uncomment the servers you want to use. For example, to enable Playwright and Filesystem:

```yaml
environment:
  - PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
  - PLAYWRIGHT_CHROME_CHANNEL=chrome
  - PLAYWRIGHT_HEADLESS=true
  - ENABLE_PLAYWRIGHT=true
  - ENABLE_FILESYSTEM=true
```

### 4. Build and Start

```bash
docker compose up -d --build
```

### 5. Verify

```bash
curl http://localhost:8080/health
```

You should see a JSON response listing your active MCP servers.

### 6. Configure Your MCP Client

Copy the relevant entries from `cursor-mcp-config.json` to your Cursor or VS Code MCP settings. Only add entries for the servers you enabled.

## Container Information

- **Container Name**: `SuperMCP`
- **Gateway Port**: 8080
- **Access Pattern**: `http://<server>:8080/<mcp-name>`
- **Volumes**:
  - `/workspace` -- shared filesystem workspace
  - `/data` -- persistent data storage

## Available MCP Servers

| Server | Enable Variable | URL Path | Notes |
|--------|----------------|----------|-------|
| Playwright | `ENABLE_PLAYWRIGHT=true` | `/playwright` | Browser automation |
| Filesystem | `ENABLE_FILESYSTEM=true` | `/filesystem` | File operations on /workspace |
| Sequential Thinking | `ENABLE_SEQUENTIAL_THINKING=true` | `/sequential-thinking` | Step-by-step reasoning |
| Memory | `ENABLE_MEMORY=true` | `/memory` | Knowledge graph memory |
| GitHub | `ENABLE_GITHUB=true` | `/github` | Needs `GITHUB_PERSONAL_ACCESS_TOKEN` |
| SearXNG | `ENABLE_SEARXNG=true` | `/searxng` | Needs `SEARXNG_SERVER_URL` |
| Context7 | `ENABLE_CONTEXT7=true` | `/context7` | Optional: `CONTEXT7_API_KEY` |
| Python Interpreter | `ENABLE_PYTHON_INTERPRETER=true` | `/python-interpreter` | Execute Python 3 code |
| YouTube Transcriber | `ENABLE_YOUTUBE_TRANSCRIBER=true` | `/youtube-transcriber` | Needs `FIREWORKS_API_KEY` |
| Fetch | `ENABLE_FETCH=true` | `/fetch` | Fetch URLs as markdown |
| Git | `ENABLE_GIT=true` | `/git` | Local git operations on /workspace |

## Management Commands

```bash
# Start container
docker compose up -d

# Stop container
docker compose down

# Rebuild after changes
docker compose up -d --build

# View gateway logs
docker logs SuperMCP

# View individual MCP logs
docker exec SuperMCP cat /var/log/mcp/playwright.log

# Check health
curl http://localhost:8080/health

# Check status
docker ps | grep SuperMCP
```

## Troubleshooting

### Container Not Starting

```bash
# Check logs for errors
docker compose logs

# Rebuild from scratch
docker compose down
docker compose build --no-cache
docker compose up -d
```

### MCP Server Not Responding

- Verify the server is enabled in `docker-compose.yml`
- Check the server's log file inside the container
- Wait 10-15 seconds after container start for backends to initialize

### Port Conflicts

If port 8080 is already in use, change the host port in `docker-compose.yml`:

```yaml
ports:
  - "9090:8080"    # Use port 9090 instead
```

Then access servers at `http://localhost:9090/<name>`.

## Support

For issues and questions, please check the main README.md or create an issue on GitHub.
