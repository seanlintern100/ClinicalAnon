//
//  HelpButton.swift
//  ClinicalAnon
//
//  Purpose: Reusable help button component with hover state
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Help Button

/// A small help icon button that shows a tooltip on hover
struct HelpButton: View {

    let action: () -> Void

    @State private var isHovered: Bool = false
    @State private var showTooltip: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 16))
                .foregroundColor(isHovered ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.textSecondary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            // Delay tooltip appearance slightly
            if hovering {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if isHovered {
                        showTooltip = true
                    }
                }
            } else {
                showTooltip = false
            }
        }
        .overlay(alignment: .bottom) {
            if showTooltip {
                Text("View help for this page")
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(4)
                    .offset(y: 28)
                    .transition(.opacity)
            }
        }
        .accessibilityLabel("Help")
        .accessibilityHint("Opens help documentation for this page")
    }
}

// MARK: - Preview

#if DEBUG
struct HelpButton_Previews: PreviewProvider {
    static var previews: some View {
        HStack {
            HelpButton(action: { print("Help tapped") })
            Text("Original Text")
                .font(DesignSystem.Typography.subheading)
        }
        .padding()
    }
}
#endif
