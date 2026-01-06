//
//  BertNERService.swift
//  Redactor
//
//  Purpose: BERT-based Named Entity Recognition via CoreML
//  Organization: 3 Big Things
//

import Foundation
import CoreML
import AppKit

// MARK: - BERT NER Service

@MainActor
class BertNERService: ObservableObject {

    // MARK: - Singleton

    static let shared = BertNERService()

    // MARK: - Model Constants

    private let modelName = "DistilBertNER_quantized"
    private let maxSequenceLength = 512
    private let vocabSize = 30522

    // BIO label mapping from the model
    private let id2label: [Int: String] = [
        0: "O",
        1: "B-PER",
        2: "I-PER",
        3: "B-ORG",
        4: "I-ORG",
        5: "B-LOC",
        6: "I-LOC",
        7: "B-MISC",
        8: "I-MISC"
    ]

    // MARK: - Published Properties

    @Published var isAvailable: Bool = false
    @Published var isModelLoaded: Bool = false
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0
    @Published var isProcessing: Bool = false
    @Published var lastError: String?

    // MARK: - Private Properties

    private var model: MLModel?
    private var vocab: [String: Int] = [:]
    private var reverseVocab: [Int: String] = [:]

    // Special tokens
    private let clsToken = "[CLS]"
    private let sepToken = "[SEP]"
    private let padToken = "[PAD]"
    private let unkToken = "[UNK]"
    private var clsTokenId: Int = 101
    private var sepTokenId: Int = 102
    private var padTokenId: Int = 0
    private var unkTokenId: Int = 100

    // MARK: - Initialization

    private init() {
        checkAvailability()
    }

    // MARK: - Public Methods

    /// Check if CoreML BERT is available (requires Apple Silicon for best performance)
    func checkAvailability() {
        #if arch(arm64)
        isAvailable = true
        print("BertNERService: CoreML available on Apple Silicon")
        #else
        // CoreML works on Intel too, but slower
        isAvailable = true
        print("BertNERService: CoreML available (Intel Mac - may be slower)")
        #endif
    }

    /// Check if the model is bundled or cached
    var isModelCached: Bool {
        // Check for bundled model first
        if Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") != nil ||
           Bundle.main.url(forResource: modelName, withExtension: "mlpackage") != nil {
            return true
        }

        // Check cache directory
        let cacheURL = cachedModelPath
        return FileManager.default.fileExists(atPath: cacheURL.path)
    }

