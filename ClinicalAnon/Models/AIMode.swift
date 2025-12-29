//
//  AIMode.swift
//  Redactor
//
//  Purpose: Defines AI operation modes
//  Organization: 3 Big Things
//

import Foundation

// MARK: - AI Mode

enum AIMode: String, CaseIterable, Identifiable {
    case polish
    case generate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .polish:
            return "Polish"
        case .generate:
            return "Generate"
        }
    }

    var description: String {
        switch self {
        case .polish:
            return "Clean up grammar, structure"
        case .generate:
            return "Create a report or section"
        }
    }

    var icon: String {
        switch self {
        case .polish:
            return "sparkles"
        case .generate:
            return "doc.text"
        }
    }
}
