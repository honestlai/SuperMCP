#!/bin/bash

echo "Testing MCP Gateway"
echo "==================="

# Check if container is running
echo "Checking container status..."
if docker ps | grep -q "SuperMCP"; then
    echo "  Container is running"
else
    echo "  ERROR: Container is not running"
    echo "  Start it with: docker compose up -d"
    exit 1
fi

# Check gateway health
echo "Checking gateway health..."
HEALTH=$(curl -sf http://localhost:8080/health 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "  Gateway is healthy"
    echo "  Response: $HEALTH"
else
    echo "  ERROR: Gateway not responding on port 8080"
    echo "  Check logs: docker logs SuperMCP"
    exit 1
fi

# Check active MCPs
echo ""
echo "Active MCP servers:"
echo "$HEALTH" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    mcps = data.get('activeMcps', [])
    if not mcps:
        print('  (none enabled)')
    for name in mcps:
        print(f'  - {name}  ->  http://localhost:8080/{name}')
except:
    print('  Could not parse health response')
" 2>/dev/null || echo "  $HEALTH"

echo ""
echo "Container Information:"
echo "  Name:   SuperMCP"
echo "  Status: $(docker inspect --format='{{.State.Status}}' SuperMCP 2>/dev/null || echo 'unknown')"
echo "  Health: $(docker inspect --format='{{.State.Health.Status}}' SuperMCP 2>/dev/null || echo 'unknown')"
echo "  Port:   8080"
echo ""
echo "Configure your MCP client using the URLs above."
echo "Full config example: cursor-mcp-config.json"
