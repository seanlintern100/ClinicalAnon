//
//  ChunkManager.swift
//  ClinicalAnon
//
//  Purpose: Splits large text into overlapping chunks for efficient parallel processing
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Chunk Info

/// Information about a text chunk including its position and overlap zones
struct ChunkInfo {
    /// The chunk text (including overlap regions)
    let text: String

    /// Offset of this chunk's start in the original text (before overlap)
    let globalOffset: Int

    /// Number of characters before the "real" content (overlap from previous chunk)
    let overlapBefore: Int

    /// Number of characters after the "real" content (overlap into next chunk)
    let overlapAfter: Int

    /// Start of real content within chunk (skip overlap)
    var contentStart: Int { overlapBefore }

    /// End of real content within chunk (before overlap)
    var contentEnd: Int { text.count - overlapAfter }
}

// MARK: - Chunk Manager

/// Manages splitting of large text into overlapping chunks for parallel processing
class ChunkManager {

    // MARK: - Configuration

    /// Default chunk size (8K chars provides good balance)
    static let defaultChunkSize = 8_000

    /// Overlap between chunks (200 chars handles most multi-word names)
    static let defaultOverlap = 200

    // MARK: - Chunk Splitting

    /// Split text into overlapping chunks for parallel processing
    /// - Parameters:
    ///   - text: The full text to split
    ///   - chunkSize: Target size for each chunk (default 8000)
    ///   - overlap: Overlap between chunks (default 200)
    /// - Returns: Array of ChunkInfo with text and position metadata
    static func splitWithOverlap(
        _ text: String,
        chunkSize: Int = defaultChunkSize,
        overlap: Int = defaultOverlap
    ) -> [ChunkInfo] {

        // Small text doesn't need chunking
        guard text.count > chunkSize else {
            return [ChunkInfo(
                text: text,
                globalOffset: 0,
                overlapBefore: 0,
                overlapAfter: 0
            )]
        }

        var chunks: [ChunkInfo] = []
        let nsText = text as NSString

        var currentStart = 0

        while currentStart < nsText.length {
            // Calculate ideal chunk end
            let idealEnd = min(currentStart + chunkSize, nsText.length)

            // Find sentence boundary near ideal end (if not at text end)
            let actualEnd: Int
            if idealEnd < nsText.length {
                actualEnd = findSentenceBoundary(in: nsText, near: idealEnd, from: currentStart)
            } else {
                actualEnd = idealEnd
            }

            // Calculate overlap regions
            let overlapStart: Int
            let overlapBefore: Int
            if currentStart == 0 {
                // First chunk: no overlap before
                overlapStart = 0
                overlapBefore = 0
            } else {
                // Add overlap from previous chunk
                overlapStart = max(0, currentStart - overlap)
                overlapBefore = currentStart - overlapStart
            }

            let overlapEnd: Int
            let overlapAfter: Int
            if actualEnd >= nsText.length {
                // Last chunk: no overlap after
                overlapEnd = nsText.length
                overlapAfter = 0
            } else {
                // Add overlap into next chunk
                overlapEnd = min(nsText.length, actualEnd + overlap)
                overlapAfter = overlapEnd - actualEnd
            }

            // Extract chunk text
            let chunkRange = NSRange(location: overlapStart, length: overlapEnd - overlapStart)
            let chunkText = nsText.substring(with: chunkRange)

            chunks.append(ChunkInfo(
                text: chunkText,
                globalOffset: overlapStart,
                overlapBefore: overlapBefore,
                overlapAfter: overlapAfter
            ))

            // Move to next chunk (skip the content we just processed, not the overlap)
            currentStart = actualEnd
        }

        #if DEBUG
        print("ChunkManager: Split \(nsText.length) chars into \(chunks.count) chunks")
        #endif

        return chunks
    }

    // MARK: - Sentence Boundary Detection

    /// Find a sentence boundary near the target position
    /// - Parameters:
    ///   - text: The text to search
    ///   - target: Target position to find boundary near
    ///   - from: Start position (don't go before this)
    /// - Returns: Position of sentence boundary (or target if none found)
    private static func findSentenceBoundary(in text: NSString, near target: Int, from start: Int) -> Int {
        // Look back up to 500 chars for a sentence boundary
        let searchStart = max(start, target - 500)
        let searchRange = NSRange(location: searchStart, length: target - searchStart)

        // Try to find ". " (sentence end)
        var foundRange = text.range(of: ". ", options: .backwards, range: searchRange)
        if foundRange.location != NSNotFound {
            return foundRange.location + foundRange.length
        }

        // Try "\n\n" (paragraph break)
        foundRange = text.range(of: "\n\n", options: .backwards, range: searchRange)
        if foundRange.location != NSNotFound {
            return foundRange.location + foundRange.length
        }

        // Try single "\n" (line break)
        foundRange = text.range(of: "\n", options: .backwards, range: searchRange)
        if foundRange.location != NSNotFound {
            return foundRange.location + foundRange.length
        }

        // No boundary found, use target position
        return target
    }

    // MARK: - Position Adjustment

    /// Adjust entity positions from chunk-local to global coordinates
    /// - Parameters:
    ///   - positions: Array of [start, end] positions in chunk coordinates
    ///   - chunk: The chunk info with offset and overlap data
    /// - Returns: Adjusted positions in global coordinates, or nil if entity is in overlap-only zone
    static func adjustPositions(_ positions: [[Int]], for chunk: ChunkInfo) -> [[Int]]? {
        var adjusted: [[Int]] = []

        for pos in positions {
            guard pos.count >= 2 else { continue }
            let localStart = pos[0]
            let localEnd = pos[1]

            // Skip entities entirely in the overlap-before zone
            // (they will be captured by the previous chunk)
            if localEnd <= chunk.overlapBefore {
                continue
            }

            // Skip entities entirely in the overlap-after zone
            // (they will be captured by the next chunk)
            if localStart >= chunk.contentEnd {
                continue
            }

            // Convert to global coordinates
            let globalStart = chunk.globalOffset + localStart
            let globalEnd = chunk.globalOffset + localEnd

            adjusted.append([globalStart, globalEnd])
        }

        return adjusted.isEmpty ? nil : adjusted
    }
}