    /// Get the path where the model would be cached
    var cachedModelPath: URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cacheDir.appendingPathComponent("BertNER").appendingPathComponent("\(modelName).mlmodelc")
    }

    /// Load the model (from bundle or cache)
    func loadModel() async throws {
        guard isAvailable else {
            throw AppError.localLLMNotAvailable
        }

        if isModelLoaded && model != nil {
            print("BertNERService: Model already loaded")
            return
        }

        isDownloading = true
        downloadProgress = 0
        lastError = nil

        print("BertNERService: Loading BERT-NER model...")

        do {
            // Try to load from bundle first
            if let bundledURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
                print("BertNERService: Loading bundled compiled model")
                model = try MLModel(contentsOf: bundledURL)
            } else if let bundledPackageURL = Bundle.main.url(forResource: modelName, withExtension: "mlpackage") {
                print("BertNERService: Loading bundled mlpackage")
                let compiledURL = try await MLModel.compileModel(at: bundledPackageURL)
                model = try MLModel(contentsOf: compiledURL)
            } else {
                // Try loading from cache
                let cacheURL = cachedModelPath
                if FileManager.default.fileExists(atPath: cacheURL.path) {
                    print("BertNERService: Loading from cache: \(cacheURL.path)")
                    model = try MLModel(contentsOf: cacheURL)
                } else {
                    throw AppError.localLLMModelNotLoaded
                }
            }

            // Load vocabulary
            try loadVocabulary()

            isModelLoaded = true
            isDownloading = false
            print("BertNERService: Model loaded successfully")

        } catch {
            isDownloading = false
            print("BertNERService: Failed to load model: \(error)")
            lastError = error.localizedDescription
            throw AppError.localLLMModelLoadFailed(error.localizedDescription)
        }
    }

    /// Unload the model to free memory
    func unloadModel() {
        model = nil
        vocab = [:]
        reverseVocab = [:]
        isModelLoaded = false
        print("BertNERService: Model unloaded")
    }

    /// Run NER scan on text and return findings
    /// - Parameters:
    ///   - text: The text to analyze
    ///   - existingEntities: Entities already detected by other methods
    /// - Returns: New PII findings not already covered
    func runNERScan(text: String, existingEntities: [Entity]) async throws -> [PIIFinding] {
        guard isAvailable else {
            throw AppError.localLLMNotAvailable
        }

        if !isModelLoaded {
            try await loadModel()
        }

        guard let mlModel = model else {
            throw AppError.localLLMModelNotLoaded
        }

        isProcessing = true
        defer { isProcessing = false }

        print("BertNERService: Starting NER scan on text of length \(text.count)")
        let startTime = Date()

        // Split text into chunks for batch processing (BERT has 512 token limit)
        let chunks = splitIntoChunks(text: text)
        print("BertNERService: Processing \(chunks.count) chunk(s)")

        var rawEntities: [BERTEntity] = []

        for (chunkIndex, chunk) in chunks.enumerated() {
            let chunkEntities = try await processChunk(
                chunk: chunk.text,
                charOffset: chunk.charOffset,
                originalText: text,
                model: mlModel
            )
            rawEntities.append(contentsOf: chunkEntities)
            print("BertNERService: Chunk \(chunkIndex + 1)/\(chunks.count) found \(chunkEntities.count) entities")
        }

        // Deduplicate entities from chunk boundaries
        rawEntities = deduplicateBERTEntities(rawEntities)

        // Post-processing: Bridge gaps between PER entities for middle names
        rawEntities = bridgeNameGaps(rawEntities, in: text)

        // Post-processing: Extend names with following surnames (same as SwiftNER)
        let extendedEntities = extendNamesWithSurnames(rawEntities, in: text)
        rawEntities.append(contentsOf: extendedEntities)

        // Post-processing: Extract first name components from full names
        let extractedComponents = extractNameComponents(rawEntities, in: text)
        rawEntities.append(contentsOf: extractedComponents)

        // Post-processing: Detect alphanumeric identifiers (codes, reference numbers)
        let identifiers = detectIdentifiers(in: text)
        rawEntities.append(contentsOf: identifiers)

        let elapsed = Date().timeIntervalSince(startTime)
        print("BertNERService: Inference completed in \(String(format: "%.3f", elapsed))s, found \(rawEntities.count) entities (after post-processing)")

        // Convert to PIIFindings and filter against existing entities
        let findings = rawEntities.compactMap { entity -> PIIFinding? in
            // Check if already covered by existing entities
            let normalizedText = entity.text.lowercased()
            let alreadyCovered = existingEntities.contains { existing in
                existing.originalText.lowercased() == normalizedText ||
                normalizedText.contains(existing.originalText.lowercased()) ||
                existing.originalText.lowercased().contains(normalizedText)
            }

            if alreadyCovered {
                print("BertNERService: '\(entity.text)' already covered by NER")
                return nil
            }

            // Filter out clinical terms and common abbreviations that are false positives
            if NERUtilities.isClinicalTerm(entity.text) {
                print("BertNERService: '\(entity.text)' filtered as clinical term")
                return nil
            }

            return PIIFinding(
                text: entity.text,
                suggestedType: entity.type,
                reason: "BERT-NER: \(entity.label)",
                confidence: entity.confidence
            )
        }

        print("BertNERService: Returning \(findings.count) new findings (delta)")
        return findings
    }

    // MARK: - Private Methods

    /// Load vocabulary from bundled vocab.txt
    private func loadVocabulary() throws {
        // Try bundle first
        var vocabURL: URL?

        if let bundledURL = Bundle.main.url(forResource: "vocab", withExtension: "txt") {
            vocabURL = bundledURL
        } else if let bundledURL = Bundle.main.url(forResource: "bert_vocab", withExtension: "txt") {
            vocabURL = bundledURL
        }

        guard let url = vocabURL else {
            print("BertNERService: vocab.txt not found in bundle, using default token IDs")
            // Use default BERT token IDs
            clsTokenId = 101
            sepTokenId = 102
            padTokenId = 0
            unkTokenId = 100
            return
        }

        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            let token = line.trimmingCharacters(in: .whitespaces)
            if !token.isEmpty {
                vocab[token] = index
                reverseVocab[index] = token
            }
        }

        // Set special token IDs
        clsTokenId = vocab[clsToken] ?? 101
        sepTokenId = vocab[sepToken] ?? 102
        padTokenId = vocab[padToken] ?? 0
        unkTokenId = vocab[unkToken] ?? 100

        print("BertNERService: Loaded vocabulary with \(vocab.count) tokens")
    }

    // MARK: - Chunk Processing

    /// Represents a text chunk with its character offset in the original text
    private struct TextChunk {
        let text: String
        let charOffset: Int
    }

    /// Split text into chunks that fit within BERT's token limit
    /// Uses sentence boundaries when possible, falls back to word boundaries
    /// Uses NSString for UTF-16 consistent position handling
    private func splitIntoChunks(text: String) -> [TextChunk] {
        // Target ~400 tokens per chunk to leave room for special tokens and overlaps
        // Average English word is ~1.3 tokens, so ~300 words per chunk
        let targetCharsPerChunk = 1500  // ~300 words * 5 chars average

        // Use NSString for UTF-16 length (consistent with other recognizers)
        let nsText = text as NSString
        let textLength = nsText.length

        guard textLength > targetCharsPerChunk else {
            return [TextChunk(text: text, charOffset: 0)]
        }

        var chunks: [TextChunk] = []
        let stepSize = targetCharsPerChunk - 200  // Small overlap

        var currentStart = 0
        while currentStart < textLength {
            // Calculate chunk end
            var chunkEnd = min(currentStart + targetCharsPerChunk, textLength)

            // If not at end, try to find a good break point (sentence or word boundary)
            if chunkEnd < textLength {
                let searchStart = max(chunkEnd - 200, currentStart + stepSize)
                let searchRange = NSRange(location: searchStart, length: chunkEnd - searchStart)

                // Try sentence boundaries in order of preference
                var foundBoundary = nsText.range(of: ". ", options: .backwards, range: searchRange)
                if foundBoundary.location == NSNotFound {
                    foundBoundary = nsText.range(of: "! ", options: .backwards, range: searchRange)
                }
                if foundBoundary.location == NSNotFound {
                    foundBoundary = nsText.range(of: "? ", options: .backwards, range: searchRange)
                }
                if foundBoundary.location == NSNotFound {
                    foundBoundary = nsText.range(of: "\n", options: .backwards, range: searchRange)
                }
                if foundBoundary.location != NSNotFound {
                    chunkEnd = foundBoundary.location + foundBoundary.length
                }
            }

            // Extract chunk using NSString (UTF-16)
            let chunkRange = NSRange(location: currentStart, length: chunkEnd - currentStart)
            let chunkText = nsText.substring(with: chunkRange)

            if !chunkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chunks.append(TextChunk(text: chunkText, charOffset: currentStart))
            }

            // Advance by step size (ensures progress)
            currentStart += stepSize

            // Break if we've covered the text
            if currentStart >= textLength - 100 {
                break
            }
        }

        return chunks
    }

    /// Process a single chunk through BERT and return entities with adjusted positions
    private func processChunk(
        chunk: String,
        charOffset: Int,
        originalText: String,
        model: MLModel
    ) async throws -> [BERTEntity] {
        // Tokenize the chunk
        let (inputIds, attentionMask, tokenToChar) = tokenize(text: chunk)

        // Create MLMultiArray inputs
        let inputIdsArray = try createMLMultiArray(from: inputIds)
        let attentionMaskArray = try createMLMultiArray(from: attentionMask)

        // Run inference
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": inputIdsArray,
            "attention_mask": attentionMaskArray
        ])

        let output = try await model.prediction(from: input)

        // Extract logits
        guard let logitsValue = output.featureValue(for: "logits"),
              let logitsArray = logitsValue.multiArrayValue else {
            throw AppError.invalidResponse
        }

        // Convert logits to BIO tags
        let tags = extractBIOTags(from: logitsArray, tokenCount: inputIds.count)

        // Aggregate tags into entities (positions relative to chunk)
        let chunkEntities = aggregateBIOTags(tags: tags, inputIds: inputIds, tokenToChar: tokenToChar, originalText: chunk)

        // Adjust positions to be relative to the original full text
        let adjustedEntities = chunkEntities.map { entity -> BERTEntity in
            BERTEntity(
                text: entity.text,
                type: entity.type,
                label: entity.label,
                start: entity.start + charOffset,
                end: entity.end + charOffset,
                confidence: entity.confidence
            )
        }

        return adjustedEntities
    }

    // MARK: - Tokenization

    /// Tokenize text using WordPiece tokenization
    /// Returns: (inputIds, attentionMask, tokenToCharMapping)
    private func tokenize(text: String) -> ([Int], [Int], [(Int, Int)]) {
        var inputIds: [Int] = [clsTokenId]
        var attentionMask: [Int] = [1]
        var tokenToChar: [(Int, Int)] = [(-1, -1)]  // CLS has no char mapping

        // Simple word tokenization first
        let words = tokenizeWords(text: text)

        for (word, charStart, charEnd) in words {
            let subwords = wordPieceTokenize(word: word)

            for (i, subword) in subwords.enumerated() {
                if inputIds.count >= maxSequenceLength - 1 {
                    break
                }

                let tokenId = vocab[subword] ?? unkTokenId
                inputIds.append(tokenId)
                attentionMask.append(1)

                // Map first subword to the word's char range
                if i == 0 {
                    tokenToChar.append((charStart, charEnd))
                } else {
                    // Continuation tokens share the same range
                    tokenToChar.append((charStart, charEnd))
                }
            }
        }

        // Add SEP token
        inputIds.append(sepTokenId)
        attentionMask.append(1)
        tokenToChar.append((-1, -1))

        // Pad to maxSequenceLength
        while inputIds.count < maxSequenceLength {
            inputIds.append(padTokenId)
            attentionMask.append(0)
            tokenToChar.append((-1, -1))
        }

        return (inputIds, attentionMask, tokenToChar)
    }

    /// Split text into words with character positions (UTF-16)
    /// Uses NSString for consistent UTF-16 position handling
    private func tokenizeWords(text: String) -> [(String, Int, Int)] {
        var words: [(String, Int, Int)] = []
        var currentWord = ""
        var wordStart = 0

        let nsText = text as NSString
        var i = 0

        while i < nsText.length {
            let char = nsText.character(at: i)
            let scalar = UnicodeScalar(char)

            let isWhitespace = CharacterSet.whitespaces.contains(scalar ?? UnicodeScalar(0))
            let isNewline = CharacterSet.newlines.contains(scalar ?? UnicodeScalar(0))
            let isPunctuation = CharacterSet.punctuationCharacters.contains(scalar ?? UnicodeScalar(0))

            if isWhitespace || isNewline || isPunctuation {
                if !currentWord.isEmpty {
                    words.append((currentWord, wordStart, i))
                    currentWord = ""
                }
                // Add punctuation as separate token
                if isPunctuation, let s = scalar {
                    words.append((String(Character(s)), i, i + 1))
                }
            } else {
                if currentWord.isEmpty {
                    wordStart = i
                }
                if let s = scalar {
                    currentWord.append(Character(s))
                }
            }
            i += 1
        }

        // Don't forget the last word
        if !currentWord.isEmpty {
            words.append((currentWord, wordStart, nsText.length))
        }

        return words
    }

    /// WordPiece tokenization
    private func wordPieceTokenize(word: String) -> [String] {
        let lowercased = word.lowercased()
        var subwords: [String] = []
        var start = lowercased.startIndex

        while start < lowercased.endIndex {
            var end = lowercased.endIndex
            var foundSubword: String?

            // Try to find longest matching subword
            while start < end {
                var subword = String(lowercased[start..<end])
                if start != lowercased.startIndex {
                    subword = "##" + subword
                }

                if vocab[subword] != nil {
                    foundSubword = subword
                    break
                }

                // Move end back
                end = lowercased.index(before: end)
            }

            if let found = foundSubword {
                subwords.append(found)
                start = end
            } else {
                // Unknown character, use UNK
                subwords.append(unkToken)
                start = lowercased.index(after: start)
            }
        }

        return subwords.isEmpty ? [unkToken] : subwords
    }

    /// Create MLMultiArray from Int array
    private func createMLMultiArray(from array: [Int]) throws -> MLMultiArray {
        let mlArray = try MLMultiArray(shape: [1, NSNumber(value: maxSequenceLength)], dataType: .int32)

        for (index, value) in array.enumerated() {
            mlArray[index] = NSNumber(value: value)
        }

        return mlArray
    }

    /// Extract BIO tags from logits
    private func extractBIOTags(from logits: MLMultiArray, tokenCount: Int) -> [String] {
        var tags: [String] = []
        let numLabels = 9  // O, B-PER, I-PER, B-ORG, I-ORG, B-LOC, I-LOC, B-MISC, I-MISC

        for tokenIdx in 0..<tokenCount {
            var maxLogit: Float = -Float.infinity
            var maxLabel = 0

            for labelIdx in 0..<numLabels {
                let index = tokenIdx * numLabels + labelIdx
                let logit = logits[index].floatValue
                if logit > maxLogit {
                    maxLogit = logit
                    maxLabel = labelIdx
                }
            }

            tags.append(id2label[maxLabel] ?? "O")
        }

        return tags
    }

    /// Aggregate BIO tags into entity spans
    private func aggregateBIOTags(
        tags: [String],
        inputIds: [Int],
        tokenToChar: [(Int, Int)],
        originalText: String
    ) -> [BERTEntity] {
        var entities: [BERTEntity] = []
        var currentEntity: (text: String, type: String, start: Int, end: Int, confidence: Double)?

        for (tokenIdx, tag) in tags.enumerated() {
            guard tokenIdx < tokenToChar.count else { break }
            let (charStart, charEnd) = tokenToChar[tokenIdx]

            // Skip special tokens (CLS, SEP, PAD)
            guard charStart >= 0 && charEnd >= 0 else {
                // End current entity if we hit a special token
                if let entity = currentEntity {
                    entities.append(createBERTEntity(from: entity, originalText: originalText))
                    currentEntity = nil
                }
                continue
            }

            if tag.hasPrefix("B-") {
                // Start of new entity
                if let entity = currentEntity {
                    entities.append(createBERTEntity(from: entity, originalText: originalText))
                }
                let entityType = String(tag.dropFirst(2))
                currentEntity = (
                    text: "",
                    type: entityType,
                    start: charStart,
                    end: charEnd,
                    confidence: 0.85
                )
            } else if tag.hasPrefix("I-") {
                // Continuation of entity
                if var entity = currentEntity {
                    let entityType = String(tag.dropFirst(2))
                    if entity.type == entityType {
                        // Extend the entity
                        entity.end = charEnd
                        currentEntity = entity
                    } else {
                        // Different type, end previous and start new
                        entities.append(createBERTEntity(from: entity, originalText: originalText))
                        currentEntity = (
                            text: "",
                            type: entityType,
                            start: charStart,
                            end: charEnd,
                            confidence: 0.85
                        )
                    }
                }
            } else {
                // O tag - end current entity
                if let entity = currentEntity {
                    entities.append(createBERTEntity(from: entity, originalText: originalText))
                    currentEntity = nil
                }
            }
        }

        // Don't forget the last entity
        if let entity = currentEntity {
            entities.append(createBERTEntity(from: entity, originalText: originalText))
        }

        return entities
    }

    /// Bridge gaps between PER entities when the gap contains capitalized words (middle names)
    /// Example: "John" + "Michael" (capitalized gap) + "Smith" → merged into "John Michael Smith"
    /// Uses NSString for UTF-16 consistent position handling
    private func bridgeNameGaps(_ entities: [BERTEntity], in text: String) -> [BERTEntity] {
        let nsText = text as NSString
        // Filter to only PER entities and sort by start position
        let personEntities = entities.filter { $0.type.isPerson }.sorted { $0.start < $1.start }
        let otherEntities = entities.filter { !$0.type.isPerson }

        guard personEntities.count >= 2 else {
            return entities
        }

        var mergedEntities: [BERTEntity] = []
        var i = 0

        while i < personEntities.count {
            var current = personEntities[i]

            // Try to merge with following entities
            while i + 1 < personEntities.count {
                let next = personEntities[i + 1]

                // Check if there's a small gap between entities
                let gapStart = current.end
                let gapEnd = next.start

                // Gap should be reasonable (< 30 chars to catch middle names with spaces)
                guard gapEnd > gapStart && gapEnd - gapStart < 30 else { break }

                // Extract gap text using NSString (UTF-16)
                let gapRange = NSRange(location: gapStart, length: gapEnd - gapStart)
                let gapText = nsText.substring(with: gapRange).trimmingCharacters(in: .whitespaces)

                // Check if gap contains only capitalized words (potential middle names)
                let gapWords = gapText.split(separator: " ")
                let allCapitalized = !gapWords.isEmpty && gapWords.allSatisfy { word in
                    guard let first = word.first else { return false }
                    return first.isUppercase && word.count >= 2
                }

                if allCapitalized {
                    // Merge entities: extend current to include next
                    let mergedStart = current.start
                    let mergedEnd = next.end
                    // Use NSString for UTF-16 consistent substring
                    let mergedRange = NSRange(location: mergedStart, length: min(mergedEnd, nsText.length) - mergedStart)
                    let mergedText = nsText.substring(with: mergedRange)

                    print("BertNERService: Bridged '\(current.text)' + '\(gapText)' + '\(next.text)' → '\(mergedText)'")

                    current = BERTEntity(
                        text: mergedText,
                        type: current.type,
                        label: current.label,
                        start: mergedStart,
                        end: mergedEnd,
                        confidence: min(current.confidence, next.confidence)
                    )
                    i += 1  // Skip the merged entity
                } else {
                    break  // Gap doesn't contain capitalized words
                }
            }

            mergedEntities.append(current)
            i += 1
        }

        // Combine with non-person entities
        return mergedEntities + otherEntities
    }

    /// Create BERT entity from aggregated span
    /// Uses NSString for UTF-16 consistent position handling
    private func createBERTEntity(
        from entity: (text: String, type: String, start: Int, end: Int, confidence: Double),
        originalText: String
    ) -> BERTEntity {
        // Use NSString for UTF-16 consistent positions
        let nsText = originalText as NSString
        let start = entity.start
        let end = min(entity.end, nsText.length)

        // Extract actual text from original using NSString (UTF-16)
        let range = NSRange(location: start, length: end - start)
        let extractedText = nsText.substring(with: range)

        return BERTEntity(
            text: extractedText,
            type: mapBERTType(entity.type),
            label: entity.type,
            start: start,
            end: end,
            confidence: entity.confidence
        )
    }

    /// Map BERT entity type to app's EntityType
    private func mapBERTType(_ bertType: String) -> EntityType {
        switch bertType {
        case "PER":
            return .personOther
        case "ORG":
            return .organization
        case "LOC":
            return .location
        case "MISC":
            return .identifier  // MISC entities mapped to identifier
        default:
            return .personOther  // Default to personOther for unknown types
        }
    }

    // MARK: - Name Post-Processing (matches SwiftNER behavior)

    /// Extend person names with following surnames
    /// If "Hannes" is detected but "Venter" follows, extend to "Hannes Venter"
    private func extendNamesWithSurnames(_ entities: [BERTEntity], in text: String) -> [BERTEntity] {
        var newEntities: [BERTEntity] = []
        let existingNames = Set(entities.map { $0.text.lowercased() })

        for entity in entities {
            // Only extend person names
            guard entity.type == .personOther || entity.type == .personClient || entity.type == .personProvider else {
                continue
            }

            // Check if there's a following word that could be a surname
            if let surname = findFollowingSurname(after: entity.end, in: text) {
                let fullName = entity.text + " " + surname

                // Skip if full name already detected
                guard !existingNames.contains(fullName.lowercased()) else { continue }

                let extendedEnd = entity.end + 1 + surname.count
                newEntities.append(BERTEntity(
                    text: fullName,
                    type: entity.type,
                    label: entity.label,
                    start: entity.start,
                    end: extendedEnd,
                    confidence: entity.confidence
                ))

                print("BertNERService: Extended '\(entity.text)' to '\(fullName)'")
            }
        }

        return newEntities
    }

    /// Find a surname following a name at the given position
    /// Uses NSString for UTF-16 consistent position handling
    private func findFollowingSurname(after endIndex: Int, in text: String) -> String? {
        let nsText = text as NSString
        guard endIndex < nsText.length else { return nil }

        // Check if followed by a space
        let charAtEnd = nsText.character(at: endIndex)
        guard charAtEnd == 32 else { return nil }  // 32 is space in UTF-16

        // Get the next word
        let afterSpace = endIndex + 1
        guard afterSpace < nsText.length else { return nil }

        // Find the end of the next word
        var wordEnd = afterSpace
        while wordEnd < nsText.length {
            let char = nsText.character(at: wordEnd)
            guard let scalar = UnicodeScalar(char), CharacterSet.letters.contains(scalar) else {
                break
            }
            wordEnd += 1
        }

        guard wordEnd > afterSpace else { return nil }

        let wordRange = NSRange(location: afterSpace, length: wordEnd - afterSpace)
        let nextWord = nsText.substring(with: wordRange)

        // Check if it looks like a surname:
        // - Starts with uppercase
        // - At least 2 characters
        // - Not a common word
        guard nextWord.count >= 2,
              nextWord.first?.isUppercase == true,
              !NERUtilities.isCommonWord(nextWord) else {
            return nil
        }

        return nextWord
    }

    /// Extract first name components from multi-word person names
    /// When "Hannes Venter" is detected, also find standalone "Hannes"
    /// Uses NSString for UTF-16 consistent position handling
    private func extractNameComponents(_ entities: [BERTEntity], in text: String) -> [BERTEntity] {
        var newEntities: [BERTEntity] = []
        let existingTexts = Set(entities.map { $0.text.lowercased() })
        let nsText = text as NSString

        for entity in entities {
            // Only process multi-word person names
            guard entity.type == .personOther || entity.type == .personClient || entity.type == .personProvider else {
                continue
            }

            let components = entity.text.split(separator: " ")
            guard components.count >= 2 else { continue }

            // Extract first name (first component)
            let firstName = String(components[0])

            // Skip if first name already detected
            guard !existingTexts.contains(firstName.lowercased()) else { continue }

            // Skip if already added
            guard !newEntities.contains(where: { $0.text.lowercased() == firstName.lowercased() }) else { continue }

            // Skip if too short or common word
            guard firstName.count >= 3, !NERUtilities.isCommonWord(firstName) else { continue }

            var foundPositions: [(start: Int, end: Int)] = []

            // Use word boundary regex to avoid matching inside other words
            // Also match possessive forms without apostrophe (e.g., "Sean" also matches "Seans")
            let escapedName = NSRegularExpression.escapedPattern(for: firstName)
            let pattern = "\\b\(escapedName)s?\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }

            let searchRange = NSRange(location: 0, length: nsText.length)
            let matches = regex.matches(in: text, options: [], range: searchRange)

            for match in matches {
                // Use NSRange directly for UTF-16 positions
                let start = match.range.location
                let end = match.range.location + match.range.length

                // Check this isn't part of the full name (already covered)
                let isPartOfFullName = (start >= entity.start && end <= entity.end)

                if !isPartOfFullName {
                    foundPositions.append((start: start, end: end))
                }
            }

            // Create entity for each standalone occurrence
            for pos in foundPositions {
                newEntities.append(BERTEntity(
                    text: firstName,
                    type: entity.type,
                    label: entity.label,
                    start: pos.start,
                    end: pos.end,
                    confidence: entity.confidence
                ))
            }

            if !foundPositions.isEmpty {
                print("BertNERService: Extracted '\(firstName)' from '\(entity.text)' (\(foundPositions.count) standalone occurrences)")
            }
        }

        return newEntities
    }

    // MARK: - Identifier Detection

    /// Detect alphanumeric identifiers (codes, reference numbers, etc.)
    /// Matches strings with both letters AND numbers like "S7798120001" or "VEND-G0M136"
    /// Uses NSString for UTF-16 consistent position handling
    private func detectIdentifiers(in text: String) -> [BERTEntity] {
        var identifiers: [BERTEntity] = []
        let nsText = text as NSString

        // Pattern: word boundaries, alphanumeric with optional hyphens, min 4 chars
        // Must contain at least one letter AND one digit
        let pattern = #"\b[A-Za-z0-9][A-Za-z0-9\-]{3,}[A-Za-z0-9]\b"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return identifiers
        }

        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)

        for match in matches {
            // Use NSString for UTF-16 consistent substring
            let matchText = nsText.substring(with: match.range)

            // Must contain both letters and digits
            let hasLetter = matchText.contains(where: { $0.isLetter })
            let hasDigit = matchText.contains(where: { $0.isNumber })
            guard hasLetter && hasDigit else { continue }

            // Skip common patterns that aren't identifiers
            if NERUtilities.isCommonAbbreviation(matchText) { continue }

            // Use NSRange directly for UTF-16 positions
            let start = match.range.location
            let end = match.range.location + match.range.length

            identifiers.append(BERTEntity(
                text: matchText,
                type: .identifier,
                label: "IDENTIFIER",
                start: start,
                end: end,
                confidence: 0.90
            ))

            print("BertNERService: Detected identifier '\(matchText)'")
        }

        return identifiers
    }

    // MARK: - Deduplication

    /// Deduplicate BERT entities by text (case-insensitive)
    /// Keeps the entity with higher confidence when duplicates found
    private func deduplicateBERTEntities(_ entities: [BERTEntity]) -> [BERTEntity] {
        var seen: [String: BERTEntity] = [:]

        for entity in entities {
            let key = entity.text.lowercased()
            if let existing = seen[key] {
                // Keep entity with higher confidence
                if entity.confidence > existing.confidence {
                    seen[key] = entity
                }
            } else {
                seen[key] = entity
            }
        }

        return Array(seen.values).sorted { $0.start < $1.start }
    }
}

// MARK: - BERT Entity

private struct BERTEntity {
    let text: String
    let type: EntityType
    let label: String
    let start: Int
    let end: Int
    let confidence: Double
}
