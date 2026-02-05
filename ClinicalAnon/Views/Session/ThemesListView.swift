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

    private func themeRow(_ theme: Theme, indentLevel: Int = 0) -> some View {
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

                    // Quote count badge
                    Text("\(theme.quoteCount)")
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

            // Expanded content: quotes and sub-themes
            if expandedThemeId == theme.id {
                quotesList(for: theme)

                // Sub-themes (recursive)
                if !theme.subThemes.isEmpty {
                    subThemesList(for: theme)
                }
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
        .padding(.leading, CGFloat(indentLevel) * 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Quotes List

    private func quotesList(for theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            ForEach(theme.quotes) { quote in
                HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
                    // Timestamp
                    Text(quote.formattedTime)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.primaryTeal)
                        .frame(width: 40, alignment: .trailing)

                    // Quote text
                    Text("\u{201C}\(quote.text)\u{201D}")
                        .font(DesignSystem.Typography.caption)
                        .italic()
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(3)
                }
            }
        }
        .padding(.leading, 24)
        .padding(.top, DesignSystem.Spacing.xs)
    }

    // MARK: - Sub-themes List

    private func subThemesList(for theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text("Sub-themes")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .padding(.leading, 24)
                .padding(.top, DesignSystem.Spacing.xs)

            ForEach(theme.subThemes) { subTheme in
                subThemeRow(subTheme)
            }
        }
    }

    private func subThemeRow(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(spacing: DesignSystem.Spacing.small) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Text(theme.name)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("\(theme.quotes.count)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.primaryTeal.opacity(0.8))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(DesignSystem.Colors.primaryTeal.opacity(0.1))
                    .clipShape(Capsule())
            }

            // Show quotes for sub-theme
            ForEach(theme.quotes) { quote in
                HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
                    Text(quote.formattedTime)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Colors.primaryTeal)
                        .frame(width: 32, alignment: .trailing)

                    Text("\u{201C}\(quote.text)\u{201D}")
                        .font(.system(size: 11))
                        .italic()
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .lineLimit(2)
                }
                .padding(.leading, 16)
            }
        }
        .padding(.leading, 32)
        .padding(.vertical, DesignSystem.Spacing.xs)
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
