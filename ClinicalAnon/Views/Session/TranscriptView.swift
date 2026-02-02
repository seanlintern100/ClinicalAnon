//
//  TranscriptView.swift
//  ClinicalAnon
//
//  Purpose: Scrolling transcript display with speaker labels
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Transcript View

/// Displays the transcript with speaker labels and auto-scrolling
struct TranscriptView: View {

    // MARK: - Properties

    @ObservedObject var session: LiveSession
    @State private var scrollProxy: ScrollViewProxy?

    /// Check if there are audio chunks that haven't been transcribed yet
    private var hasUnprocessedChunks: Bool {
        let unprocessedCount = session.audioChunkPaths.filter { !$0.isProcessed && $0.stream == .microphone }.count
        return unprocessedCount > 0
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    if session.transcriptSegments.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(sortedContent, id: \.id) { item in
                            switch item {
                            case .segment(let segment):
                                TranscriptSegmentRow(
                                    segment: segment,
                                    entities: session.detectedEntities
                                )
                                // Force refresh when entities change by including count in ID
                                .id("\(segment.id)-\(session.detectedEntities.count)")

                            case .gap(let gap):
                                TranscriptionGapRow(gap: gap)
                                    .id(gap.id)
                            }
                        }

                        // Scroll anchor
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                }
                .padding(DesignSystem.Spacing.large)
            }
            .onAppear {
                scrollProxy = proxy
            }
            .onChange(of: session.transcriptSegments.count) { _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Sorted Content

    /// Combined and sorted segments and gaps
    private var sortedContent: [TranscriptItem] {
        var items: [TranscriptItem] = []

        // Add segments
        for segment in session.transcriptSegments {
            items.append(.segment(segment))
        }

        // Add gaps
        for gap in session.transcriptionGaps {
            items.append(.gap(gap))
        }

        // Sort by start time
        return items.sorted { item1, item2 in
            item1.startTime < item2.startTime
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            Spacer()

            if session.state == .recording {
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
            } else if session.state == .complete && hasUnprocessedChunks {
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()

                Text("Transcribing...")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Text("Processing audio, transcript will appear shortly.")
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

                Text("Start recording to generate a transcript.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Transcript Item

/// Wrapper for transcript content (segment or gap)
enum TranscriptItem: Identifiable {
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

// MARK: - Transcript Segment Row

/// Individual segment row with speaker label and entity highlighting
struct TranscriptSegmentRow: View {

    let segment: TranscriptSegment
    let entities: [Entity]

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
            // Timestamp
            Text(segment.formattedStartTime)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 50, alignment: .trailing)

            // Speaker label
            speakerLabel

            // Text content with entity highlighting
            VStack(alignment: .leading, spacing: 4) {
                LiveHighlightedSegment(
                    text: segment.text,
                    entities: entities
                )
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

                // Warning indicators
                HStack(spacing: DesignSystem.Spacing.small) {
                    if segment.hasOverlap {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.caption2)
                            Text("Overlapping speech")
                                .font(DesignSystem.Typography.caption)
                        }
                        .foregroundStyle(.yellow)
                        .help("Both speakers were talking at the same time - transcription may be less accurate")
                    }

                    if segment.isLowConfidence {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                            Text("Low confidence")
                                .font(DesignSystem.Typography.caption)
                        }
                        .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var speakerLabel: some View {
        Text(speakerDisplayLabel)
            .font(DesignSystem.Typography.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(speakerColor)
            )
    }

    /// Display label for the speaker, including voice-based ID if available
    private var speakerDisplayLabel: String {
        if segment.speaker == .other, let speakerId = segment.speakerId {
            // Convert "SPEAKER_00" to "Other A", "SPEAKER_01" to "Other B", etc.
            let suffix = speakerIdToLetter(speakerId)
            return "Other \(suffix)"
        }
        return segment.speaker.label
    }

    /// Convert speaker ID like "SPEAKER_00" to letter suffix "A", "B", etc.
    private func speakerIdToLetter(_ speakerId: String) -> String {
        // Extract number from speaker ID (e.g., "SPEAKER_00" -> 0)
        let number = speakerId
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .joined()
        if let index = Int(number), index < 26 {
            return String(UnicodeScalar(65 + index)!) // A=65, B=66, etc.
        }
        return speakerId
    }

    private var speakerColor: Color {
        switch segment.speaker {
        case .clinician: return .blue
        case .other:
            // Use different shades of green for different remote speakers
            if let speakerId = segment.speakerId {
                let hash = abs(speakerId.hashValue)
                let hue = Double(hash % 60) / 360.0 + 0.25 // Green-ish hues (0.25-0.42)
                return Color(hue: hue, saturation: 0.6, brightness: 0.7)
            }
            return .green
        }
    }
}

// MARK: - Transcription Gap Row

/// Row showing a gap in transcription
struct TranscriptionGapRow: View {

    let gap: TranscriptionGap

    var body: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.small) {
            // Timestamp
            Text(gap.formattedDuration)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 50, alignment: .trailing)

            // Gap indicator
            HStack(spacing: 8) {
                Image(systemName: gap.reason.iconName)
                    .font(.body)

                Text(gap.shortDisplay)
                    .font(DesignSystem.Typography.body)

                if gap.isRecoverable {
                    Button("Retry") {
                        retryTranscription()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .foregroundStyle(gapColor)
            .padding(.horizontal, DesignSystem.Spacing.small)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .fill(gapColor.opacity(0.1))
            )

            Spacer()
        }
    }

    private var gapColor: Color {
        switch gap.reason {
        case .paused: return .orange
        case .transcriptionFailed: return .red
        case .audioCorrupted: return .red
        case .noSpeech: return DesignSystem.Colors.textSecondary
        }
    }

    private func retryTranscription() {
        // Post notification to retry transcription
        if let chunkIndex = gap.chunkIndex {
            NotificationCenter.default.post(
                name: .retryTranscription,
                object: chunkIndex
            )
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let retryTranscription = Notification.Name("retryTranscription")
}

// MARK: - Preview

#if DEBUG
struct TranscriptView_Previews: PreviewProvider {
    static var previews: some View {
        TranscriptView(session: LiveSession.sample)
    }
}
#endif
