//
//  ThemesListView.swift
//  ClinicalAnon
//
//  Purpose: List of recurring themes with mention counts
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Themes List View

/// List of Theme items with mention counts and explored status
struct ThemesListView: View {

    // MARK: - Properties

    @ObservedObject var assistantService: SessionAssistantService
    @State private var expandedThemeId: UUID?

    // MARK: - Body

    var body: some View {
        Group {
            if assistantService.state.themes.isEmpty {
                emptyState
            } else {
                themesList
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            Spacer()

            Image(systemName: "lightbulb")
                .font(.largeTitle)
                .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.5))

            Text("No themes detected yet")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text("Recurring patterns and themes will be identified and tracked as the session progresses")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignSystem.Spacing.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Themes List

    private var themesList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                // Unexplored themes first
                let unexplored = assistantService.state.themes.filter { !$0.isExplored }
                let explored = assistantService.state.themes.filter { $0.isExplored }

                if !unexplored.isEmpty {
                    sectionHeader("To Explore", count: unexplored.count)
                    ForEach(unexplored) { theme in
                        themeRow(theme)
                    }
                }

                if !explored.isEmpty {
                    sectionHeader("Explored", count: explored.count)
                    ForEach(explored) { theme in
                        themeRow(theme)
                    }
                }
            }
            .padding(DesignSystem.Spacing.medium)
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)

            Spacer()

            Text("\(count)")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .padding(.top, DesignSystem.Spacing.small)
        .padding(.bottom, DesignSystem.Spacing.xs)
    }

    // MARK: - Theme Row

    private func themeRow(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedThemeId == theme.id {
                        expandedThemeId = nil
                    } else {
                        expandedThemeId = theme.id
                    }
                }
            } label: {
                HStack(spacing: DesignSystem.Spacing.small) {
                    // Expand/collapse chevron
                    Image(systemName: expandedThemeId == theme.id ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .frame(width: 12)

                    // Theme name
                    Text(theme.name)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    // Mention count badge
                    Text("\(theme.mentionCount)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.primaryTeal)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.primaryTeal.opacity(0.1))
                        .clipShape(Capsule())

                    Spacer()

                    // Explored indicator
                    if theme.isExplored {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            .buttonStyle(.plain)

            // Expanded mentions
            if expandedThemeId == theme.id {
                mentionsList(for: theme)
            }

            // Mark as explored button (if not explored)
            if !theme.isExplored {
                Button {
                    assistantService.markThemeExplored(theme)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.caption2)
                        Text("Mark as Explored")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(DesignSystem.Colors.primaryTeal)
                    .padding(.leading, 24)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignSystem.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Mentions List

    private func mentionsList(for theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            ForEach(theme.mentions) { mention in
                HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
                    // Timestamp
                    Text(mention.formattedTime)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.primaryTeal)
                        .frame(width: 40, alignment: .trailing)

                    // Context
                    Text(mention.context)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.leading, 24)
        .padding(.top, DesignSystem.Spacing.xs)
    }
}

// MARK: - Preview

#if DEBUG
struct ThemesListView_Previews: PreviewProvider {
    static var previews: some View {
        ThemesListView(
            assistantService: SessionManager.shared.assistantService
        )
        .frame(width: 320, height: 400)
    }
}
#endif
