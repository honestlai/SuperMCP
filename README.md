## About The 3 Amigos MCP

After discovering, using, and being absolutely blown away by the possibilities of Playwright MCP, I started looking around for other complementary MCP projects I could/should put together. This led me to what I call the "Three Amigos" - a powerful trio that I believe will be essential for most small to medium-sized projects I'll be building or experimenting with.

The idea was simple: combine browser automation, file system access, and database operations into one seamless container. Why? Because when you're building modern applications, you're almost always working with web interfaces, managing files, and handling data. Having all three capabilities available directly in your AI coding environment just makes sense.

I feel like moving forward most small to medium sized projects I'll be building or experimenting on will likely benefit greatly from these '3 amigos'.

*Note: A container hub build is on its way... I know this is kind of a hefty 3-headed beast to build :P*

## Meet the Amigos

🎭 **Playwright** - The Browser Whisperer
- Full browser automation and web scraping
- Screenshot capture and visual testing
- Form filling and navigation automation
- Mobile device emulation and responsive testing
- PDF generation from web pages
- Network interception and debugging

📁 **Filesystem** - The File Wrangler
- File and directory operations
- Read/write access to your local filesystem workspace
- Direct access to codebases and development files
- Secure access control and permissions
- File watching and monitoring
- Batch file operations
- Workspace organization and management

🗄️ **Database** - The Data Guardian
- Multi-database support (SQLite, PostgreSQL, MySQL)
- Query execution and data management
- Database schema exploration
- Data import/export operations
- Connection pooling and optimization
- Environment-based configuration

## 🏗️ Architecture

This container provides two connection modes optimized for different deployment scenarios:

### **Command-Based Mode (Recommended for SSH/Remote)**

* **Best for**: SSH tunnels, remote servers, Cloudflare connections
* **How it works**: Client executes MCP servers directly via `docker exec`
* **Benefits**: No persistent HTTP connections, eliminates timeout issues
* **Use case**: When you're connecting over SSH or experiencing connection drops

### **HTTP Mode (Suitable for Local)**

* **Best for**: Local development, direct connections
* **How it works**: MCP servers run as HTTP services on ports 8091-8093
* **Benefits**: Standard MCP protocol, familiar HTTP endpoints
* **Use case**: When running locally without network issues

## 🚀 Quick Start

### Prerequisites

* Docker and Docker Compose installed
* Cursor or VS Code with MCP support

### 1\. Clone and Start

```bash
git clone https://github.com/honestlai/3AmigosMCP.git
cd 3AmigosMCP
docker compose up -d
```

### 2\. Verify Everything is Working

```bash
./test-mcps.sh
```

### 3\. Configure Your MCP Client

#### For Command-Based Mode (SSH/Remote Recommended)

```json
{
  "mcpServers": {
    "Playwright_MCP": {
      "command": "docker",
      "args": [
        "exec",
        "-i",
        "3AmigosMCP",
        "npx",
        "@playwright/mcp@latest",
        "--isolated",
        "--no-sandbox",
        "--browser",
        "chrome"
      ]
    },
    "Filesystem_MCP": {
      "command": "docker",
      "args": [
        "exec",
        "-i",
        "3AmigosMCP",
        "npx",
        "@modelcontextprotocol/server-filesystem",
        "/workspace"
      ]
    },
    "Database_MCP": {
      "command": "docker",
      "args": [
        "exec",
        "-i",
        "3AmigosMCP",
        "npx",
        "@ahmetbarut/mcp-database-server",
        "--database",
        "/data/data.db",
        "--allowed-directories",
        "/workspace"
      ]
    }
  }
}
```

#### For HTTP Mode (Local Development)

```json
{
  "mcpServers": {
    "Playwright_MCP": {
      "url": "http://localhost:8091/mcp",
      "retryDelay": 1000,
      "maxRetries": 20,
      "timeout": 60000
    },
    "Filesystem_MCP": {
      "url": "http://localhost:8092/mcp",
      "retryDelay": 1000,
      "maxRetries": 20,
      "timeout": 60000
    },
    "Database_MCP": {
      "url": "http://localhost:8093/mcp",
      "retryDelay": 1000,
      "maxRetries": 20,
      "timeout": 60000
    }
  }
}
```

