//
//  DocumentTypeManager.swift
//  Redactor
//
//  Purpose: Manages document types with persistence for custom types and prompt overrides
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Document Type Manager

@MainActor
class DocumentTypeManager: ObservableObject {

    // MARK: - Singleton

    static let shared = DocumentTypeManager()

    // MARK: - Published Properties

    /// All available document types (built-in + custom)
    @Published private(set) var documentTypes: [DocumentType] = []

    // MARK: - UserDefaults Keys

    private let customTypesKey = "customDocumentTypes"
    private let promptOverridesKey = "promptOverrides"

    // MARK: - Initialization

    init() {
        loadTypes()
    }

    // MARK: - Loading

    /// Load all document types (built-in with overrides + custom)
    func loadTypes() {
        var types: [DocumentType] = []

        // Load built-in types with any prompt overrides
        let overrides = loadPromptOverrides()
        for builtIn in DocumentType.builtInTypes {
            var docType = builtIn
            if let override = overrides[builtIn.id.uuidString] {
                docType.prompt = override
            }
            types.append(docType)
        }

        // Load custom types
        let customTypes = loadCustomTypes()
        types.append(contentsOf: customTypes)

        documentTypes = types
    }

    // MARK: - Custom Types

    /// Add a new custom document type
    func addCustomType(name: String, prompt: String, icon: String) {
        let newType = DocumentType(
            id: UUID(),
            name: name,
            prompt: prompt,
            icon: icon,
            isBuiltIn: false
        )

        var customTypes = loadCustomTypes()
        customTypes.append(newType)
        saveCustomTypes(customTypes)

        loadTypes() // Refresh
    }

    /// Delete a custom document type
    func deleteCustomType(_ type: DocumentType) {
        guard !type.isBuiltIn else { return }

        var customTypes = loadCustomTypes()
        customTypes.removeAll { $0.id == type.id }
        saveCustomTypes(customTypes)

        loadTypes() // Refresh
    }

    /// Update a custom document type
    func updateCustomType(_ type: DocumentType) {
        guard !type.isBuiltIn else { return }

        var customTypes = loadCustomTypes()
        if let index = customTypes.firstIndex(where: { $0.id == type.id }) {
            customTypes[index] = type
            saveCustomTypes(customTypes)
            loadTypes() // Refresh
        }
    }

    // MARK: - Prompt Overrides (for built-in types)

    /// Update the prompt for a document type
    func updatePrompt(for typeId: UUID, newPrompt: String) {
        // Check if it's a built-in type
        if let builtIn = DocumentType.builtInTypes.first(where: { $0.id == typeId }) {
            // Save as override
            var overrides = loadPromptOverrides()
            overrides[typeId.uuidString] = newPrompt
            savePromptOverrides(overrides)
        } else {
            // It's a custom type - update directly
            var customTypes = loadCustomTypes()
            if let index = customTypes.firstIndex(where: { $0.id == typeId }) {
                customTypes[index].prompt = newPrompt
                saveCustomTypes(customTypes)
            }
        }

        loadTypes() // Refresh
    }

    /// Reset a built-in type's prompt to default
    func resetToDefault(typeId: UUID) {
        var overrides = loadPromptOverrides()
        overrides.removeValue(forKey: typeId.uuidString)
        savePromptOverrides(overrides)

        loadTypes() // Refresh
    }

    /// Check if a built-in type has a custom prompt
    func hasCustomPrompt(typeId: UUID) -> Bool {
        let overrides = loadPromptOverrides()
        return overrides[typeId.uuidString] != nil
    }

    // MARK: - Private Persistence

    private func loadCustomTypes() -> [DocumentType] {
        guard let data = UserDefaults.standard.data(forKey: customTypesKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([DocumentType].self, from: data)
        } catch {
            print("Failed to decode custom types: \(error)")
            return []
        }
    }

    private func saveCustomTypes(_ types: [DocumentType]) {
        do {
            let data = try JSONEncoder().encode(types)
            UserDefaults.standard.set(data, forKey: customTypesKey)
        } catch {
            print("Failed to encode custom types: \(error)")
        }
    }

    private func loadPromptOverrides() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: promptOverridesKey) as? [String: String] ?? [:]
    }

    private func savePromptOverrides(_ overrides: [String: String]) {
        UserDefaults.standard.set(overrides, forKey: promptOverridesKey)
    }
}
