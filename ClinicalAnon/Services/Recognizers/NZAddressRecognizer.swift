//
//  NZAddressRecognizer.swift
//  ClinicalAnon
//
//  Purpose: Detects NZ addresses and Auckland suburbs
//  Organization: 3 Big Things
//

import Foundation

// MARK: - NZ Address Recognizer

/// Recognizes New Zealand addresses and known Auckland suburbs
class NZAddressRecognizer: PatternRecognizer {

    init() {
        let patterns: [(String, EntityType, Double)] = [
            // Street addresses: "123 High Street", "45 Queen Street"
            // Common NZ street types: Road, Street, Terrace, Avenue, Drive, Lane, Place, Crescent, Way, Grove
            ("\\d+\\s+[A-Z][a-z]+(?:\\s+[A-Z][a-z]+)*\\s+(?:Road|Street|Terrace|Avenue|Drive|Lane|Place|Crescent|Way|Grove|Close|Court)\\b", .location, 0.9),

            // Known Auckland suburbs (high confidence)
            ("\\b(?:Otahuhu|Manukau|Papatoetoe|Mangere|Mt Eden|Ponsonby|Parnell|Remuera|Epsom|Newmarket|Grey Lynn|Avondale|New Lynn|Henderson|Albany|Takapuna|Devonport|Ellerslie|Panmure|Howick|Pakuranga|Botany|Flat Bush)\\b", .location, 0.95),

            // Other major NZ cities
            ("\\b(?:Wellington|Christchurch|Dunedin|Hamilton|Tauranga|Napier|Hastings|Palmerston North|Rotorua|Nelson|Queenstown|Invercargill|Whangarei)\\b", .location, 0.95),

            // Hospital names (NZ specific)
            ("\\b(?:Auckland|Middlemore|North Shore|Waitakere|Starship|Greenlane|Wellington|Hutt|Christchurch|Dunedin)\\s+Hospital\\b", .location, 0.95),

            // Clinic/DHB references
            ("\\b(?:Auckland|Waitemata|Counties Manukau|Canterbury|Southern|Capital & Coast|Hutt Valley)\\s+(?:DHB|District Health Board|Clinic)\\b", .organization, 0.9)
        ]

        super.init(patterns: patterns)
    }
}
