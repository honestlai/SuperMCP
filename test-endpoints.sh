#!/bin/bash
# Test all MCP endpoints via Streamable HTTP protocol
# Handles both plain JSON and SSE (text/event-stream) responses
# Usage: ./test-endpoints.sh [base_url]

BASE="${1:-http://localhost:9080}"
PASS=0
FAIL=0

# Extract JSON from response (handles both plain JSON and SSE format)
extract_json() {
    local response="$1"
    # If it starts with "event:", it's SSE - extract the data line
    if echo "$response" | grep -q "^event:"; then
        echo "$response" | grep "^data:" | head -1 | sed 's/^data: *//'
    else
        echo "$response"
    fi
}

test_mcp() {
    local name=$1
    local url="${BASE}/${name}"
    
    # Step 1: Initialize
    local raw_response
    raw_response=$(curl -sf --max-time 15 -X POST "$url" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json, text/event-stream" \
        -D /tmp/mcp_headers_${name} \
        -d '{
            "jsonrpc": "2.0",
            "method": "initialize",
            "id": 1,
            "params": {
                "protocolVersion": "2025-03-26",
                "capabilities": {},
                "clientInfo": {"name": "test", "version": "1.0"}
            }
        }' 2>/dev/null)
    
    if [ -z "$raw_response" ]; then
        echo "  FAIL: ${name} - no response (backend may have crashed)"
        FAIL=$((FAIL + 1))
        return 1
    fi
    
    local json_response
    json_response=$(extract_json "$raw_response")
    
    # Check if initialize succeeded
    local has_result
    has_result=$(echo "$json_response" | python3 -c "import sys,json; d=json.load(sys.stdin); print('yes' if 'result' in d else 'no')" 2>/dev/null)
    
    if [ "$has_result" != "yes" ]; then
        echo "  FAIL: ${name} - initialize failed: $(echo "$json_response" | head -c 150)"
        FAIL=$((FAIL + 1))
        return 1
    fi
    
    local server_info
    server_info=$(echo "$json_response" | python3 -c "
import sys, json
d = json.load(sys.stdin)
si = d['result'].get('serverInfo', {})
print(f\"{si.get('name', '?')} v{si.get('version', '?')}\")
" 2>/dev/null)
    
    # Get session ID from headers
    local session_id
    session_id=$(grep -i 'mcp-session-id' /tmp/mcp_headers_${name} 2>/dev/null | tr -d '\r\n' | awk '{print $2}')
    
    # Step 2: Send initialized notification
    curl -sf --max-time 5 -X POST "$url" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json, text/event-stream" \
        ${session_id:+-H "Mcp-Session-Id: ${session_id}"} \
        -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' > /dev/null 2>&1
    
    # Step 3: List tools
    local raw_tools
    raw_tools=$(curl -sf --max-time 15 -X POST "$url" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json, text/event-stream" \
        ${session_id:+-H "Mcp-Session-Id: ${session_id}"} \
        -d '{"jsonrpc":"2.0","method":"tools/list","id":2,"params":{}}' 2>/dev/null)
    
    local json_tools
    json_tools=$(extract_json "$raw_tools")
    
    local tool_info
    tool_info=$(echo "$json_tools" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    tools = d.get('result', {}).get('tools', [])
    names = [t['name'] for t in tools[:5]]
    extra = f' +{len(tools)-5} more' if len(tools) > 5 else ''
    print(f'{len(tools)} tools: {', '.join(names)}{extra}')
except Exception as e:
    print(f'error: {e}')
" 2>/dev/null)
    
    local tool_count
    tool_count=$(echo "$json_tools" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(len(d.get('result', {}).get('tools', [])))
except:
    print(0)
" 2>/dev/null)
    
    if [ "$tool_count" -gt 0 ] 2>/dev/null; then
        echo "  PASS: ${name} (${server_info}) - ${tool_info}"
        PASS=$((PASS + 1))
    else
        echo "  WARN: ${name} (${server_info}) - initialized OK but 0 tools returned"
        FAIL=$((FAIL + 1))
    fi
}

echo "============================================"
echo "  Testing MCP Endpoints at ${BASE}"
echo "============================================"
echo ""

# Get active MCPs from health endpoint
ACTIVE=$(curl -sf "${BASE}/health" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for name in d['activeMcps']:
    print(name)
" 2>/dev/null)

if [ -z "$ACTIVE" ]; then
    echo "ERROR: Could not reach health endpoint at ${BASE}/health"
    exit 1
fi

echo "Active servers: $(echo $ACTIVE | tr '\n' ' ')"
echo ""

for mcp in $ACTIVE; do
    test_mcp "$mcp"
done

echo ""
echo "============================================"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "============================================"

rm -f /tmp/mcp_headers_* 2>/dev/null
exit $FAIL
