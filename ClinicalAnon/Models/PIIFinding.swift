//
//  PIIFinding.swift
//  ClinicalAnon
//
//  Purpose: PII finding model shared between full app (LocalLLMService) and Lite.
//  Organization: 3 Big Things
//

import Foundation

struct PIIFinding {
    let text: String
    let suggestedType: EntityType
    let reason: String
    let confidence: Double
}
