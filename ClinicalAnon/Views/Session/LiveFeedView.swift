//
//  LiveFeedView.swift
//  ClinicalAnon
//
//  Purpose: Live feed of flags, suggestions, and alerts during session
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Feed Filter

enum FeedFilter: String, CaseIterable, Identifiable {
    case all
    case flags
    case suggestions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .flags: return "Flags"
        case .suggestions: return "Tips"
        }
    }

    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .flags: return "flag"
        case .suggestions: return "lightbulb"
        }
    }
}

// MARK: - Live Feed View

/// Main container for the live feed with auto-scroll
struct LiveFeedView: View {

    // MARK: - Properties

    @ObservedObject var assistantService: SessionAssistantService
    @State private var selectedFilter: FeedFilter = .all
    @State private var userHasScrolled = false
    @State private var lastItemCount = 0

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header with filter
            header

            Divider()

            // Feed content
            if filteredItems.isEmpty {
                emptyState
            } else {
                feedList
            }
        }
        .background(DesignSystem.Colors.surface.opacity(0.5))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            Text("Live Feed")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)

            // Safety flag indicator
            let safetyCount = assistantService.state.safetyFlags.count
            if safetyCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                    Text("\(safetyCount)")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red)
                .clipShape(Capsule())
            }

            Spacer()

            // Filter picker
            filterPicker
        }
        .padding(.horizontal, DesignSystem.Spacing.small)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Filter Picker

    private var filterPicker: some View {
        HStack(spacing: 0) {
            ForEach(FeedFilter.allCases) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedFilter = filter
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: filter.icon)
                            .font(.system(size: 9))
                        Text(filter.title)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(
                        selectedFilter == filter
                            ? DesignSystem.Colors.primaryTeal
                            : DesignSystem.Colors.textSecondary
                    )
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        selectedFilter == filter
                            ? DesignSystem.Colors.primaryTeal.opacity(0.1)
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(DesignSystem.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            Spacer()

            Image(systemName: emptyStateIcon)
                .font(.largeTitle)
                .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.5))

            Text(emptyStateTitle)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text(emptyStateMessage)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignSystem.Spacing.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Feed List

    private var feedList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.small) {
                    // Show newest items at top
                    ForEach(filteredItems.reversed()) { item in
                        LiveFeedItemView(
                            item: item,
                            onStar: { assistantService.starItem(item) },
                            onDismiss: { assistantService.dismissItem(item) }
                        )
                        .id(item.id)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                    }
                }
                .padding(DesignSystem.Spacing.small)
            }
            .onChange(of: filteredItems.count) { newCount in
                // Auto-scroll to newest item (top) when new items arrive
                if newCount > lastItemCount, !userHasScrolled {
                    if let newestItem = filteredItems.last {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(newestItem.id, anchor: .top)
                        }
                    }
                }
                lastItemCount = newCount
            }
        }
    }

    // MARK: - Computed Properties

    private var filteredItems: [FeedItem] {
        let activeItems = assistantService.state.activeFeedItems

        switch selectedFilter {
        case .all:
            // Show only live feed types (flags, suggestions, theme alerts)
            return activeItems.filter {
                $0.itemType == .flag || $0.itemType == .suggestion || $0.itemType == .themeAlert
            }
        case .flags:
            return activeItems.filter { $0.itemType == .flag }
        case .suggestions:
            return activeItems.filter {
                $0.itemType == .suggestion || $0.itemType == .themeAlert
            }
        }
    }

    private var emptyStateIcon: String {
        switch selectedFilter {
        case .all: return "sparkles"
        case .flags: return "flag"
        case .suggestions: return "lightbulb"
        }
    }

    private var emptyStateTitle: String {
        switch selectedFilter {
        case .all: return "No alerts yet"
        case .flags: return "No flags yet"
        case .suggestions: return "No suggestions yet"
        }
    }

    private var emptyStateMessage: String {
        switch selectedFilter {
        case .all:
            return "Flags, suggestions, and alerts will appear here as the session progresses"
        case .flags:
            return "Safety and important flags will appear here when detected"
        case .suggestions:
            return "Therapeutic suggestions and theme alerts will appear here"
        }
    }
}

// MARK: - Preview

#if DEBUG
struct LiveFeedView_Previews: PreviewProvider {
    static var previews: some View {
        LiveFeedView(
            assistantService: SessionManager.shared.assistantService
        )
        .frame(width: 280, height: 400)
    }
}
#endif
