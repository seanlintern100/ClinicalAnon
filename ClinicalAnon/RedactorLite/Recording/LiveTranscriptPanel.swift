//
//  LiveTranscriptPanel.swift
//  Redactor Lite
//
//  Purpose: Center panel — auto-scrolling live transcript with speaker labels
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Live Transcript Panel

struct LiveTranscriptPanel: View {

    let session: LiveSession?
    let phase: RecordingPhase

    var body: some View {
        if let session = session {
            LiveTranscriptContent(session: session, phase: phase)
        } else {
            VStack(spacing: DesignSystem.Spacing.medium) {
                Spacer()
                Image(systemName: "mic.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.5))
                Text("Ready to Record")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Text("Fill in session details and press Start Recording")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

/// Inner view that can @ObservedObject the non-optional session
private struct LiveTranscriptContent: View {

    @ObservedObject var session: LiveSession
    let phase: RecordingPhase

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Transcript")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Text("\(session.transcriptSegments.count) segments")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .padding(DesignSystem.Spacing.medium)

            Divider().opacity(0.15)

            // Content
            if !session.transcriptSegments.isEmpty {
                transcriptScrollView(session: session)
            } else {
                emptyStateView
            }
        }
    }

    // MARK: - Transcript Scroll View

    private func transcriptScrollView(session: LiveSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    ForEach(sortedContent(session: session), id: \.id) { item in
                        switch item {
                        case .segment(let segment):
                            segmentRow(segment: segment, entities: session.detectedEntities)
                                .id("\(segment.id)-\(session.detectedEntities.count)")
                        case .gap(let gap):
                            gapRow(gap: gap)
                                .id(gap.id)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(DesignSystem.Spacing.large)
            }
            .onChange(of: session.transcriptSegments.count) { _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Segment Row

    private func segmentRow(segment: TranscriptSegment, entities: [Entity]) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
            // Timestamp
            Text(segment.formattedStartTime)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 50, alignment: .trailing)

            // Speaker label
            Text(speakerDisplayLabel(for: segment))
                .font(DesignSystem.Typography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(speakerColor(for: segment))
                )

            // Text with entity highlights
            Text(redactedText(segment: segment, entities: entities))
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
    }

    // MARK: - Gap Row

    private func gapRow(gap: TranscriptionGap) -> some View {
        HStack(spacing: 8) {
            Text(gap.formattedDuration)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 50, alignment: .trailing)

            HStack(spacing: 4) {
                Image(systemName: gap.reason.iconName)
                Text(gap.shortDisplay)
            }
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.orange.opacity(0.1))
            )

            Spacer()
        }
    }

    // MARK: - Content Sorting

    private enum ContentItem: Identifiable {
        case segment(TranscriptSegment)
        case gap(TranscriptionGap)

        var id: UUID {
            switch self {
            case .segment(let s): return s.id
            case .gap(let g): return g.id
            }
        }

        var startTime: TimeInterval {
            switch self {
            case .segment(let s): return s.startTime
            case .gap(let g): return g.startTime
            }
        }
    }

    private func sortedContent(session: LiveSession) -> [ContentItem] {
        var items: [ContentItem] = []
        for segment in session.transcriptSegments {
            items.append(.segment(segment))
        }
        for gap in session.transcriptionGaps {
            items.append(.gap(gap))
        }
        return items.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Speaker Helpers

    private func speakerDisplayLabel(for segment: TranscriptSegment) -> String {
        switch segment.speaker {
        case .clinician:
            if let speakerId = segment.speakerId {
                let number = speakerId.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                if let index = Int(number) {
                    let letterIndex = index > 0 ? index - 1 : index
                    if letterIndex < 26 {
                        return "Therapist \(String(UnicodeScalar(65 + letterIndex)!))"
                    }
                }
            }
            return "Therapist"
        case .other:
            if let speakerId = segment.speakerId {
                let number = speakerId.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                if let index = Int(number) {
                    let letterIndex = index > 0 ? index - 1 : index
                    if letterIndex < 26 {
                        return "Client \(String(UnicodeScalar(65 + letterIndex)!))"
                    }
                }
            }
            return "Client"
        }
    }

    private func speakerColor(for segment: TranscriptSegment) -> Color {
        switch segment.speaker {
        case .clinician:
            if let speakerId = segment.speakerId,
               let num = Int(speakerId.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()),
               num > 1 {
                return .purple  // Secondary clinician (supervisor)
            }
            return .blue  // Primary clinician (therapist)
        case .other: return .green
        }
    }

    // MARK: - Redaction

    private func redactedText(segment: TranscriptSegment, entities: [Entity]) -> String {
        var text = segment.text
        for entity in entities {
            text = text.replacingOccurrences(
                of: entity.originalText,
                with: entity.replacementCode,
                options: .caseInsensitive
            )
        }
        return text
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            Spacer()

            if phase == .setup {
                Image(systemName: "mic.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.5))
                Text("Ready to Record")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Text("Fill in session details and press Start Recording")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            } else if phase == .recording {
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
                Text("Listening...")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Text("Transcript will appear after the first audio chunk is processed.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "text.bubble")
                    .font(.system(size: 48))
                    .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.5))
                Text("No Transcript")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
