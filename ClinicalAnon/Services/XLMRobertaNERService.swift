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

    // BIO label mapping from the model (Davlan/xlm-roberta-base-ner-hrl)
    private let id2label: [Int: String] = [
        0: "O",
        1: "B-PER",
        2: "I-PER",
        3: "B-ORG",
        4: "I-ORG",
        5: "B-LOC",
        6: "I-LOC",
        7: "B-DATE",
        8: "I-DATE"
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

    // XLM-R special tokens (different from BERT!)
    private let clsTokenId = 0      // <s>
    private let sepTokenId = 2      // </s>
    private let padTokenId = 1      // <pad>
    private let unkTokenId = 3      // <unk>

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

    /// Run NER scan on text and return findings
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
        let normalizedText = text.precomposedStringWithCanonicalMapping

        // Tokenize the input
        let (inputIds, attentionMask, tokenToChar) = spmTokenizer.tokenize(
            text: normalizedText,
            maxLength: maxSequenceLength,
            clsTokenId: clsTokenId,
            sepTokenId: sepTokenId,
            padTokenId: padTokenId
        )

        // Create MLMultiArray inputs
        let inputIdsArray = try createMLMultiArray(from: inputIds)
        let attentionMaskArray = try createMLMultiArray(from: attentionMask)

        // Run inference
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": inputIdsArray,
            "attention_mask": attentionMaskArray
        ])

        let output = try await mlModel.prediction(from: input)

        // Extract logits
        guard let logitsValue = output.featureValue(for: "logits"),
              let logitsArray = logitsValue.multiArrayValue else {
            throw AppError.invalidResponse
        }

        // Convert logits to BIO tags
        let tags = extractBIOTags(from: logitsArray, tokenCount: inputIds.count)

        // Aggregate tags into entities
        var rawEntities = aggregateBIOTags(
            tags: tags,
            inputIds: inputIds,
            tokenToChar: tokenToChar,
            originalText: normalizedText
        )

        // Post-processing: Bridge gaps between PER entities for middle names
        rawEntities = bridgeNameGaps(rawEntities, in: normalizedText)

        // Post-processing: Extend names with following surnames
        let extendedEntities = extendNamesWithSurnames(rawEntities, in: normalizedText)
        rawEntities.append(contentsOf: extendedEntities)

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

    /// Load SentencePiece tokenizer
    private func loadTokenizer() throws {
        // Look for sentencepiece model in bundle
        guard let spmURL = Bundle.main.url(forResource: "sentencepiece.bpe", withExtension: "model") else {
            // Fall back to tokenizer directory
            if let tokenizerDir = Bundle.main.url(forResource: "tokenizer", withExtension: nil),
               let spmPath = try? FileManager.default.contentsOfDirectory(at: tokenizerDir, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "model" }) {
                tokenizer = try SentencePieceTokenizer(modelPath: spmPath)
                print("XLMRobertaNERService: Loaded SentencePiece tokenizer from tokenizer directory")
                return
            }
            throw AppError.localLLMModelLoadFailed("SentencePiece model not found")
        }

        tokenizer = try SentencePieceTokenizer(modelPath: spmURL)
        print("XLMRobertaNERService: Loaded SentencePiece tokenizer")
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
        var entities: [XLMREntity] = []
        var currentEntity: (text: String, type: String, start: Int, end: Int, confidence: Double)?

        for (tokenIdx, tag) in tags.enumerated() {
            guard tokenIdx < tokenToChar.count else { break }
            let (charStart, charEnd) = tokenToChar[tokenIdx]

            // Skip special tokens
            guard charStart >= 0 && charEnd >= 0 else {
                if let entity = currentEntity {
                    entities.append(createXLMREntity(from: entity, originalText: originalText))
                    currentEntity = nil
                }
                continue
            }

            if tag.hasPrefix("B-") {
                // Start of new entity
                if let entity = currentEntity {
                    entities.append(createXLMREntity(from: entity, originalText: originalText))
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
                        entities.append(createXLMREntity(from: entity, originalText: originalText))
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
                    entities.append(createXLMREntity(from: entity, originalText: originalText))
                    currentEntity = nil
                }
            }
        }

        if let entity = currentEntity {
            entities.append(createXLMREntity(from: entity, originalText: originalText))
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
        let start = entity.start
        let end = min(entity.end, originalText.count)

        let startIdx = originalText.index(originalText.startIndex, offsetBy: start)
        let endIdx = originalText.index(originalText.startIndex, offsetBy: end)
        let extractedText = String(originalText[startIdx..<endIdx])

        return XLMREntity(
            text: extractedText,
            type: mapXLMRType(entity.type),
            label: entity.type,
            start: start,
            end: end,
            confidence: entity.confidence
        )
    }

    /// Map XLM-R entity type to app's EntityType
    private func mapXLMRType(_ xlmrType: String) -> EntityType {
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

    /// Extend person names with following surnames
    private func extendNamesWithSurnames(_ entities: [XLMREntity], in text: String) -> [XLMREntity] {
        var newEntities: [XLMREntity] = []
        let existingNames = Set(entities.map { $0.text.lowercased() })

        for entity in entities {
            guard entity.type == .personOther || entity.type == .personClient || entity.type == .personProvider else {
                continue
            }

            if let surname = findFollowingSurname(after: entity.end, in: text) {
                let fullName = entity.text + " " + surname

                guard !existingNames.contains(fullName.lowercased()) else { continue }

                let extendedEnd = entity.end + 1 + surname.count
                newEntities.append(XLMREntity(
                    text: fullName,
                    type: entity.type,
                    label: entity.label,
                    start: entity.start,
                    end: extendedEnd,
                    confidence: entity.confidence
                ))

                print("XLMRobertaNERService: Extended '\(entity.text)' to '\(fullName)'")
            }
        }

        return newEntities
    }

    /// Find a surname following a name
    private func findFollowingSurname(after endIndex: Int, in text: String) -> String? {
        guard endIndex < text.count else { return nil }

        let startIdx = text.index(text.startIndex, offsetBy: endIndex)
        guard startIdx < text.endIndex, text[startIdx] == " " else { return nil }

        let afterSpace = text.index(after: startIdx)
        guard afterSpace < text.endIndex else { return nil }

        var wordEnd = afterSpace
        while wordEnd < text.endIndex && text[wordEnd].isLetter {
            wordEnd = text.index(after: wordEnd)
        }

        guard wordEnd > afterSpace else { return nil }

        let nextWord = String(text[afterSpace..<wordEnd])

        guard nextWord.count >= 2,
              nextWord.first?.isUppercase == true,
              !isCommonWord(nextWord) else {
            return nil
        }

        return nextWord
    }

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

/// SentencePiece tokenizer for XLM-RoBERTa
/// Note: This is a placeholder. In production, use swift-transformers package
/// or implement native SentencePiece binding.
class SentencePieceTokenizer {

    private let modelPath: URL
    private var vocab: [String: Int] = [:]
    private var reverseVocab: [Int: String] = [:]

    init(modelPath: URL) throws {
        self.modelPath = modelPath
        // TODO: Load actual SentencePiece model
        // For now, fall back to simple whitespace tokenization
        print("SentencePieceTokenizer: Initialized with model at \(modelPath)")
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

        // Simple word-based tokenization (placeholder for SentencePiece)
        // In production, use actual SentencePiece tokenization
        let words = tokenizeWords(text: text)

        for (word, charStart, charEnd) in words {
            if inputIds.count >= maxLength - 1 {
                break
            }

            // For now, use a simple hash-based token ID (placeholder)
            let tokenId = abs(word.hashValue % 250000) + 4  // Avoid special tokens 0-3

            inputIds.append(tokenId)
            attentionMask.append(1)
            tokenToChar.append((charStart, charEnd))
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

    /// Split text into words with character positions
    private func tokenizeWords(text: String) -> [(String, Int, Int)] {
        var words: [(String, Int, Int)] = []
        var currentWord = ""
        var wordStart = 0

        for (index, char) in text.enumerated() {
            if char.isWhitespace || char.isPunctuation {
                if !currentWord.isEmpty {
                    words.append((currentWord, wordStart, index))
                    currentWord = ""
                }
                if char.isPunctuation {
                    words.append((String(char), index, index + 1))
                }
            } else {
                if currentWord.isEmpty {
                    wordStart = index
                }
                currentWord.append(char)
            }
        }

        if !currentWord.isEmpty {
            words.append((currentWord, wordStart, text.count))
        }

        return words
    }
}
