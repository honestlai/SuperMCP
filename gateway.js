'use strict';

const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');

const app = express();
const PORT = 8080;

// MCP server registry: name -> { internal port, env var name }
// All backends serve MCP Streamable HTTP at /mcp via supergateway
const MCP_REGISTRY = {
  'playwright':          { port: 8081, envVar: 'ENABLE_PLAYWRIGHT' },
  'filesystem':          { port: 8082, envVar: 'ENABLE_FILESYSTEM' },
  'sequential-thinking': { port: 8083, envVar: 'ENABLE_SEQUENTIAL_THINKING' },
  'memory':              { port: 8084, envVar: 'ENABLE_MEMORY' },
  'github':              { port: 8085, envVar: 'ENABLE_GITHUB' },
  'searxng':             { port: 8086, envVar: 'ENABLE_SEARXNG' },
  'context7':            { port: 8087, envVar: 'ENABLE_CONTEXT7' },
  'python-interpreter':  { port: 8088, envVar: 'ENABLE_PYTHON_INTERPRETER' },
  'youtube-transcriber': { port: 8089, envVar: 'ENABLE_YOUTUBE_TRANSCRIBER' },
  'fetch':               { port: 8090, envVar: 'ENABLE_FETCH' },
  'git':                 { port: 8091, envVar: 'ENABLE_GIT' },
  'video-doc':           { port: 8092, envVar: 'ENABLE_VIDEO_DOC' },
};

// Determine active MCPs from environment variables
const activeMcps = {};
for (const [name, config] of Object.entries(MCP_REGISTRY)) {
  if (process.env[config.envVar] === 'true') {
    activeMcps[name] = config;
  }
}

const activeNames = Object.keys(activeMcps);
console.log(`Active MCP servers: ${activeNames.join(', ') || 'none'}`);

// ── API key authentication ───────────────────────────────────────────────────
// Set GATEWAY_API_KEY to require Bearer token auth on all MCP endpoints.
// If not set, the gateway runs open (no auth).
const API_KEY = process.env.GATEWAY_API_KEY || '';
if (API_KEY) {
  console.log('API key authentication: ENABLED');
} else {
  console.log('API key authentication: disabled (set GATEWAY_API_KEY to enable)');
}

// ── CORS middleware ──────────────────────────────────────────────────────────
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Accept, Authorization, Mcp-Session-Id, Last-Event-ID');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

// ── Health endpoint (always open, used by Docker healthcheck) ────────────────
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    service: 'MCP Gateway',
    auth: API_KEY ? 'enabled' : 'disabled',
    activeMcps: activeNames,
    endpoints: activeNames.map(name => `/${name}`),
  });
});

// ── Bearer token auth middleware ─────────────────────────────────────────────
// Applied to everything AFTER /health so Docker healthchecks don't need a token.
if (API_KEY) {
  app.use((req, res, next) => {
    const authHeader = req.headers['authorization'] || '';
    const match = authHeader.match(/^Bearer\s+(.+)$/i);
    if (!match || match[1] !== API_KEY) {
      return res.status(401).json({
        error: 'Unauthorized',
        message: 'Valid Bearer token required. Set the Authorization header: Bearer <your-api-key>',
      });
    }
    next();
  });
}

// ── Index page ───────────────────────────────────────────────────────────────
app.get('/', (req, res) => {
  if (activeNames.length === 0) {
    res.type('text/plain').send(
      'MCP Gateway\n' +
      '===========\n\n' +
      'No MCP servers are currently enabled.\n\n' +
      'Enable servers by setting environment variables in docker-compose.yml:\n' +
      '  ENABLE_PLAYWRIGHT=true\n' +
      '  ENABLE_FILESYSTEM=true\n' +
      '  ENABLE_SEQUENTIAL_THINKING=true\n' +
      '  ENABLE_MEMORY=true\n' +
      '  ENABLE_GITHUB=true          (requires GITHUB_PERSONAL_ACCESS_TOKEN)\n' +
      '  ENABLE_SEARXNG=true         (requires SEARXNG_SERVER_URL)\n' +
      '  ENABLE_CONTEXT7=true        (optional: CONTEXT7_API_KEY)\n' +
      '  ENABLE_PYTHON_INTERPRETER=true\n' +
      '  ENABLE_YOUTUBE_TRANSCRIBER=true (requires TRANSCRIBER_API_KEY)\n' +
      '  ENABLE_FETCH=true\n' +
      '  ENABLE_GIT=true\n\n' +
      'Health check: /health\n'
    );
  } else {
    const mcpList = activeNames.map(name => `  ${name}  ->  http://<server>:${PORT}/${name}`).join('\n');
    res.type('text/plain').send(
      'MCP Gateway\n' +
      '===========\n\n' +
      'Active MCP Servers:\n' + mcpList + '\n\n' +
      'Health check: /health\n'
    );
  }
});

// ── Proxy routes for each active MCP ─────────────────────────────────────────
for (const [name, config] of Object.entries(activeMcps)) {
  const proxyMiddleware = createProxyMiddleware({
    target: `http://localhost:${config.port}`,
    changeOrigin: true,
    // Rewrite /<mcpname> to /mcp (supergateway serves at /mcp)
    pathRewrite: { '^/': '/mcp' },
    // Timeout settings
    proxyTimeout: 120000,
    timeout: 120000,
    on: {
      proxyRes: (proxyRes, req, res) => {
        // Disable buffering for SSE / streaming responses
        res.setHeader('X-Accel-Buffering', 'no');
      },
      error: (err, req, res) => {
        console.error(`[${name}] Proxy error: ${err.message}`);
        if (!res.headersSent) {
          res.writeHead(502, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({
            error: `MCP server '${name}' is not responding`,
            details: err.message,
          }));
        }
      },
    },
  });

  app.use(`/${name}`, proxyMiddleware);
  console.log(`  Route: /${name}  ->  http://localhost:${config.port}/mcp`);
}

// ── 404 handler ──────────────────────────────────────────────────────────────
app.use((req, res) => {
  res.status(404).json({
    error: 'Not found',
    hint: 'Available endpoints: /health, ' + activeNames.map(n => `/${n}`).join(', '),
  });
});

// ── Start server ─────────────────────────────────────────────────────────────
const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(`MCP Gateway listening on http://0.0.0.0:${PORT}`);
});
server.setMaxListeners(20);
