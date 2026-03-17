//
//  SessionHTTPServer.swift
//  Redactor Lite
//
//  Purpose: Lightweight HTTP server that serves session data files and the
//           live dashboard HTML to the browser. Runs on 127.0.0.1:8787.
//           Cowork's pipeline writes session_state.json; this server serves it.
//  Organization: 3 Big Things
//

import Foundation
import Network
import AppKit

// MARK: - Session HTTP Server

@MainActor
final class SessionHTTPServer {

    // MARK: - Shared Instance

    static let shared = SessionHTTPServer()

    // MARK: - Properties

    private var listener: NWListener?
    private var sessionFolder: URL?
    private var authToken: String = ""
    private(set) var isRunning = false
    private(set) var port: UInt16 = 8787

    private init() {}

    // MARK: - Public Methods

    /// Start serving session data from the given folder
    func start(sessionFolder: URL) {
        guard !isRunning else { return }

        self.sessionFolder = sessionFolder
        self.authToken = generateToken()

        // Write token file so Cowork pipeline can read it
        writeTokenFile()

        // Copy dashboard HTML template into session folder
        copyDashboardTemplate()

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
                        print("[SessionHTTPServer] Listening on 127.0.0.1:\(self?.port ?? 8787)")
                    case .failed(let error):
                        print("[SessionHTTPServer] Failed: \(error)")
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }
            listener?.start(queue: .main)
        } catch {
            print("[SessionHTTPServer] Error starting: \(error)")
        }
    }

    /// Stop the server
    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        print("[SessionHTTPServer] Stopped")
    }

    /// Open the dashboard in the default browser
    func openDashboard() {
        guard isRunning else { return }
        let url = URL(string: "http://127.0.0.1:\(port)/dashboard")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                connection.cancel()
                return
            }
            let request = String(data: data, encoding: .utf8) ?? ""
            Task { @MainActor in
                self.handleRequest(request, connection: connection)
            }
        }
    }

    private func handleRequest(_ request: String, connection: NWConnection) {
        // Parse first line: GET /path?query HTTP/1.1
        let firstLine = request.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"bad request\"}")
            return
        }

        let fullPath = parts[1]
        let components = fullPath.components(separatedBy: "?")
        let path = components[0]
        let query = components.count > 1 ? components[1] : ""

        // Dashboard — no auth required (served to browser)
        if path == "/dashboard" {
            serveDashboard(connection: connection)
            return
        }

        // Health check — no auth required
        if path == "/health" {
            sendJSON(connection: connection, json: "{\"status\":\"ok\"}")
            return
        }

        // All other endpoints require auth
        guard checkToken(query: query) else {
            sendResponse(connection: connection, status: 403, body: "{\"error\":\"invalid or missing token\"}")
            return
        }

        switch path {
        case "/state":
            serveFile(connection: connection, filename: "session_state.json")
        case "/entities":
            serveFile(connection: connection, filename: "entity_map.json")
        case "/complete":
            if let folder = sessionFolder,
               FileManager.default.fileExists(atPath: folder.appendingPathComponent("session_complete.json").path) {
                serveFile(connection: connection, filename: "session_complete.json")
            } else {
                sendJSON(connection: connection, json: "{\"complete\":false}")
            }
        default:
            sendResponse(connection: connection, status: 404, body: "{\"error\":\"not found\"}")
        }
    }

    // MARK: - File Serving

    private func serveFile(connection: NWConnection, filename: String) {
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

    private func serveDashboard(connection: NWConnection) {
        guard let folder = sessionFolder else {
            sendResponse(connection: connection, status: 500, body: "No session")
            return
        }
        let htmlURL = folder.appendingPathComponent("dashboard.html")
        guard let data = try? Data(contentsOf: htmlURL),
              var html = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, status: 404, body: "dashboard.html not found")
            return
        }
        // Inject the auth token at serve time
        html = html.replacingOccurrences(of: "__SESSION_TOKEN__", with: authToken)
        sendHTML(connection: connection, html: html)
    }

    // MARK: - Auth

    private func checkToken(query: String) -> Bool {
        // Parse token=xxx from query string
        let params = query.components(separatedBy: "&")
        for param in params {
            let kv = param.components(separatedBy: "=")
            if kv.count == 2 && kv[0] == "token" && kv[1] == authToken {
                return true
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

    // MARK: - Response Helpers

    private func sendJSON(connection: NWConnection, json: String) {
        let headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: application/json",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, OPTIONS",
            "Cache-Control: no-cache, no-store",
            "Connection: close",
            "Content-Length: \(json.utf8.count)",
            "", ""
        ].joined(separator: "\r\n")
        let response = headers + json
        send(connection: connection, string: response)
    }

    private func sendHTML(connection: NWConnection, html: String) {
        let headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/html; charset=utf-8",
            "Cache-Control: no-cache, no-store",
            "Connection: close",
            "Content-Length: \(html.utf8.count)",
            "", ""
        ].joined(separator: "\r\n")
        let response = headers + html
        send(connection: connection, string: response)
    }

    private func sendResponse(connection: NWConnection, status: Int, body: String) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
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

    // MARK: - Dashboard Template

    private func copyDashboardTemplate() {
        guard let folder = sessionFolder else { return }
        let destURL = folder.appendingPathComponent("dashboard.html")

        // Don't overwrite if it already exists
        guard !FileManager.default.fileExists(atPath: destURL.path) else { return }

        // Look for dashboard.html template in CoWork Files folder
        // (sibling to the TEMP Transcripts folder, i.e. parent of parent)
        let coworkFolder = folder
            .deletingLastPathComponent()  // TEMP Transcripts
            .deletingLastPathComponent()  // project root
            .appendingPathComponent("CoWork Files")
            .appendingPathComponent("dashboard.html")

        if FileManager.default.fileExists(atPath: coworkFolder.path) {
            try? FileManager.default.copyItem(at: coworkFolder, to: destURL)
            print("[SessionHTTPServer] Copied dashboard template to session folder")
        }
    }
}
