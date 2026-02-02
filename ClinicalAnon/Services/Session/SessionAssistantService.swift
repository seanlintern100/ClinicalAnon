//
//  SessionAssistantService.swift
//  ClinicalAnon
//
//  Purpose: Main service for AI-powered session assistance
//  Organization: 3 Big Things
//

import Foundation

/// Main service for AI-powered session assistance
@MainActor
class SessionAssistantService: ObservableObject {

    // MARK: - Dependencies

    private let bedrockService: BedrockService
    private let preferencesManager: ClinicianPreferencesManager

    // MARK: - Configuration

    private let analysisIntervalChunks = 3  // Analyse every 3 chunks (3 minutes)
    private let maxTranscriptTokens = 8000
    private let tokensPerWord = 1.3
    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 2.0

    // MARK: - Feature Toggles

    var featureToggles: AssistantFeatureToggles = .default

    // MARK: - State

    @Published var state: SessionAssistantState
    @Published var isEnabled: Bool = true

    private var chunksProcessedSinceAnalysis = 0
    private var cumulativeTranscript: String = ""
    private var lastAnalysedChunkIndex: Int = -1

    // MARK: - Initialisation

    init(bedrockService: BedrockService, preferencesManager: ClinicianPreferencesManager) {
        self.bedrockService = bedrockService
        self.preferencesManager = preferencesManager
        self.state = SessionAssistantState()
    }

    // MARK: - Transcript Processing

    /// Called when new transcript segments arrive
    func processNewSegments(_ segments: [TranscriptSegment], for session: LiveSession) async {
        guard isEnabled else { return }
        guard !segments.isEmpty else { return }

        // Format new segments
        let newText = segments.map { "[\($0.speaker.label)] \($0.text)" }.joined(separator: "\n")

        // Append to cumulative (with truncation)
        cumulativeTranscript = truncateTranscript(cumulativeTranscript + "\n" + newText)

        // Track chunks
        chunksProcessedSinceAnalysis += 1

        // Trigger full analysis every 3 chunks
        if chunksProcessedSinceAnalysis >= analysisIntervalChunks {
            await runAnalysis(for: session)
            chunksProcessedSinceAnalysis = 0
        }
    }

    // MARK: - Transcript Truncation

    private func truncateTranscript(_ text: String) -> String {
        let words = text.split(separator: " ")
        let estimatedTokens = Int(Double(words.count) * tokensPerWord)

        if estimatedTokens <= maxTranscriptTokens {
            return text
        }

        // Keep most recent content
        let targetWords = Int(Double(maxTranscriptTokens) / tokensPerWord)
        let truncated = words.suffix(targetWords).joined(separator: " ")
        return "[Earlier transcript truncated for context limits]\n\n" + truncated
    }

    // MARK: - AI Analysis

