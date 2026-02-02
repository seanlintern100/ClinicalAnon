//
//  ParkingLotView.swift
//  ClinicalAnon
//
//  Purpose: Tabbed panel showing persistent reference information from session
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Parking Lot View

/// Tabbed panel with Details, Quotes, Agenda, and Themes tabs
struct ParkingLotView: View {

    // MARK: - Properties

    @ObservedObject var assistantService: SessionAssistantService
    @State private var selectedTab: ParkingLotTab = .details

    // Sheets
    @State private var showAddDetail = false
    @State private var showAddQuote = false
    @State private var showAddAgenda = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            tabBar

            Divider()

            // Tab content
            tabContent
        }
        .sheet(isPresented: $showAddDetail) {
            AddDetailSheet(assistantService: assistantService)
        }
        .sheet(isPresented: $showAddQuote) {
            AddQuoteSheet(assistantService: assistantService)
        }
        .sheet(isPresented: $showAddAgenda) {
            AddAgendaSheet(assistantService: assistantService)
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ParkingLotTab.allCases) { tab in
                tabButton(for: tab)
            }

            Spacer()

            // Add button
            addButton
        }
        .padding(.horizontal, DesignSystem.Spacing.small)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .background(DesignSystem.Colors.surface)
    }

    private func tabButton(for tab: ParkingLotTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.caption)

                Text(tab.title)
                    .font(DesignSystem.Typography.caption)

                // Badge count
                let count = itemCount(for: tab)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            selectedTab == tab
                                ? DesignSystem.Colors.primaryTeal.opacity(0.2)
                                : DesignSystem.Colors.textSecondary.opacity(0.2)
                        )
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(
                selectedTab == tab
                    ? DesignSystem.Colors.primaryTeal
                    : DesignSystem.Colors.textSecondary
            )
            .padding(.horizontal, DesignSystem.Spacing.small)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(
                selectedTab == tab
                    ? DesignSystem.Colors.primaryTeal.opacity(0.1)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        Button {
            switch selectedTab {
            case .details:
                showAddDetail = true
            case .quotes:
                showAddQuote = true
            case .agenda:
                showAddAgenda = true
            case .themes:
                // Themes are auto-detected, no manual add
                break
            }
        } label: {
            Image(systemName: "plus")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .padding(6)
                .background(DesignSystem.Colors.surface)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(selectedTab == .themes)
        .opacity(selectedTab == .themes ? 0.3 : 1.0)
        .help(selectedTab == .themes ? "Themes are auto-detected" : "Add \(selectedTab.title.lowercased())")
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .details:
            DetailsListView(assistantService: assistantService)
        case .quotes:
            QuotesListView(assistantService: assistantService)
        case .agenda:
            AgendaListView(assistantService: assistantService)
        case .themes:
            ThemesListView(assistantService: assistantService)
        }
    }

    // MARK: - Helpers

    private func itemCount(for tab: ParkingLotTab) -> Int {
        switch tab {
        case .details:
            return assistantService.state.details.count
        case .quotes:
            return assistantService.state.quotes.count
        case .agenda:
            return assistantService.state.agendaItems.count
        case .themes:
            return assistantService.state.themes.count
        }
    }
}

// MARK: - Parking Lot Tab

enum ParkingLotTab: String, CaseIterable, Identifiable {
    case details
    case quotes
    case agenda
    case themes

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .details: return "person.text.rectangle"
        case .quotes: return "quote.bubble"
        case .agenda: return "checklist"
        case .themes: return "lightbulb"
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ParkingLotView_Previews: PreviewProvider {
    static var previews: some View {
        ParkingLotView(
            assistantService: SessionManager.shared.assistantService
        )
        .frame(width: 320, height: 400)
    }
}
#endif
