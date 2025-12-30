//
//  DocumentTypeManager.swift
//  Redactor
//
//  Purpose: Manages document types with persistence for slider settings and prompt overrides
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Document Type Manager

@MainActor
class DocumentTypeManager: ObservableObject {

    // MARK: - Singleton

    static let shared = DocumentTypeManager()

    // MARK: - Published Properties

    /// All available document types (built-in only for now)
    @Published private(set) var documentTypes: [DocumentType] = []

    // MARK: - UserDefaults Keys

    private let sliderOverridesKey = "sliderOverrides"
    private let promptOverridesKey = "promptTemplateOverrides"
    private let customInstructionsKey = "customInstructions"

    // MARK: - Initialization

    init() {
        loadTypes()
    }

    // MARK: - Loading

    /// Load all document types with any saved overrides
    func loadTypes() {
        var types: [DocumentType] = []

        let sliderOverrides = loadSliderOverrides()
        let promptOverrides = loadPromptOverrides()
        let customInstructions = loadCustomInstructions()

        for builtIn in DocumentType.builtInTypes {
            var docType = builtIn

            // Apply slider overrides
            if let sliders = sliderOverrides[builtIn.id.uuidString] {
                docType.defaultSliders = sliders
            }

            // Apply prompt template overrides
            if let promptOverride = promptOverrides[builtIn.id.uuidString] {
                docType.promptTemplate = promptOverride
            }

            // Apply custom instructions (for Custom type)
            if let instructions = customInstructions[builtIn.id.uuidString] {
                docType.customInstructions = instructions
            }

            types.append(docType)
        }

        documentTypes = types
    }

    // MARK: - Slider Settings

    /// Update slider settings for a document type
    func updateSliders(for typeId: UUID, sliders: SliderSettings) {
        var overrides = loadSliderOverrides()
        overrides[typeId.uuidString] = sliders
        saveSliderOverrides(overrides)
        loadTypes()
    }

    /// Get current sliders for a document type (with overrides applied)
    func getSliders(for typeId: UUID) -> SliderSettings {
        let overrides = loadSliderOverrides()
        if let sliders = overrides[typeId.uuidString] {
            return sliders
        }
        return DocumentType.defaultSliders(for: typeId) ?? SliderSettings()
    }

    /// Reset sliders to default for a document type
    func resetSliders(for typeId: UUID) {
        var overrides = loadSliderOverrides()
        overrides.removeValue(forKey: typeId.uuidString)
        saveSliderOverrides(overrides)
        loadTypes()
    }

    // MARK: - Prompt Template Overrides

    /// Update the prompt template for a document type
    func updatePromptTemplate(for typeId: UUID, newTemplate: String) {
        var overrides = loadPromptOverrides()
        overrides[typeId.uuidString] = newTemplate
        savePromptOverrides(overrides)
        loadTypes()
    }

    /// Reset prompt template to default
    func resetPromptTemplate(for typeId: UUID) {
        var overrides = loadPromptOverrides()
        overrides.removeValue(forKey: typeId.uuidString)
        savePromptOverrides(overrides)
        loadTypes()
    }

    /// Check if a type has a custom prompt template
    func hasCustomPrompt(typeId: UUID) -> Bool {
        let overrides = loadPromptOverrides()
        return overrides[typeId.uuidString] != nil
    }

    /// Check if a type has custom sliders
    func hasCustomSliders(typeId: UUID) -> Bool {
        let overrides = loadSliderOverrides()
        return overrides[typeId.uuidString] != nil
    }

    // MARK: - Custom Instructions (for Custom type)

    /// Update custom instructions
    func updateCustomInstructions(for typeId: UUID, instructions: String) {
        var saved = loadCustomInstructions()
        saved[typeId.uuidString] = instructions
        saveCustomInstructions(saved)
        loadTypes()
    }

    /// Get custom instructions for a type
    func getCustomInstructions(for typeId: UUID) -> String {
        let saved = loadCustomInstructions()
        return saved[typeId.uuidString] ?? ""
    }

    // MARK: - Reset All

    /// Reset all overrides for a document type
    func resetAllOverrides(for typeId: UUID) {
        resetSliders(for: typeId)
        resetPromptTemplate(for: typeId)

        var instructions = loadCustomInstructions()
        instructions.removeValue(forKey: typeId.uuidString)
        saveCustomInstructions(instructions)

        loadTypes()
    }

    // MARK: - Private Persistence

    private func loadSliderOverrides() -> [String: SliderSettings] {
        guard let data = UserDefaults.standard.data(forKey: sliderOverridesKey) else {
            return [:]
        }
        do {
            return try JSONDecoder().decode([String: SliderSettings].self, from: data)
        } catch {
            print("Failed to decode slider overrides: \(error)")
            return [:]
        }
    }

    private func saveSliderOverrides(_ overrides: [String: SliderSettings]) {
        do {
            let data = try JSONEncoder().encode(overrides)
            UserDefaults.standard.set(data, forKey: sliderOverridesKey)
        } catch {
            print("Failed to encode slider overrides: \(error)")
        }
    }

    private func loadPromptOverrides() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: promptOverridesKey) as? [String: String] ?? [:]
    }

    private func savePromptOverrides(_ overrides: [String: String]) {
        UserDefaults.standard.set(overrides, forKey: promptOverridesKey)
    }

    private func loadCustomInstructions() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: customInstructionsKey) as? [String: String] ?? [:]
    }

    private func saveCustomInstructions(_ instructions: [String: String]) {
        UserDefaults.standard.set(instructions, forKey: customInstructionsKey)
    }
}
