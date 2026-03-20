//
//  CopilotHTTPServer.swift
//  Redactor Lite
//
//  Purpose: Lightweight HTTP server for MCP copilot control and session data.
//           Runs on 127.0.0.1:8787. Supports standby mode (health only)
//           and active session mode (full API).
//  Organization: 3 Big Things
//

import Foundation
import Network
import AppKit

// MARK: - MCP Notification Names

extension Notification.Name {
    static let mcpStopRecording = Notification.Name("mcpStopRecording")
    static let mcpPauseRecording = Notification.Name("mcpPauseRecording")
    static let mcpResumeRecording = Notification.Name("mcpResumeRecording")
    static let clinicalNotesReceived = Notification.Name("clinicalNotesReceived")
}

// MARK: - Copilot HTTP Server

@MainActor
final class CopilotHTTPServer: ObservableObject {

    // MARK: - Shared Instance

    static let shared = CopilotHTTPServer()

    // MARK: - Properties

    private var listener: NWListener?
    private var sessionFolder: URL?
    private(set) var authToken: String = ""
    @Published private(set) var isRunning = false
    private(set) var port: UInt16 = 8787

    /// Private folder URL for entity_map.json (separate from session folder)
    var privateFolderURL: URL?

    /// Whether a session is currently active (folder + token assigned)
    var isSessionActive: Bool { sessionFolder != nil }

    private init() {}

    // MARK: - Public Methods

