//
//  TextContentCard.swift
//  Redactor
//
//  Purpose: Reusable card wrapper for text content panels
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Text Content Card

/// A card wrapper for text content in main panels.
/// Goes inside existing ScrollView - does not contain its own.
struct TextContentCard<Content: View>: View {

    // MARK: - Properties

    /// Whether this is a source/input panel (warm tones) vs output panel (neutral)
    let isSourcePanel: Bool

    /// Whether the content has been processed (affects warm card background)
    let isProcessed: Bool

    /// The content to wrap
    @ViewBuilder let content: () -> Content

    // MARK: - Computed Properties

    private var cardBackground: Color {
        if isSourcePanel && isProcessed {
            return DesignSystem.Colors.cardWarm
        }
        return .white
    }

    // MARK: - Body

    var body: some View {
        VStack {
            content()
                .lineSpacing(6)
                .frame(maxWidth: 620, alignment: .leading)
                .padding(32)
                .background(cardBackground)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

// MARK: - Preview

#if DEBUG
struct TextContentCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Source panel (processed)
            TextContentCard(isSourcePanel: true, isProcessed: true) {
                Text("This is source content that has been processed. It shows the warm card background.")
                    .font(.system(size: 14))
            }
            .background(DesignSystem.Colors.panelWarm)

            // Output panel
            TextContentCard(isSourcePanel: false, isProcessed: false) {
                Text("This is output content. It shows the white card background.")
                    .font(.system(size: 14))
            }
            .background(DesignSystem.Colors.panelNeutral)
        }
        .frame(width: 600, height: 400)
    }
}
#endif
