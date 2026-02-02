//
//  SessionExportService.swift
//  ClinicalAnon
//
//  Purpose: Handles export of session transcripts and audio files
//  Organization: 3 Big Things
//

import Foundation
import AVFoundation
import AppKit

// MARK: - Export Format

/// Format options for transcript export
enum ExportFormat: String, CaseIterable {
    case textPlain = "txt"
    case markdown = "md"

    var displayName: String {
        switch self {
        case .textPlain: return "Plain Text"
        case .markdown: return "Markdown"
        }
    }

    var fileExtension: String {
        rawValue
    }

    var utType: String {
        switch self {
        case .textPlain: return "public.plain-text"
        case .markdown: return "net.daringfireball.markdown"
        }
    }
}

// MARK: - Export Error

/// Errors that can occur during export
enum ExportError: LocalizedError {
    case cancelled
    case fileWriteFailed(String)
    case noAudioAvailable
    case audioExportFailed(String)
    case noTranscriptAvailable

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Export was cancelled"
        case .fileWriteFailed(let reason):
            return "Failed to write file: \(reason)"
        case .noAudioAvailable:
            return "No audio files available for this session"
        case .audioExportFailed(let reason):
            return "Audio export failed: \(reason)"
        case .noTranscriptAvailable:
            return "No transcript available for this session"
        }
    }
}

// MARK: - Session Export Service

/// Handles export of session transcripts and audio files
@MainActor
class SessionExportService {

    // MARK: - Singleton

    static let shared = SessionExportService()

    private init() {}

    // MARK: - Transcript Export

    /// Export transcript to file, showing save panel
    /// - Parameters:
    ///   - session: The session to export
    ///   - format: Export format (plain text or markdown)
    ///   - redacted: Whether to export redacted or raw transcript
    /// - Returns: URL of the saved file
    func exportTranscript(
        session: LiveSession,
        format: ExportFormat,
        redacted: Bool
    ) async throws -> URL {
        // Get transcript text
        let text = redacted ? session.redactedTranscript : session.rawTranscript

        guard !text.isEmpty else {
            throw ExportError.noTranscriptAvailable
        }

        // Format the content
        let content = formatTranscript(session: session, text: text, format: format, redacted: redacted)

        // Create temp file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(
            "\(session.displayName).\(format.fileExtension)"
        )

        do {
            try content.write(to: tempFile, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.fileWriteFailed(error.localizedDescription)
        }

        // Show save panel
        guard let destinationURL = await showSavePanel(
            suggestedName: "\(session.displayName)\(redacted ? "" : "-unredacted").\(format.fileExtension)",
            allowedTypes: [format.fileExtension]
        ) else {
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempFile)
            throw ExportError.cancelled
        }

