//
//  EntityListView.swift
//  ClinicalAnon
//
//  Purpose: Displays list of detected entities
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Entity List View

/// Displays a list of detected entities with their details
struct EntityListView: View {

    // MARK: - Properties

    let entities: [Entity]
    let onEntityTap: ((Entity) -> Void)?

    // MARK: - Initialization

    init(entities: [Entity], onEntityTap: ((Entity) -> Void)? = nil) {
        self.entities = entities
        self.onEntityTap = onEntityTap
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Detected Entities")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Spacer()

                Text("\(entities.count)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, DesignSystem.Spacing.small)
                    .padding(.vertical, 2)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(DesignSystem.CornerRadius.small)
            }
            .padding(DesignSystem.Spacing.medium)

            Divider()

            // Entity list
            if entities.isEmpty {
                EmptyEntityListView()
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.xs) {
                        ForEach(entities.sorted()) { entity in
                            EntityRow(entity: entity) {
                                onEntityTap?(entity)
                            }
                        }
                    }
                    .padding(DesignSystem.Spacing.small)
                }
            }
        }
        .background(DesignSystem.Colors.background)
        .cornerRadius(DesignSystem.CornerRadius.medium)
    }
}

// MARK: - Entity Row

struct EntityRow: View {
    let entity: Entity
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DesignSystem.Spacing.small) {
                // Type icon
                Image(systemName: entity.type.iconName)
                    .font(.system(size: 16))
                    .foregroundColor(DesignSystem.Colors.primaryTeal)
                    .frame(width: 24)

                // Entity info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text(entity.originalText)
                            .font(DesignSystem.Typography.bodyBold)
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundColor(DesignSystem.Colors.textSecondary)

                        Text(entity.replacementCode)
                            .font(DesignSystem.Typography.monospace)
                            .foregroundColor(DesignSystem.Colors.orange)
                    }

                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text(entity.type.displayName)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)

                        if entity.occurrenceCount > 1 {
                            Text("•")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)

                            Text("\(entity.occurrenceCount) occurrences")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .padding(DesignSystem.Spacing.small)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.CornerRadius.small)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty State

struct EmptyEntityListView: View {
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.5))

            Text("No entities detected")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            Text("Enter clinical text and click Analyze to detect entities")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignSystem.Spacing.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Entity List with Grouping

struct GroupedEntityListView: View {
    let entities: [Entity]
    let onEntityTap: ((Entity) -> Void)?

    private var groupedEntities: [(EntityType, [Entity])] {
        let grouped = Dictionary(grouping: entities) { $0.type }
        return grouped.sorted { $0.key.displayName < $1.key.displayName }
            .map { ($0.key, $0.value.sorted()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Detected Entities")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Spacer()

                Text("\(entities.count)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, DesignSystem.Spacing.small)
                    .padding(.vertical, 2)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(DesignSystem.CornerRadius.small)
            }
            .padding(DesignSystem.Spacing.medium)

            Divider()

            if entities.isEmpty {
                EmptyEntityListView()
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.small, pinnedViews: [.sectionHeaders]) {
                        ForEach(groupedEntities, id: \.0) { type, typeEntities in
                            Section {
                                ForEach(typeEntities) { entity in
                                    EntityRow(entity: entity) {
                                        onEntityTap?(entity)
                                    }
                                }
                            } header: {
                                HStack {
                                    Image(systemName: type.iconName)
                                        .font(.system(size: 14))
                                    Text(type.displayName)
                                        .font(DesignSystem.Typography.caption)
                                    Text("(\(typeEntities.count))")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                }
                                .foregroundColor(DesignSystem.Colors.primaryTeal)
                                .padding(.horizontal, DesignSystem.Spacing.small)
                                .padding(.vertical, DesignSystem.Spacing.xs)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(DesignSystem.Colors.background)
                            }
                        }
                    }
                    .padding(DesignSystem.Spacing.small)
                }
            }
        }
        .background(DesignSystem.Colors.background)
        .cornerRadius(DesignSystem.CornerRadius.medium)
    }
}

// MARK: - Preview

#if DEBUG
struct EntityListView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // With entities
            EntityListView(entities: Entity.samples) { entity in
                print("Tapped: \(entity.originalText)")
            }
            .frame(width: 300, height: 400)
            .padding()
            .previewDisplayName("With Entities")

            // Empty
            EntityListView(entities: [])
            .frame(width: 300, height: 400)
            .padding()
            .previewDisplayName("Empty")

            // Grouped
            GroupedEntityListView(entities: Entity.samples, onEntityTap: nil)
            .frame(width: 300, height: 400)
            .padding()
            .previewDisplayName("Grouped")
        }
    }
}
#endif
