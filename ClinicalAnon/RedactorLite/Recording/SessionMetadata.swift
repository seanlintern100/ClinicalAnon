//
//  SessionMetadata.swift
//  Redactor Lite
//
//  Purpose: Metadata model for a recording session (saved as session_info.json)
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Session Type

enum SessionType: String, Codable, CaseIterable, Identifiable {
    case therapy = "Therapy"
    case coaching = "Coaching"
    case supervision = "Supervision"
    case other = "Other"

    var id: String { rawValue }
}

// MARK: - Session Metadata

struct SessionMetadata: Codable {
    var clientInitials: String
    var sessionType: SessionType
    var otherTypeDescription: String?
    var sessionDate: Date
    var sessionLengthMinutes: Int
    var sessionGoals: String

    // MARK: - Defaults

    static var `default`: SessionMetadata {
        SessionMetadata(
            clientInitials: "",
            sessionType: .therapy,
            sessionDate: Date(),
            sessionLengthMinutes: lastUsedLength,
            sessionGoals: ""
        )
    }

    // MARK: - Folder Name

    /// Generates folder name like "JB_2026-03-17_1430"
    var folderName: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmm"
        let dateStr = dateFormatter.string(from: sessionDate)
        let initials = clientInitials.trimmingCharacters(in: .whitespaces).uppercased()
        return "\(initials)_\(dateStr)"
    }

    // MARK: - Persistence of Last-Used Values

    private static let lastInitialsKey = "cowork.lastClientInitials"
    private static let lastTypeKey = "cowork.lastSessionType"
    private static let lastLengthKey = "cowork.lastSessionLength"

    static var lastUsedLength: Int {
        let stored = UserDefaults.standard.integer(forKey: lastLengthKey)
        return stored > 0 ? stored : 50
    }

    /// Save current values for pre-populating next session
    func saveAsLastUsed() {
        UserDefaults.standard.set(clientInitials, forKey: Self.lastInitialsKey)
        UserDefaults.standard.set(sessionType.rawValue, forKey: Self.lastTypeKey)
        UserDefaults.standard.set(sessionLengthMinutes, forKey: Self.lastLengthKey)
    }

    /// Pre-populate from last-used values (initials cleared, type and length preserved)
    static func fromLastUsed() -> SessionMetadata {
        let typeStr = UserDefaults.standard.string(forKey: lastTypeKey) ?? "Therapy"
        let sessionType = SessionType(rawValue: typeStr) ?? .therapy
        return SessionMetadata(
            clientInitials: "",
            sessionType: sessionType,
            sessionDate: Date(),
            sessionLengthMinutes: lastUsedLength,
            sessionGoals: ""
        )
    }
}
