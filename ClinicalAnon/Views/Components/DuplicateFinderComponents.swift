//
//  DuplicateFinderComponents.swift
//  Redactor
//
//  Purpose: Duplicate entity finder modal with high/low confidence sections.
//           Shared between full app and Lite.
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Duplicate Finder Modal

struct DuplicateFinderModal: View {

    let findDuplicates: () -> [DuplicateGroup]
    let onMergeGroups: ([DuplicateGroup]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var groups: [DuplicateGroup] = []

    private var highConfidenceGroups: [DuplicateGroup] {
        groups.filter { $0.confidence == .high }
    }

    private var lowConfidenceGroups: [DuplicateGroup] {
        groups.filter { $0.confidence == .low }
    }

    private var selectedGroups: [DuplicateGroup] {
        groups.filter { $0.isSelected }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Potential Duplicate Names")
                    .font(DesignSystem.Typography.heading)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close dialog")
            }
            .padding(DesignSystem.Spacing.medium)

            Divider().opacity(0.15)

            // Content
            if groups.isEmpty {
                // Empty state
                VStack(spacing: DesignSystem.Spacing.medium) {
                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(DesignSystem.Colors.success)

                    Text("No potential duplicates found")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text("All person entities appear to be unique")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.medium) {
                        // High Confidence Section
                        if !highConfidenceGroups.isEmpty {
                            DuplicateSection(
                                title: "High Confidence",
                                subtitle: "Full name matches with overlapping components",
                                color: DesignSystem.Colors.success,
                                groups: highConfidenceGroups,
                                onToggle: toggleGroup,
                                onSetAnchor: setAnchor
                            )
                        }

                        // Low Confidence Section
                        if !lowConfidenceGroups.isEmpty {
                            DuplicateSection(
                                title: "Low Confidence",
                                subtitle: "Partial matches without full name anchor",
                                color: .orange,
                                groups: lowConfidenceGroups,
                                onToggle: toggleGroup,
                                onSetAnchor: setAnchor
                            )
                        }
                    }
                    .padding(DesignSystem.Spacing.medium)
                }
            }

            Divider().opacity(0.15)

            // Footer buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()

                if !groups.isEmpty {
                    Text("\(selectedGroups.count) group\(selectedGroups.count == 1 ? "" : "s") selected")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                Button("Merge Selected") {
                    onMergeGroups(selectedGroups)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedGroups.isEmpty)
            }
            .padding(DesignSystem.Spacing.medium)
        }
        .frame(width: 500, height: 450)
        .onAppear {
            groups = findDuplicates()
        }
    }

    private func toggleGroup(_ group: DuplicateGroup) {
        if let idx = groups.firstIndex(where: { $0.id == group.id }) {
            groups[idx].isSelected.toggle()
        }
    }

    private func setAnchor(_ group: DuplicateGroup, _ newAnchor: Entity) {
        if let idx = groups.firstIndex(where: { $0.id == group.id }) {
            groups[idx] = group.withNewAnchor(newAnchor)
        }
    }
}

// MARK: - Duplicate Section

struct DuplicateSection: View {

    let title: String
    let subtitle: String
    let color: Color
    let groups: [DuplicateGroup]
    let onToggle: (DuplicateGroup) -> Void
    let onSetAnchor: (DuplicateGroup, Entity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            // Section header
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)

                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }

                Text(subtitle)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            // Groups
            ForEach(groups) { group in
                DuplicateGroupRow(
                    group: group,
                    onToggle: { onToggle(group) },
                    onSetAnchor: { newAnchor in onSetAnchor(group, newAnchor) }
                )
            }
        }
    }
}

// MARK: - Duplicate Group Row

struct DuplicateGroupRow: View {

    let group: DuplicateGroup
    let onToggle: () -> Void
    let onSetAnchor: (Entity) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: group.isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundColor(group.isSelected ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .accessibilityLabel(group.isSelected ? "Deselect merge group for \(group.primary.originalText)" : "Select merge group for \(group.primary.originalText)")

            // Group content
            VStack(alignment: .leading, spacing: 4) {
                // Primary entity (anchor) with star indicator
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)

                    Text(group.primary.replacementCode)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(group.primary.type.highlightColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(group.primary.type.highlightColor.opacity(0.15))
                        .cornerRadius(3)

                    Text(group.primary.originalText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text("Primary")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.yellow.opacity(0.2))
                        .cornerRadius(3)
                }

                // Matches with "Make Primary" buttons
                ForEach(group.matches, id: \.id) { match in
                    HStack(spacing: 6) {
                        Text("├─")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(DesignSystem.Colors.textSecondary)

                        Text(match.originalText)
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.Colors.textSecondary)

                        Text(match.replacementCode)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.7))

                        Spacer()

                        Button(action: { onSetAnchor(match) }) {
                            Text("Make Primary")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.primaryTeal)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Make \(match.originalText) the primary entity")
                    }
                    .padding(.leading, 8)
                }
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(group.isSelected ? DesignSystem.Colors.primaryTeal.opacity(0.08) : DesignSystem.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(group.isSelected ? DesignSystem.Colors.primaryTeal.opacity(0.3) : DesignSystem.Colors.border.opacity(0.3), lineWidth: 1)
        )
    }
}
