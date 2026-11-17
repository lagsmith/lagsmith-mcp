# Installing the Lagsmith MCP server

These steps are for AI agents (such as Cline) setting up this server for a user.

## 1. Check the requirements

- The user is on macOS 13 or later. The server does nothing useful on other systems.
- The Lagsmith app is installed in `/Applications` (or `~/Applications`). If it isn't, ask the user to download it from https://lagsmith.com/download and open it. Don't try to install the app yourself: it needs the user to approve a network extension in System Settings.
- In Lagsmith, **Allow Automation** is on (menu bar icon › Automation). Ask the user to turn it on if a tool call reports that automation is off.
- Node.js 18 or later is installed (`node --version`). If it isn't, use the server inside the app instead (step 2, option B).

## 2. Add the server to the MCP settings

No API key, environment variable or clone is needed.

Option A, with Node.js:

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

Option B, without Node.js:

```json
{
  "mcpServers": {
    "lagsmith": {
      "command": "/Applications/Lagsmith.app/Contents/MacOS/lagsmith-mcp"
    }
  }
}
```

If the settings file already has other servers, add the `lagsmith` entry inside the existing `mcpServers` object.

## 3. Check it works

Call the `status` tool. It should report whether Lagsmith's proxy is running and list any rules. Then call `list_targets` to see running Mac apps and booted iOS Simulators.

If `status` says Lagsmith can't be reached, ask the user to open the Lagsmith app and turn on **Allow Automation**.
