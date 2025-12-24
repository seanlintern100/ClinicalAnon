//
//  ExclusionSettingsView.swift
//  ClinicalAnon
//
//  Purpose: Settings view for managing user-defined word exclusions
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Exclusion Settings View

/// Settings view for managing words excluded from PII detection
struct ExclusionSettingsView: View {

    // MARK: - Properties

    @ObservedObject private var exclusionManager = UserExclusionManager.shared
    @State private var newWord: String = ""
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
                    .frame(minWidth: 200)

                // Right: Add/Import controls
                controlsView
                    .frame(minWidth: 200, maxWidth: 300)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .sheet(isPresented: $showingImportSheet) {
            importSheetView
        }
        .alert("Clear All Exclusions", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                exclusionManager.clearAll()
            }
        } message: {
            Text("This will remove all \(exclusionManager.excludedWords.count) excluded words. This cannot be undone.")
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Excluded Words")
                .font(.headline)

            Text("Words in this list will never be flagged as PII in any document.")
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
            // Search/filter could go here in future

            if exclusionManager.excludedWords.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(exclusionManager.sortedWords, id: \.self) { word in
                        HStack {
                            Text(word)
                                .font(.body)

                            Spacer()

                            Button(action: {
                                exclusionManager.removeWord(word)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove '\(word)' from exclusions")
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // Footer with count
            HStack {
                Text("\(exclusionManager.excludedWords.count) word\(exclusionManager.excludedWords.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if !exclusionManager.excludedWords.isEmpty {
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

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.badge.minus")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("No excluded words")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Add words that should never be detected as PII.")
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

                HStack {
                    TextField("Enter word...", text: $newWord)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addNewWord()
                        }

                    Button("Add") {
                        addNewWord()
                    }
                    .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Text("Press Enter or click Add")
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
                    .disabled(exclusionManager.excludedWords.isEmpty)
                }

                Text("Import from or export to comma-separated list")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Help text
            VStack(alignment: .leading, spacing: 4) {
                Text("Tips:")
                    .font(.caption)
                    .fontWeight(.medium)

                Text("• Add clinical terms that get flagged incorrectly")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("• Add organization names specific to your practice")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("• Exclusions are case-insensitive")
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
            Text("Import Excluded Words")
                .font(.headline)

            Text("Paste a comma-separated list of words to exclude:")
                .font(.caption)
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
                    exclusionManager.importFromCSV(importText)
                    importText = ""
                    showingImportSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 250)
    }

    // MARK: - Actions

    private func addNewWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        exclusionManager.addWord(trimmed)
        newWord = ""
    }

    private func exportToClipboard() {
        let csv = exclusionManager.exportAsCSV()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csv, forType: .string)
    }
}

// MARK: - Preview

#if DEBUG
struct ExclusionSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ExclusionSettingsView()
    }
}
#endif
