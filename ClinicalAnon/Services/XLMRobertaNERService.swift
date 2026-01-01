//
//  XLMRobertaNERService.swift
//  Redactor
//
//  Purpose: XLM-RoBERTa-based Named Entity Recognition for multilingual names
//  Organization: 3 Big Things
//

import Foundation
import CoreML
import NaturalLanguage

// MARK: - XLM-RoBERTa NER Service

@MainActor
class XLMRobertaNERService: ObservableObject {

    // MARK: - Singleton

    static let shared = XLMRobertaNERService()

    // MARK: - Model Constants

    private let modelName = "XLMRobertaNER"
    private let maxSequenceLength = 512
    private let vocabSize = 250002  // XLM-R vocab size

    // Chunking settings for long documents
    private let chunkSize = 450        // Tokens per chunk (leaving room for CLS/SEP)
    private let chunkOverlap = 100     // Overlapping tokens between chunks
    private let maxCharsPerChunk = 2000  // Approximate chars per chunk (conservative estimate)

    // BIO label mapping from the model (Davlan/xlm-roberta-base-ner-hrl)
    private let id2label: [Int: String] = [
        0: "O",
        1: "B-DATE",
        2: "I-DATE",
        3: "B-PER",
        4: "I-PER",
        5: "B-ORG",
        6: "I-ORG",
        7: "B-LOC",
        8: "I-LOC"
    ]

    // Static version for nonisolated methods
    private static let staticId2label: [Int: String] = [
        0: "O",
        1: "B-DATE",
        2: "I-DATE",
        3: "B-PER",
        4: "I-PER",
        5: "B-ORG",
        6: "I-ORG",
        7: "B-LOC",
        8: "I-LOC"
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
    private var tokenizer: SentencePieceTokenizer?

    // XLM-R special tokens (from HuggingFace tokenizer)
    private let clsTokenId = 0      // <s>
    private let sepTokenId = 2      // </s>
    private let padTokenId = 1      // <pad>
    private let unkTokenId = 3      // <unk>
    private let vocabSizeExpected = 250002  // Full XLM-R vocab with special tokens

    // MARK: - Initialization

    private init() {
        checkAvailability()
    }

    // MARK: - Public Methods

    /// Check if CoreML XLM-R is available
    func checkAvailability() {
        #if arch(arm64)
        isAvailable = true
        print("XLMRobertaNERService: CoreML available on Apple Silicon")
        #else
        isAvailable = true
        print("XLMRobertaNERService: CoreML available (Intel Mac - may be slower)")
        #endif
    }

    /// Check if the model is bundled or cached
    var isModelCached: Bool {
        if Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") != nil ||
           Bundle.main.url(forResource: modelName, withExtension: "mlpackage") != nil {
            return true
        }
        let cacheURL = cachedModelPath
        return FileManager.default.fileExists(atPath: cacheURL.path)
    }

    /// Get the path where the model would be cached
    var cachedModelPath: URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cacheDir.appendingPathComponent("XLMRobertaNER").appendingPathComponent("\(modelName).mlmodelc")
    }

