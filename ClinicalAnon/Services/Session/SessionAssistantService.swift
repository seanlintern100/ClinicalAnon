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

    /// Format transcript segments as redacted text (applies entity replacements)
    private func formatSegmentsAsRedactedTranscript(_ segments: [TranscriptSegment], entities: [Entity]) -> String {
        guard !segments.isEmpty else {
            return "[No new transcript segments since last analysis]"
        }

        // Format segments as transcript text
        let sortedSegments = segments.sorted { $0.startTime < $1.startTime }
        var transcript = sortedSegments
            .map { "[\($0.speaker.label)] \($0.text)" }
            .joined(separator: "\n\n")

        // Apply entity replacements (case-insensitive)
        for entity in entities {
            transcript = transcript.replacingOccurrences(
                of: entity.originalText,
                with: entity.replacementCode,
                options: .caseInsensitive
            )
        }

        return truncateTranscript(transcript)
    }

    // MARK: - De-redaction

    /// De-redact text using current session's entity mapping
    /// Converts codes like [PERSON_A] or PERSON_A back to original names for display
    private func deRedact(_ text: String) -> String {
        guard let session = currentSession else {
            print("SessionAssistant: [DE-REDACT] No session - returning unchanged: \(text.prefix(100))")
            return text
        }

        var result = text

        // Get all mappings and sort by length (longest first to avoid partial replacements)
        let allMappings = session.entityMapping.allMappings.sorted {
            $0.replacement.count > $1.replacement.count
        }

        for mapping in allMappings where !mapping.original.isEmpty {
            // Replace bracketed version: [PERSON_A] → "John"
            result = result.replacingOccurrences(of: mapping.replacement, with: mapping.original)

            // Also replace unbracketed version: PERSON_A → "John"
            // AI sometimes drops brackets in its response
            let unbracketed = mapping.replacement
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
            if !unbracketed.isEmpty && unbracketed != mapping.replacement {
                result = result.replacingOccurrences(of: unbracketed, with: mapping.original)
            }
        }

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

        // Get ONLY NEW segments since last analysis (prevents unbounded transcript growth)
        let newSegments = session.transcriptSegments.filter { $0.chunkIndex > lastAnalysedChunkIndex }
        let redactedTranscript = formatSegmentsAsRedactedTranscript(newSegments, entities: session.detectedEntities)

        // Update lastAnalysedChunkIndex for next analysis
        let maxChunkIndex = session.transcriptSegments.map { $0.chunkIndex }.max() ?? -1
        lastAnalysedChunkIndex = maxChunkIndex
        print("SessionAssistant: [CHUNKS] Analysing \(newSegments.count) new segments (chunks > \(lastAnalysedChunkIndex - (maxChunkIndex - lastAnalysedChunkIndex)), now at \(lastAnalysedChunkIndex))")

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
                // Use 8192 max_tokens as safety net (response is typically ~4K)
                let response = try await bedrockService.invoke(
                    systemPrompt: systemPrompt,
                    messages: [ChatMessage.user(userMessage)],
                    model: preferencesManager.selectedModel,
                    maxTokens: 8192
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
                    print("SessionAssistant: [PARSED] details=\(analysisResponse.details.count), agenda=\(analysisResponse.agenda.count), themes=\(analysisResponse.themes.count), flags=\(analysisResponse.flags.count), suggestions=\(analysisResponse.suggestions.count)")
                    processAnalysisResponse(analysisResponse)
                    print("SessionAssistant: [PROCESSED] State now has: details=\(state.details.count), agenda=\(state.agendaItems.count), themes=\(state.themes.count)")
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
        You are a clinical documentation assistant supporting a mental health clinician during a live session. Your role is to silently track clinically relevant information — helping the clinician stay present while ensuring nothing important is lost.

        ## CONTEXT

        **Transcript source:** Automatic speech recognition (Whisper) of a video therapy session.

        **Expect:**
        - Transcription errors (names, clinical terms, NZ place names)
        - Phonetic variants (Sean/Shawn, Māori names)
        - Natural speech patterns (fillers, false starts, repetition)
        - Speaker labels: [Clinician] = microphone, [Other] = system audio (may swap during overlap)

        **Placeholder codes:**
        - Some identifying information appears as codes: [PERSON_A], [DATE_A], [ORG_A], [LOCATION_A], etc.
        - Treat codes as consistent identifiers (same code = same entity throughout)
        - Never attempt to reveal or guess the values behind codes
        - Any text that appears as plain text must remain as plain text — do NOT replace it with codes or invent new placeholders

        ## GROUNDING RULE

        Report only what is explicitly stated. Do not infer unstated relationships, fill in redacted details, or assume context not provided. If uncertain, note it.

        ## FORMAT

        Valid JSON only. No preamble, no markdown. All timestamps are numbers (seconds from session start).

        ```
        {
          "details": [],
          "agenda": [],
          "themes": [],
          "flags": [],
          "suggestions": [],
          "analysis_note": ""
        }
        ```

        ---

        ## 1. KEY FACTS — Complete State (max 20)

        A quick-reference fact map of the client's world. Think cast list, not case notes.

        Each entry is a single, short fact — never a paragraph. If you can't say it in one line, it's too much. The clinician glances at this to remember a name, an age, a relationship, a date. Nothing more.

        **What belongs here:**
        - People: names, roles, relationships (e.g., "[PERSON_A] — partner", "[PERSON_B] — daughter, age 7")
        - Ages and dates (e.g., "Age: 34", "Started current job [DATE_A]")
        - Key life events, stated briefly (e.g., "Mother died 2 years ago")
        - Diagnoses, medications, professionals involved (e.g., "On sertraline 50mg", "GP: [PERSON_C]")
        - Living situation, employment — one line each

        **What does NOT belong here:**
        - Summaries of what was discussed
        - Interpretations or clinical observations (these belong in themes)
        - Context or background narratives
        - Anything longer than one short sentence
        - Emotional states or opinions

        Categories: `Person` | `Relationship` | `Employment` | `Living situation` | `Health` | `Key event`

        You own this list. Each cycle: preserve existing items, update if corrected, merge duplicates, add new facts. Reorder with most referenced/relevant first. Items with stable_id starting "manual_" must always be preserved.

        The test: Could this entry fit on a sticky note with room to spare? If not, it's too long.

        ```
        {
          "stable_id": "detail_partner",
          "content": "[PERSON_A] — partner, together 5 years",
          "category": "Relationship",
          "timestamp": 142
        }
        ```

        ---

        ## 2. AGENDA — Complete State

        Session goals and topics. You own this list — return the complete updated state each analysis.

        - Preserve all items from current state (keep their stable_id)
        - Update status and evidence as discussion progresses
        - Add new items with new stable_id values
        - Items with stable_id starting with "manual_" MUST be preserved

        ```
        {
          "stable_id": "grief_mother",
          "topic": "Processing mother's death",
          "agreed_at": 45,
          "status": "partial",
          "evidence": "discussed initial feelings",
          "parent_id": null,
          "progress_note": "Opened up about guilt"
        }
        ```

        Status: `not_started` | `partial` | `covered`

        ---

        ## 3. THEMES — Complete State

        Recurring patterns, emotional undercurrents, or psychological themes. You own this list — return the complete updated state each analysis.

        - Preserve existing themes (keep stable_id)
        - Add new quotes to existing themes as evidence builds
        - Create new themes when patterns emerge
        - Use sub_themes for related aspects of a theme as they develop
        - Items with stable_id starting with "manual_" MUST be preserved

        ```
        {
          "stable_id": "theme_control",
          "name": "Need for control",
          "quotes": [
            {"text": "I need to know exactly what's happening", "timestamp": 89},
            {"text": "When plans change I feel lost", "timestamp": 203}
          ],
          "sub_themes": [
            {
              "stable_id": "theme_control_work",
              "name": "Control at work",
              "quotes": [{"text": "I have to manage every detail", "timestamp": 245}],
              "sub_themes": [],
              "explored": false
            }
          ],
          "explored": false
        }
        ```

        ---

        ## 4. FLAGS — Additive

        Clinical observations requiring attention.

        Severity levels:
        - `safety`: Risk language, crisis indicators — always flag, even if uncertain
        - `important`: Significant revelations, contradictions, ruptures
        - `note`: Patterns, process observations, areas to explore

        ```
        {
          "severity": "important",
          "content": "Client described hopelessness about the future",
          "timestamp": 267,
          "rationale": "Potential depressive cognition worth monitoring"
        }
        ```

        ---

        ## 5. SUGGESTIONS — Additive

        Brief therapeutic considerations. Use sparingly — only when clinically indicated.

        ```
        {
          "content": "Consider exploring the connection between control and anxiety",
          "rationale": "Theme appeared twice in different contexts",
          "timestamp": 310
        }
        ```

        ---

        ## PRIORITIES

        1. **Safety first** — Always flag risk language
        2. **Stay grounded** — Only what's in the transcript
        3. **Complete state** — Agenda and Themes are full replacements
        4. **Quality over quantity** — Don't overwhelm with noise
        5. **Preserve their words** — Keep quotes verbatim
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

        ## NEW TRANSCRIPT (since last analysis)

        \(transcript)

        ---

        Analyse this NEW transcript and return structured JSON.
        - Details/Agenda/Themes: Return COMPLETE organised lists (you own these - preserve existing stable_ids, add new, reorder as needed)
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
        // Reconcile details (AI owns the complete organised list)
        if featureToggles.detailsEnabled {
            reconcileDetails(response.details)
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

    // MARK: - Details Reconciliation

    /// Reconcile AI's complete details list with local state
    /// AI owns the list - can reorder, update, and organise facts
    private func reconcileDetails(_ aiDetails: [AIDetail]) {
        var existingByStableId: [String: ClientDetail] = [:]
        for detail in state.details {
            existingByStableId[detail.stableId] = detail
        }

        var returnedStableIds: Set<String> = []
        var newDetails: [ClientDetail] = []
        var reconciled: [ClientDetail] = []

        // Process in order returned by AI (preserves AI's organisation)
        for aiDetail in aiDetails {
            let content = deRedact(aiDetail.content)
            returnedStableIds.insert(aiDetail.stableId)

            if let existing = existingByStableId[aiDetail.stableId] {
                // Update existing detail (content/category may have been refined)
                var updated = existing
                updated.content = content
                updated.category = aiDetail.category
                reconciled.append(updated)
            } else {
                // New detail
                let newDetail = ClientDetail(
                    stableId: aiDetail.stableId,
                    content: content,
                    category: aiDetail.category,
                    timestamp: aiDetail.timestamp,
                    isManuallyAdded: false
                )
                reconciled.append(newDetail)
                newDetails.append(newDetail)
            }
        }

        // Preserve manual details that AI didn't return
        for (stableId, existing) in existingByStableId {
            if !returnedStableIds.contains(stableId) && existing.isManuallyAdded {
                reconciled.append(existing)
                print("SessionAssistant: Preserved manual detail: \(existing.content)")
            }
        }

        state.details = reconciled

        // Generate feed items only for genuinely new details
        for detail in newDetails {
            let feedItem = FeedItem(
                itemType: .detail,
                content: detail.content,
                rationale: "",
                timestamp: detail.timestamp,
                detailCategory: detail.category
            )
            state.feedItems.append(feedItem)
        }
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
        var reconciled: [Theme] = []

        for aiTheme in aiThemes {
            returnedStableIds.insert(aiTheme.stableId)
            let converted = convertAITheme(aiTheme, existingByStableId: existingByStableId)
            reconciled.append(converted)
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
        // Themes only appear in parking lot - no feed items generated
    }

    /// Convert AITheme to Theme, merging with existing if present
    private func convertAITheme(_ aiTheme: AITheme, existingByStableId: [String: Theme]) -> Theme {
        let name = deRedact(aiTheme.name)
        let newQuotes = aiTheme.quotes.map {
            ThemeQuote(text: deRedact($0.text), timestamp: $0.timestamp)
        }
        let subThemes = aiTheme.subThemes.map { convertAITheme($0, existingByStableId: existingByStableId) }

        if let existing = existingByStableId[aiTheme.stableId] {
            // Update existing theme
            var updated = existing
            updated.name = name

            // Merge quotes (avoid duplicates by timestamp proximity)
            let existingTimestamps = Set(existing.quotes.map { Int($0.timestamp) })
            let trulyNewQuotes = newQuotes.filter { quote in
                !existingTimestamps.contains(Int(quote.timestamp))
            }
            updated.quotes.append(contentsOf: trulyNewQuotes)

            // Merge sub-themes
            updated.subThemes = subThemes

            // Update explored (preserve manual marking)
            updated.explored = aiTheme.explored || existing.manuallyMarkedExplored

            return updated
        } else {
            // New theme
            return Theme(
                stableId: aiTheme.stableId,
                name: name,
                quotes: newQuotes,
                subThemes: subThemes,
                explored: aiTheme.explored,
                manuallyMarkedExplored: false
            )
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
                    timestamp: item.timestamp,
                    isManuallyAdded: true
                )
                // Only add if not duplicate
                if !state.details.contains(where: { $0.content.lowercased() == detail.content.lowercased() }) {
                    state.details.append(detail)
                }
            }

        default:
            break // Flags, suggestions don't move to parking lot
        }
    }

    func dismissItem(_ item: FeedItem) {
        guard let index = state.feedItems.firstIndex(where: { $0.id == item.id }) else { return }
        state.feedItems[index].status = .dismissed
    }

    // MARK: - Manual Parking Lot Actions

    func addManualDetail(_ content: String, category: String) {
        let detail = ClientDetail(
            content: content,
            category: category,
            timestamp: 0,
            isManuallyAdded: true
        )
        state.details.append(detail)
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
