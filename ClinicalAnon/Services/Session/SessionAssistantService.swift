//
//  SessionAssistantService.swift
//  ClinicalAnon
//
//  Purpose: Main service for AI-powered session assistance
//  Organization: 3 Big Things
//

import Foundation
import Combine

/// Main service for AI-powered session assistance
@MainActor
class SessionAssistantService: ObservableObject {

    // MARK: - Dependencies

    private let bedrockService: BedrockService
    private let preferencesManager: ClinicianPreferencesManager
    private var cancellables = Set<AnyCancellable>()

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
    private var lastAnalysedChunkIndex: Int = -1
    private weak var currentSession: LiveSession?

    // MARK: - Initialisation

    init(bedrockService: BedrockService, preferencesManager: ClinicianPreferencesManager) {
        self.bedrockService = bedrockService
        self.preferencesManager = preferencesManager
        self.state = SessionAssistantState()

        // Forward state changes to service (nested ObservableObject fix)
        state.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    // MARK: - Transcript Processing

    /// Called when new transcript segments arrive (after LiveRedactor has processed them)
    func processNewSegments(_ segments: [TranscriptSegment], for session: LiveSession) async {
        guard isEnabled else {
            print("SessionAssistant: Skipping - assistant disabled")
            return
        }
        guard !segments.isEmpty else { return }

        // Track chunks (transcript is obtained from session.redactedTranscript when needed)
        chunksProcessedSinceAnalysis += 1
        print("SessionAssistant: Received \(segments.count) segments. Chunks since analysis: \(chunksProcessedSinceAnalysis)/\(analysisIntervalChunks)")

        // Trigger full analysis every 3 chunks
        if chunksProcessedSinceAnalysis >= analysisIntervalChunks {
            print("SessionAssistant: Triggering analysis (reached \(analysisIntervalChunks) chunks)")
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

    // MARK: - De-redaction

    /// De-redact text using current session's entity mapping
    /// Converts codes like [PERSON_A] back to original names for display
    private func deRedact(_ text: String) -> String {
        guard let session = currentSession else {
            print("SessionAssistant: [DE-REDACT] No session - returning unchanged: \(text.prefix(100))")
            return text
        }

        let reidentifier = TextReidentifier()
        let result = reidentifier.restore(text: text, using: session.entityMapping, normalizeDates: false)

        // Log if text changed (redaction codes were replaced)
        if result != text {
            print("SessionAssistant: [DE-REDACT] Transformed:")
            print("  Input:  \(text.prefix(150))")
            print("  Output: \(result.prefix(150))")
        }

        return result
    }

    /// Log entity mapping state for debugging
    private func logEntityMappingState(for session: LiveSession) {
        let mapping = session.entityMapping
        print("SessionAssistant: [ENTITY-MAPPING] State:")
        print("  Total mappings: \(mapping.totalMappings)")

        // Show sample mappings (first 5)
        let samples = Array(mapping.allMappings.prefix(5))
        for entry in samples {
            print("    \(entry.replacement) → \"\(entry.original)\"")
        }

        if mapping.totalMappings > 5 {
            print("    ... and \(mapping.totalMappings - 5) more")
        }

        // Check if mapping is empty
        if mapping.totalMappings == 0 {
            print("  ⚠️ WARNING: EntityMapping is EMPTY - no de-redaction will occur!")
        }
    }

    // MARK: - AI Analysis

    /// Run AI analysis with retry logic for transient failures
    func runAnalysis(for session: LiveSession) async {
        // Store session for de-redaction of AI responses
        currentSession = session

        print("SessionAssistant: [START] Running analysis...")

        // Log detected entities
        print("SessionAssistant: [ENTITIES] Detected: \(session.detectedEntities.count) entities")
        for entity in session.detectedEntities.prefix(10) {
            print("  \(entity.replacementCode) ← \"\(entity.originalText)\" (\(entity.type))")
        }
        if session.detectedEntities.count > 10 {
            print("  ... and \(session.detectedEntities.count - 10) more")
        }

        // Log entity mapping state
        logEntityMappingState(for: session)

        // Get redacted transcript
        let redactedTranscript = truncateTranscript(session.redactedTranscript)

        // Log what we're sending (check for redaction codes)
        print("SessionAssistant: [SENDING] Transcript length: \(redactedTranscript.count) chars")
        print("SessionAssistant: [SENDING] Transcript preview (first 800 chars):")
        print("---TRANSCRIPT START---")
        print(redactedTranscript.prefix(800))
        print("---TRANSCRIPT END---")

        // Check if redaction codes are present
        let hasPersonCodes = redactedTranscript.contains("[PERSON_")
        let hasDateCodes = redactedTranscript.contains("[DATE_")
        let hasOrgCodes = redactedTranscript.contains("[ORG_")
        let hasLocationCodes = redactedTranscript.contains("[LOCATION_")
        print("SessionAssistant: [REDACTION CHECK] Contains codes: PERSON=\(hasPersonCodes), DATE=\(hasDateCodes), ORG=\(hasOrgCodes), LOCATION=\(hasLocationCodes)")

        // Also check for raw transcript to compare
        let rawPreview = session.rawTranscript.prefix(300)
        print("SessionAssistant: [RAW COMPARE] Raw transcript preview (first 300):")
        print(rawPreview)

        guard bedrockService.isConfigured else {
            state.lastAnalysisError = "AI service not configured"
            print("SessionAssistant: [ERROR] Bedrock not configured")
            return
        }

        state.isAnalysing = true
        state.lastAnalysisError = nil

        defer {
            state.isAnalysing = false
            state.lastAnalysisTime = Date()
            print("SessionAssistant: [END] Analysis complete")
        }

        // Build prompts
        let systemPrompt = buildSystemPrompt()
        let userMessage = buildUserMessage(transcript: redactedTranscript)
        print("SessionAssistant: Sending to AI (model: \(preferencesManager.selectedModel))...")

        // Retry loop with exponential backoff
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                // BedrockService uses [ChatMessage]
                let response = try await bedrockService.invoke(
                    systemPrompt: systemPrompt,
                    messages: [ChatMessage.user(userMessage)],
                    model: preferencesManager.selectedModel,
                    maxTokens: 4096
                )

                print("SessionAssistant: [RECEIVED] Response length: \(response.count) chars")

                // Check if AI response contains redaction codes (it should)
                let responseHasPersonCodes = response.contains("[PERSON_")
                let responseHasDateCodes = response.contains("[DATE_")
                print("SessionAssistant: [AI RESPONSE] Contains codes: PERSON=\(responseHasPersonCodes), DATE=\(responseHasDateCodes)")
                print("SessionAssistant: [AI RESPONSE] Preview (first 500):")
                print(String(response.prefix(500)))

                // Parse and process response
                if let analysisResponse = parseAIResponse(response) {
                    print("SessionAssistant: [PARSED] details=\(analysisResponse.details.count), quotes=\(analysisResponse.quotes.count), agenda=\(analysisResponse.agenda.count), themes=\(analysisResponse.themes.count), flags=\(analysisResponse.flags.count), suggestions=\(analysisResponse.suggestions.count)")
                    processAnalysisResponse(analysisResponse)
                    print("SessionAssistant: [PROCESSED] State now has: details=\(state.details.count), quotes=\(state.quotes.count), agenda=\(state.agendaItems.count), themes=\(state.themes.count)")
                    return  // Success
                } else {
                    state.lastAnalysisError = "Failed to parse AI response"
                    print("SessionAssistant: [ERROR] Failed to parse response")
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

        Analyse the transcript and return structured observations.

        **IMPORTANT: All timestamp fields must be NUMBERS (seconds from session start), e.g. 45, 120, 180. NOT strings like "early" or "3:00".**

        ### 1. DETAILS (→ Parking Lot) — Additive
        Extract NEW factual information: people mentioned, relationships, ages, professions, durations, key facts.
        For each: content, category (person|relationship|fact|profession|history), source_quote, timestamp (number in seconds)

        ### 2. QUOTES (→ Parking Lot) — Additive
        Capture NEW significant language: metaphors, emotionally charged statements, repeated phrases, self-descriptions.
        For each: text, timestamp (number in seconds), significance

        ### 3. AGENDA (→ Parking Lot) — COMPLETE STATE MANAGEMENT

        **CRITICAL: Return the COMPLETE agenda list every analysis, not just new items.**

        You OWN this list. Each analysis:
        - Include ALL items from current state (preserve their stable_id)
        - Update status, evidence as discussion progresses
        - Add new items with new stable_id values
        - Create sub-items using parent_id
        - Add progress_note when meaningful progress occurs

        **Manual items:** Items with stable_id starting with "manual_" MUST be preserved.

        **Stable IDs:** Use descriptive identifiers: "work_stress", "relationship_mother", "sleep_issues"

        For each item:
        - stable_id (required): Persistent identifier
        - topic: Clear description
        - agreed_at: When agreed (seconds)
        - status: not_started | partial | covered
        - evidence: Supporting quote/summary
        - parent_id (optional): For sub-items (references parent's stable_id)
        - progress_note (optional): New observation this analysis

        ### 4. THEMES (→ Parking Lot / Live Feed) — COMPLETE STATE MANAGEMENT

        **CRITICAL: Return the COMPLETE themes list every analysis.**

        You OWN this list. Each analysis:
        - Include ALL themes (preserve stable_id)
        - Add new mentions to existing themes
        - Update explored status
        - Create new themes with new stable_id
        - Link related themes using related_theme_ids

        **Manual items:** Themes with stable_id starting with "manual_" MUST be preserved.

        For each theme:
        - stable_id (required): Persistent identifier (e.g., "theme_anxiety", "theme_control")
        - name: Clear theme name
        - description (optional): Brief explanation
        - mentions: [{timestamp, context}]
        - explored: true if acknowledged
        - related_theme_ids (optional): Linked theme stable_ids

        ### 5. FLAGS (→ Live Feed) — Additive
        🔴 SAFETY: Risk language, crisis indicators — always flag even if uncertain
        🟠 IMPORTANT: Significant revelations, contradictions, emotional moments
        🟡 NOTE: Observations, patterns, areas to explore
        For each: severity, content, timestamp (number in seconds), rationale

        ### 6. SUGGESTIONS (→ Live Feed) — Additive
        Offer therapeutic ideas when contextually appropriate.
        For each: content, rationale, timestamp (number in seconds)

        ## OUTPUT FORMAT

        Respond with valid JSON only. No preamble, no markdown code blocks.
        Include all six keys, even if empty arrays.
        All timestamps MUST be numbers (seconds), not strings.

        Example structure:
        {
          "details": [{"content": "Client has a brother", "category": "relationship", "source_quote": "my brother and I", "timestamp": 45}],
          "quotes": [{"text": "I feel like I'm drowning", "timestamp": 120, "significance": "Metaphor for overwhelm"}],
          "agenda": [
            {"stable_id": "work_stress", "topic": "Work stress and burnout", "agreed_at": 30, "status": "partial", "evidence": "discussed workload"},
            {"stable_id": "work_manager", "topic": "Conflict with manager", "parent_id": "work_stress", "agreed_at": 150, "status": "not_started"}
          ],
          "themes": [
            {"stable_id": "theme_perfectionism", "name": "Perfectionism", "description": "Pattern of self-criticism", "mentions": [{"timestamp": 45, "context": "mentioned being hard on self"}], "explored": false}
          ],
          "flags": [{"severity": "note", "content": "Client seemed hesitant", "timestamp": 90, "rationale": "Long pause before answering"}],
          "suggestions": [],
          "analysis_note": "Optional note"
        }

        ## CRITICAL GUIDELINES

        1. Safety first — Always flag risk language, even if uncertain
        2. Agenda/Themes — Return COMPLETE updated lists, not just new items
        3. Quality over quantity — Don't flood the clinician
        4. Use their language — Preserve client's exact words in quotes
        5. Stay grounded — Only report what's explicitly in the transcript
        """
    }

    /// Build user message using redacted transcript
    private func buildUserMessage(transcript: String) -> String {
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

        \(transcript)

        ---

        Analyse this transcript and return structured JSON.
        - Details/Quotes: Only report NEW items not already in Parking Lot
        - Agenda/Themes: Return COMPLETE updated lists (you own these - update existing, add new)
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
        // Process details (additive)
        if featureToggles.detailsEnabled {
            for aiDetail in response.details {
                processDetail(aiDetail)
            }
        }

        // Process quotes (additive)
        if featureToggles.quotesEnabled {
            for aiQuote in response.quotes {
                processQuote(aiQuote)
            }
        }

        // Reconcile agenda (AI owns the complete list)
        if featureToggles.agendaEnabled {
            reconcileAgenda(response.agenda)
        }

        // Reconcile themes (AI owns the complete list)
        if featureToggles.themesEnabled {
            reconcileThemes(response.themes)
        }

        // Process flags (additive)
        if featureToggles.flagsEnabled {
            for aiFlag in response.flags {
                processFlag(aiFlag)
            }
        }

        // Process suggestions (additive)
        if featureToggles.suggestionsEnabled {
            for aiSuggestion in response.suggestions {
                processSuggestion(aiSuggestion)
            }
        }
    }

    private func processDetail(_ aiDetail: AIDetail) {
        // De-redact AI response text
        let content = deRedact(aiDetail.content)
        let sourceQuote = deRedact(aiDetail.sourceQuote)

        // Check for duplicate using de-redacted content
        let isDuplicate = state.details.contains {
            $0.content.lowercased() == content.lowercased()
        }
        guard !isDuplicate else { return }

        let category = DetailCategory(rawValue: aiDetail.category) ?? .fact

        let detail = ClientDetail(
            content: content,
            category: category,
            sourceQuote: sourceQuote,
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
        // De-redact AI response text
        let text = deRedact(aiQuote.text)
        let significance = deRedact(aiQuote.significance)

        // Check for duplicate (fuzzy match) using de-redacted text
        let isDuplicate = state.quotes.contains {
            $0.text.lowercased().contains(text.lowercased()) ||
            text.lowercased().contains($0.text.lowercased())
        }
        guard !isDuplicate else { return }

        let quote = Quote(
            text: text,
            timestamp: aiQuote.timestamp,
            significance: significance
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

    // MARK: - Agenda Reconciliation

    /// Reconcile AI's complete agenda with local state
    /// AI owns the list - local state is updated to match, preserving manual items
    private func reconcileAgenda(_ aiAgenda: [AIAgendaItem]) {
        // Build lookup of existing items by stableId
        var existingByStableId: [String: AgendaItem] = [:]
        for item in state.agendaItems {
            existingByStableId[item.stableId] = item
        }

        // Track which items AI returned
        var returnedStableIds: Set<String> = []

        // Track changes for feed items
        var newItems: [AgendaItem] = []
        var statusChanges: [(item: AgendaItem, oldStatus: AgendaStatus, newStatus: AgendaStatus)] = []

        // Process AI items
        var reconciled: [AgendaItem] = []

        for aiItem in aiAgenda {
            let topic = deRedact(aiItem.topic)
            let evidence = aiItem.evidence.map { deRedact($0) }
            let status = AgendaStatus(rawValue: aiItem.status) ?? .notStarted
            let timeRange = aiItem.timeRange.map { TimeRange(start: $0.start, end: $0.end) }

            returnedStableIds.insert(aiItem.stableId)

            if let existing = existingByStableId[aiItem.stableId] {
                // Update existing item
                var updated = existing
                updated.topic = topic
                updated.status = status
                updated.evidence = evidence
                updated.timeRange = timeRange
                updated.parentId = aiItem.parentId

                // Track status change
                if existing.status != status {
                    statusChanges.append((item: updated, oldStatus: existing.status, newStatus: status))
                }

                // Add progress note if provided
                if let progressNote = aiItem.progressNote, !progressNote.isEmpty {
                    let note = ProgressNote(
                        timestamp: aiItem.agreedAt,
                        note: deRedact(progressNote),
                        statusAtTime: status
                    )
                    updated.progressNotes.append(note)
                }

                reconciled.append(updated)

            } else {
                // New item
                let newItem = AgendaItem(
                    stableId: aiItem.stableId,
                    topic: topic,
                    agreedAt: aiItem.agreedAt,
                    status: status,
                    evidence: evidence,
                    timeRange: timeRange,
                    isManuallyAdded: false,
                    parentId: aiItem.parentId
                )
                reconciled.append(newItem)
                newItems.append(newItem)
            }
        }

        // Preserve manual items that AI didn't return
        for (stableId, existing) in existingByStableId {
            if !returnedStableIds.contains(stableId) && existing.isManuallyAdded {
                reconciled.append(existing)
                print("SessionAssistant: Preserved manual agenda item: \(existing.topic)")
            }
        }

        // Sort: top-level items by agreedAt, then sub-items grouped under parents
        reconciled.sort { a, b in
            if a.isTopLevel && !b.isTopLevel { return true }
            if !a.isTopLevel && b.isTopLevel { return false }
            return a.agreedAt < b.agreedAt
        }

        // Update state
        state.agendaItems = reconciled

        // Generate feed items
        generateAgendaFeedItems(new: newItems, statusChanges: statusChanges)
    }

    /// Generate feed items for agenda changes
    private func generateAgendaFeedItems(
        new: [AgendaItem],
        statusChanges: [(item: AgendaItem, oldStatus: AgendaStatus, newStatus: AgendaStatus)]
    ) {
        // New items
        for item in new {
            let isSubItem = item.parentId != nil
            let content = isSubItem
                ? "Sub-topic: \(item.topic)"
                : "New agenda: \(item.topic)"

            let feedItem = FeedItem(
                itemType: .agendaUpdate,
                content: content,
                rationale: item.evidence ?? "Agreed to discuss",
                timestamp: item.agreedAt,
                agendaTopic: item.topic,
                agendaStatus: item.status
            )
            state.feedItems.append(feedItem)
        }

        // Status changes (only significant ones)
        for (item, oldStatus, newStatus) in statusChanges {
            // Only notify on forward progress
            let isSignificant = (oldStatus == .notStarted && newStatus == .partial) ||
                               (oldStatus == .partial && newStatus == .covered) ||
                               (oldStatus == .notStarted && newStatus == .covered)

            guard isSignificant else { continue }

            let feedItem = FeedItem(
                itemType: .agendaUpdate,
                content: "\(item.topic): \(newStatus.displayName)",
                rationale: item.evidence ?? "Status updated",
                timestamp: item.timeRange?.end ?? item.agreedAt,
                agendaTopic: item.topic,
                agendaStatus: newStatus
            )
            state.feedItems.append(feedItem)
        }
    }

    // MARK: - Theme Reconciliation

    /// Reconcile AI's complete theme state with local state
    private func reconcileThemes(_ aiThemes: [AITheme]) {
        var existingByStableId: [String: Theme] = [:]
        for theme in state.themes {
            existingByStableId[theme.stableId] = theme
        }

        var returnedStableIds: Set<String> = []
        var newThemes: [Theme] = []

        var reconciled: [Theme] = []

        for aiTheme in aiThemes {
            let name = deRedact(aiTheme.name)
            let description = aiTheme.description.map { deRedact($0) }
            let newMentions = aiTheme.mentions.map {
                ThemeMention(timestamp: $0.timestamp, context: deRedact($0.context))
            }

            returnedStableIds.insert(aiTheme.stableId)

            if let existing = existingByStableId[aiTheme.stableId] {
                // Update existing theme
                var updated = existing
                updated.name = name
                updated.description = description
                updated.relatedThemeIds = aiTheme.relatedThemeIds

                // Merge mentions (avoid duplicates by timestamp proximity)
                let existingTimestamps = Set(existing.mentions.map { Int($0.timestamp) })
                let trulyNewMentions = newMentions.filter { mention in
                    !existingTimestamps.contains(Int(mention.timestamp))
                }
                updated.mentions.append(contentsOf: trulyNewMentions)

                // Update explored (preserve manual marking)
                updated.explored = aiTheme.explored || existing.manuallyMarkedExplored

                reconciled.append(updated)

            } else {
                // New theme
                let newTheme = Theme(
                    stableId: aiTheme.stableId,
                    name: name,
                    mentions: newMentions,
                    explored: aiTheme.explored,
                    manuallyMarkedExplored: false,
                    relatedThemeIds: aiTheme.relatedThemeIds,
                    description: description
                )
                reconciled.append(newTheme)
                newThemes.append(newTheme)
            }
        }

        // Preserve manual themes that AI didn't return
        for (stableId, existing) in existingByStableId {
            if !returnedStableIds.contains(stableId) &&
               (existing.stableId.hasPrefix("manual_") || existing.manuallyMarkedExplored) {
                reconciled.append(existing)
                print("SessionAssistant: Preserved manual theme: \(existing.name)")
            }
        }

        state.themes = reconciled

        // Generate feed items for new unexplored themes
        for theme in newThemes where !theme.explored {
            let feedItem = FeedItem(
                itemType: .themeAlert,
                content: "Theme: \(theme.name)",
                rationale: theme.description ?? "New pattern detected — consider exploring",
                timestamp: theme.mentions.first?.timestamp ?? 0,
                themeName: theme.name
            )
            state.feedItems.append(feedItem)
        }
    }

    private func processFlag(_ aiFlag: AIFlag) {
        // De-redact AI response text
        let content = deRedact(aiFlag.content)
        let rationale = deRedact(aiFlag.rationale)

        let severity = FlagSeverity(rawValue: aiFlag.severity) ?? .note

        let feedItem = FeedItem(
            itemType: .flag,
            content: content,
            rationale: rationale,
            timestamp: aiFlag.timestamp,
            flagSeverity: severity
        )
        state.feedItems.append(feedItem)
    }

    private func processSuggestion(_ aiSuggestion: AISuggestion) {
        // De-redact AI response text
        let content = deRedact(aiSuggestion.content)
        let rationale = deRedact(aiSuggestion.rationale)

        let feedItem = FeedItem(
            itemType: .suggestion,
            content: content,
            rationale: rationale,
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
        currentSession = nil
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
