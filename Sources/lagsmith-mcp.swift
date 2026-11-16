// lagsmith-mcp: an MCP server that lets AI agents (Claude Code, Cursor, Codex and others) see and
// change the network of individual apps with Lagsmith, without slowing the agent itself down.
//
// It speaks MCP over stdin and stdout (newline-delimited JSON-RPC 2.0) and turns each tool call
// into a request to the app's automation server on 127.0.0.1. The app has to be running with
// Allow Automation on.
import Foundation

let serverName = "lagsmith"
let serverVersion = "1.0.0"
let port = ProcessInfo.processInfo.environment["LAGSMITH_PORT"].flatMap(Int.init) ?? 47300
let automationHeader = "X-Lagsmith"

let instructions = """
Lagsmith slows down and breaks the network of individual apps on this Mac: iOS Simulator apps \
and Mac apps. Only the apps you target are affected, so your own connection, the terminal and \
test runners stay at full speed. Use it to test how an app copes with a slow or failing network, \
for example before or during end-to-end and UI tests.

Typical flow: list_targets to find the app's bundle ID and simulator; set_network with a preset \
like 3G or a failure like airplane; relaunch_app so every connection the app makes goes through \
the new conditions (needed the first time, and gives request monitoring); run the tests or use \
the app; get_requests to see what the app actually sent and got back; reset_network when done. \
fail_endpoint and mock_endpoint break or fake one endpoint while the rest works.

For simulator apps pass simulator: "booted" (the running simulator), a device name or a UDID. \
Leave simulator out for a Mac app.

Airplane mode in a simulator app launched with relaunch_app acts like a device's, within about 2 \
seconds: requests fail with NSURLErrorNotConnectedToInternet (-1009), NWPathMonitor reports an \
unsatisfied path and calls its handler, and SCNetworkReachability reports no network. The app also \
gets an in-app notification "LagsmithNetworkDidChange" (userInfo["offline"]: Bool).
"""

// MARK: Tools

struct Tool {
    let name: String
    let command: String
    let description: String
    let properties: [String: Any]
    let required: [String]
    /// Extra parameters every call sends, like a reset's preset.
    var fixed: [String: Any] = [:]
}

let app: [String: Any] = ["type": "string", "description": "The app: a bundle ID like com.me.MyApp, an app name, or * for every app in a simulator."]
let simulator: [String: Any] = ["type": "string", "description": "For iOS Simulator apps: booted, any, a device name or a UDID. Leave out for a Mac app."]

let tools: [Tool] = [
    Tool(name: "list_targets", command: "targets",
         description: "List running simulators and the apps installed on them, running Mac apps, the presets, and the current rules.",
         properties: [:], required: []),
    Tool(name: "status", command: "status",
         description: "Show every rule, what it's doing, and whether Lagsmith's proxy is running.",
         properties: [:], required: []),
    Tool(name: "set_network", command: "set",
         description: "Slow down or break one app's network, and only that app's. Creates the rule if needed and turns it on. Combine a preset with exact values or a failure mode.",
         properties: [
            "app": app, "simulator": simulator,
            "preset": ["type": "string", "description": "No Throttling, Edge, 3G, DSL, LTE, WiFi, Very Bad Network, 100% Loss, or a saved preset."],
            "down": ["type": "number", "description": "Download bandwidth in kilobits per second."],
            "up": ["type": "number", "description": "Upload bandwidth in kilobits per second."],
            "latency": ["type": "number", "description": "Added latency in milliseconds."],
            "jitter": ["type": "number", "description": "Latency variation in milliseconds."],
            "loss": ["type": "number", "description": "Packet loss percent, 0 to 100."],
            "failure": ["type": "string", "enum": ["none", "airplane", "refuse", "timeout", "drop", "outages"],
                        "description": "airplane: every connection fails at once. refuse: refuse a percent of new connections. timeout: connections never answer. drop: cut connections after some seconds. outages: go offline and back repeatedly."],
            "percent": ["type": "number", "description": "For refuse: the percent of connections refused."],
            "after": ["type": "number", "description": "For drop: seconds before a connection is cut."],
            "online": ["type": "number", "description": "For outages: seconds online."],
            "offline": ["type": "number", "description": "For outages: seconds offline."],
            "hosts": ["type": "string", "description": "Comma-separated hosts to limit the rule to, like api.me.com,*.cdn.me.com."],
            "hosts_mode": ["type": "string", "enum": ["only", "except", "all"], "description": "only (default): just those hosts; except: everything but them."],
         ], required: ["app"]),
    Tool(name: "reset_network", command: "reset",
         description: "Put an app back to full speed with no failures, host limits or endpoint rules. It stays watched, so its requests still show.",
         properties: ["app": app, "simulator": simulator], required: ["app"]),
    Tool(name: "stop_watching", command: "stop",
         description: "Turn off an app's rule. Its traffic goes back to normal and stops being watched.",
         properties: ["app": app, "simulator": simulator], required: ["app"]),
    Tool(name: "relaunch_app", command: "relaunch",
         description: "Quit and reopen a simulator app with request monitoring, so every connection it makes goes through its rule and its requests are recorded. Do this after the first set_network for an app that was already running.",
         properties: ["app": app, "simulator": simulator], required: ["app", "simulator"]),
    Tool(name: "get_requests", command: "requests",
         description: "A simulator app's recent HTTP requests, newest first: method, URL, status, errors, time, and optionally bodies. Needs the app to have been launched with request monitoring (relaunch_app).",
         properties: [
            "app": app, "simulator": simulator,
            "limit": ["type": "integer", "description": "How many, 1 to 500. Default 50."],
            "filter": ["type": "string", "description": "A search: words, or filters like status:4xx, method:POST, host:api, path:/v1, is:failed, -host:cdn."],
            "include_bodies": ["type": "boolean", "description": "Include request and response bodies (up to 4,000 characters each)."],
         ], required: ["app", "simulator"]),
    Tool(name: "fail_endpoint", command: "fail-endpoint",
         description: "Make requests to one endpoint fail inside a simulator app while the rest of the app works.",
         properties: [
            "app": app, "simulator": simulator,
            "pattern": ["type": "string", "description": "Requests whose URL contains this, like api.me.com/v1/feed. Use * for any text."],
            "kind": ["type": "string", "enum": ["offline", "timeout", "status", "delay"],
                     "description": "offline: fails as no internet. timeout: times out. status: answers with an HTTP status. delay: sent after a wait."],
            "value": ["type": "number", "description": "For status: the HTTP status (default 500). For delay: seconds (default 3). For timeout: at most this many seconds."],
         ], required: ["app", "simulator", "pattern", "kind"]),
    Tool(name: "mock_endpoint", command: "mock-endpoint",
         description: "Answer requests to one endpoint in a simulator app with a made-up response, without reaching the server.",
         properties: [
            "app": app, "simulator": simulator,
            "pattern": ["type": "string", "description": "Requests whose URL contains this, like api.me.com/v1/user. Use * for any text."],
            "status": ["type": "integer", "description": "HTTP status. Default 200."],
            "body": ["type": "string", "description": "The response body, usually JSON."],
            "content_type": ["type": "string", "description": "Default application/json."],
            "delay": ["type": "number", "description": "Seconds to wait before answering."],
         ], required: ["app", "simulator", "pattern"]),
    Tool(name: "clear_endpoints", command: "clear-endpoints",
         description: "Remove an app's endpoint failures and mocks: all of them, or those for one pattern.",
         properties: ["app": app, "simulator": simulator,
                      "pattern": ["type": "string", "description": "Only remove rules for this pattern."]],
         required: ["app"]),
]

