<p align="center"><img src="https://lagsmith.com/icon-256.png" width="96" height="96" alt="Lagsmith"></p>

# Lagsmith MCP server

[![M8ven Score](https://m8ven.ai/badge/mcp/shabbirv-lagsmith-mcp-zutdv7?v=4432f5bb014a8e500323cfca3ce1c549)](https://m8ven.ai/mcp/shabbirv-lagsmith-mcp-zutdv7?s=readme)

Let your AI coding agent test your app on bad networks. This [MCP](https://modelcontextprotocol.io) server lets Claude Code, Cursor, Codex, Claude Desktop, Windsurf and other MCP clients slow down, break and mock the network of **one app at a time** on your Mac, including iOS Simulator apps, using [Lagsmith](https://lagsmith.com). Only the app under test is affected, so the agent's own connection, your terminal and your test runners stay at full speed.

With it, an agent can:

- throttle one app to 3G, Edge, LTE or Very Bad Network, or set exact bandwidth, latency, jitter and packet loss
- put one simulator app in Airplane Mode: requests fail with `NSURLErrorNotConnectedToInternet` (-1009), and `NWPathMonitor` and `SCNetworkReachability` report no network, like on a real device
- refuse, time out or drop connections, or take the app offline and back again on a loop
- make one API endpoint fail or return a made-up response while the rest of the app works
- read the app's recent HTTP requests with status, timing and bodies, to see what actually broke

## Requirements

- macOS 13 Ventura or later, on Apple silicon or Intel
- [Lagsmith](https://lagsmith.com/download) in your Applications folder, running, with **Allow Automation** on (menu bar icon › Automation). Automation, including MCP, is part of Lagsmith Pro, and every install starts with a free 14-day Pro trial. See [pricing](https://lagsmith.com/pricing).
- Node.js 18 or later for the `npx` setup below, or [skip Node](#without-nodejs) and use the server inside the app

## Setup

### Claude Code

```sh
claude mcp add --scope user lagsmith -- npx -y lagsmith-mcp
```

`--scope user` makes Lagsmith available in every project. Start a new session and run `/mcp` to check it's connected.

### Cursor, Claude Desktop, Windsurf, Cline and other JSON configs

```json
{
  "mcpServers": {
    "lagsmith": {
      "command": "npx",
      "args": ["-y", "lagsmith-mcp"]
    }
  }
}
```

| Client | Config file |
| --- | --- |
| Cursor | `~/.cursor/mcp.json`, or `.cursor/mcp.json` in a project |
| Claude Desktop | Settings › Developer › Edit Config, then restart Claude Desktop |
| Windsurf | `~/.codeium/windsurf/mcp_config.json` |
| Cline | MCP Servers icon › Configure › Configure MCP Servers (opens `cline_mcp_settings.json`) |

If the file already has other servers, add the `lagsmith` entry inside the existing `mcpServers` section.

### Codex

In `~/.codex/config.toml`:

```toml
[mcp_servers.lagsmith]
command = "npx"
args = ["-y", "lagsmith-mcp"]
```

### Without Node.js

The same server ships inside the app, so you can point any client straight at it:

```sh
claude mcp add --scope user lagsmith -- /Applications/Lagsmith.app/Contents/MacOS/lagsmith-mcp
```

In JSON configs, use `"command": "/Applications/Lagsmith.app/Contents/MacOS/lagsmith-mcp"` with no `args`.

## Tools

| Tool | What it does | Main parameters |
| --- | --- | --- |
| `list_targets` | Running simulators and their apps, running Mac apps, presets and current rules | none |
| `status` | Every rule, what it's doing, and whether the proxy is running | none |
| `set_network` | Slow down or break one app's network | `app`, `simulator`; `preset`, or `down`/`up` (kbps), `latency`/`jitter` (ms), `loss` (%); `failure` (`airplane`, `refuse`, `timeout`, `drop`, `outages`); `hosts`, `hosts_mode` |
| `reset_network` | Back to full speed; the app stays watched | `app`, `simulator` |
| `stop_watching` | Turn the app's rule off entirely | `app`, `simulator` |
| `relaunch_app` | Relaunch a simulator app with request monitoring | `app`, `simulator` |
| `get_requests` | The app's recent HTTP requests, newest first | `app`, `simulator`, `limit`, `filter` (e.g. `is:failed`, `status:5xx`), `include_bodies` |
| `fail_endpoint` | Make one endpoint fail while the rest works | `app`, `simulator`, `pattern`, `kind` (`offline`, `timeout`, `status`, `delay`), `value` |
| `mock_endpoint` | Answer one endpoint with a made-up response | `app`, `simulator`, `pattern`, `status`, `body`, `content_type`, `delay` |
| `clear_endpoints` | Remove endpoint failures and mocks | `app`, `simulator`, `pattern` |

For simulator apps, pass `simulator: "booted"`, a device name or a UDID. Leave `simulator` out for a Mac app.

## Example prompts

- "Relaunch the app on 3G with monitoring, sign in, and list requests slower than two seconds."
- "Put the app in Airplane Mode and check that the offline banner appears."
- "Make POST /v1/orders return 500 and check the app shows a retry button."
- "Run the checkout UI tests on 3G with the payments API returning 503s, and tell me what breaks."

See a full example session in the [MCP docs](https://lagsmith.com/docs/mcp).

## How it works

`lagsmith-mcp` speaks MCP over stdio and turns each tool call into a request to Lagsmith's automation server on `127.0.0.1:47300` (set `LAGSMITH_PORT` to change the port). It's one dependency-free Swift file: [`Sources/lagsmith-mcp.swift`](Sources/lagsmith-mcp.swift), the same source that's built into the app.

The npm package is a small launcher. It runs the server inside your installed copy of Lagsmith, so the server always matches your app version. If Lagsmith isn't installed, the launcher still answers with the list of tools, and every tool call explains how to install the app. If your copy of Lagsmith isn't in `/Applications` or `~/Applications`, set `LAGSMITH_APP` to its path.

To build the server yourself:

```sh
xcrun swiftc -O -o lagsmith-mcp Sources/lagsmith-mcp.swift
```

## Privacy

Everything runs on your Mac. The requests Lagsmith slows down, mocks or shows you are never sent anywhere. Lagsmith's anonymous usage statistics count which features are used, including tool calls through MCP. They never include your apps' traffic. See the [privacy policy](https://lagsmith.com/privacy). What your AI agent does with what it reads is governed by that agent's own privacy policy.

## Links

- [Lagsmith](https://lagsmith.com)
- [MCP documentation](https://lagsmith.com/docs/mcp)
- [Download for Mac](https://lagsmith.com/download)
- [Support](https://lagsmith.com/support)

## License

This repository, the MCP server and its npm launcher, is under the [MIT License](LICENSE). The Lagsmith app itself is proprietary: see the [terms](https://lagsmith.com/terms).