    /// Load the model
    func loadModel() async throws {
        guard isAvailable else {
            throw AppError.localLLMNotAvailable
        }

        if isModelLoaded && model != nil {
            print("XLMRobertaNERService: Model already loaded")
            return
        }

        isDownloading = true
        downloadProgress = 0
        lastError = nil

        print("XLMRobertaNERService: Loading XLM-RoBERTa NER model...")

        do {
            // Try to load from bundle first
            if let bundledURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
                print("XLMRobertaNERService: Loading bundled compiled model")
                model = try MLModel(contentsOf: bundledURL)
            } else if let bundledPackageURL = Bundle.main.url(forResource: modelName, withExtension: "mlpackage") {
                print("XLMRobertaNERService: Loading bundled mlpackage")
                let compiledURL = try await MLModel.compileModel(at: bundledPackageURL)
                model = try MLModel(contentsOf: compiledURL)
            } else {
                let cacheURL = cachedModelPath
                if FileManager.default.fileExists(atPath: cacheURL.path) {
                    print("XLMRobertaNERService: Loading from cache: \(cacheURL.path)")
                    model = try MLModel(contentsOf: cacheURL)
                } else {
                    throw AppError.localLLMModelNotLoaded
                }
            }

            // Load SentencePiece tokenizer
            try loadTokenizer()

            isModelLoaded = true
            isDownloading = false
            print("XLMRobertaNERService: Model loaded successfully")

        } catch {
            isDownloading = false
            print("XLMRobertaNERService: Failed to load model: \(error)")
            lastError = error.localizedDescription
            throw AppError.localLLMModelLoadFailed(error.localizedDescription)
        }
    }

    /// Unload the model to free memory
    func unloadModel() {
        model = nil
        tokenizer = nil
        isModelLoaded = false
        print("XLMRobertaNERService: Model unloaded")
    }

    /// Run NER scan on text and return findings (with chunking for long documents)
    func runNERScan(text: String, existingEntities: [Entity]) async throws -> [PIIFinding] {
        guard isAvailable else {
            throw AppError.localLLMNotAvailable
        }

        if !isModelLoaded {
            try await loadModel()
        }

        guard let mlModel = model, let spmTokenizer = tokenizer else {
            throw AppError.localLLMModelNotLoaded
        }

        isProcessing = true
        defer { isProcessing = false }

        // Detect language for logging
        let language = detectLanguage(text)
        print("XLMRobertaNERService: Starting NER scan (language: \(language ?? "unknown"), length: \(text.count))")

        let startTime = Date()

        // Normalize Unicode (NFC)
        print("XLMRobertaNERService: Normalizing text...")
        let normalizedText = text.precomposedStringWithCanonicalMapping
        print("XLMRobertaNERService: Text normalized")

        // Split into chunks for long documents
        print("XLMRobertaNERService: Splitting into chunks...")
        let chunks = splitIntoChunks(normalizedText)
        print("XLMRobertaNERService: Split into \(chunks.count) chunk(s)")

        // Process each chunk and collect entities
        var allRawEntities: [XLMREntity] = []

        for (chunkIndex, chunk) in chunks.enumerated() {
            let chunkEntities = try await processChunk(
                chunk: chunk,
                chunkIndex: chunkIndex,
                totalChunks: chunks.count,
                model: mlModel,
                tokenizer: spmTokenizer,
                maxSeqLen: maxSequenceLength,
                clsId: clsTokenId,
                sepId: sepTokenId,
                padId: padTokenId
            )
            allRawEntities.append(contentsOf: chunkEntities)
        }

        // Deduplicate entities from overlapping chunks
        var rawEntities = deduplicateEntities(allRawEntities)

        // Post-processing: Bridge gaps between PER entities for middle names
        rawEntities = bridgeNameGaps(rawEntities, in: normalizedText)

        // Post-processing: Extract first name components from full names
        let extractedComponents = extractNameComponents(rawEntities, in: normalizedText)
        rawEntities.append(contentsOf: extractedComponents)

        // Post-processing: Detect alphanumeric identifiers
        let identifiers = detectIdentifiers(in: normalizedText)
        rawEntities.append(contentsOf: identifiers)

        let elapsed = Date().timeIntervalSince(startTime)
        print("XLMRobertaNERService: Inference completed in \(String(format: "%.3f", elapsed))s, found \(rawEntities.count) entities")

        // Convert to PIIFindings and filter against existing entities
        let findings = rawEntities.compactMap { entity -> PIIFinding? in
            let normalizedEntityText = entity.text.lowercased()
            let alreadyCovered = existingEntities.contains { existing in
                existing.originalText.lowercased() == normalizedEntityText ||
                normalizedEntityText.contains(existing.originalText.lowercased()) ||
                existing.originalText.lowercased().contains(normalizedEntityText)
            }

            if alreadyCovered {
                return nil
            }

            return PIIFinding(
                text: entity.text,
                suggestedType: entity.type,
                reason: "XLM-R NER: \(entity.label)",
                confidence: entity.confidence
            )
        }

        print("XLMRobertaNERService: Returning \(findings.count) new findings")
        return findings
    }

    // MARK: - Private Methods

    /// Detect dominant language
    private func detectLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    // MARK: - Text Chunking for Long Documents

    /// Represents a chunk of text with its position in the original document
    private struct TextChunk {
        let text: String
        let startOffset: Int  // Character offset in original text
        let endOffset: Int
    }

    /// Split long text into overlapping chunks
    private func splitIntoChunks(_ text: String) -> [TextChunk] {
        // Convert to Array for O(1) indexing (Swift String indexing is O(n))
        let chars = Array(text)
        let textLength = chars.count

        // If text is short enough, return as single chunk
        if textLength <= maxCharsPerChunk {
            return [TextChunk(text: text, startOffset: 0, endOffset: textLength)]
        }

        var chunks: [TextChunk] = []
        let stepSize = maxCharsPerChunk - 200  // Small overlap of 200 chars

        var currentStart = 0
        while currentStart < textLength {
            // Calculate chunk end
            var chunkEnd = min(currentStart + maxCharsPerChunk, textLength)

            // Try to break at sentence boundary (search last 200 chars)
            if chunkEnd < textLength {
                let searchStart = max(chunkEnd - 200, currentStart + stepSize)  // Don't search too far back
                for i in stride(from: chunkEnd - 1, through: searchStart, by: -1) {
                    let c = chars[i]
                    if c == "." || c == "!" || c == "?" || c == "\n" {
                        chunkEnd = i + 1
                        break
                    }
                }
            }

            // Extract chunk
            let chunkText = String(chars[currentStart..<chunkEnd])

            chunks.append(TextChunk(
                text: chunkText,
                startOffset: currentStart,
                endOffset: chunkEnd
            ))

            // Advance by step size (ensures progress)
            currentStart += stepSize

            // Break if we've covered the text
            if currentStart >= textLength - 100 {
                break
            }
        }

        print("XLMRobertaNERService: Created \(chunks.count) chunks")
        return chunks
    }

    /// Process a single chunk and return entities with adjusted positions
    nonisolated private func processChunk(
        chunk: TextChunk,
        chunkIndex: Int,
        totalChunks: Int,
        model: MLModel,
        tokenizer: SentencePieceTokenizer,
        maxSeqLen: Int,
        clsId: Int,
        sepId: Int,
        padId: Int
    ) async throws -> [XLMREntity] {

        print("XLMRobertaNERService: Processing chunk \(chunkIndex + 1)/\(totalChunks) (chars \(chunk.startOffset)-\(chunk.endOffset))")

        // Tokenize the chunk
        let (inputIds, attentionMask, tokenToChar) = tokenizer.tokenize(
            text: chunk.text,
            maxLength: maxSeqLen,
            clsTokenId: clsId,
            sepTokenId: sepId,
            padTokenId: padId
        )

        // Create MLMultiArray inputs
        let inputIdsArray = try createMLMultiArrayNonisolated(from: inputIds, maxLength: maxSeqLen)
        let attentionMaskArray = try createMLMultiArrayNonisolated(from: attentionMask, maxLength: maxSeqLen)

        // Run inference
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": inputIdsArray,
            "attention_mask": attentionMaskArray
        ])

        print("XLMRobertaNERService: Running inference for chunk \(chunkIndex + 1)...")

        // Run inference on background thread to avoid blocking
        let output = try await Task.detached(priority: .userInitiated) {
            try model.prediction(from: input)
        }.value

        print("XLMRobertaNERService: Inference complete for chunk \(chunkIndex + 1)")

        // Extract logits
        guard let logitsValue = output.featureValue(for: "logits"),
              let logitsArray = logitsValue.multiArrayValue else {
            throw AppError.invalidResponse
        }

        // Convert logits to BIO tags
        let tags = Self.extractBIOTagsStatic(from: logitsArray, tokenCount: inputIds.count, id2label: Self.staticId2label)

        // Aggregate tags into entities (with chunk-local positions)
        let localEntities = Self.aggregateBIOTagsStatic(
            tags: tags,
            inputIds: inputIds,
            tokenToChar: tokenToChar,
            originalText: chunk.text
        )

        // Adjust entity positions to global document coordinates
        let globalEntities = localEntities.map { entity -> XLMREntity in
            XLMREntity(
                text: entity.text,
                type: entity.type,
                label: entity.label,
                start: entity.start + chunk.startOffset,
                end: entity.end + chunk.startOffset,
                confidence: entity.confidence
            )
        }

        print("XLMRobertaNERService: Chunk \(chunkIndex + 1) found \(globalEntities.count) entities")
        return globalEntities
    }

    /// Deduplicate entities from overlapping chunks
    private func deduplicateEntities(_ entities: [XLMREntity]) -> [XLMREntity] {
        guard !entities.isEmpty else { return [] }

        // Sort by start position, then by length (prefer longer matches)
        let sorted = entities.sorted { a, b in
            if a.start != b.start {
                return a.start < b.start
            }
            return (a.end - a.start) > (b.end - b.start)
        }

        var result: [XLMREntity] = []
        var lastEnd = -1

        for entity in sorted {
            // Skip if this entity overlaps significantly with a previous one
            if entity.start < lastEnd {
                // Check if it's mostly overlapping (>50%)
                let overlapAmount = lastEnd - entity.start
                let entityLength = entity.end - entity.start
                if overlapAmount > entityLength / 2 {
                    continue  // Skip duplicate
                }
            }

            result.append(entity)
            lastEnd = max(lastEnd, entity.end)
        }

        print("XLMRobertaNERService: Deduplicated \(entities.count) → \(result.count) entities")
        return result
    }

    /// Load SentencePiece tokenizer with vocabulary JSON
    private func loadTokenizer() throws {
        // Primary: look for xlmr_vocab.json in bundle
        if let vocabURL = Bundle.main.url(forResource: "xlmr_vocab", withExtension: "json") {
            tokenizer = try SentencePieceTokenizer(modelPath: vocabURL)
            print("XLMRobertaNERService: Loaded tokenizer from xlmr_vocab.json")
            return
        }

        // Fallback: look in BERT resources directory
        if let bertDir = Bundle.main.url(forResource: "BERT", withExtension: nil) {
            let vocabPath = bertDir.appendingPathComponent("xlmr_vocab.json")
            if FileManager.default.fileExists(atPath: vocabPath.path) {
                tokenizer = try SentencePieceTokenizer(modelPath: vocabPath)
                print("XLMRobertaNERService: Loaded tokenizer from BERT/xlmr_vocab.json")
                return
            }
        }

        // Fallback: look for sentencepiece model (tokenizer will look for JSON in same directory)
        if let spmURL = Bundle.main.url(forResource: "sentencepiece.bpe", withExtension: "model") {
            tokenizer = try SentencePieceTokenizer(modelPath: spmURL)
            print("XLMRobertaNERService: Loaded tokenizer via SentencePiece model path")
            return
        }

        throw AppError.localLLMModelLoadFailed("XLM-R vocabulary file not found (xlmr_vocab.json)")
    }

    /// Create MLMultiArray from Int array
    private func createMLMultiArray(from array: [Int]) throws -> MLMultiArray {
        let mlArray = try MLMultiArray(shape: [1, NSNumber(value: maxSequenceLength)], dataType: .int32)

        for (index, value) in array.enumerated() {
            mlArray[index] = NSNumber(value: value)
        }

        return mlArray
    }

    /// Create MLMultiArray from Int array (nonisolated version for background processing)
    nonisolated private func createMLMultiArrayNonisolated(from array: [Int], maxLength: Int) throws -> MLMultiArray {
        let mlArray = try MLMultiArray(shape: [1, NSNumber(value: maxLength)], dataType: .int32)

        for (index, value) in array.enumerated() {
            mlArray[index] = NSNumber(value: value)
        }

        return mlArray
    }

    /// Extract BIO tags from logits
    private func extractBIOTags(from logits: MLMultiArray, tokenCount: Int) -> [String] {
        return Self.extractBIOTagsStatic(from: logits, tokenCount: tokenCount, id2label: id2label)
    }

    /// Extract BIO tags from logits (static version for background processing)
    nonisolated private static func extractBIOTagsStatic(from logits: MLMultiArray, tokenCount: Int, id2label: [Int: String]) -> [String] {
        var tags: [String] = []
        let numLabels = id2label.count

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
    ) -> [XLMREntity] {
        return Self.aggregateBIOTagsStatic(tags: tags, inputIds: inputIds, tokenToChar: tokenToChar, originalText: originalText)
    }

    /// Aggregate BIO tags into entity spans (static version for background processing)
    nonisolated private static func aggregateBIOTagsStatic(
        tags: [String],
        inputIds: [Int],
        tokenToChar: [(Int, Int)],
        originalText: String
    ) -> [XLMREntity] {
        var entities: [XLMREntity] = []
        var currentEntity: (text: String, type: String, start: Int, end: Int, confidence: Double)?

        for (tokenIdx, tag) in tags.enumerated() {
            guard tokenIdx < tokenToChar.count else { break }
            let (charStart, charEnd) = tokenToChar[tokenIdx]

            // Skip special tokens
            guard charStart >= 0 && charEnd >= 0 else {
                if let entity = currentEntity {
                    entities.append(createXLMREntityStatic(from: entity, originalText: originalText))
                    currentEntity = nil
                }
                continue
            }

            if tag.hasPrefix("B-") {
                // Start of new entity
                if let entity = currentEntity {
                    entities.append(createXLMREntityStatic(from: entity, originalText: originalText))
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
                        entity.end = charEnd
                        currentEntity = entity
                    } else {
                        entities.append(createXLMREntityStatic(from: entity, originalText: originalText))
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
                    entities.append(createXLMREntityStatic(from: entity, originalText: originalText))
                    currentEntity = nil
                }
            }
        }

        if let entity = currentEntity {
            entities.append(createXLMREntityStatic(from: entity, originalText: originalText))
        }

        return entities
    }

    /// Bridge gaps between PER entities when the gap contains capitalized words
    private func bridgeNameGaps(_ entities: [XLMREntity], in text: String) -> [XLMREntity] {
        let personEntities = entities.filter { $0.type.isPerson }.sorted { $0.start < $1.start }
        let otherEntities = entities.filter { !$0.type.isPerson }

        guard personEntities.count >= 2 else {
            return entities
        }

        var mergedEntities: [XLMREntity] = []
        var i = 0

        while i < personEntities.count {
            var current = personEntities[i]

            while i + 1 < personEntities.count {
                let next = personEntities[i + 1]
                let gapStart = current.end
                let gapEnd = next.start

                guard gapEnd > gapStart && gapEnd - gapStart < 30 else { break }

                let gapStartIdx = text.index(text.startIndex, offsetBy: gapStart)
                let gapEndIdx = text.index(text.startIndex, offsetBy: gapEnd)
                let gapText = String(text[gapStartIdx..<gapEndIdx]).trimmingCharacters(in: .whitespaces)

                let gapWords = gapText.split(separator: " ")
                let allCapitalized = !gapWords.isEmpty && gapWords.allSatisfy { word in
                    guard let first = word.first else { return false }
                    return first.isUppercase && word.count >= 2
                }

                if allCapitalized {
                    let mergedStart = current.start
                    let mergedEnd = next.end
                    let startIdx = text.index(text.startIndex, offsetBy: mergedStart)
                    let endIdx = text.index(text.startIndex, offsetBy: min(mergedEnd, text.count))
                    let mergedText = String(text[startIdx..<endIdx])

                    print("XLMRobertaNERService: Bridged '\(current.text)' + '\(gapText)' + '\(next.text)' → '\(mergedText)'")

                    current = XLMREntity(
                        text: mergedText,
                        type: current.type,
                        label: current.label,
                        start: mergedStart,
                        end: mergedEnd,
                        confidence: min(current.confidence, next.confidence)
                    )
                    i += 1
                } else {
                    break
                }
            }

            mergedEntities.append(current)
            i += 1
        }

        return mergedEntities + otherEntities
    }

    /// Create XLMREntity from aggregated span
    private func createXLMREntity(
        from entity: (text: String, type: String, start: Int, end: Int, confidence: Double),
        originalText: String
    ) -> XLMREntity {
        return Self.createXLMREntityStatic(from: entity, originalText: originalText)
    }

    nonisolated private static func createXLMREntityStatic(
        from entity: (text: String, type: String, start: Int, end: Int, confidence: Double),
        originalText: String
    ) -> XLMREntity {
        let start = entity.start
        let end = min(entity.end, originalText.count)

        let startIdx = originalText.index(originalText.startIndex, offsetBy: start)
        let endIdx = originalText.index(originalText.startIndex, offsetBy: end)
        let extractedText = String(originalText[startIdx..<endIdx])

        return XLMREntity(
            text: extractedText,
            type: mapXLMRTypeStatic(entity.type),
            label: entity.type,
            start: start,
            end: end,
            confidence: entity.confidence
        )
    }

    /// Map XLM-R entity type to app's EntityType
    private func mapXLMRType(_ xlmrType: String) -> EntityType {
        return Self.mapXLMRTypeStatic(xlmrType)
    }

    nonisolated private static func mapXLMRTypeStatic(_ xlmrType: String) -> EntityType {
        switch xlmrType {
        case "PER":
            return .personOther
        case "ORG":
            return .organization
        case "LOC":
            return .location
        case "DATE":
            return .date
        default:
            return .personOther
        }
    }

    // MARK: - Name Post-Processing

    /// Extract first name components from multi-word names
    private func extractNameComponents(_ entities: [XLMREntity], in text: String) -> [XLMREntity] {
        var newEntities: [XLMREntity] = []
        let existingTexts = Set(entities.map { $0.text.lowercased() })

        for entity in entities {
            guard entity.type == .personOther || entity.type == .personClient || entity.type == .personProvider else {
                continue
            }

            let components = entity.text.split(separator: " ")
            guard components.count >= 2 else { continue }

            let firstName = String(components[0])

            guard !existingTexts.contains(firstName.lowercased()) else { continue }
            guard !newEntities.contains(where: { $0.text.lowercased() == firstName.lowercased() }) else { continue }
            guard firstName.count >= 3, !isCommonWord(firstName) else { continue }

            var searchStart = text.startIndex
            var foundPositions: [(start: Int, end: Int)] = []

            while let range = text.range(of: firstName, options: .caseInsensitive, range: searchStart..<text.endIndex) {
                let start = text.distance(from: text.startIndex, to: range.lowerBound)
                let end = text.distance(from: text.startIndex, to: range.upperBound)

                let isPartOfFullName = (start >= entity.start && end <= entity.end)

                if !isPartOfFullName {
                    foundPositions.append((start: start, end: end))
                }
                searchStart = range.upperBound
            }

            for pos in foundPositions {
                newEntities.append(XLMREntity(
                    text: firstName,
                    type: entity.type,
                    label: entity.label,
                    start: pos.start,
                    end: pos.end,
                    confidence: entity.confidence
                ))
            }
        }

        return newEntities
    }

    /// Check if a word is common
    private func isCommonWord(_ word: String) -> Bool {
        let commonWords: Set<String> = [
            "the", "and", "for", "are", "but", "not", "you", "all", "can", "had",
            "her", "was", "one", "our", "out", "has", "his", "him", "how", "its",
            "may", "new", "now", "old", "see", "way", "who", "did", "get",
            "let", "put", "say", "she", "too", "use", "very", "well", "with",
            "this", "that", "they", "from", "have", "been", "were", "what", "when",
            "will", "more", "some", "them", "than", "then", "only", "come", "could",
            "january", "february", "march", "april", "june", "july", "august",
            "september", "october", "november", "december", "monday", "tuesday",
            "wednesday", "thursday", "friday", "saturday", "sunday"
        ]
        return commonWords.contains(word.lowercased())
    }

    // MARK: - Identifier Detection

    /// Detect alphanumeric identifiers
    private func detectIdentifiers(in text: String) -> [XLMREntity] {
        var identifiers: [XLMREntity] = []

        let pattern = #"\b[A-Za-z0-9][A-Za-z0-9\-]{3,}[A-Za-z0-9]\b"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return identifiers
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        for match in matches {
            guard let swiftRange = Range(match.range, in: text) else { continue }
            let matchText = String(text[swiftRange])

            let hasLetter = matchText.contains(where: { $0.isLetter })
            let hasDigit = matchText.contains(where: { $0.isNumber })
            guard hasLetter && hasDigit else { continue }

            if isCommonAbbreviation(matchText) { continue }

            let start = text.distance(from: text.startIndex, to: swiftRange.lowerBound)
            let end = text.distance(from: text.startIndex, to: swiftRange.upperBound)

            identifiers.append(XLMREntity(
                text: matchText,
                type: .identifier,
                label: "IDENTIFIER",
                start: start,
                end: end,
                confidence: 0.90
            ))

            print("XLMRobertaNERService: Detected identifier '\(matchText)'")
        }

        return identifiers
    }

    /// Check for common abbreviations
    private func isCommonAbbreviation(_ text: String) -> Bool {
        let commonPatterns: Set<String> = [
            "1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th", "10th",
            "11th", "12th", "13th", "14th", "15th", "16th", "17th", "18th", "19th", "20th",
            "21st", "22nd", "23rd", "24th", "25th", "26th", "27th", "28th", "29th", "30th", "31st",
            "covid19", "covid-19", "h1n1", "mp3", "mp4", "a4", "b12", "c19"
        ]
        return commonPatterns.contains(text.lowercased())
    }
}

