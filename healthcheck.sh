#!/bin/bash

# Health check for MCP Gateway
# Verifies the gateway is responding on port 8080

if ! curl -sf http://localhost:8080/health > /dev/null 2>&1; then
    echo "MCP Gateway not responding on port 8080"
    exit 1
fi

echo "MCP Gateway is healthy"
exit 0
