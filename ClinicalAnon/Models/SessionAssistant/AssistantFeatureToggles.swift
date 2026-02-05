//
//  AssistantFeatureToggles.swift
//  ClinicalAnon
//
//  Purpose: Feature toggles for session assistant modularity
//  Organization: 3 Big Things
//

import Foundation

/// Feature toggles for modularity and gradual rollout
struct AssistantFeatureToggles: Codable {
    var detailsEnabled: Bool = true
    var agendaEnabled: Bool = true
    var themesEnabled: Bool = true
    var flagsEnabled: Bool = true
    var suggestionsEnabled: Bool = true

    static let `default` = AssistantFeatureToggles()

    static let flagsOnly = AssistantFeatureToggles(
        detailsEnabled: false,
        agendaEnabled: false,
        themesEnabled: false,
        flagsEnabled: true,
        suggestionsEnabled: false
    )
}