// MARK: Calling the app

/// Runs one automation command and returns its JSON reply as text, and whether it failed.
func call(_ command: String, _ arguments: [String: Any]) -> (text: String, isError: Bool) {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/\(command)")!)
    request.httpMethod = "POST"
    // Any value works; "mcp" lets Lagsmith count how often agents use it.
    request.setValue("mcp", forHTTPHeaderField: automationHeader)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 60
    request.httpBody = try? JSONSerialization.data(withJSONObject: arguments)

    let done = DispatchSemaphore(value: 0)
    var result: (String, Bool) = ("", true)
    URLSession.shared.dataTask(with: request) { data, response, error in
        defer { done.signal() }
        guard let data = data, let http = response as? HTTPURLResponse else {
            result = ("Couldn't reach Lagsmith on 127.0.0.1:\(port). Open the app and turn on Allow Automation (menu bar icon › Automation). \(error?.localizedDescription ?? "")", true)
            return
        }
        let text = String(decoding: data, as: UTF8.self)
        result = (text, http.statusCode >= 400)
    }.resume()
    done.wait()
    return result
}

// MARK: JSON-RPC over stdio

func send(_ message: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes]) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func reply(_ id: Any, result: [String: Any]) {
    send(["jsonrpc": "2.0", "id": id, "result": result])
}

func reply(_ id: Any, errorCode: Int, message: String) {
    send(["jsonrpc": "2.0", "id": id, "error": ["code": errorCode, "message": message]])
}

func handle(_ message: [String: Any]) {
    let method = message["method"] as? String ?? ""
    // Notifications have no id and get no reply.
    guard let id = message["id"] else { return }
    let params = message["params"] as? [String: Any] ?? [:]
    switch method {
    case "initialize":
        let version = params["protocolVersion"] as? String ?? "2025-06-18"
        reply(id, result: [
            "protocolVersion": version,
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": serverName, "version": serverVersion],
            "instructions": instructions,
        ])
    case "ping":
        reply(id, result: [:])
    case "tools/list":
        reply(id, result: ["tools": tools.map { tool in
            ["name": tool.name, "description": tool.description,
             "inputSchema": ["type": "object", "properties": tool.properties, "required": tool.required]]
        }])
    case "tools/call":
        guard let name = params["name"] as? String, let tool = tools.first(where: { $0.name == name }) else {
            return reply(id, errorCode: -32602, message: "Unknown tool.")
        }
        var arguments = params["arguments"] as? [String: Any] ?? [:]
        tool.fixed.forEach { arguments[$0.key] = $0.value }
        let (text, isError) = call(tool.command, arguments)
        reply(id, result: ["content": [["type": "text", "text": text]], "isError": isError])
    default:
        reply(id, errorCode: -32601, message: "Method not found: \(method)")
    }
}

// Responses are written as they're produced; nothing else may go to stdout.
setvbuf(stdout, nil, _IONBF, 0)
while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty, let data = line.data(using: .utf8),
          let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        if !line.isEmpty { send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]]) }
        continue
    }
    handle(message)
}