// MARK: - XLM-R Entity

private struct XLMREntity {
    let text: String
    let type: EntityType
    let label: String
    let start: Int
    let end: Int
    let confidence: Double
}

// MARK: - SentencePiece Tokenizer

/// SentencePiece tokenizer for XLM-RoBERTa using vocabulary JSON
class SentencePieceTokenizer {

    private var vocab: [String: Int] = [:]
    private let unkTokenId: Int
    private let wordPrefix = "▁"  // Unicode U+2581

    init(modelPath: URL) throws {
        // Try to load vocabulary JSON (xlmr_vocab.json)
        let vocabURL: URL
        if modelPath.pathExtension == "json" {
            vocabURL = modelPath
        } else {
            // Look for vocab JSON in same directory
            let directory = modelPath.deletingLastPathComponent()
            vocabURL = directory.appendingPathComponent("xlmr_vocab.json")
        }

        guard FileManager.default.fileExists(atPath: vocabURL.path) else {
            throw NSError(domain: "SentencePieceTokenizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Vocabulary file not found at \(vocabURL.path)"])
        }

        let data = try Data(contentsOf: vocabURL)
        vocab = try JSONDecoder().decode([String: Int].self, from: data)

        // Find UNK token ID (should be 3 for XLM-R)
        unkTokenId = vocab["<unk>"] ?? 3

