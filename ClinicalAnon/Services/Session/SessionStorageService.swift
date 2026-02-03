//
//  SessionStorageService.swift
//  ClinicalAnon
//
//  Purpose: Handles persistence of live session data to disk
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Session Storage Error

enum SessionStorageError: Error, LocalizedError {
    case directoryCreationFailed(String)
    case sessionSaveFailed(String)
    case sessionLoadFailed(String)
    case sessionNotFound(UUID)
    case deletionFailed(String)
    case invalidSessionData

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let path):
            return "Failed to create session directory at \(path)"
        case .sessionSaveFailed(let reason):
            return "Failed to save session: \(reason)"
        case .sessionLoadFailed(let reason):
            return "Failed to load session: \(reason)"
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        case .deletionFailed(let reason):
            return "Failed to delete session: \(reason)"
        case .invalidSessionData:
            return "Session data is invalid or corrupted"
        }
    }
}

// MARK: - Session Storage Service

/// Handles persistence of live session data to disk
@MainActor
class SessionStorageService {

    // MARK: - Singleton

    static let shared = SessionStorageService()

    // MARK: - Configuration

    /// Base directory for all session data
    private let sessionsBaseDirectory: URL

    /// File name for session metadata JSON
    private let sessionMetadataFilename = "session.json"

    /// Subdirectory name for audio files
    private let audioSubdirectory = "audio"

    // MARK: - Initialization

