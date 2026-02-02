//
//  AgendaListView.swift
//  ClinicalAnon
//
//  Purpose: List of session agenda items with status tracking
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Agenda List View

/// List of AgendaItem with status controls
struct AgendaListView: View {

    // MARK: - Properties

    @ObservedObject var assistantService: SessionAssistantService

    // MARK: - Body

    var body: some View {
        Group {
            if assistantService.state.agendaItems.isEmpty {
                emptyState
            } else {
                agendaList
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            Spacer()

            Image(systemName: "checklist")
                .font(.largeTitle)
                .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.5))

            Text("No agenda items yet")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text("Topics agreed to discuss will be tracked here with their coverage status")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignSystem.Spacing.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Agenda List

    private var agendaList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                ForEach(assistantService.state.agendaItems) { item in
                    agendaRow(item)
                }
            }
            .padding(DesignSystem.Spacing.medium)
        }
    }

    // MARK: - Agenda Row

    private func agendaRow(_ item: AgendaItem) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            // Topic with status icon
            HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
                // Status icon
                Image(systemName: item.statusIcon)
                    .font(.body)
                    .foregroundStyle(item.statusColor)

                VStack(alignment: .leading, spacing: 4) {
                    // Topic
                    Text(item.topic)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    // Evidence
                    if let evidence = item.evidence, !evidence.isEmpty {
                        Text(evidence)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .lineLimit(2)
                    }

                    // Time range
                    if let timeRange = item.timeRange {
                        Text(timeRange.formatted)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }

                Spacer()
            }

            // Status controls
            statusControls(for: item)
        }
        .padding(DesignSystem.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button(role: .destructive) {
                assistantService.deleteAgendaItem(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Status Controls

    private func statusControls(for item: AgendaItem) -> some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            ForEach(AgendaStatus.allCases, id: \.rawValue) { status in
                Button {
                    assistantService.updateAgendaStatus(item, to: status)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: status.icon)
                            .font(.caption2)
                        Text(status.displayName)
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        item.status == status
                            ? status.color.opacity(0.2)
                            : DesignSystem.Colors.background
                    )
                    .foregroundStyle(
                        item.status == status
                            ? status.color
                            : DesignSystem.Colors.textSecondary
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(
                                item.status == status
                                    ? status.color.opacity(0.5)
                                    : DesignSystem.Colors.textSecondary.opacity(0.2),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Manual indicator
            if item.isManuallyAdded {
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
}

// MARK: - Preview

#if DEBUG
struct AgendaListView_Previews: PreviewProvider {
    static var previews: some View {
        AgendaListView(
            assistantService: SessionManager.shared.assistantService
        )
        .frame(width: 320, height: 400)
    }
}
#endif