    /// Start the TCP listener in standby mode. Only /health responds until a session is activated.
    func startListening() {
        guard !isRunning else { return }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleConnection(connection)
                }
            }
            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        print("[CopilotHTTPServer] Listening on 127.0.0.1:\(self?.port ?? 8787)")
                    case .failed(let error):
                        print("[CopilotHTTPServer] Failed: \(error)")
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }
            listener?.start(queue: .main)
        } catch {
            print("[CopilotHTTPServer] Error starting: \(error)")
        }
    }

    /// Activate a session: sets folder, generates token, writes token file and initial state.
    /// Does NOT start the listener (call startListening() first or use start(sessionFolder:)).
    func activateSession(sessionFolder: URL) {
        self.sessionFolder = sessionFolder
        self.authToken = generateToken()
        writeTokenFile()
        writeInitialSessionState()
        print("[CopilotHTTPServer] Session activated: \(sessionFolder.lastPathComponent)")
    }

    /// Convenience: start listener + activate session in one call.
    func start(sessionFolder: URL) {
        if !isRunning {
            startListening()
        }
        activateSession(sessionFolder: sessionFolder)
    }

    /// Deactivate the current session (clears folder/token but keeps listener alive)
    func deactivateSession() {
        sessionFolder = nil
        authToken = ""
        privateFolderURL = nil
        print("[CopilotHTTPServer] Session deactivated")
    }

    /// Stop the server entirely
    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        sessionFolder = nil
        authToken = ""
        privateFolderURL = nil
        print("[CopilotHTTPServer] Stopped")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        // Accumulate data until we have the full HTTP request (headers + body)
        var accumulated = Data()
        func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                guard let self = self else { connection.cancel(); return }
                if let data = data { accumulated.append(data) }
                if error != nil { connection.cancel(); return }

                let request = String(data: accumulated, encoding: .utf8) ?? ""

                // Check if we have the full body by reading Content-Length
                if let clRange = request.range(of: "Content-Length: "),
                   let endRange = request[clRange.upperBound...].range(of: "\r\n") {
                    let clStr = String(request[clRange.upperBound..<endRange.lowerBound])
                    if let contentLength = Int(clStr),
                       let bodyStart = request.range(of: "\r\n\r\n") {
                        let bodyBytes = request[bodyStart.upperBound...].utf8.count
                        if bodyBytes < contentLength && !isComplete {
                            // Need more data
                            readMore()
                            return
                        }
                    }
                }

                Task { @MainActor in
                    self.handleRequest(request, connection: connection)
                }
            }
        }
        readMore()
    }

    private func handleRequest(_ request: String, connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        let firstLine = lines.first ?? ""
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"bad request\"}")
            return
        }

        let method = parts[0]
        let fullPath = parts[1]
        let components = fullPath.components(separatedBy: "?")
        let path = components[0]
        let query = components.count > 1 ? components[1] : ""

        // OPTIONS preflight — always allowed
        if method == "OPTIONS" {
            sendCORSPreflight(connection: connection)
            return
        }

        // Health check — no auth required
        if path == "/health" {
            let active = isSessionActive ? "true" : "false"
            sendJSON(connection: connection, json: "{\"status\":\"ok\",\"session_active\":\(active)}")
            return
        }

        // POST /start — no auth required (creates the session)
        if method == "POST" && path == "/start" {
            handleStartSession(request: request, connection: connection)
            return
        }

        // All other endpoints require auth
        guard checkToken(query: query, headers: lines) else {
            sendResponse(connection: connection, status: 403, body: "{\"error\":\"invalid or missing token\"}")
            return
        }

        switch (method, path) {
        // MCP control endpoints
        case ("POST", "/stop"):
            NotificationCenter.default.post(name: .mcpStopRecording, object: nil)
            sendJSON(connection: connection, json: "{\"status\":\"stopping\"}")

        case ("POST", "/pause"):
            NotificationCenter.default.post(name: .mcpPauseRecording, object: nil)
            sendJSON(connection: connection, json: "{\"status\":\"pausing\"}")

        case ("POST", "/resume"):
            NotificationCenter.default.post(name: .mcpResumeRecording, object: nil)
            sendJSON(connection: connection, json: "{\"status\":\"resuming\"}")

        case ("POST", "/state"):
            handlePostState(request: request, connection: connection)

        // Data endpoints
        case ("GET", "/state"):
            serveSessionFile(connection: connection, filename: "session_state.json")

        case ("GET", "/entities"):
            serveEntityMap(connection: connection)

        case ("GET", "/session-info"):
            serveSessionFile(connection: connection, filename: "session_info.json")

        case ("GET", "/complete"):
            if let folder = sessionFolder,
               FileManager.default.fileExists(atPath: folder.appendingPathComponent("session_complete.json").path) {
                serveSessionFile(connection: connection, filename: "session_complete.json")
            } else {
                sendJSON(connection: connection, json: "{\"complete\":false}")
            }

        case ("GET", "/chunks"):
            handleGetChunks(query: query, connection: connection)

        case ("POST", "/notes"):
            handlePostNotes(request: request, connection: connection)

        case ("GET", "/notes"):
            serveSessionFile(connection: connection, filename: "clinical_notes.json")

        default:
            sendResponse(connection: connection, status: 404, body: "{\"error\":\"not found\"}")
        }
    }

    // MARK: - POST /start Handler

    private func handleStartSession(request: String, connection: NWConnection) {
        // Parse JSON body from request
        let body = extractBody(from: request)
        var info: [String: String] = [:]

        if let bodyData = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            if let initials = json["initials"] as? String { info["initials"] = initials }
            if let type = json["type"] as? String { info["type"] = type }
            if let length = json["length"] as? Int { info["length"] = String(length) }
            if let length = json["length"] as? String { info["length"] = length }
            if let goals = json["goals"] as? String { info["goals"] = goals }
            if let multi = json["multiSpeaker"] as? Bool { info["multiSpeaker"] = multi ? "true" : "false" }
            if let multi = json["multiSpeaker"] as? String { info["multiSpeaker"] = multi }
        }

        // Close existing recording window if open, then open fresh
        if RecordingWindowController.shared.isWindowOpen {
            RecordingWindowController.shared.closeRecordingWindow()
            // Brief delay to allow cleanup before reopening
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                RecordingWindowController.shared.showRecordingWindow()
                // Post auto-start notification with metadata
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(
                        name: .autoStartRecording,
                        object: nil,
                        userInfo: info
                    )
                }
            }
        } else {
            RecordingWindowController.shared.showRecordingWindow()
            // Post auto-start notification with metadata after window settles
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(
                    name: .autoStartRecording,
                    object: nil,
                    userInfo: info
                )
            }
        }

        sendJSON(connection: connection, json: "{\"status\":\"starting\"}")
    }

    // MARK: - POST /state Handler

    private func handlePostState(request: String, connection: NWConnection) {
        guard let folder = sessionFolder else {
            sendResponse(connection: connection, status: 500, body: "{\"error\":\"no session folder\"}")
            return
        }
        let body = extractBody(from: request)
        guard !body.isEmpty else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"empty body\"}")
            return
        }
        let stateURL = folder.appendingPathComponent("session_state.json")
        do {
            // Preserve therapist_request if the incoming state doesn't include one
            // (prevents Cowork from accidentally overwriting the app's request)
            if var incoming = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] {
                if incoming["therapist_request"] == nil || incoming["therapist_request"] is NSNull {
                    if let existing = try? Data(contentsOf: stateURL),
                       let current = try? JSONSerialization.jsonObject(with: existing) as? [String: Any],
                       let req = current["therapist_request"] as? String, !req.isEmpty {
                        incoming["therapist_request"] = req
                    }
                }
                let merged = try JSONSerialization.data(withJSONObject: incoming, options: [.prettyPrinted, .sortedKeys])
                try merged.write(to: stateURL, options: .atomic)
            } else {
                try body.write(to: stateURL, atomically: true, encoding: .utf8)
            }
            sendJSON(connection: connection, json: "{\"status\":\"ok\"}")
        } catch {
            sendResponse(connection: connection, status: 500, body: "{\"error\":\"write failed\"}")
        }
    }

    // MARK: - POST /notes Handler

    private func handlePostNotes(request: String, connection: NWConnection) {
        guard let folder = sessionFolder else {
            sendResponse(connection: connection, status: 500, body: "{\"error\":\"no session folder\"}")
            return
        }
        let body = extractBody(from: request)
        guard !body.isEmpty else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"empty body\"}")
            return
        }
        let notesURL = folder.appendingPathComponent("clinical_notes.json")
        do {
            if let parsed = try? JSONSerialization.jsonObject(with: Data(body.utf8)),
               let pretty = try? JSONSerialization.data(withJSONObject: parsed, options: [.prettyPrinted, .sortedKeys]) {
                try pretty.write(to: notesURL, options: .atomic)
            } else {
                try body.write(to: notesURL, atomically: true, encoding: .utf8)
            }
            NotificationCenter.default.post(name: .clinicalNotesReceived, object: nil)
            sendJSON(connection: connection, json: "{\"status\":\"ok\"}")
        } catch {
            sendResponse(connection: connection, status: 500, body: "{\"error\":\"write failed\"}")
        }
    }

    // MARK: - GET /chunks Handler

    private func handleGetChunks(query: String, connection: NWConnection) {
        guard let folder = sessionFolder else {
            sendResponse(connection: connection, status: 500, body: "{\"error\":\"no session folder\"}")
            return
        }

        // Parse since=N from query
        var since = 0
        let params = query.components(separatedBy: "&")
        for param in params {
            let kv = param.components(separatedBy: "=")
            if kv.count == 2 && kv[0] == "since", let n = Int(kv[1]) {
                since = n
            }
        }

        // Find chunk files with index > since
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            sendJSON(connection: connection, json: "[]")
            return
        }

        var chunks: [(index: Int, content: String)] = []
        for file in files {
            let name = file.lastPathComponent
            // Match chunk_NNN.json pattern
            guard name.hasPrefix("chunk_") && name.hasSuffix(".json") else { continue }
            let indexStr = name.dropFirst(6).dropLast(5) // Remove "chunk_" and ".json"
            guard let index = Int(indexStr), index > since else { continue }
            if let data = try? Data(contentsOf: file),
               let content = String(data: data, encoding: .utf8) {
                chunks.append((index: index, content: content))
            }
        }

        // Sort by index
        chunks.sort { $0.index < $1.index }

        // Build JSON array from raw chunk contents
        let jsonArray = "[" + chunks.map { $0.content }.joined(separator: ",") + "]"
        sendJSON(connection: connection, json: jsonArray)
    }

    // MARK: - File Serving

    private func serveSessionFile(connection: NWConnection, filename: String) {
        guard let folder = sessionFolder else {
            sendResponse(connection: connection, status: 500, body: "{\"error\":\"no session folder\"}")
            return
        }
        let fileURL = folder.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, status: 404, body: "{\"error\":\"\(filename) not found\"}")
            return
        }
        sendJSON(connection: connection, json: content)
    }

    private func serveEntityMap(connection: NWConnection) {
        // Entity map lives in the Private/ folder, not the session folder
        if let privateFolder = privateFolderURL {
            let fileURL = privateFolder.appendingPathComponent("entity_map.json")
            if let data = try? Data(contentsOf: fileURL),
               let content = String(data: data, encoding: .utf8) {
                sendJSON(connection: connection, json: content)
                return
            }
        }
        // Fallback: try session folder
        serveSessionFile(connection: connection, filename: "entity_map.json")
    }

    // MARK: - Auth

    private func checkToken(query: String, headers: [String]) -> Bool {
        // Check query string: token=xxx
        let params = query.components(separatedBy: "&")
        for param in params {
            let kv = param.components(separatedBy: "=")
            if kv.count == 2 && kv[0] == "token" && kv[1] == authToken {
                return true
            }
        }

        // Check Authorization: Bearer xxx header
        for line in headers {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("authorization:") {
                let value = trimmed.dropFirst("authorization:".count).trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("Bearer ") {
                    let token = String(value.dropFirst("Bearer ".count))
                    if token == authToken {
                        return true
                    }
                }
            }
        }

        return false
    }

    private func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Request Parsing

    private func extractBody(from request: String) -> String {
        // HTTP body comes after the blank line (\r\n\r\n)
        let parts = request.components(separatedBy: "\r\n\r\n")
        guard parts.count >= 2 else { return "" }
        return parts.dropFirst().joined(separator: "\r\n\r\n")
    }

    // MARK: - Response Helpers

    private func sendJSON(connection: NWConnection, json: String) {
        let headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: application/json",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Authorization, Content-Type",
            "Cache-Control: no-cache, no-store",
            "Connection: close",
            "Content-Length: \(json.utf8.count)",
            "", ""
        ].joined(separator: "\r\n")
        let response = headers + json
        send(connection: connection, string: response)
    }

    private func sendCORSPreflight(connection: NWConnection) {
        let headers = [
            "HTTP/1.1 204 No Content",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Authorization, Content-Type",
            "Access-Control-Max-Age: 86400",
            "Connection: close",
            "Content-Length: 0",
            "", ""
        ].joined(separator: "\r\n")
        send(connection: connection, string: headers)
    }

    private func sendResponse(connection: NWConnection, status: Int, body: String) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 204: statusText = "No Content"
        case 400: statusText = "Bad Request"
        case 403: statusText = "Forbidden"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Error"
        }
        let headers = [
            "HTTP/1.1 \(status) \(statusText)",
            "Content-Type: application/json",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Authorization, Content-Type",
            "Connection: close",
            "Content-Length: \(body.utf8.count)",
            "", ""
        ].joined(separator: "\r\n")
        let response = headers + body
        send(connection: connection, string: response)
    }

    private func send(connection: NWConnection, string: String) {
        let data = Data(string.utf8)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Token File

    private func writeTokenFile() {
        guard let folder = sessionFolder else { return }
        let tokenData: [String: Any] = ["token": authToken, "port": Int(port)]
        let tokenURL = folder.appendingPathComponent(".server_token")
        if let data = try? JSONSerialization.data(withJSONObject: tokenData) {
            try? data.write(to: tokenURL)
        }
    }

    // MARK: - Initial Session State

    private func writeInitialSessionState() {
        guard let folder = sessionFolder else { return }
        let stateURL = folder.appendingPathComponent("session_state.json")
        let initialState: [String: Any] = [
            "phase": "setup",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: initialState, options: .prettyPrinted) {
            try? data.write(to: stateURL)
        }
    }
}