    private init() {
        // Use Application Support directory for persistent storage
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        sessionsBaseDirectory = appSupport
            .appendingPathComponent("Redactor", isDirectory: true)
            .appendingPathComponent("Sessions", isDirectory: true)

        // Create base directory if needed
        try? FileManager.default.createDirectory(
            at: sessionsBaseDirectory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Static Directory Helpers

    /// Get the directory for a specific session
    static func sessionDirectory(for session: LiveSession) -> URL {
        return SessionStorageService.shared.sessionsBaseDirectory
            .appendingPathComponent(session.id.uuidString, isDirectory: true)
    }

    /// Get the audio directory for a specific session
    static func audioDirectory(for session: LiveSession) -> URL {
        return sessionDirectory(for: session)
            .appendingPathComponent("audio", isDirectory: true)
    }

    // MARK: - Directory Management

    /// Create session directory structure
    func createSessionDirectory(for session: LiveSession) throws {
        let sessionDir = Self.sessionDirectory(for: session)
        let audioDir = sessionDir.appendingPathComponent(audioSubdirectory, isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: sessionDir,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: audioDir,
                withIntermediateDirectories: true
            )
        } catch {
            throw SessionStorageError.directoryCreationFailed(sessionDir.path)
        }
    }

    /// Check if session directory exists
    func sessionDirectoryExists(for session: LiveSession) -> Bool {
        let sessionDir = Self.sessionDirectory(for: session)
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: sessionDir.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    // MARK: - Session Persistence

    /// Save session metadata to disk
    /// - Parameters:
    ///   - session: The session to save
    ///   - assistantState: Optional AI assistant state (parking lot) to persist with session
    func saveSession(_ session: LiveSession, assistantState: SessionAssistantStateData? = nil) async throws {
        let sessionDir = Self.sessionDirectory(for: session)
        let metadataURL = sessionDir.appendingPathComponent(sessionMetadataFilename)

        // Ensure directory exists
        if !sessionDirectoryExists(for: session) {
            try createSessionDirectory(for: session)
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            // Use LiveSessionData for encoding, including assistant state
            let sessionData = LiveSessionData(from: session, assistantState: assistantState)
            let data = try encoder.encode(sessionData)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            throw SessionStorageError.sessionSaveFailed(error.localizedDescription)
        }
    }

    /// Load a single session from disk
    func loadSession(id: UUID) async throws -> LiveSession {
        let sessionDir = sessionsBaseDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        let metadataURL = sessionDir.appendingPathComponent(sessionMetadataFilename)

        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw SessionStorageError.sessionNotFound(id)
        }

        do {
            let data = try Data(contentsOf: metadataURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            // Decode to LiveSessionData, then create LiveSession
            let sessionData = try decoder.decode(LiveSessionData.self, from: data)
            let session = LiveSession(from: sessionData)
            return session
        } catch {
            throw SessionStorageError.sessionLoadFailed(error.localizedDescription)
        }
    }

    /// Load all sessions from disk
    func loadAllSessions() async throws -> [LiveSession] {
        let result = try await loadAllSessionsWithState()
        return result.sessions
    }

    /// Result type for loading sessions with their assistant state
    struct SessionLoadResult {
        let sessions: [LiveSession]
        let assistantStates: [UUID: SessionAssistantStateData]
    }

    /// Load all sessions from disk, including their assistant state data
    func loadAllSessionsWithState() async throws -> SessionLoadResult {
        var sessions: [LiveSession] = []
        var assistantStates: [UUID: SessionAssistantStateData] = [:]

        let contents = try FileManager.default.contentsOfDirectory(
            at: sessionsBaseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for item in contents {
            // Check if this is a valid session directory (UUID format)
            guard let _ = UUID(uuidString: item.lastPathComponent) else {
                continue
            }

            let metadataURL = item.appendingPathComponent(sessionMetadataFilename)

            // Skip if no metadata file
            guard FileManager.default.fileExists(atPath: metadataURL.path) else {
                continue
            }

            do {
                let data = try Data(contentsOf: metadataURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                // Decode to LiveSessionData, then create LiveSession
                let sessionData = try decoder.decode(LiveSessionData.self, from: data)
                let session = LiveSession(from: sessionData)
                sessions.append(session)

                // Cache the assistant state if present
                if let assistantState = sessionData.assistantStateData {
                    assistantStates[session.id] = assistantState
                }
            } catch {
                // Log error but continue loading other sessions
                print("SessionStorageService: Failed to load session at \(item.path): \(error)")
                continue
            }
        }

        // Sort by creation date (newest first)
        let sortedSessions = sessions.sorted { $0.createdAt > $1.createdAt }
        return SessionLoadResult(sessions: sortedSessions, assistantStates: assistantStates)
    }

    // MARK: - Session Deletion

    /// Delete a session and all associated files
    func deleteSession(_ session: LiveSession) async throws {
        let sessionDir = Self.sessionDirectory(for: session)

        guard FileManager.default.fileExists(atPath: sessionDir.path) else {
            // Already deleted, nothing to do
            return
        }

        do {
            try FileManager.default.removeItem(at: sessionDir)
        } catch {
            throw SessionStorageError.deletionFailed(error.localizedDescription)
        }
    }

    /// Delete a session by ID
    func deleteSession(id: UUID) async throws {
        let sessionDir = sessionsBaseDirectory.appendingPathComponent(id.uuidString, isDirectory: true)

        guard FileManager.default.fileExists(atPath: sessionDir.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: sessionDir)
        } catch {
            throw SessionStorageError.deletionFailed(error.localizedDescription)
        }
    }

    // MARK: - Audio File Helpers

    /// Get the URL for an audio chunk file
    func audioChunkURL(for session: LiveSession, stream: AudioStream, chunkIndex: Int) -> URL {
        let audioDir = Self.audioDirectory(for: session)
        let filename = "\(stream.rawValue)_\(String(format: "%03d", chunkIndex)).m4a"
        return audioDir.appendingPathComponent(filename)
    }

    /// Check if an audio chunk exists
    func audioChunkExists(for session: LiveSession, stream: AudioStream, chunkIndex: Int) -> Bool {
        let url = audioChunkURL(for: session, stream: stream, chunkIndex: chunkIndex)
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Get the file size of an audio chunk
    func audioChunkSize(for session: LiveSession, stream: AudioStream, chunkIndex: Int) -> Int64 {
        let url = audioChunkURL(for: session, stream: stream, chunkIndex: chunkIndex)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return 0
        }
        return size
    }

    // MARK: - Statistics

    /// Get total storage used by all sessions
    func totalStorageUsed() -> Int64 {
        var totalSize: Int64 = 0

        if let enumerator = FileManager.default.enumerator(
            at: sessionsBaseDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
        }

        return totalSize
    }

    /// Get storage used by a specific session
    func storageUsed(for session: LiveSession) -> Int64 {
        let sessionDir = Self.sessionDirectory(for: session)
        var totalSize: Int64 = 0

        if let enumerator = FileManager.default.enumerator(
            at: sessionDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
        }

        return totalSize
    }

    /// Format bytes as human-readable string
    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Cleanup

    /// Delete all session data (for privacy/reset)
    func deleteAllSessions() async throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: sessionsBaseDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for item in contents {
            try FileManager.default.removeItem(at: item)
        }
    }

    /// Delete sessions older than a specified number of days
    func deleteSessionsOlderThan(days: Int) async throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        let sessions = try await loadAllSessions()

        for session in sessions {
            if session.createdAt < cutoffDate {
                try await deleteSession(session)
            }
        }
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension SessionStorageService {
    /// Create a mock storage service for testing
    static var preview: SessionStorageService {
        return SessionStorageService.shared
    }
}
#endif
