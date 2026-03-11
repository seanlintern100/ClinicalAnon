//
//  EntityActions.swift
//  Redactor
//
//  Purpose: Closure bag for decoupling entity UI components from any specific ViewModel.
//           Both WorkflowViewModel and LiteViewModel can construct this.
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Entity Actions

/// Closure bag that decouples entity UI components from any specific ViewModel.
/// Constructed by WorkflowViewModel (full app) or LiteViewModel (Lite app).
struct EntityActions {
    let isEntityExcluded: (Entity) -> Bool
    let toggleEntity: (Entity) -> Void
    let toggleEntities: ([Entity]) -> Void
    let mergeEntities: (_ alias: Entity, _ into: Entity) -> Void
    let startEditingNameStructure: (Entity) -> Void
    let reclassifyEntity: (UUID, EntityType) -> Void
    let allEntities: [Entity]
}
