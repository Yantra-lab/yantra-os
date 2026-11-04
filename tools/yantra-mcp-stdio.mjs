#!/usr/bin/env node
// tools/yantra-mcp-stdio.mjs
// Zero-dependency MCP stdio server exposing all 22 BrowserOS-parity tools
// and forwarding tool invocations to the running Yantra OS engine on http://127.0.0.1:9229.

import readline from "node:readline";

const YANTRA_MCP_URL = process.env.YANTRA_MCP_URL || "http://127.0.0.1:9229";

const BROWSEROS_PARITY_TOOLS = [
  {
    name: "tabs",
    description: "Manages Yantra OS tabs categorized by ownership (Your tabs, User's tabs, Other agents' tabs). Actions: list, new, close, active.",
    inputSchema: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["list", "new", "close", "active"] },
        url: { type: "string" },
        tabId: { type: "integer" },
        owner: { type: "string" }
      }
    }
  },
  {
    name: "tab_groups",
    description: "Manages tab groups (create, title, color: grey|blue|red|yellow|green|pink|purple|cyan|orange, toggle collapsed/expanded).",
    inputSchema: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["list", "create", "toggle", "close"] },
        groupId: { type: "integer" },
        title: { type: "string" },
        color: { type: "string", enum: ["grey", "blue", "red", "yellow", "green", "pink", "purple", "cyan", "orange"] }
      }
    }
  },
  {
    name: "windows",
    description: "Manages Yantra OS windows (list, open visible or headless, focus, show/hide, close).",
    inputSchema: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["list", "open", "focus", "close"] },
        title: { type: "string" },
        headless: { type: "boolean" }
      }
    }
  },
  {
    name: "snapshot",
    description: "Captures the live Yantra OS scene & embedded AppViews as an indented accessibility tree with stable [ref=eN] handles.",
    inputSchema: { type: "object", properties: {} }
  },
  {
    name: "diff",
    description: "Returns only what changed in the accessibility tree since the last snapshot/action.",
    inputSchema: { type: "object", properties: {} }
  },
  {
    name: "read",
    description: "Extracts the current Yantra scene content as clean Markdown, plain text, or hyperlinks.",
    inputSchema: {
      type: "object",
      properties: { format: { type: "string", enum: ["markdown", "text", "links"] } }
    }
  },
  {
    name: "grep",
    description: "Fast search across the accessibility tree (over='ax') or visible content (over='content') while preserving [ref=eN] handles.",
    inputSchema: {
      type: "object",
      properties: {
        pattern: { type: "string" },
        over: { type: "string", enum: ["ax", "content"] }
      },
      required: ["pattern"]
    }
  },
  {
    name: "screenshot",
    description: "Takes a visual PNG/JPEG screenshot of the current Yantra OS viewport.",
    inputSchema: { type: "object", properties: { path: { type: "string" } } }
  },
  {
    name: "pdf",
    description: "Exports the entire Yantra OS scene into a vector PDF document saved to disk.",
    inputSchema: { type: "object", properties: { path: { type: "string" } } }
  },
  {
    name: "navigate",
    description: "Navigates Yantra OS to an app URL (e.g. 'y:daw', 'y:editor', 'y:files', 'reload') and returns a fresh snapshot.",
    inputSchema: { type: "object", properties: { url: { type: "string" } }, required: ["url"] }
  },
  {
    name: "act",
    description: "Drives interactions using [ref=eN] handles (click, hover, focus, type, press, drag, scroll, fill with fields[], check, uncheck, select) and returns a diff.",
    inputSchema: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["click", "hover", "focus", "type", "press", "drag", "scroll", "fill", "check", "uncheck", "select"] },
        ref: { type: "string" },
        text: { type: "string" },
        fields: { type: "array", items: { type: "object" } }
      },
      required: ["action"]
    }
  },
  {
    name: "upload",
    description: "Uploads a local file directly into the Yantra OS sandbox store.",
    inputSchema: {
      type: "object",
      properties: { filePath: { type: "string" }, key: { type: "string" } },
      required: ["filePath"]
    }
  },
  {
    name: "download",
    description: "Intercepts and saves exported data from Yantra OS to a designated local path.",
    inputSchema: { type: "object", properties: { savePath: { type: "string" } }, required: ["savePath"] }
  },
  {
    name: "wait",
    description: "Pauses execution until duration (for='time'), text (for='text'), or selector (for='selector') matches.",
    inputSchema: {
      type: "object",
      properties: {
        for: { type: "string", enum: ["time", "text", "selector"] },
        ms: { type: "integer" },
        value: { type: "string" }
      }
    }
  },
  {
    name: "evaluate",
    description: "Evaluates expressions or pushes live Nim source ('liveedit:<appId>:<nimCode>') directly into Yantra OS.",
    inputSchema: { type: "object", properties: { expression: { type: "string" } }, required: ["expression"] }
  },
  {
    name: "run",
    description: "Chains multi-step automation (snapshot, navigate, act, evaluate) in a single round-trip.",
    inputSchema: {
      type: "object",
      properties: { steps: { type: "array", items: { type: "object" } } },
      required: ["steps"]
    }
  },
  {
    name: "connector_mcp_servers",
    description: "Lists connection and authentication status of Yantra OS managed app connectors.",
    inputSchema: { type: "object", properties: {} }
  },
  {
    name: "discover_server_categories_or_actions",
    description: "Discovers available action categories and endpoints across connected services.",
    inputSchema: { type: "object", properties: { serverId: { type: "string" } } }
  },
  {
    name: "get_category_actions",
    description: "Lists specific operations available within a discovered service category.",
    inputSchema: { type: "object", properties: { category: { type: "string" } }, required: ["category"] }
  },
  {
    name: "get_action_details",
    description: "Retrieves detailed parameter specifications for a specific connector action.",
    inputSchema: { type: "object", properties: { action: { type: "string" } }, required: ["action"] }
  },
  {
    name: "execute_action",
    description: "Executes a structured connector action (such as writing & hot-reloading a Nim WASM app).",
    inputSchema: {
      type: "object",
      properties: { action: { type: "string" }, params: { type: "object" } },
      required: ["action"]
    }
  },
  {
    name: "search_documentation",
    description: "Keyword search across Yantra SDK and connector endpoint documentation.",
    inputSchema: { type: "object", properties: { query: { type: "string" } }, required: ["query"] }
  },
  {
    name: "handle_auth_failure",
    description: "Recovers from connector authentication errors.",
    inputSchema: { type: "object", properties: { serverId: { type: "string" } } }
  }
];

