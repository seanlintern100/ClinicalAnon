//
//  DetailsListView.swift
//  ClinicalAnon
//
//  Purpose: List of client details grouped by category
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Details List View

/// List of ClientDetail items grouped by category
struct DetailsListView: View {

    // MARK: - Properties

    @ObservedObject var assistantService: SessionAssistantService

    // MARK: - Body

    var body: some View {
        Group {
            if assistantService.state.details.isEmpty {
                emptyState
            } else {
                detailsList
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            Spacer()

            Image(systemName: "person.text.rectangle")
                .font(.largeTitle)
                .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.5))

            Text("No details yet")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text("Details about people, relationships, and facts will appear here as the session progresses")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignSystem.Spacing.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Details List

    /// Unique categories from current details, sorted alphabetically
    private var sortedCategories: [String] {
        Array(Set(assistantService.state.details.map { $0.category })).sorted()
    }

    private var detailsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                ForEach(sortedCategories, id: \.self) { category in
                    let categoryDetails = assistantService.state.details.filter {
                        $0.category == category
                    }

                    if !categoryDetails.isEmpty {
                        categorySection(category: category, details: categoryDetails)
                    }
                }
            }
            .padding(DesignSystem.Spacing.medium)
        }
    }

    // MARK: - Category Section

    private func categorySection(category: String, details: [ClientDetail]) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            // Category header
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: iconForCategory(category))
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.primaryTeal)

                Text(category)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .textCase(.uppercase)

                Spacer()

                Text("\(details.count)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .padding(.bottom, DesignSystem.Spacing.xs)

            // Detail rows
            ForEach(details) { detail in
                detailRow(detail)
            }
        }
        .padding(.bottom, DesignSystem.Spacing.small)
    }

    private func iconForCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "person": return "person.fill"
        case "relationship": return "heart.fill"
        case "employment": return "briefcase.fill"
        case "living situation": return "house.fill"
        case "health": return "cross.case.fill"
        case "key event": return "star.fill"
        default: return "pin.fill"
        }
    }

    // MARK: - Detail Row

    private func detailRow(_ detail: ClientDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Content
            Text(detail.content)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            // Metadata
            HStack(spacing: DesignSystem.Spacing.small) {
                if detail.timestamp > 0 {
                    Text(formatTime(detail.timestamp))
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                if detail.isManuallyAdded {
                    Text("Manual")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.primaryTeal)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(DesignSystem.Colors.primaryTeal.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(DesignSystem.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button(role: .destructive) {
                assistantService.deleteDetail(detail)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Preview

#if DEBUG
struct DetailsListView_Previews: PreviewProvider {
    static var previews: some View {
        DetailsListView(
            assistantService: SessionManager.shared.assistantService
        )
        .frame(width: 320, height: 400)
    }
}
#endif