    /// Run AI analysis with retry logic for transient failures
    func runAnalysis(for session: LiveSession) async {
        guard bedrockService.isConfigured else {
            state.lastAnalysisError = "AI service not configured"
            return
        }

        state.isAnalysing = true
        state.lastAnalysisError = nil

        defer {
            state.isAnalysing = false
            state.lastAnalysisTime = Date()
        }

        // Build prompts
        let systemPrompt = buildSystemPrompt()
        let userMessage = buildUserMessage()

        // Retry loop with exponential backoff
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                // BedrockService uses [ChatMessage]
                let response = try await bedrockService.invoke(
                    systemPrompt: systemPrompt,
                    messages: [ChatMessage.user(userMessage)],
                    model: preferencesManager.selectedModel,
                    maxTokens: 2048
                )

                // Parse and process response
                if let analysisResponse = parseAIResponse(response) {
                    processAnalysisResponse(analysisResponse)
                    return  // Success
                } else {
                    state.lastAnalysisError = "Failed to parse AI response"
                    return  // Don't retry parse failures
                }

            } catch let error as AppError {
                if case .aiThrottled = error {
                    // Throttled - retry with backoff
                    lastError = error
                    let delay = baseRetryDelay * pow(2.0, Double(attempt))
                    print("SessionAssistant: Throttled, retrying in \(delay)s (attempt \(attempt + 1)/\(maxRetries))")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    // Other AppError - don't retry
                    state.lastAnalysisError = error.localizedDescription
                    print("SessionAssistant analysis failed: \(error)")
                    return
                }

            } catch {
                // Other errors - don't retry
                state.lastAnalysisError = error.localizedDescription
                print("SessionAssistant analysis failed: \(error)")
                return
            }
        }

        // All retries exhausted
        state.lastAnalysisError = lastError?.localizedDescription ?? "Analysis failed after \(maxRetries) attempts"
    }

    // MARK: - System Prompt

    private func buildSystemPrompt() -> String {
        return """
        You are a clinical psychology AI assistant monitoring a live therapy session in New Zealand. Your role is to support the clinician by tracking important information and surfacing relevant observations — without interrupting the therapeutic process.

        ## ABOUT THIS TRANSCRIPT

        This transcript was generated by automatic speech recognition (Whisper) from a live session recording.

        Transcription characteristics:
        - **Errors expected**: Misspellings of names, clinical terms, and NZ place names are common
        - **Phonetic variants**: Names may appear differently (Sean/Shawn/Shaun, Māori names may be mangled)
        - **Natural speech**: Filler words (um, uh, like, you know), false starts, self-corrections, and repetition
        - **Speaker labels**: [Clinician] = microphone audio, [Other] = system audio (video call). May occasionally be wrong during overlap
        - **Incomplete sentences**: Normal — follow meaning, not grammar

        Privacy:
        - All identifying information has been redacted: [PERSON_A], [DATE_A], [ORG_A], etc.
        - Never attempt to guess or reveal redacted information
        - Treat redaction codes as consistent identifiers throughout the session
        - The same code always refers to the same entity

        ## GROUNDING RULE — CRITICAL

        Only report information explicitly stated in the transcript.
        - Do NOT infer relationships not stated
        - Do NOT assume context not provided
        - Do NOT fill in redacted information
        - If uncertain, note uncertainty in rationale

        ## YOUR TASKS

        Analyse the NEW transcript content and return structured observations. You will receive the current Parking Lot state — DO NOT re-report items already captured.

        ### 1. DETAILS (→ Parking Lot)
        Extract factual information: people mentioned, relationships, ages, professions, durations, key facts.
        For each: content, category (person|relationship|fact|profession|history), source_quote, timestamp

        ### 2. QUOTES (→ Parking Lot)
        Capture significant language: metaphors, emotionally charged statements, repeated phrases, self-descriptions.
        For each: text, timestamp, significance

        ### 3. AGENDA (→ Parking Lot)
        Track topics agreed to discuss. Status: not_started, partial, covered.
        For each: topic, agreed_at, status, evidence, time_range

        ### 4. THEMES (→ Parking Lot / Live Feed)
        Identify recurring patterns. Mark explored (true/false) based on clinician acknowledgment.
        For each: name, mentions (timestamp + context), explored

        ### 5. FLAGS (→ Live Feed)
        🔴 SAFETY: Risk language, crisis indicators — always flag even if uncertain
        🟠 IMPORTANT: Significant revelations, contradictions, emotional moments
        🟡 NOTE: Observations, patterns, areas to explore
        For each: severity, content, timestamp, rationale

        ### 6. SUGGESTIONS (→ Live Feed)
        Offer therapeutic ideas when contextually appropriate.
        For each: content, rationale, timestamp

        ## OUTPUT FORMAT

        Respond with valid JSON only. No preamble, no markdown.
        Include all six keys, even if empty arrays.

        ```json
        {
          "details": [],
          "quotes": [],
          "agenda": [],
          "themes": [],
          "flags": [],
          "suggestions": [],
          "analysis_note": "Optional note"
        }
        ```

        ## CRITICAL GUIDELINES

        1. Safety first — Always flag risk language, even if uncertain
        2. No duplicates — Check Parking Lot before reporting
        3. Quality over quantity — Don't flood the clinician
        4. Use their language — Preserve client's exact words in quotes
        5. Stay grounded — Only report what's explicitly in the transcript
        """
    }

    /// Build user message using cumulative transcript
    private func buildUserMessage() -> String {
        let preferences = preferencesManager.preferences

        // Format starred/dismissed items
        let starredText = state.starredItems.isEmpty ? "None yet" :
            state.starredItems.map { "• \($0.content)" }.joined(separator: "\n")

        let dismissedText = state.dismissedItems.isEmpty ? "None yet" :
            state.dismissedItems.map { "• \($0.content)" }.joined(separator: "\n")

        return """
        ## CLINICIAN PREFERENCES

        \(preferences.formattedForPrompt)

        ## THIS SESSION FEEDBACK

        Starred (found useful):
        \(starredText)

        Dismissed (not useful):
        \(dismissedText)

        ## CURRENT PARKING LOT STATE

        \(state.parkingLotJSON)

        ## TRANSCRIPT TO ANALYSE

        \(cumulativeTranscript)

        ---

        Analyse this transcript and return structured JSON with your observations.
        Only report NEW information not already in the Parking Lot.
        """
    }

    // MARK: - Response Parsing

    private func parseAIResponse(_ response: String) -> AIAnalysisResponse? {
        // Clean response (remove markdown code blocks if present)
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            print("SessionAssistant: Failed to convert response to data")
            return nil
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(AIAnalysisResponse.self, from: data)
        } catch {
            print("SessionAssistant: JSON parsing failed: \(error)")
            print("SessionAssistant: Raw response: \(response.prefix(500))...")
            return nil
        }
    }

    // MARK: - Response Processing

    private func processAnalysisResponse(_ response: AIAnalysisResponse) {
        // Process details
        if featureToggles.detailsEnabled {
            for aiDetail in response.details {
                processDetail(aiDetail)
            }
        }

        // Process quotes
        if featureToggles.quotesEnabled {
            for aiQuote in response.quotes {
                processQuote(aiQuote)
            }
        }

        // Process agenda items
        if featureToggles.agendaEnabled {
            for aiAgenda in response.agenda {
                processAgendaItem(aiAgenda)
            }
        }

        // Process themes
        if featureToggles.themesEnabled {
            for aiTheme in response.themes {
                processTheme(aiTheme)
            }
        }

        // Process flags
        if featureToggles.flagsEnabled {
            for aiFlag in response.flags {
                processFlag(aiFlag)
            }
        }

        // Process suggestions
        if featureToggles.suggestionsEnabled {
            for aiSuggestion in response.suggestions {
                processSuggestion(aiSuggestion)
            }
        }
    }

    private func processDetail(_ aiDetail: AIDetail) {
        // Check for duplicate
        let isDuplicate = state.details.contains {
            $0.content.lowercased() == aiDetail.content.lowercased()
        }
        guard !isDuplicate else { return }

        let category = DetailCategory(rawValue: aiDetail.category) ?? .fact

        let detail = ClientDetail(
            content: aiDetail.content,
            category: category,
            sourceQuote: aiDetail.sourceQuote,
            timestamp: aiDetail.timestamp
        )

        state.details.append(detail)

        // Add to feed
        let feedItem = FeedItem(
            itemType: .detail,
            content: detail.content,
            rationale: detail.sourceQuote,
            timestamp: detail.timestamp,
            detailCategory: category
        )
        state.feedItems.append(feedItem)
    }

    private func processQuote(_ aiQuote: AIQuote) {
        // Check for duplicate (fuzzy match)
        let isDuplicate = state.quotes.contains {
            $0.text.lowercased().contains(aiQuote.text.lowercased()) ||
            aiQuote.text.lowercased().contains($0.text.lowercased())
        }
        guard !isDuplicate else { return }

        let quote = Quote(
            text: aiQuote.text,
            timestamp: aiQuote.timestamp,
            significance: aiQuote.significance
        )

        state.quotes.append(quote)

        // Add to feed
        let feedItem = FeedItem(
            itemType: .quote,
            content: "\u{201C}\(quote.text)\u{201D}",
            rationale: quote.significance,
            timestamp: quote.timestamp
        )
        state.feedItems.append(feedItem)
    }

    private func processAgendaItem(_ aiAgenda: AIAgendaItem) {
        let status = AgendaStatus(rawValue: aiAgenda.status) ?? .notStarted
        let timeRange = aiAgenda.timeRange.map { TimeRange(start: $0.start, end: $0.end) }

        // Check if existing agenda item (match by topic)
        if let index = state.agendaItems.firstIndex(where: {
            $0.topic.lowercased() == aiAgenda.topic.lowercased()
        }) {
            // Update existing
            let oldStatus = state.agendaItems[index].status
            state.agendaItems[index].status = status
            state.agendaItems[index].evidence = aiAgenda.evidence
            state.agendaItems[index].timeRange = timeRange

            // Add feed item if status changed
            if oldStatus != status {
                let feedItem = FeedItem(
                    itemType: .agendaUpdate,
                    content: "\(aiAgenda.topic): \(status.displayName)",
                    rationale: aiAgenda.evidence ?? "Status updated",
                    timestamp: aiAgenda.agreedAt,
                    agendaTopic: aiAgenda.topic,
                    agendaStatus: status
                )
                state.feedItems.append(feedItem)
            }
        } else {
            // New agenda item
            let item = AgendaItem(
                topic: aiAgenda.topic,
                agreedAt: aiAgenda.agreedAt,
                status: status,
                evidence: aiAgenda.evidence,
                timeRange: timeRange
            )
            state.agendaItems.append(item)

            // Add to feed
            let feedItem = FeedItem(
                itemType: .agendaUpdate,
                content: "New agenda: \(item.topic)",
                rationale: "Agreed to discuss",
                timestamp: item.agreedAt,
                agendaTopic: item.topic,
                agendaStatus: status
            )
            state.feedItems.append(feedItem)
        }
    }

    private func processTheme(_ aiTheme: AITheme) {
        let newMentions = aiTheme.mentions.map {
            ThemeMention(timestamp: $0.timestamp, context: $0.context)
        }

        // Check if existing theme
        if let index = state.themes.firstIndex(where: {
            $0.name.lowercased() == aiTheme.name.lowercased()
        }) {
            // Add new mentions to existing
            state.themes[index].mentions.append(contentsOf: newMentions)
            state.themes[index].explored = aiTheme.explored || state.themes[index].manuallyMarkedExplored
        } else {
            // New theme
            let theme = Theme(
                name: aiTheme.name,
                mentions: newMentions,
                explored: aiTheme.explored
            )
            state.themes.append(theme)

            // Add to feed if unexplored
            if !theme.explored {
                let feedItem = FeedItem(
                    itemType: .themeAlert,
                    content: "Theme: \(theme.name) (\(theme.mentionCount) mentions)",
                    rationale: "Not yet explored — consider addressing",
                    timestamp: newMentions.first?.timestamp ?? 0,
                    themeName: theme.name
                )
                state.feedItems.append(feedItem)
            }
        }
    }

    private func processFlag(_ aiFlag: AIFlag) {
        let severity = FlagSeverity(rawValue: aiFlag.severity) ?? .note

        let feedItem = FeedItem(
            itemType: .flag,
            content: aiFlag.content,
            rationale: aiFlag.rationale,
            timestamp: aiFlag.timestamp,
            flagSeverity: severity
        )
        state.feedItems.append(feedItem)
    }

    private func processSuggestion(_ aiSuggestion: AISuggestion) {
        let feedItem = FeedItem(
            itemType: .suggestion,
            content: aiSuggestion.content,
            rationale: aiSuggestion.rationale,
            timestamp: aiSuggestion.timestamp
        )
        state.feedItems.append(feedItem)
    }

    // MARK: - Clinician Actions

    func starItem(_ item: FeedItem) {
        guard let index = state.feedItems.firstIndex(where: { $0.id == item.id }) else { return }
        state.feedItems[index].status = .starred

        // Move to parking lot based on type (if not already there)
        switch item.itemType {
        case .detail:
            if let category = item.detailCategory {
                let detail = ClientDetail(
                    content: item.content,
                    category: category,
                    sourceQuote: item.rationale,
                    timestamp: item.timestamp,
                    isManuallyAdded: true
                )
                // Only add if not duplicate
                if !state.details.contains(where: { $0.content.lowercased() == detail.content.lowercased() }) {
                    state.details.append(detail)
                }
            }

        case .quote:
            let text = item.content.replacingOccurrences(of: "\u{201C}", with: "").replacingOccurrences(of: "\u{201D}", with: "")
            let quote = Quote(
                text: text,
                timestamp: item.timestamp,
                significance: item.rationale,
                isManuallyAdded: true
            )
            // Only add if not duplicate
            if !state.quotes.contains(where: { $0.text.lowercased() == quote.text.lowercased() }) {
                state.quotes.append(quote)
            }

        default:
            break // Flags and suggestions don't move to parking lot
        }
    }

    func dismissItem(_ item: FeedItem) {
        guard let index = state.feedItems.firstIndex(where: { $0.id == item.id }) else { return }
        state.feedItems[index].status = .dismissed
    }

    // MARK: - Manual Parking Lot Actions

    func addManualDetail(_ content: String, category: DetailCategory) {
        let detail = ClientDetail(
            content: content,
            category: category,
            sourceQuote: "Manually added",
            timestamp: 0,
            isManuallyAdded: true
        )
        state.details.append(detail)
    }

    func addManualQuote(_ text: String, significance: String) {
        let quote = Quote(
            text: text,
            timestamp: 0,
            significance: significance,
            isManuallyAdded: true
        )
        state.quotes.append(quote)
    }

    func addManualAgendaItem(_ topic: String) {
        let item = AgendaItem(
            topic: topic,
            agreedAt: 0,
            status: .notStarted,
            isManuallyAdded: true
        )
        state.agendaItems.append(item)
    }

    func updateAgendaStatus(_ item: AgendaItem, to status: AgendaStatus) {
        guard let index = state.agendaItems.firstIndex(where: { $0.id == item.id }) else { return }
        state.agendaItems[index].status = status
    }

    func markThemeExplored(_ theme: Theme) {
        guard let index = state.themes.firstIndex(where: { $0.id == theme.id }) else { return }
        state.themes[index].manuallyMarkedExplored = true
    }

    func deleteDetail(_ detail: ClientDetail) {
        state.details.removeAll { $0.id == detail.id }
    }

    func deleteQuote(_ quote: Quote) {
        state.quotes.removeAll { $0.id == quote.id }
    }

    func deleteAgendaItem(_ item: AgendaItem) {
        state.agendaItems.removeAll { $0.id == item.id }
    }

    // MARK: - Session Lifecycle

    func reset() {
        state.reset()
        cumulativeTranscript = ""
        chunksProcessedSinceAnalysis = 0
        lastAnalysedChunkIndex = -1
    }

    func endSession() async {
        // Update preferences based on session feedback
        await preferencesManager.updateFromSession(
            starred: state.starredItems,
            dismissed: state.dismissedItems
        )
    }
}
