#!/usr/bin/env node
// Starts Lagsmith's MCP server, which ships inside the Lagsmith app, so `npx lagsmith-mcp` always
// runs the server that matches the installed app.
//
// Without the app (or on a system other than macOS) it answers as a stand-in: MCP clients and
// directories still see the real tools, and every tool call says how to get Lagsmith.
'use strict';

const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const readline = require('node:readline');

const SERVER_IN_APP = 'Contents/MacOS/lagsmith-mcp';
const DOWNLOAD = 'https://lagsmith.com/download';

function findServer() {
  if (process.platform !== 'darwin') return null;
  const apps = [
    process.env.LAGSMITH_APP,
    '/Applications/Lagsmith.app',
    path.join(os.homedir(), 'Applications', 'Lagsmith.app'),
  ];
  for (const app of apps) {
    if (!app) continue;
    const server = path.join(app, SERVER_IN_APP);
    try {
      fs.accessSync(server, fs.constants.X_OK);
      return server;
    } catch {}
  }
  return null;
}

function run(server) {
  const child = spawn(server, process.argv.slice(2), { stdio: 'inherit' });
  const forward = (signal) => child.kill(signal);
  for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) process.on(signal, forward);
  child.on('error', (error) => {
    process.stderr.write(`lagsmith-mcp: couldn't start ${server}: ${error.message}\n`);
    standIn(`Couldn't start Lagsmith's MCP server (${error.message}). Reinstall Lagsmith from ${DOWNLOAD}.`);
  });
  child.on('exit', (code, signal) => {
    process.exit(signal ? 128 + (os.constants.signals[signal] || 0) : code ?? 1);
  });
}

function standIn(problem) {
  const { instructions, tools } = require('../tools.json');
  const { version } = require('../package.json');
  process.stderr.write(`lagsmith-mcp: ${problem}\n`);

  const send = (message) => process.stdout.write(JSON.stringify(message) + '\n');
  const lines = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
  lines.on('line', (line) => {
    if (!line.trim()) return;
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      return send({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } });
    }
    // Notifications have no id and get no reply.
    if (!message || typeof message !== 'object' || !('id' in message)) return;
    const reply = (result) => send({ jsonrpc: '2.0', id: message.id, result });
    switch (message.method) {
      case 'initialize':
        return reply({
          protocolVersion: message.params?.protocolVersion ?? '2025-06-18',
          capabilities: { tools: { listChanged: false } },
          serverInfo: { name: 'lagsmith', version },
          instructions: `${problem}\n\n${instructions}`,
        });
      case 'ping':
        return reply({});
      case 'tools/list':
        return reply({ tools });
      case 'tools/call':
        return reply({ content: [{ type: 'text', text: problem }], isError: true });
      default:
        return send({ jsonrpc: '2.0', id: message.id, error: { code: -32601, message: `Method not found: ${message.method}` } });
    }
  });
}

const server = findServer();
if (server) {
  run(server);
} else if (process.platform === 'darwin') {
  standIn(`Lagsmith isn't installed. Download it from ${DOWNLOAD}, move it to Applications, open it, and turn on Allow Automation (menu bar icon › Automation). Then restart this MCP server.`);
} else {
  standIn(`Lagsmith runs on macOS only (macOS 13 Ventura or later). See ${DOWNLOAD}.`);
}
