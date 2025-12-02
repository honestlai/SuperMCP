#!/bin/bash

# Start script for 3AmigosMCP container
# This script starts all three MCP servers in the background with detailed logging

echo "Starting 3AmigosMCP servers..."

# Create log directory
mkdir -p /var/log/mcp

# Ensure workspace directory has proper permissions
chmod 755 /workspace 2>/dev/null || true
chmod 755 /data 2>/dev/null || true

# Function to start MCP server with logging
start_mcp_server() {
    local name=$1
    local command=$2
    local port=$3
    
    echo "Starting $name on port $port..."
    echo "$(date): Starting $name server" >> /var/log/mcp/${name,,}.log
    
    # Start the server in background with logging
    $command >> /var/log/mcp/${name,,}.log 2>&1 &
    local pid=$!
    echo $pid > /var/run/${name,,}.pid
    
    echo "$(date): $name server started with PID $pid" >> /var/log/mcp/${name,,}.log
    echo "$name server started with PID $pid"
}

# Start Playwright MCP server on port 8081
start_mcp_server "Playwright" "npx @playwright/mcp@latest --headless --isolated --no-sandbox --browser chromium --port 8081" 8081

# Start simple HTTP server for Filesystem MCP on port 8082
start_mcp_server "Filesystem-HTTP" "node /filesystem-server.js" 8082

# Start simple HTTP server for Database MCP on port 8083
start_mcp_server "Database-HTTP" "node /database-server.js" 8083

# Note: Both Filesystem and Database MCP servers are available via stdio transport
# They will be started via docker exec commands as configured in cursor-mcp-config.json
echo "Filesystem and Database MCP servers are available via stdio transport"

echo "All MCP servers started. Logs available in /var/log/mcp/"
echo "Playwright MCP: http://localhost:8081"
echo "Filesystem MCP: http://localhost:8082"
echo "Database MCP: http://localhost:8083"

# Keep the container running and show logs
echo "Container logs will be displayed below. Press Ctrl+C to stop."
echo "================================================================"

# Function to monitor and display logs
monitor_logs() {
    while true; do
        echo "$(date): Container is running - MCP servers active"
        echo "Recent Playwright MCP logs:"
        tail -n 5 /var/log/mcp/playwright.log 2>/dev/null || echo "No logs yet"
        echo "Recent Filesystem MCP logs:"
        tail -n 5 /var/log/mcp/filesystem.log 2>/dev/null || echo "No logs yet"
        echo "Recent Database MCP logs:"
        tail -n 5 /var/log/mcp/database.log 2>/dev/null || echo "No logs yet"
        echo "================================================================"
        sleep 30
    done
}

# Start log monitoring in background
monitor_logs &
monitor_pid=$!

# Wait for interrupt signal
trap 'echo "Shutting down MCP servers..."; kill $(cat /var/run/*.pid 2>/dev/null) 2>/dev/null; kill $monitor_pid 2>/dev/null; exit 0' INT TERM

# Keep container running
wait
