//
//  SessionNamePromptView.swift
//  ClinicalAnon
//
//  Purpose: Modal dialog for naming a completed session
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Session Name Prompt View

/// Modal dialog for naming a session after recording stops
struct SessionNamePromptView: View {

    // MARK: - Properties

    @ObservedObject var session: LiveSession
    let onSave: (String) -> Void
    let onDismiss: () -> Void

    @State private var sessionName: String = ""
    @FocusState private var isNameFieldFocused: Bool

    // MARK: - Body

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            // Header
            headerView

            // Name input
            nameInputView

            // Buttons
            buttonRow
        }
        .padding(DesignSystem.Spacing.large)
        .frame(width: 400)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        .onAppear {
            sessionName = session.name.isEmpty ? suggestedName : session.name
            isNameFieldFocused = true
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: DesignSystem.Spacing.small) {
            Image(systemName: "pencil.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(DesignSystem.Colors.primaryTeal)

            Text("Name This Session")
                .font(DesignSystem.Typography.title)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("Give your session a descriptive name for easy reference.")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Name Input

    private var nameInputView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Text("Session Name")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            TextField("e.g., Morning Consultation", text: $sessionName)
                .textFieldStyle(.roundedBorder)
                .font(DesignSystem.Typography.body)
                .focused($isNameFieldFocused)
                .onSubmit {
                    saveAndDismiss()
                }

            // Session info
            HStack(spacing: DesignSystem.Spacing.medium) {
                Label(session.formattedDuration, systemImage: "clock")
                Label("\(session.segmentCount) segments", systemImage: "text.bubble")
            }
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }

    // MARK: - Button Row

    private var buttonRow: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            Button("Skip") {
                onDismiss()
            }
            .buttonStyle(SecondaryButtonStyle())
            .keyboardShortcut(.escape)

            Spacer()

            Button("Save") {
                saveAndDismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(sessionName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Helpers

    private var suggestedName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "Session – \(formatter.string(from: session.createdAt))"
    }

    private func saveAndDismiss() {
        let trimmedName = sessionName.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty {
            onSave(trimmedName)
        }
        onDismiss()
    }
}

// MARK: - Session Name Sheet Modifier

/// View modifier to show the session naming sheet
struct SessionNameSheetModifier: ViewModifier {
    @Binding var session: LiveSession?
    let sessionManager: SessionManager

    func body(content: Content) -> some View {
        content
            .sheet(item: $session) { session in
                SessionNamePromptView(
                    session: session,
                    onSave: { name in
                        sessionManager.renameSession(session, name: name)
                    },
                    onDismiss: {
                        self.session = nil
                    }
                )
            }
    }
}

extension View {
    func sessionNameSheet(session: Binding<LiveSession?>, sessionManager: SessionManager) -> some View {
        modifier(SessionNameSheetModifier(session: session, sessionManager: sessionManager))
    }
}

// MARK: - Preview

#if DEBUG
struct SessionNamePromptView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.3)
                .ignoresSafeArea()

            SessionNamePromptView(
                session: LiveSession.completed,
                onSave: { _ in },
                onDismiss: {}
            )
        }
    }
}
#endif
