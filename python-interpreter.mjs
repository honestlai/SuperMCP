import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { execSync } from 'child_process';

const server = new McpServer({
  name: 'python-interpreter',
  version: '1.0.0',
});

server.tool(
  'execute_python',
  'Execute Python code and return the output. Code is run with Python 3 via stdin.',
  { code: z.string().describe('Python code to execute') },
  async ({ code }) => {
    try {
      const result = execSync('python3.11 -', {
        input: code,
        timeout: 30000,
        encoding: 'utf-8',
        maxBuffer: 10 * 1024 * 1024,
        stdio: ['pipe', 'pipe', 'pipe'],
      });
      return {
        content: [{ type: 'text', text: result || 'Code executed successfully (no output)' }],
      };
    } catch (error) {
      const stderr = error.stderr ? error.stderr.toString() : '';
      const stdout = error.stdout ? error.stdout.toString() : '';
      return {
        content: [{ type: 'text', text: `Error:\n${stderr}\n${stdout}`.trim() }],
        isError: true,
      };
    }
  }
);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch(console.error);
