//
//  AudioChunkReference.swift
//  ClinicalAnon
//
//  Purpose: Reference to an audio chunk file on disk
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Audio Stream

/// Represents the source of an audio stream
enum AudioStream: String, Codable, CaseIterable {
    case microphone = "mic"
    case system = "sys"

    /// Display name for UI
    var displayName: String {
        switch self {
        case .microphone: return "Microphone"
        case .system: return "System Audio"
        }
    }

    /// Short label for file naming
    var filePrefix: String {
        rawValue
    }

    /// Icon name for SF Symbols
    var iconName: String {
        switch self {
        case .microphone: return "mic.fill"
        case .system: return "speaker.wave.2.fill"
        }
    }
}

// MARK: - Audio Chunk Reference

/// Reference to an audio chunk file stored on disk
struct AudioChunkReference: Identifiable, Codable, Hashable {

    // MARK: - Properties

    /// Unique identifier
    let id: UUID

    /// Which audio stream this chunk belongs to
    let stream: AudioStream

    /// Sequential chunk index (0, 1, 2, ...)
    let chunkIndex: Int

    /// Start time in seconds from session start
    let startTime: TimeInterval

    /// End time in seconds from session start
    let endTime: TimeInterval

    /// Relative path to audio file within session directory
    let filePath: String

    /// File size in bytes
    let fileSize: Int64

    /// Whether transcription has been completed for this chunk
    var isProcessed: Bool

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        stream: AudioStream,
        chunkIndex: Int,
        startTime: TimeInterval,
        endTime: TimeInterval,
        filePath: String,
        fileSize: Int64,
        isProcessed: Bool = false
    ) {
        self.id = id
        self.stream = stream
        self.chunkIndex = chunkIndex
        self.startTime = startTime
        self.endTime = endTime
        self.filePath = filePath
        self.fileSize = fileSize
        self.isProcessed = isProcessed
    }

    // MARK: - Computed Properties

    /// Standard file name for this chunk (e.g., "mic_000.m4a")
    var fileName: String {
        "\(stream.rawValue)_\(String(format: "%03d", chunkIndex)).m4a"
    }

    /// Duration of this chunk in seconds
    var duration: TimeInterval {
        endTime - startTime
    }

    /// Formatted duration for display
    var formattedDuration: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    /// Human-readable file size
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    /// Whether this is a microphone chunk
    var isMicrophone: Bool {
        stream == .microphone
    }

    /// Whether this is a system audio chunk
    var isSystemAudio: Bool {
        stream == .system
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension AudioChunkReference {
    /// Sample microphone chunk for previews
    static var sampleMic: AudioChunkReference {
        AudioChunkReference(
            stream: .microphone,
            chunkIndex: 0,
            startTime: 0,
            endTime: 180,
            filePath: "audio/mic_000.m4a",
            fileSize: 2_500_000,
            isProcessed: true
        )
    }

    /// Sample system audio chunk for previews
    static var sampleSys: AudioChunkReference {
        AudioChunkReference(
            stream: .system,
            chunkIndex: 0,
            startTime: 0,
            endTime: 180,
            filePath: "audio/sys_000.m4a",
            fileSize: 2_300_000,
            isProcessed: true
        )
    }

    /// Sample chunks list
    static var samples: [AudioChunkReference] {
        [
            AudioChunkReference(
                stream: .microphone,
                chunkIndex: 0,
                startTime: 0,
                endTime: 180,
                filePath: "audio/mic_000.m4a",
                fileSize: 2_500_000,
                isProcessed: true
            ),
            AudioChunkReference(
                stream: .system,
                chunkIndex: 0,
                startTime: 0,
                endTime: 180,
                filePath: "audio/sys_000.m4a",
                fileSize: 2_300_000,
                isProcessed: true
            ),
            AudioChunkReference(
                stream: .microphone,
                chunkIndex: 1,
                startTime: 150,
                endTime: 330,
                filePath: "audio/mic_001.m4a",
                fileSize: 2_600_000,
                isProcessed: false
            ),
            AudioChunkReference(
                stream: .system,
                chunkIndex: 1,
                startTime: 150,
                endTime: 330,
                filePath: "audio/sys_001.m4a",
                fileSize: 2_400_000,
                isProcessed: false
            )
        ]
    }
}
#endif
