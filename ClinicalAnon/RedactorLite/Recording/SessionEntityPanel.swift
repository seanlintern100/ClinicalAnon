//
//  SessionEntityPanel.swift
//  Redactor Lite
//
//  Purpose: Right panel — detected entities grouped by type during live recording
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Session Entity Panel

struct SessionEntityPanel: View {

    let session: LiveSession?

    var body: some View {
        if let session = session {
            SessionEntityContent(session: session)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            Spacer()
            Image(systemName: "person.crop.rectangle.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.5))
            Text("No Entities Detected")
                .font(DesignSystem.Typography.subheading)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

private struct SessionEntityContent: View {

    @ObservedObject var session: LiveSession

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Entities")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Text("\(session.detectedEntities.count)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(DesignSystem.Colors.textSecondary.opacity(0.2))
                        )
            }
            .padding(DesignSystem.Spacing.medium)

            Divider().opacity(0.15)

            if !session.detectedEntities.isEmpty {
                entityList(session: session)
            } else {
                VStack {
                    Spacer()
                    Text("Entities will appear as they are detected")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }

    // MARK: - Entity List

    private func entityList(session: LiveSession) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                ForEach(groupedEntities(session: session), id: \.type) { group in
                    entityGroupView(group: group, mapping: session.entityMapping)
                }
            }
            .padding(DesignSystem.Spacing.medium)
        }
    }

    // MARK: - Entity Group

    private func entityGroupView(group: EntityGroup, mapping: EntityMapping) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Group header
            HStack {
                Text(group.type.displayName)
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
                Text("\(group.entities.count)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            // Entities in group
            ForEach(group.entities, id: \.id) { entity in
                HStack {
                    Text(entity.originalText)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    let code = mapping.existingMapping(for: entity.originalText.lowercased()) ?? entity.replacementCode
                    Text("[\(code)]")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(entityColor(for: entity.type))
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.bottom, DesignSystem.Spacing.small)
    }

    // MARK: - Helpers

    private struct EntityGroup {
        let type: EntityType
        let entities: [Entity]
    }

    private func groupedEntities(session: LiveSession) -> [EntityGroup] {
        let grouped = Dictionary(grouping: session.detectedEntities) { $0.type }
        return grouped.map { (key: EntityType, value: [Entity]) -> EntityGroup in
            EntityGroup(type: key, entities: value)
        }
        .sorted { $0.type.displayName < $1.type.displayName }
    }

    private func entityColor(for type: EntityType) -> Color {
        switch type {
        case .personClient, .personProvider, .personOther:
            return .blue
        case .date:
            return .orange
        case .location:
            return .green
        case .organization:
            return .purple
        default:
            return .gray
        }
    }
}
