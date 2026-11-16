#!/bin/sh
# Copies the MCP server source from the Lagsmith app repo, then regenerates tools.json (the tool
# list the npm launcher serves when the app isn't installed) from that exact source.
#
# Usage: scripts/sync-from-app.sh [path to the app repo]   (default: ../InternetVariability)
set -eu
cd "$(dirname "$0")/.."
APP_REPO="${1:-../InternetVariability}"

cp "$APP_REPO/MCP/lagsmith-mcp.swift" Sources/lagsmith-mcp.swift

BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
xcrun --sdk macosx swiftc -O -o "$BUILD/lagsmith-mcp" Sources/lagsmith-mcp.swift

printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"sync-from-app","version":"1"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | "$BUILD/lagsmith-mcp" \
  | node -e '
      const replies = require("fs").readFileSync(0, "utf8").trim().split("\n").map((line) => JSON.parse(line));
      const result = (id) => replies.find((reply) => reply.id === id).result;
      // Swift writes dictionary keys in a random order; fix the order so syncs only show real changes.
      const first = ["name", "description", "inputSchema", "type", "enum", "properties", "required"];
      const rank = (key) => (first.includes(key) ? first.indexOf(key) : first.length);
      const ordered = (value) =>
        Array.isArray(value) ? value.map(ordered)
        : value && typeof value === "object"
          ? Object.fromEntries(Object.keys(value)
              .sort((a, b) => rank(a) - rank(b) || a.localeCompare(b))
              .map((key) => [key, ordered(value[key])]))
          : value;
      const out = ordered({ instructions: result(1).instructions, tools: result(2).tools });
      require("fs").writeFileSync("tools.json", JSON.stringify(out, null, 2) + "\n");
      console.log(`tools.json: ${out.tools.length} tools (server ${result(1).serverInfo.version})`);
    '