## 📊 Connection Mode Comparison

| Feature                | Command-Based  | HTTP Mode         |
| ---------------------- | -------------- | ----------------- |
| **SSH Stability**      | ✅ Excellent    | ⚠️ May timeout    |
| **Connection Drops**   | ✅ None         | ⚠️ Can occur      |
| **Setup Complexity**   | ⚠️ More config | ✅ Simple          |
| **Performance**        | ✅ Optimal      | ✅ Good            |
| **Local Development**  | ✅ Works        | ✅ Works           |
| **Remote Development** | ✅ Recommended  | ❌ Not recommended |

## 🛠️ Usage Examples

### Browser Automation with Playwright

```javascript
// Navigate to a website
await browser.navigate({ url: "https://example.com" });

// Take a screenshot
await browser.take_screenshot({ 
  filename: "screenshot.png",
  fullPage: true 
});

// Fill a form field (IMPORTANT: Click the field first before typing)
await browser.click({ 
  element: "Username textbox", 
  ref: "ref-username-field" 
});
await browser.type({ 
  element: "Username textbox", 
  ref: "ref-username-field",
  text: "myuser" 
});

// Note: For form inputs, you must click the field first to focus it before typing.
// This is a known requirement for reliable form field interaction.
```

### File Operations with Filesystem

```javascript
// Read a file
const content = await filesystem.readFile({ path: "config.json" });

// Write a file
await filesystem.writeFile({ 
  path: "output.txt", 
  content: "Hello, World!" 
});

// List directory contents
const files = await filesystem.listDir({ path: "/workspace" });
```

### Database Operations

```javascript
// Execute a query on the default database
const results = await database.query({ 
  sql: "SELECT * FROM users WHERE active = true" 
});

// Insert data
await database.execute({ 
  sql: "INSERT INTO logs (message, timestamp) VALUES (?, ?)",
  params: ["User logged in", new Date().toISOString()]
});

// Connect to a database in your workspace
await database.connect({
  connection_name: "workspace_db",
  database: "/workspace/myproject/database.db"
});

// Execute queries on workspace database
const workspaceResults = await database.execute_query({
  connection_name: "workspace_db",
  query: "SELECT * FROM projects WHERE status = 'active'"
});
```

## 🔧 Configuration

### Environment Variables

```yaml
# docker-compose.yml
environment:
  - PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
  - NODE_ENV=production
```

### Port Mapping

```yaml
ports:
  - "8091:8081"  # Playwright MCP
  - "8092:8082"  # Filesystem MCP
  - "8093:8083"  # Database MCP
```

### Volume Mounts

```yaml
volumes:
  - /workspace:/workspace:rw  # Local filesystem workspace access
  - data:/data:rw            # Database storage (persistent volume)
```

The workspace volume provides direct access to your local filesystem workspace, allowing both the Filesystem MCP and Database MCP to access files and databases within your development environment. The data volume persists database files across container restarts.

### Database MCP Workspace Access

The Database MCP is configured with `--allowed-directories /workspace` to enable access to databases stored within your workspace directory. This is essential for:

- **Development Databases**: Access SQLite databases in your project directories
- **Database Scripts**: Execute SQL files located in your workspace
- **Schema Files**: Read database schema definitions and migration scripts
- **Test Data**: Access test databases and fixtures in your project structure
- **Configuration**: Read database configuration files from your workspace

This configuration allows the Database MCP to work seamlessly with databases that are part of your development workflow, not just the persistent `/data` volume.

## 🔍 Troubleshooting

### Container Health

```bash
# Check container status
docker ps | grep 3AmigosMCP

# View logs
docker logs 3AmigosMCP

# Health check
docker inspect --format='{{.State.Health.Status}}' 3AmigosMCP

# Test all MCPs
./test-mcps.sh
```

