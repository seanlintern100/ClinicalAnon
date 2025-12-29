//
//  WorkflowPhase.swift
//  Redactor
//
//  Purpose: Defines the phases of the redaction workflow
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Workflow Phase

enum WorkflowPhase: String, CaseIterable, Identifiable {
    case redact
    case improve
    case restore

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .redact:
            return "Redact"
        case .improve:
            return "Improve"
        case .restore:
            return "Restore"
        }
    }

    var stepNumber: Int {
        switch self {
        case .redact:
            return 1
        case .improve:
            return 2
        case .restore:
            return 3
        }
    }

    var isFirst: Bool {
        self == .redact
    }

    var isLast: Bool {
        self == .restore
    }

    var previous: WorkflowPhase? {
        switch self {
        case .redact:
            return nil
        case .improve:
            return .redact
        case .restore:
            return .improve
        }
    }

    var next: WorkflowPhase? {
        switch self {
        case .redact:
            return .improve
        case .improve:
            return .restore
        case .restore:
            return nil
        }
    }
}
