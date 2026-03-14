# Kubernetes MCP for Claude Desktop

Connect Claude Desktop to your OKE cluster so you can query and manage it conversationally — no terminal required.

## Prerequisites

- [Claude Desktop](https://claude.ai/download) installed
- [Node.js](https://nodejs.org/) v18+ installed (provides `npx`)
- The `oci-create` workflow completed successfully

## Step 1 — Download the kubeconfig artifact

1. Go to your GitHub repository → **Actions**
2. Open the latest successful `OCI Create Pipeline` run
3. Scroll to **Artifacts** at the bottom of the run summary
4. Download **`kubeconfig`** and extract `kubeconfig.yaml`
5. Save it somewhere permanent, e.g.:
   - Windows: `C:\Users\<you>\.kube\oke-kubeconfig.yaml`
   - macOS/Linux: `~/.kube/oke-kubeconfig.yaml`

## Step 2 — Configure Claude Desktop

Open the Claude Desktop config file:

- **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`
- **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`

If the file doesn't exist, create it. Add the following, replacing the path with the absolute path to your kubeconfig:

```json
{
  "mcpServers": {
    "kubernetes": {
      "command": "npx",
      "args": ["-y", "mcp-server-kubernetes"],
      "env": {
        "KUBECONFIG": "C:\\Users\\<you>\\.kube\\oke-kubeconfig.yaml"
      }
    }
  }
}
```

> **Windows paths**: use double backslashes (`\\`) or forward slashes (`/`) in the JSON.

If you already have other MCP servers configured, add the `"kubernetes"` block inside the existing `"mcpServers"` object.

## Step 3 — Restart Claude Desktop

Fully quit and relaunch Claude Desktop. You should see a tools icon (hammer) in the chat input — click it to confirm the `kubernetes` server is listed.

## Step 4 — Try it

Ask Claude Desktop:
- *"What pods are running in the workflows namespace?"*
- *"Is the n8n deployment healthy?"*
- *"Show me recent warning events in the cluster."*

## Notes

- The OKE API endpoint is **publicly accessible** — no VPN required for cluster management
- VPN (`wg0-client` artifact) is only needed to access n8n, pgadmin, and grafana in the browser
- The kubeconfig contains a time-limited token — if it expires, re-download the artifact from a fresh workflow run
- MCP server used: [`mcp-server-kubernetes`](https://github.com/Flux159/mcp-server-kubernetes)