        print("SentencePieceTokenizer: Loaded \(vocab.count) vocabulary entries")

        // Verify special tokens
        let clsId = vocab["<s>"] ?? -1
        let sepId = vocab["</s>"] ?? -1
        let padId = vocab["<pad>"] ?? -1
        print("SentencePieceTokenizer: Special tokens - <s>=\(clsId), </s>=\(sepId), <pad>=\(padId), <unk>=\(unkTokenId)")
    }

    /// Tokenize text and return (inputIds, attentionMask, tokenToCharMapping)
    func tokenize(
        text: String,
        maxLength: Int,
        clsTokenId: Int,
        sepTokenId: Int,
        padTokenId: Int
    ) -> ([Int], [Int], [(Int, Int)]) {

        var inputIds: [Int] = [clsTokenId]
        var attentionMask: [Int] = [1]
        var tokenToChar: [(Int, Int)] = [(-1, -1)]  // CLS has no char mapping

        // Tokenize using BPE with word prefix
        let tokens = bpeTokenize(text: text)

        for token in tokens {
            if inputIds.count >= maxLength - 1 {
                break
            }

            inputIds.append(token.id)
            attentionMask.append(1)
            tokenToChar.append((token.charStart, token.charEnd))
        }

        // Add SEP token
        inputIds.append(sepTokenId)
        attentionMask.append(1)
        tokenToChar.append((-1, -1))

        // Pad to maxLength
        while inputIds.count < maxLength {
            inputIds.append(padTokenId)
            attentionMask.append(0)
            tokenToChar.append((-1, -1))
        }

        return (inputIds, attentionMask, tokenToChar)
    }

    /// Token with ID and character positions
    private struct Token {
        let piece: String
        let id: Int
        let charStart: Int
        let charEnd: Int
    }

    /// BPE tokenize text into subword tokens
    private func bpeTokenize(text: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(text)
        var i = 0

        while i < chars.count {
            // Skip whitespace but track position
            if chars[i].isWhitespace {
                i += 1
                continue
            }

            // Find the end of this word (until whitespace)
            var wordEnd = i
            while wordEnd < chars.count && !chars[wordEnd].isWhitespace {
                wordEnd += 1
            }

            // Extract word
            let wordStart = i
            let word = String(chars[wordStart..<wordEnd])

            // Tokenize this word with BPE
            let wordTokens = tokenizeWord(word, charOffset: wordStart, isWordStart: true)
            tokens.append(contentsOf: wordTokens)

            i = wordEnd
        }

        return tokens
    }

    /// Tokenize a single word using greedy BPE matching
    private func tokenizeWord(_ word: String, charOffset: Int, isWordStart: Bool) -> [Token] {
        var tokens: [Token] = []
        var remaining = word
        var currentOffset = charOffset
        var isFirst = isWordStart

        while !remaining.isEmpty {
            // Try to find the longest matching piece
            var found = false

            // For first subword of a word, try with ▁ prefix
            let prefixedRemaining = isFirst ? (wordPrefix + remaining) : remaining

            // Try longest to shortest
            for length in stride(from: prefixedRemaining.count, through: 1, by: -1) {
                let endIndex = prefixedRemaining.index(prefixedRemaining.startIndex, offsetBy: length)
                let candidate = String(prefixedRemaining[prefixedRemaining.startIndex..<endIndex])

                if let tokenId = vocab[candidate] {
                    // Found a match
                    let actualLength = isFirst ? (length - 1) : length  // Subtract ▁ prefix length
                    let pieceEndOffset = currentOffset + actualLength

                    tokens.append(Token(
                        piece: candidate,
                        id: tokenId,
                        charStart: currentOffset,
                        charEnd: pieceEndOffset
                    ))

                    // Advance
                    if actualLength > 0 {
                        let advanceIndex = remaining.index(remaining.startIndex, offsetBy: actualLength)
                        remaining = String(remaining[advanceIndex...])
                        currentOffset = pieceEndOffset
                    } else {
                        // Edge case: only matched the prefix itself
                        break
                    }

                    isFirst = false
                    found = true
                    break
                }
            }

            if !found {
                // No match found - use UNK token for first character and continue
                let firstChar = String(remaining.prefix(1))

                // Try the character with prefix if first
                let charPiece = isFirst ? (wordPrefix + firstChar) : firstChar
                let tokenId = vocab[charPiece] ?? vocab[firstChar] ?? unkTokenId

                tokens.append(Token(
                    piece: charPiece,
                    id: tokenId,
                    charStart: currentOffset,
                    charEnd: currentOffset + 1
                ))

                remaining = String(remaining.dropFirst())
                currentOffset += 1
                isFirst = false
            }
        }

        return tokens
    }
}