        // Copy to final location
        do {
            // Remove existing file if it exists
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: tempFile, to: destinationURL)
            try FileManager.default.removeItem(at: tempFile)
        } catch {
            throw ExportError.fileWriteFailed(error.localizedDescription)
        }

        return destinationURL
    }

    /// Format transcript content based on format type
    private func formatTranscript(
        session: LiveSession,
        text: String,
        format: ExportFormat,
        redacted: Bool
    ) -> String {
        switch format {
        case .textPlain:
            return formatPlainText(session: session, redacted: redacted)

        case .markdown:
            return formatMarkdown(session: session, redacted: redacted)
        }
    }

    /// Format transcript as plain text
    private func formatPlainText(session: LiveSession, redacted: Bool) -> String {
        var lines: [String] = []

        // Header
        lines.append("Session: \(session.displayName)")
        lines.append("Date: \(formattedDate(session.createdAt))")
        lines.append("Duration: \(session.formattedDuration)")
        if !redacted {
            lines.append("*** CONTAINS UNREDACTED PII ***")
        }
        lines.append("")
        lines.append(String(repeating: "-", count: 50))
        lines.append("")

        // Segments
        let segments = session.transcriptSegments.sorted { $0.startTime < $1.startTime }
        for segment in segments {
            let text = redacted ? applyRedactions(segment.text, entities: session.detectedEntities) : segment.text
            lines.append("[\(segment.speaker.label)] (\(segment.formattedStartTime))")
            lines.append(text)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Format transcript as markdown
    private func formatMarkdown(session: LiveSession, redacted: Bool) -> String {
        var lines: [String] = []

        // Header
        lines.append("# Session: \(session.displayName)")
        lines.append("")
        lines.append("**Date:** \(formattedDate(session.createdAt))")
        lines.append("**Duration:** \(session.formattedDuration)")
        if !redacted {
            lines.append("")
            lines.append("> ⚠️ **Warning:** This transcript contains unredacted personal information.")
        }
        lines.append("")
        lines.append("---")
        lines.append("")
        lines.append("## Transcript")
        lines.append("")

        // Segments
        let segments = session.transcriptSegments.sorted { $0.startTime < $1.startTime }
        for segment in segments {
            let text = redacted ? applyRedactions(segment.text, entities: session.detectedEntities) : segment.text
            lines.append("**[\(segment.speaker.label)]** (\(segment.formattedStartTime))")
            lines.append(text)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Apply entity redactions to text
    private func applyRedactions(_ text: String, entities: [Entity]) -> String {
        var result = text
        let sortedEntities = entities.sorted { entity1, entity2 in
            let pos1 = entity1.positions.first?.first ?? 0
            let pos2 = entity2.positions.first?.first ?? 0
            return pos1 > pos2
        }
        for entity in sortedEntities {
            result = result.replacingOccurrences(
                of: entity.originalText,
                with: entity.replacementCode,
                options: .caseInsensitive
            )
        }
        return result
    }

    /// Format date for display
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Audio Export

    /// Export audio stream to file
    /// - Parameters:
    ///   - session: The session containing the audio
    ///   - stream: Which audio stream to export (microphone or system)
    /// - Returns: URL of the saved file
    func exportAudio(
        session: LiveSession,
        stream: AudioStream
    ) async throws -> URL {
        // Find chunks for this stream
        let chunks = session.audioChunkPaths.filter { $0.stream == stream }
            .sorted { $0.chunkIndex < $1.chunkIndex }

        guard !chunks.isEmpty else {
            throw ExportError.noAudioAvailable
        }

        // Get session audio directory
        let audioDir = SessionStorageService.audioDirectory(for: session)

        // Verify chunks exist - use stored filePath, not hardcoded fileName
        let sessionDir = SessionStorageService.sessionDirectory(for: session)
        let chunkURLs = chunks.compactMap { chunk -> URL? in
            let url = sessionDir.appendingPathComponent(chunk.filePath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }

        guard !chunkURLs.isEmpty else {
            throw ExportError.noAudioAvailable
        }

        // Determine output file
        let outputURL: URL
        if chunkURLs.count == 1 {
            // Single chunk - use directly
            outputURL = chunkURLs[0]
        } else {
            // Multiple chunks - concatenate
            outputURL = try await concatenateAudioFiles(chunkURLs, stream: stream)
        }

        // Determine file extension from source
        let sourceExtension = chunkURLs.first?.pathExtension ?? "m4a"

        // Show save panel
        let suggestedName = "\(session.displayName)-\(stream.displayName).\(sourceExtension)"
        guard let destinationURL = await showSavePanel(
            suggestedName: suggestedName,
            allowedTypes: [sourceExtension]
        ) else {
            // Clean up temp file if we created one
            if chunkURLs.count > 1 {
                try? FileManager.default.removeItem(at: outputURL)
            }
            throw ExportError.cancelled
        }

        // Copy to final location
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: outputURL, to: destinationURL)

            // Clean up temp file if we created one
            if chunkURLs.count > 1 {
                try? FileManager.default.removeItem(at: outputURL)
            }
        } catch {
            throw ExportError.fileWriteFailed(error.localizedDescription)
        }

        return destinationURL
    }

    /// Export combined audio (mic + system mixed together)
    /// - Parameters:
    ///   - session: The session containing the audio
    /// - Returns: URL of the saved file
    func exportCombinedAudio(session: LiveSession) async throws -> URL {
        // Get all chunks for both streams
        let micChunks = session.audioChunkPaths.filter { $0.stream == .microphone }
            .sorted { $0.chunkIndex < $1.chunkIndex }
        let sysChunks = session.audioChunkPaths.filter { $0.stream == .system }
            .sorted { $0.chunkIndex < $1.chunkIndex }

        guard !micChunks.isEmpty || !sysChunks.isEmpty else {
            throw ExportError.noAudioAvailable
        }

        let sessionDir = SessionStorageService.sessionDirectory(for: session)

        // Get URLs for all chunks
        let micURLs = micChunks.compactMap { chunk -> URL? in
            let url = sessionDir.appendingPathComponent(chunk.filePath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        let sysURLs = sysChunks.compactMap { chunk -> URL? in
            let url = sessionDir.appendingPathComponent(chunk.filePath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }

        guard !micURLs.isEmpty || !sysURLs.isEmpty else {
            throw ExportError.noAudioAvailable
        }

        // Mix the audio streams
        let mixedURL = try await mixAudioStreams(micURLs: micURLs, sysURLs: sysURLs)

        // Show save panel
        let suggestedName = "\(session.displayName)-Combined.m4a"
        guard let destinationURL = await showSavePanel(
            suggestedName: suggestedName,
            allowedTypes: ["m4a"]
        ) else {
            try? FileManager.default.removeItem(at: mixedURL)
            throw ExportError.cancelled
        }

        // Copy to final location
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: mixedURL, to: destinationURL)
            try? FileManager.default.removeItem(at: mixedURL)
        } catch {
            throw ExportError.fileWriteFailed(error.localizedDescription)
        }

        return destinationURL
    }

    /// Mix mic and system audio streams into a single file
    private func mixAudioStreams(micURLs: [URL], sysURLs: [URL]) async throws -> URL {
        let composition = AVMutableComposition()

        // Add mic audio track
        if !micURLs.isEmpty {
            guard let micTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw ExportError.audioExportFailed("Failed to create mic audio track")
            }

            var currentTime = CMTime.zero
            for url in micURLs {
                let asset = AVURLAsset(url: url)
                do {
                    let tracks = try await asset.loadTracks(withMediaType: .audio)
                    guard let sourceTrack = tracks.first else { continue }
                    let duration = try await asset.load(.duration)
                    let timeRange = CMTimeRange(start: .zero, duration: duration)
                    try micTrack.insertTimeRange(timeRange, of: sourceTrack, at: currentTime)
                    currentTime = CMTimeAdd(currentTime, duration)
                } catch {
                    print("SessionExportService: Failed to load mic chunk: \(error)")
                }
            }
        }

        // Add system audio track (plays simultaneously with mic)
        if !sysURLs.isEmpty {
            guard let sysTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw ExportError.audioExportFailed("Failed to create system audio track")
            }

            var currentTime = CMTime.zero
            for url in sysURLs {
                let asset = AVURLAsset(url: url)
                do {
                    let tracks = try await asset.loadTracks(withMediaType: .audio)
                    guard let sourceTrack = tracks.first else { continue }
                    let duration = try await asset.load(.duration)
                    let timeRange = CMTimeRange(start: .zero, duration: duration)
                    try sysTrack.insertTimeRange(timeRange, of: sourceTrack, at: currentTime)
                    currentTime = CMTimeAdd(currentTime, duration)
                } catch {
                    print("SessionExportService: Failed to load sys chunk: \(error)")
                }
            }
        }

        // Export to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("export-combined-\(UUID().uuidString).m4a")

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw ExportError.audioExportFailed("Failed to create export session")
        }

        exportSession.outputURL = tempFile
        exportSession.outputFileType = .m4a

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            return tempFile
        case .failed:
            throw ExportError.audioExportFailed(exportSession.error?.localizedDescription ?? "Unknown error")
        case .cancelled:
            throw ExportError.cancelled
        default:
            throw ExportError.audioExportFailed("Export ended with unexpected status")
        }
    }

    /// Concatenate multiple audio files into one
    private func concatenateAudioFiles(_ urls: [URL], stream: AudioStream) async throws -> URL {
        let composition = AVMutableComposition()

        guard let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.audioExportFailed("Failed to create audio track")
        }

        var currentTime = CMTime.zero

        for url in urls {
            let asset = AVURLAsset(url: url)

            do {
                let tracks = try await asset.loadTracks(withMediaType: .audio)
                guard let sourceTrack = tracks.first else { continue }

                let duration = try await asset.load(.duration)
                let timeRange = CMTimeRange(start: .zero, duration: duration)

                try audioTrack.insertTimeRange(timeRange, of: sourceTrack, at: currentTime)
                currentTime = CMTimeAdd(currentTime, duration)
            } catch {
                // Skip this chunk if it fails to load
                print("SessionExportService: Failed to load chunk \(url.lastPathComponent): \(error)")
                continue
            }
        }

        // Export to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(
            "export-\(stream.rawValue)-\(UUID().uuidString).m4a"
        )

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw ExportError.audioExportFailed("Failed to create export session")
        }

        exportSession.outputURL = tempFile
        exportSession.outputFileType = .m4a

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            return tempFile
        case .failed:
            throw ExportError.audioExportFailed(exportSession.error?.localizedDescription ?? "Unknown error")
        case .cancelled:
            throw ExportError.cancelled
        default:
            throw ExportError.audioExportFailed("Export ended with unexpected status")
        }
    }

    // MARK: - Save Panel

    /// Show save panel for file export
    private func showSavePanel(suggestedName: String, allowedTypes: [String]) async -> URL? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = suggestedName
                panel.allowedContentTypes = allowedTypes.compactMap { ext in
                    switch ext {
                    case "txt": return .plainText
                    case "md": return .init(filenameExtension: "md")
                    case "m4a": return .init(filenameExtension: "m4a")
                    case "wav": return .wav
                    default: return .init(filenameExtension: ext)
                    }
                }
                panel.canCreateDirectories = true
                panel.isExtensionHidden = false

                panel.begin { response in
                    if response == .OK {
                        continuation.resume(returning: panel.url)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
}
