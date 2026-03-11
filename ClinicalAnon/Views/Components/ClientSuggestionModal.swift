//
//  ClientSuggestionModal.swift
//  ClinicalAnon
//
//  Purpose: Modal to suggest the most frequently mentioned person as the client.
//  Organization: 3 Big Things
//

import SwiftUI

struct ClientSuggestionModal: View {

    let suggestedClient: Entity?
    let candidates: [Entity]
    let onConfirm: (Entity) -> Void
    let onDismiss: () -> Void

    @State private var selectedEntity: Entity?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: DesignSystem.Spacing.small) {
                Image(systemName: "person.fill.questionmark")
                    .font(.system(size: 32))
                    .foregroundColor(DesignSystem.Colors.primaryTeal)

                Text("Identify Primary Client")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text("The most frequently mentioned person is likely the client. Select the correct person below.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 350)
            }
            .padding(.top, DesignSystem.Spacing.large)
            .padding(.bottom, DesignSystem.Spacing.medium)

            Divider().opacity(0.2)

            // Candidate list
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(candidates, id: \.id) { candidate in
                        let isSelected = (selectedEntity ?? suggestedClient)?.id == candidate.id
                        let posCount = candidate.positions.count

                        Button(action: { selectedEntity = candidate }) {
                            HStack(spacing: DesignSystem.Spacing.small) {
                                // Selection indicator
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 16))
                                    .foregroundColor(isSelected ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.textSecondary.opacity(0.4))

                                // Name
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.originalText)
                                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                                        .foregroundColor(DesignSystem.Colors.textPrimary)

                                    Text("\(posCount) occurrence\(posCount == 1 ? "" : "s") \u{2022} \(candidate.replacementCode)")
                                        .font(.system(size: 11))
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                }

                                Spacer()

                                // Badge for suggested
                                if candidate.id == suggestedClient?.id {
                                    Text("Suggested")
                                        .font(.system(size: 10, weight: .medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(DesignSystem.Colors.primaryTeal.opacity(0.2))
                                        .foregroundColor(DesignSystem.Colors.primaryTeal)
                                        .cornerRadius(4)
                                }
                            }
                            .padding(.horizontal, DesignSystem.Spacing.medium)
                            .padding(.vertical, DesignSystem.Spacing.small)
                            .background(isSelected ? DesignSystem.Colors.primaryTeal.opacity(0.08) : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.small)
                .padding(.vertical, DesignSystem.Spacing.small)
            }
            .frame(maxHeight: 300)

            Divider().opacity(0.2)

            // Action buttons
            HStack(spacing: DesignSystem.Spacing.medium) {
                Button("Skip") {
                    onDismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                Button(action: {
                    if let entity = selectedEntity ?? suggestedClient {
                        onConfirm(entity)
                    }
                }) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "person.fill.checkmark")
                        Text("Set as Client")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedEntity == nil && suggestedClient == nil)
            }
            .padding(DesignSystem.Spacing.medium)
        }
        .frame(width: 420)
        .background(DesignSystem.Colors.warmWhite)
        .cornerRadius(DesignSystem.CornerRadius.xxlarge)
    }
}
