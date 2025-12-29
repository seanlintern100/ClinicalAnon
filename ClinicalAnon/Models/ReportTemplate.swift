//
//  ReportTemplate.swift
//  Redactor
//
//  Purpose: Defines report templates for AI generation
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Report Template

enum ReportTemplate: String, CaseIterable, Identifiable {
    case progressNote
    case referralLetter
    case assessment
    case discharge
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .progressNote:
            return "Progress Note"
        case .referralLetter:
            return "Referral Letter"
        case .assessment:
            return "Assessment"
        case .discharge:
            return "Discharge Summary"
        case .custom:
            return "Custom..."
        }
    }

    var shortName: String {
        switch self {
        case .progressNote:
            return "Progress"
        case .referralLetter:
            return "Referral"
        case .assessment:
            return "Assessment"
        case .discharge:
            return "Discharge"
        case .custom:
            return "Custom"
        }
    }

    /// Templates that appear as quick-select chips (excludes custom)
    static var quickSelectTemplates: [ReportTemplate] {
        [.progressNote, .referralLetter, .assessment, .discharge]
    }
}
