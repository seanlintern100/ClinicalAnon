//
//  FeedItem.swift
//  ClinicalAnon
//
//  Purpose: Feed item model for session assistant live feed
//  Organization: 3 Big Things
//

import Foundation
import SwiftUI

struct FeedItem: Identifiable, Codable, Equatable {
    let id: UUID
    var itemType: FeedItemType
    var content: String
    var rationale: String
    var timestamp: TimeInterval
    var createdAt: Date
    var status: FeedItemStatus

    // Optional associated data for specific types
    var detailCategory: String?       // AI-determined category string
    var flagSeverity: FlagSeverity?
    var agendaTopic: String?
    var agendaStatus: AgendaStatus?

    init(
        id: UUID = UUID(),
        itemType: FeedItemType,
        content: String,
        rationale: String,
        timestamp: TimeInterval,
        createdAt: Date = Date(),
        status: FeedItemStatus = .active,
        detailCategory: String? = nil,
        flagSeverity: FlagSeverity? = nil,
        agendaTopic: String? = nil,
        agendaStatus: AgendaStatus? = nil
    ) {
        self.id = id
        self.itemType = itemType
        self.content = content
        self.rationale = rationale
        self.timestamp = timestamp
        self.createdAt = createdAt
        self.status = status
        self.detailCategory = detailCategory
        self.flagSeverity = flagSeverity
        self.agendaTopic = agendaTopic
        self.agendaStatus = agendaStatus
    }

    var icon: String {
        switch itemType {
        case .detail:
            return iconForCategory(detailCategory)
        case .flag:
            return flagSeverity?.icon ?? "flag"
        case .suggestion:
            return "lightbulb"
        case .agendaUpdate:
            return "list.bullet.clipboard"
        }
    }

    private func iconForCategory(_ category: String?) -> String {
        guard let cat = category?.lowercased() else { return "pin.fill" }
        switch cat {
        case "person": return "person.fill"
        case "relationship": return "heart.fill"
        case "employment": return "briefcase.fill"
        case "living situation": return "house.fill"
        case "health": return "cross.case.fill"
        case "key event": return "star.fill"
        default: return "pin.fill"
        }
    }

    var iconColor: Color {
        switch itemType {
        case .flag:
            return flagSeverity?.color ?? .yellow
        case .suggestion:
            return .blue
        default:
            return .secondary
        }
    }

    var formattedTimestamp: String {
        let mins = Int(timestamp) / 60
        let secs = Int(timestamp) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

enum FeedItemType: String, Codable {
    case detail
    case flag
    case suggestion
    case agendaUpdate
}

enum FeedItemStatus: String, Codable {
    case active
    case starred
    case dismissed
}

enum FlagSeverity: String, Codable, CaseIterable {
    case safety
    case important
    case note

    var icon: String {
        switch self {
        case .safety: return "exclamationmark.triangle.fill"
        case .important: return "exclamationmark.circle.fill"
        case .note: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .safety: return .red
        case .important: return .orange
        case .note: return .yellow
        }
    }

    var displayName: String {
        rawValue.uppercased()
    }
}
