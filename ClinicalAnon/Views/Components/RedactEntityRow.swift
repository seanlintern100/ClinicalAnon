//
//  RedactEntityRow.swift
//  Redactor
//
//  Purpose: Entity row for redact-phase sidebar — shows entity with toggle,
//           context menus (merge, change type, edit name structure), and variant badges.
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Redact Entity Row

struct RedactEntityRow: View {

    let entity: Entity
    let isExcluded: Bool
    let isFromAIReview: Bool
    let isFromDeepScan: Bool
    let isChild: Bool
    let onToggle: () -> Void
    let mergeTargets: [Entity]
    let onMerge: (Entity) -> Void
    let onEditNameStructure: () -> Void
    let onChangeType: (EntityType) -> Void

    /// Text color: gray for excluded or child entities, primary for anchors
    private var textColor: Color {
        if isExcluded { return DesignSystem.Colors.textSecondary }
        return isChild ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.textPrimary
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Button(action: onToggle) {
                Image(systemName: isExcluded ? "square" : "checkmark.square.fill")
                    .foregroundColor(isExcluded ? DesignSystem.Colors.textSecondary : entity.type.highlightColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExcluded ? "Include \(entity.originalText) in redaction" : "Exclude \(entity.originalText) from redaction")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entity.originalText)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(textColor)
                        .lineLimit(1)
                        .strikethrough(isExcluded && !isFromDeepScan)

                    if isFromAIReview {
                        Text("AI")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .cornerRadius(3)
                    }
                }

                // Only show replacement code and variant badge for anchors, not children
                if !isChild {
                    HStack(spacing: 4) {
                        Text("→ \(entity.replacementCode)")
                            .font(.system(size: 10))
                            .foregroundColor(DesignSystem.Colors.textSecondary)

                        if let variant = entity.nameVariant {
                            Text(variant.displayName)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(entity.type.highlightColor.opacity(0.8))
                                .cornerRadius(3)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, DesignSystem.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isExcluded ? Color.clear : (isFromAIReview ? Color.orange.opacity(0.1) : entity.type.highlightColor.opacity(0.1)))
        )
        .contextMenu {
            if !mergeTargets.isEmpty {
                Menu("Merge with...") {
                    ForEach(mergeTargets) { target in
                        Button("\(target.originalText) \(target.replacementCode)") {
                            onMerge(target)
                        }
                    }
                }
            }

            // Edit Name Structure - only for person types
            if entity.type.isPerson {
                Button(action: onEditNameStructure) {
                    Label("Edit Name Structure", systemImage: "person.text.rectangle")
                }
            }

            // Change Type submenu
            Menu("Change Type") {
                ForEach(EntityType.allCases.filter { $0 != entity.type }, id: \.self) { newType in
                    Button(newType.displayName) {
                        onChangeType(newType)
                    }
                }
            }
        }
    }
}
