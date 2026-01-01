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

        // Tokenize the input
        let (inputIds, attentionMask, tokenToChar) = tokenize(text: text)

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
        var rawEntities = aggregateBIOTags(tags: tags, inputIds: inputIds, tokenToChar: tokenToChar, originalText: text)

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
                // Add punctuation as separate token
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

        // Don't forget the last word
        if !currentWord.isEmpty {
            words.append((currentWord, wordStart, text.count))
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
    /// Example: "Ronald" + "Praneer" (capitalized gap) + "Nath" → merged into "Ronald Praneer Nath"
    private func bridgeNameGaps(_ entities: [BERTEntity], in text: String) -> [BERTEntity] {
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

                // Extract gap text
                let gapStartIdx = text.index(text.startIndex, offsetBy: gapStart)
                let gapEndIdx = text.index(text.startIndex, offsetBy: gapEnd)
                let gapText = String(text[gapStartIdx..<gapEndIdx]).trimmingCharacters(in: .whitespaces)

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
                    let startIdx = text.index(text.startIndex, offsetBy: mergedStart)
                    let endIdx = text.index(text.startIndex, offsetBy: min(mergedEnd, text.count))
                    let mergedText = String(text[startIdx..<endIdx])

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
    private func createBERTEntity(
        from entity: (text: String, type: String, start: Int, end: Int, confidence: Double),
        originalText: String
    ) -> BERTEntity {
        let start = entity.start
        let end = min(entity.end, originalText.count)

        // Extract actual text from original
        let startIdx = originalText.index(originalText.startIndex, offsetBy: start)
        let endIdx = originalText.index(originalText.startIndex, offsetBy: end)
        let extractedText = String(originalText[startIdx..<endIdx])

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
    private func findFollowingSurname(after endIndex: Int, in text: String) -> String? {
        guard endIndex < text.count else { return nil }

        let startIdx = text.index(text.startIndex, offsetBy: endIndex)

        // Check if followed by a space
        guard startIdx < text.endIndex, text[startIdx] == " " else { return nil }

        // Get the next word
        let afterSpace = text.index(after: startIdx)
        guard afterSpace < text.endIndex else { return nil }

        // Find the end of the next word
        var wordEnd = afterSpace
        while wordEnd < text.endIndex && text[wordEnd].isLetter {
            wordEnd = text.index(after: wordEnd)
        }

        guard wordEnd > afterSpace else { return nil }

        let nextWord = String(text[afterSpace..<wordEnd])

        // Check if it looks like a surname:
        // - Starts with uppercase
        // - At least 2 characters
        // - Not a common word
        guard nextWord.count >= 2,
              nextWord.first?.isUppercase == true,
              !isCommonWord(nextWord) else {
            return nil
        }

        return nextWord
    }

    /// Extract first name components from multi-word person names
    /// When "Hannes Venter" is detected, also find standalone "Hannes"
    private func extractNameComponents(_ entities: [BERTEntity], in text: String) -> [BERTEntity] {
        var newEntities: [BERTEntity] = []
        let existingTexts = Set(entities.map { $0.text.lowercased() })

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
            guard firstName.count >= 3, !isCommonWord(firstName) else { continue }

            // Find standalone occurrences of first name
            var searchStart = text.startIndex
            var foundPositions: [(start: Int, end: Int)] = []

            while let range = text.range(of: firstName, options: .caseInsensitive, range: searchStart..<text.endIndex) {
                let start = text.distance(from: text.startIndex, to: range.lowerBound)
                let end = text.distance(from: text.startIndex, to: range.upperBound)

                // Check this isn't part of the full name (already covered)
                let isPartOfFullName = (start >= entity.start && end <= entity.end)

                if !isPartOfFullName {
                    foundPositions.append((start: start, end: end))
                }
                searchStart = range.upperBound
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

    /// Check if a word is a common English word (not a name)
    private func isCommonWord(_ word: String) -> Bool {
        let commonWords: Set<String> = [
            "the", "and", "for", "are", "but", "not", "you", "all", "can", "had",
            "her", "was", "one", "our", "out", "has", "his", "him", "how", "its",
            "may", "new", "now", "old", "see", "way", "who", "did", "get", "has",
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

    /// Detect alphanumeric identifiers (codes, reference numbers, etc.)
    /// Matches strings with both letters AND numbers like "S7798120001" or "VEND-G0M136"
    private func detectIdentifiers(in text: String) -> [BERTEntity] {
        var identifiers: [BERTEntity] = []

        // Pattern: word boundaries, alphanumeric with optional hyphens, min 4 chars
        // Must contain at least one letter AND one digit
        let pattern = #"\b[A-Za-z0-9][A-Za-z0-9\-]{3,}[A-Za-z0-9]\b"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return identifiers
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        for match in matches {
            guard let swiftRange = Range(match.range, in: text) else { continue }
            let matchText = String(text[swiftRange])

            // Must contain both letters and digits
            let hasLetter = matchText.contains(where: { $0.isLetter })
            let hasDigit = matchText.contains(where: { $0.isNumber })
            guard hasLetter && hasDigit else { continue }

            // Skip common patterns that aren't identifiers
            if isCommonAbbreviation(matchText) { continue }

            let start = text.distance(from: text.startIndex, to: swiftRange.lowerBound)
            let end = text.distance(from: text.startIndex, to: swiftRange.upperBound)

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

    /// Check if a string is a common abbreviation (not an identifier)
    private func isCommonAbbreviation(_ text: String) -> Bool {
        let commonPatterns: Set<String> = [
            // Ordinals
            "1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th", "10th",
            "11th", "12th", "13th", "14th", "15th", "16th", "17th", "18th", "19th", "20th",
            "21st", "22nd", "23rd", "24th", "25th", "26th", "27th", "28th", "29th", "30th", "31st",
            // Common abbreviations
            "covid19", "covid-19", "h1n1", "mp3", "mp4", "a4", "b12", "c19"
        ]
        return commonPatterns.contains(text.lowercased())
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