const rl = readline.createInterface({ input: process.stdin, terminal: false });

rl.on("line", async (line) => {
  if (!line.trim()) return;
  let msg;
  try {
    msg = JSON.parse(line);
  } catch {
    return;
  }

  if (msg.method === "initialize") {
    process.stdout.write(JSON.stringify({
      jsonrpc: "2.0",
      id: msg.id,
      result: {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "yantra-os-mcp", version: "2.0.0" }
      }
    }) + "\n");
    return;
  }

  if (msg.method === "tools/list") {
    process.stdout.write(JSON.stringify({
      jsonrpc: "2.0",
      id: msg.id,
      result: { tools: BROWSEROS_PARITY_TOOLS }
    }) + "\n");
    return;
  }

  if (msg.method === "tools/call") {
    try {
      const resp = await fetch(YANTRA_MCP_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(msg)
      });
      const data = await resp.json();
      process.stdout.write(JSON.stringify(data) + "\n");
    } catch (err) {
      process.stdout.write(JSON.stringify({
        jsonrpc: "2.0",
        id: msg.id,
        result: {
          content: [{ type: "text", text: JSON.stringify({ error: `Yantra OS engine unreachable at ${YANTRA_MCP_URL}: ${err.message}` }) }],
          isError: true
        }
      }) + "\n");
    }
  }
});