### Common Issues

#### Connection Drops (SSH/Remote)

* **Solution**: Switch to command-based mode
* **Why**: Eliminates persistent HTTP connections that can timeout

#### Container Won't Start

* **Check**: Port 8091-8093 availability
* **Fix**: `docker compose down && docker compose up -d`

#### MCP Tools Not Available

* **Check**: Client configuration
* **Verify**: Container is healthy and running
* **Test**: Run `./test-mcps.sh` to verify all MCPs

#### Browser Not Visible / Headless Mode

* **Issue**: Browser actions happen invisibly
* **Solution**: The `--headless` flag has been removed from the default configuration to show browser actions
* **To Show Browser**: The configuration now runs Playwright in "headed" mode (visible browser) by default
* **To Hide Browser**: Add `--headless` back to the Playwright MCP args in `cursor-mcp-config.json` if you want to hide the browser window
* **Note**: When running in Docker, browser visibility depends on your display configuration. Cursor's browser MCP integration may handle display differently.

#### Form Field Input Not Working

* **Issue**: `browser_type` fails with "Element not found" error
* **Solution**: **Click the form field first** before typing to focus it
* **Example**:
  ```javascript
  // Step 1: Click to focus the field
  await browser.click({ element: "Username field", ref: "ref-username" });
  // Step 2: Then type
  await browser.type({ element: "Username field", ref: "ref-username", text: "admin" });
  ```
* **Why**: Form fields need to be focused before text input can be reliably entered
* **Note**: This is a known requirement for reliable form field interaction with Playwright MCP

#### Material-UI TextField Components Not Working

* **Issue**: Cannot type into Material-UI TextField components even after clicking
* **Root Cause**: Material-UI TextFields have a complex nested DOM structure where the actual `<input>` element is nested inside multiple wrapper divs. Playwright MCP uses the accessibility tree to interact with elements, which may point to the wrapper div instead of the actual input element.
* **Status**: **Known Limitation** - This is a fundamental incompatibility between Playwright MCP's accessibility tree approach and Material-UI's component structure.
* **Workarounds**:
  * **Option 1 (Recommended)**: Replace Material-UI TextField components with standard HTML `<input>` elements or simpler form libraries
  * **Option 2**: Use native HTML inputs wrapped in Material-UI styling instead of TextField components
  * **Option 3**: Wait for Playwright MCP to add support for nested input elements in complex component libraries
* **Why This Happens**: The accessibility tree identifies the TextField wrapper as the interactive element, but the actual input handling requires interaction with the nested `<input>` element, which the MCP cannot reliably locate.

## 📈 Performance

### Resource Usage

* **Memory**: ~300MB typical usage
* **CPU**: Low usage during idle
* **Network**: Minimal overhead

### Optimization Tips

* Use `--headless` mode for Playwright automation (removed by default to show browser actions)
* Enable `--isolated` for clean browser sessions
* Monitor resource usage with `docker stats`

## 🎯 Why These Three MCPs?

The combination of Playwright, Filesystem, and Database MCPs covers the most common development scenarios:

1. **Web Development**: Playwright handles browser automation, testing, and web scraping
2. **File Management**: Filesystem MCP provides workspace organization and file operations
3. **Data Operations**: Database MCP enables data persistence, queries, and analysis

Together, they create a comprehensive development environment that can handle everything from simple scripts to complex web applications.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly with `./test-mcps.sh`
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

* Playwright for the amazing browser automation framework
* Model Context Protocol for the MCP specification
* The Cursor/VS Code community for MCP integration
* The MCP ecosystem for providing these powerful tools

---

**Ready to supercharge your development workflow?** 🚀

The Three Amigos bring together browser automation, file management, and database operations into one seamless container. Whether you're building web applications, managing data, or automating workflows, these MCPs provide the tools you need right in your editor.

## About

A comprehensive Docker container combining Playwright, Filesystem, and Database MCP servers for enhanced development workflows.
