FROM mcr.microsoft.com/playwright:v1.50.0-noble

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# Install base system dependencies + Python extras
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget git sqlite3 gnupg ca-certificates \
    software-properties-common ffmpeg \
    python3-pip python3-venv \
    xvfb \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages for MCP servers
RUN python3 -m pip install --no-cache-dir --break-system-packages \
    mcp openai yt-dlp mcp-server-fetch mcp-server-git \
    faster-whisper opencv-python-headless python-docx Pillow

# Install all MCP server packages globally
# These are installed at build time but only start when enabled via environment variables
RUN npm install -g \
    @playwright/mcp@latest \
    @modelcontextprotocol/server-filesystem@latest \
    @modelcontextprotocol/server-sequential-thinking@latest \
    @modelcontextprotocol/server-memory@latest \
    @modelcontextprotocol/server-github@latest \
    mcp-searxng@latest \
    @upstash/context7-mcp@latest \
    supergateway@latest

# Set up gateway application with dependencies
RUN mkdir -p /app && \
    echo '{"name":"mcp-gateway","private":true}' > /app/package.json && \
    cd /app && npm install express http-proxy-middleware@^3 @modelcontextprotocol/sdk zod

# Install Playwright browsers
RUN npx playwright install --with-deps

# Create directories
RUN mkdir -p /workspace /data /var/log/mcp /var/run && \
    chmod 755 /workspace /data

# Copy application files
COPY gateway.js /app/gateway.js
COPY python-interpreter.mjs /app/python-interpreter.mjs
COPY youtube_summerizer.py /app/youtube_transcriber.py
COPY video2doc_mcp.py /app/video2doc_mcp.py

# Copy scripts
COPY healthcheck.sh /healthcheck.sh
COPY start-mcps.sh /start-mcps.sh
RUN chmod +x /healthcheck.sh /start-mcps.sh

# Set working directory
WORKDIR /workspace

# Expose gateway port only
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /healthcheck.sh

# Default command - start MCP gateway
CMD ["/start-mcps.sh"]
