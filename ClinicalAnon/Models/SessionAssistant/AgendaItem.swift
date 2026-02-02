//
//  AgendaItem.swift
//  ClinicalAnon
//
//  Purpose: Agenda item model for session assistant parking lot
//  Organization: 3 Big Things
//

import Foundation
import SwiftUI

struct AgendaItem: Identifiable, Codable, Equatable {
    let id: UUID
    var stableId: String              // AI-assigned ID for continuity across analyses
    var topic: String
    var agreedAt: TimeInterval
    var status: AgendaStatus
    var evidence: String?
    var timeRange: TimeRange?
    var isManuallyAdded: Bool
    var parentId: String?             // For sub-items (references parent's stableId)
    var progressNotes: [ProgressNote] // Timestamped progress tracking

    init(
        id: UUID = UUID(),
        stableId: String? = nil,
        topic: String,
        agreedAt: TimeInterval,
        status: AgendaStatus = .notStarted,
        evidence: String? = nil,
        timeRange: TimeRange? = nil,
        isManuallyAdded: Bool = false,
        parentId: String? = nil,
        progressNotes: [ProgressNote] = []
    ) {
        self.id = id
        self.stableId = stableId ?? "manual_\(id.uuidString.prefix(8))"
        self.topic = topic
        self.agreedAt = agreedAt
        self.status = status
        self.evidence = evidence
        self.timeRange = timeRange
        self.isManuallyAdded = isManuallyAdded
        self.parentId = parentId
        self.progressNotes = progressNotes
    }

    var statusIcon: String {
        status.icon
    }

    var statusColor: Color {
        status.color
    }

    /// Returns true if this is a top-level item (not a sub-item)
    var isTopLevel: Bool {
        parentId == nil
    }
}

// MARK: - Progress Note

struct ProgressNote: Codable, Equatable, Identifiable {
    let id: UUID
    var timestamp: TimeInterval
    var note: String
    var statusAtTime: AgendaStatus

    init(id: UUID = UUID(), timestamp: TimeInterval, note: String, statusAtTime: AgendaStatus) {
        self.id = id
        self.timestamp = timestamp
        self.note = note
        self.statusAtTime = statusAtTime
    }
}

enum AgendaStatus: String, Codable, CaseIterable {
    case notStarted = "not_started"
    case partial
    case covered

    var icon: String {
        switch self {
        case .notStarted: return "circle"
        case .partial: return "circle.lefthalf.filled"
        case .covered: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .notStarted: return .secondary
        case .partial: return .orange
        case .covered: return .green
        }
    }

    var displayName: String {
        switch self {
        case .notStarted: return "Not Started"
        case .partial: return "In Progress"
        case .covered: return "Covered"
        }
    }
}

struct TimeRange: Codable, Equatable {
    var start: TimeInterval
    var end: TimeInterval

    var duration: TimeInterval {
        end - start
    }

    var formatted: String {
        "\(formatTime(start)) – \(formatTime(end))"
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
