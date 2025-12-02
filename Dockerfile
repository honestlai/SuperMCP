FROM mcr.microsoft.com/playwright:v1.40.0-focal

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# Install system dependencies and Node.js
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    sqlite3 \
    gnupg \
    ca-certificates \
    && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install MCP servers
RUN npm install -g @playwright/mcp@latest \
    @modelcontextprotocol/server-filesystem@latest \
    @ahmetbarut/mcp-database-server@latest

# Install Playwright browsers (Chromium only for headless mode)
# Chromium comes bundled with Playwright and is optimized for headless automation
RUN npx playwright install chromium --with-deps

# Create workspace directory with proper permissions
RUN mkdir -p /workspace /data && \
    chmod 755 /workspace && \
    chmod 755 /data

# Set working directory
WORKDIR /workspace

# Expose ports for MCP servers
EXPOSE 8081 8082 8083

# Health check
COPY healthcheck.sh /healthcheck.sh
RUN chmod +x /healthcheck.sh

# Copy startup script and HTTP server files
COPY start-mcps.sh /start-mcps.sh
COPY filesystem-server.js /filesystem-server.js
COPY database-server.js /database-server.js
RUN chmod +x /start-mcps.sh

# Create necessary directories
RUN mkdir -p /var/log/mcp /var/run

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD /healthcheck.sh

# Default command - start MCP servers
CMD ["/start-mcps.sh"]
