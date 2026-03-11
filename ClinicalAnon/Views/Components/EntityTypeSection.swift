//
//  EntityTypeSection.swift
//  Redactor
//
//  Purpose: Collapsible entity section with toggle-all, anchor/child grouping,
//           and per-entity context menus. Shared between full app and Lite.
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Entity Type Section

struct EntityTypeSection: View {
    let title: String
    let icon: String
    let color: Color
    let entities: [Entity]
    let actions: EntityActions
    let isAISection: Bool
    let isDeepScanSection: Bool

    @State private var isExpanded: Bool = true

    /// Check state: all included, all excluded, or mixed
    private var checkState: CheckState {
        let excludedCount = entities.filter { actions.isEntityExcluded($0) }.count
        if excludedCount == 0 {
            return .allIncluded
        } else if excludedCount == entities.count {
            return .allExcluded
        } else {
            return .mixed
        }
    }

    private enum CheckState {
        case allIncluded, allExcluded, mixed
    }

    /// Group entities: anchors with their children, sorted alphabetically by anchor
    private func groupedEntities() -> [(anchor: Entity, children: [Entity])] {
        // Separate anchors and children
        let anchors = entities.filter { $0.isAnchor }
        let children = entities.filter { !$0.isAnchor }

        // Group children by baseId
        var childrenByBaseId: [String: [Entity]] = [:]
        for child in children {
            if let baseId = child.baseId {
                childrenByBaseId[baseId, default: []].append(child)
            }
        }

        // Build groups: each anchor with its children
        var groups: [(anchor: Entity, children: [Entity])] = []
        for anchor in anchors.sorted(by: { $0.originalText.lowercased() < $1.originalText.lowercased() }) {
            let anchorChildren = anchor.baseId.flatMap { childrenByBaseId[$0] } ?? []
            // Sort children alphabetically within group
            let sortedChildren = anchorChildren.sorted { $0.originalText.lowercased() < $1.originalText.lowercased() }
            groups.append((anchor: anchor, children: sortedChildren))
        }

        return groups
    }

    /// Create entity row with optional indentation
    @ViewBuilder
    private func entityRow(for entity: Entity, indented: Bool) -> some View {
        HStack(spacing: 0) {
            if indented {
                // Indentation spacer for child entities
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 16)
            }

            RedactEntityRow(
                entity: entity,
                isExcluded: actions.isEntityExcluded(entity),
                isFromAIReview: isAISection,
                isFromDeepScan: isDeepScanSection,
                isChild: indented,
                onToggle: { actions.toggleEntity(entity) },
                mergeTargets: actions.allEntities.filter { target in
                    target.id != entity.id && target.isAnchor &&
                    (entity.type.isPerson ? target.type.isPerson : target.type == entity.type)
                }.sorted { $0.originalText.lowercased() < $1.originalText.lowercased() },
                onMerge: { target in actions.mergeEntities(entity, target) },
                onEditNameStructure: { actions.startEditingNameStructure(entity) },
                onChangeType: { newType in actions.reclassifyEntity(entity.id, newType) }
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            HStack(spacing: 6) {
                // Toggle all checkbox
                Button(action: { actions.toggleEntities(entities) }) {
                    Image(systemName: checkState == .allIncluded ? "checkmark.square.fill" :
                                      checkState == .mixed ? "minus.square.fill" : "square")
                        .font(.system(size: 12))
                        .foregroundColor(checkState == .allExcluded ? DesignSystem.Colors.textSecondary : color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(checkState == .allIncluded ? "Deselect all \(title)" : "Select all \(title)")

                // Expand/collapse button for rest of header
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .foregroundColor(color)
                            .frame(width: 16)

                        Text(title.uppercased())
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        Text("(\(entities.count))")
                            .font(.system(size: 10))
                            .foregroundColor(DesignSystem.Colors.textSecondary)

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse \(title) section" : "Expand \(title) section")
            }
            .padding(.vertical, 6)
            .padding(.horizontal, DesignSystem.Spacing.xs)
            .background(color.opacity(0.6))
            .cornerRadius(4)

            // Entity rows (grouped by anchor with children indented)
            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(groupedEntities(), id: \.anchor.id) { group in
                        // Anchor row (no indent)
                        entityRow(for: group.anchor, indented: false)

                        // Child rows (indented)
                        ForEach(group.children) { child in
                            entityRow(for: child, indented: true)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}
