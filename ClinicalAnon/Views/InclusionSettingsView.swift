//
//  InclusionSettingsView.swift
//  ClinicalAnon
//
//  Purpose: Settings view for managing user-defined word inclusions
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Inclusion Settings View

/// Settings view for managing words that should always be flagged as PII
struct InclusionSettingsView: View {

    // MARK: - Properties

    @ObservedObject private var inclusionManager = UserInclusionManager.shared
    @State private var newWord: String = ""
    @State private var newType: EntityType = .personOther
    @State private var importText: String = ""
    @State private var showingImportSheet = false
    @State private var showingClearConfirmation = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Main content
            HSplitView {
                // Left: Word list
                wordListView
                    .frame(minWidth: 280)

                // Right: Add/Import controls
                controlsView
                    .frame(minWidth: 200, maxWidth: 300)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .sheet(isPresented: $showingImportSheet) {
            importSheetView
        }
        .alert("Clear All Inclusions", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                inclusionManager.clearAll()
            }
        } message: {
            Text("This will remove all \(inclusionManager.inclusions.count) included words. This cannot be undone.")
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Included Words")
                .font(.headline)

            Text("Words in this list will always be flagged as PII in every document.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Word List View

    private var wordListView: some View {
        VStack(spacing: 0) {
            // Header row
            HStack {
                Text("Word")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Type")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(width: 120, alignment: .leading)

                // Spacer for delete button
                Spacer()
                    .frame(width: 30)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            if inclusionManager.inclusions.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(inclusionManager.sortedInclusions) { inclusion in
                        inclusionRow(inclusion)
                    }
                }
            }

            // Footer with count
            HStack {
                Text("\(inclusionManager.inclusions.count) word\(inclusionManager.inclusions.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if !inclusionManager.inclusions.isEmpty {
                    Button("Clear All") {
                        showingClearConfirmation = true
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    // MARK: - Inclusion Row

    private func inclusionRow(_ inclusion: UserInclusion) -> some View {
        HStack {
            Text(inclusion.word)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("", selection: Binding(
                get: { inclusion.type },
                set: { newType in
                    inclusionManager.updateType(for: inclusion.word, to: newType)
                }
            )) {
                ForEach(EntityType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .labelsHidden()
            .frame(width: 120)

            Button(action: {
                inclusionManager.removeInclusion(inclusion.word)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove '\(inclusion.word)' from inclusions")
        }
        .padding(.vertical, 2)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("No included words")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Add words that should always be detected as PII.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Controls View

    private var controlsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Add single word
            VStack(alignment: .leading, spacing: 8) {
                Text("Add Word")
                    .font(.subheadline)
                    .fontWeight(.medium)

                TextField("Enter word...", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addNewWord()
                    }

                HStack {
                    Text("Type:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("", selection: $newType) {
                        ForEach(EntityType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .labelsHidden()
                }

                Button("Add") {
                    addNewWord()
                }
                .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Divider()

            // Import/Export
            VStack(alignment: .leading, spacing: 8) {
                Text("Import / Export")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    Button("Import...") {
                        showingImportSheet = true
                    }

                    Button("Export") {
                        exportToClipboard()
                    }
                    .disabled(inclusionManager.inclusions.isEmpty)
                }

                Text("Format: word,type (one per line)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Help text
            VStack(alignment: .leading, spacing: 4) {
                Text("Tips:")
                    .font(.caption)
                    .fontWeight(.medium)

                Text("• Add names that are often missed by detection")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("• Add unique identifiers specific to your practice")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("• Inclusions are case-insensitive")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
        .padding()
    }

    // MARK: - Import Sheet

    private var importSheetView: some View {
        VStack(spacing: 16) {
            Text("Import Included Words")
                .font(.headline)

            Text("Paste words to include (one per line, optionally with type):")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Format: word or word,type")
                .font(.caption2)
                .foregroundColor(.secondary)

            TextEditor(text: $importText)
                .font(.body)
                .frame(minHeight: 100)
                .border(Color.gray.opacity(0.3))

            HStack {
                Button("Cancel") {
                    importText = ""
                    showingImportSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Import") {
                    inclusionManager.importFromCSV(importText)
                    importText = ""
                    showingImportSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 280)
    }

    // MARK: - Actions

    private func addNewWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        inclusionManager.addInclusion(trimmed, type: newType)
        newWord = ""
    }

    private func exportToClipboard() {
        let csv = inclusionManager.exportAsCSV()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csv, forType: .string)
    }
}

// MARK: - Preview

#if DEBUG
struct InclusionSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        InclusionSettingsView()
    }
}
#endif
