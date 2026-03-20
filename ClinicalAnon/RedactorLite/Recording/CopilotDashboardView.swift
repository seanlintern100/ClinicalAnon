//
//  CopilotDashboardView.swift
//  Redactor Lite
//
//  Purpose: Native SwiftUI session dashboard — reads session_state.json
//           from disk on a timer and renders live metrics, agenda, themes, people.
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Dashboard State Model

struct DashboardState: Codable {
    var session_id: String?
    var session_type: String?
    var session_date: String?
    var session_start: String?
    var session_duration_seconds: Int?
    var chunks_processed: Int?
    var last_chunk_timestamp: String?
    var second_speaker_at: String?

    var speaker_totals: SpeakerTotals?
    var utterance_counts: UtteranceCounts?
    var rolling_10m: RollingWindow?
    var engagement: EngagementData?

    var therapist_agenda: [AgendaItemModel]?
    var client_agenda: [AgendaItemModel]?
    var people: [PersonModel]?
    var themes: [ThemeModel]?
    var rupture: RuptureModel?
    var risk: RiskModel?

    struct SpeakerTotals: Codable {
        var therapist_seconds: Double?
        var client_seconds: Double?
        var client_talk_pct: Double?
    }

    struct UtteranceCounts: Codable {
        var therapist_questions: Int?
        var therapist_sr: Int?
        var therapist_cr: Int?
        var therapist_ex: Int?
        var rq_ratio: Double?
        var ex_pct: Double?
    }

    struct RollingWindow: Codable {
        var window_start_timestamp: String?
        var therapist_seconds: Double?
        var client_seconds: Double?
        var client_talk_pct: Double?
        var engagement_score: Double?
    }

    struct EngagementData: Codable {
        var session_score: Double?
        var mean_client_words_per_turn: Double?
        var elaborated_turns: Int?
        var total_client_turns: Int?
    }

    struct AgendaItemModel: Codable, Identifiable {
        var id: String
        var text: String?
        var status: String?
        var evidence: [Evidence]?

        struct Evidence: Codable {
            var type: String?
            var text: String?
        }
    }

    struct PersonModel: Codable, Identifiable {
        var id: String { token ?? UUID().uuidString }
        var token: String?
        var role: String?
        var details: [String: AnyCodableValue]?
        var events: [String]?
    }

    struct ThemeModel: Codable, Identifiable {
        var id: String
        var text: String?
        var phrases: [String]?
    }

    struct RuptureModel: Codable {
        var detected: Bool?
        var type: String?
        var chunk_index: Int?
        var timestamp: String?
    }

    struct RiskModel: Codable {
        var detected: Bool?
        var flagged: Bool?
        var chunk_index: Int?
        var timestamp: String?
    }
}

enum AnyCodableValue: Codable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else { self = .string("") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        }
    }

    var displayString: String {
        switch self {
        case .string(let v): return v
        case .bool(let v): return v ? "Yes" : "No"
        case .int(let v): return "\(v)"
        case .double(let v): return String(format: "%.1f", v)
        }
    }
}

// MARK: - Dashboard Color Palette (Light theme, hardcoded)

private enum DashColors {
    static let background = Color(red: 250/255, green: 247/255, blue: 244/255)       // #FAF7F4
    static let cardBg = Color.white                                                     // #FFFFFF
    static let cardBorder = Color(red: 46/255, green: 46/255, blue: 46/255).opacity(0.12)
    static let cardShadow = Color.black.opacity(0.06)

    static let textPrimary = Color(red: 46/255, green: 46/255, blue: 46/255)           // #2E2E2E
    static let textSecondary = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.6)
    static let textDim = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.35)

    static let teal = Color(red: 10/255, green: 107/255, blue: 124/255)                // #0A6B7C
    static let orange = Color(red: 230/255, green: 138/255, blue: 46/255)              // #E68A2E
    static let green = Color(red: 45/255, green: 157/255, blue: 94/255)                // #2D9D5E
    static let red = Color(red: 214/255, green: 69/255, blue: 69/255)                  // #D64545
    static let amber = Color(red: 212/255, green: 147/255, blue: 13/255)               // #D4930D
    static let sandDark = Color(red: 212/255, green: 174/255, blue: 128/255)           // #D4AE80
    static let blue = Color(red: 74/255, green: 158/255, blue: 255/255)                // #4A9EFF
    static let purple = Color(red: 139/255, green: 111/255, blue: 192/255)             // #8B6FC0

    static let panelBg = Color(red: 248/255, green: 246/255, blue: 243/255)            // slightly off-white for evidence bg
    static let trackGray = Color(red: 46/255, green: 46/255, blue: 46/255).opacity(0.08)
}

// MARK: - Theme colors array

private let themeColors: [Color] = [
    DashColors.teal, DashColors.blue, DashColors.orange,
    DashColors.purple, DashColors.red, DashColors.green, DashColors.sandDark
]

// MARK: - Main Dashboard View

struct CopilotDashboardView: View {

    let sessionFolder: URL?
    let privateFolderURL: URL?

    @State private var state: DashboardState?
    @State private var entityMap: [String: String] = [:]
    @State private var viewMode: ViewMode = .session
    @State private var startTime = Date()
    @State private var wallElapsed: Int = 0
    @State private var expandedAgendaIds: Set<String> = []
    @State private var expandedThemeIds: Set<String> = []

    enum ViewMode { case session, rolling }

    private let pollTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            DashColors.background.ignoresSafeArea()

            if let s = state {
                dashboardBody(s)
            } else {
                waitingState
            }
        }
        .onAppear {
            startTime = Date()
            loadState()
        }
        .onReceive(pollTimer) { _ in
            loadState()
        }
        .onReceive(clockTimer) { _ in
            wallElapsed = Int(Date().timeIntervalSince(startTime))
        }
    }

    private func loadState() {
        guard let folder = sessionFolder else { return }
        let url = folder.appendingPathComponent("session_state.json")
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            let decoded = try JSONDecoder().decode(DashboardState.self, from: data)
            state = decoded
        } catch {
            print("[Dashboard] Failed to decode session_state.json: \(error)")
            return
        }

        // Load entity map from Private/ folder for display substitution (codes → real names)
        guard let privateFolder = privateFolderURL else { return }
        let mapURL = privateFolder.appendingPathComponent("entity_map.json")
        if let mapData = try? Data(contentsOf: mapURL),
           let mapJSON = try? JSONSerialization.jsonObject(with: mapData) as? [String: Any],
           let mappings = mapJSON["mappings"] as? [String: String] {
            entityMap = mappings
        }
    }

    /// Substitute entity codes like [PERSON_A] with real names for display
    private func sub(_ text: String) -> String {
        var result = text
        for (code, name) in entityMap {
            result = result.replacingOccurrences(of: "[\(code)]", with: name)
        }
        return result
    }

    private var waitingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(DashColors.teal)
            Text("Waiting for session data\u{2026}")
                .font(.system(size: 13))
                .foregroundColor(DashColors.textDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main Layout

    private func dashboardBody(_ s: DashboardState) -> some View {
        VStack(spacing: 12) {
            headerRow(s)
                .padding(.horizontal, 20)
            progressBar(s)
                .padding(.horizontal, 20)
            instrumentsCard(s)
                .padding(.horizontal, 20)
            contentGrid(s)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .padding(.top, 16)
    }

    // MARK: - Header Row

    private func headerRow(_ s: DashboardState) -> some View {
        HStack(spacing: 8) {
            dashSectionLabel("3 Big Things")

            Spacer().frame(width: 12)

            // Live status
            Circle()
                .fill(DashColors.green)
                .frame(width: 7, height: 7)
                .shadow(color: DashColors.green.opacity(0.5), radius: 4)

            Text("Live \u{00B7} \(s.chunks_processed ?? 0) chunks")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(DashColors.textSecondary)

            Spacer()

            Text("\(s.session_type ?? "") \u{00B7} \(s.session_date ?? "")")
                .font(.system(size: 12))
                .foregroundColor(DashColors.textSecondary)
        }
    }

    // MARK: - Progress Bar

    private func progressBar(_ s: DashboardState) -> some View {
        let duration = Double(s.session_duration_seconds ?? 3000)
        let elapsed = Double(wallElapsed)
        let remaining = max(0, duration - elapsed)
        let pct = min(1.0, elapsed / duration)
        let isComplete = remaining <= 0
        let color: Color = isComplete ? DashColors.green
            : remaining < 300 ? DashColors.red
            : remaining < 720 ? DashColors.amber
            : DashColors.teal

        return HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DashColors.trackGray)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * pct)
                        .animation(.easeInOut(duration: 0.5), value: pct)
                }
            }
            .frame(height: 8)

            Text(isComplete ? "Complete" : formatTime(Int(remaining)) + " left")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .frame(minWidth: 100, alignment: .trailing)
        }
    }

    // MARK: - Instruments Card

    private func instrumentsCard(_ s: DashboardState) -> some View {
        HStack(spacing: 0) {
            // 4 arc gauges — spread evenly across available space
            HStack(spacing: 0) {
                DashArcGauge(
                    value: effectiveValue(s, \.speaker_totals?.client_talk_pct),
                    maxValue: 100, label: "Client Talk", unit: "%",
                    zones: [(0, 50, DashColors.red), (50, 65, DashColors.amber), (65, 100, DashColors.green)]
                )
                .frame(maxWidth: .infinity)
                DashArcGauge(
                    value: effectiveValue(s, \.utterance_counts?.rq_ratio),
                    maxValue: 4, label: "R:Q Ratio", unit: ":1",
                    zones: [(0, 1, DashColors.red), (1, 2, DashColors.amber), (2, 4, DashColors.green)]
                )
                .frame(maxWidth: .infinity)
                DashArcGauge(
                    value: effectiveValue(s, \.utterance_counts?.ex_pct),
                    maxValue: 100, label: "Expert", unit: "%",
                    zones: [(0, 20, DashColors.green), (20, 40, DashColors.amber), (40, 100, DashColors.red)]
                )
                .frame(maxWidth: .infinity)
                DashArcGauge(
                    value: viewMode == .session
                        ? (s.engagement?.session_score ?? 0)
                        : (s.rolling_10m?.engagement_score ?? 0),
                    maxValue: 100, label: "Engagement", unit: "%",
                    zones: [(0, 45, DashColors.red), (45, 65, DashColors.amber), (65, 100, DashColors.green)]
                )
                .frame(maxWidth: .infinity)
            }

            verticalDivider()
                .padding(.horizontal, 16)

            // View toggle pill
            VStack(spacing: 6) {
                Text("VIEW")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(DashColors.textDim)
                    .tracking(1.2)

                HStack(spacing: 0) {
                    viewToggleButton("Full", mode: .session, isLeft: true)
                    viewToggleButton("10m", mode: .rolling, isLeft: false)
                }
                .background(DashColors.trackGray)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(width: 90)

            verticalDivider()
                .padding(.horizontal, 12)

            // Signal cards
            HStack(spacing: 8) {
                DashSignalCard(
                    isActive: s.rupture?.detected ?? false,
                    label: "Rupture",
                    activeColor: DashColors.orange,
                    icon: "\u{26A0}",
                    detail: s.rupture?.type
                )
                DashSignalCard(
                    isActive: s.risk?.flagged ?? false,
                    label: "Risk",
                    activeColor: DashColors.red,
                    icon: "\u{26A0}",
                    detail: nil
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .dashCard()
    }

    private func effectiveValue(_ s: DashboardState, _ kp: KeyPath<DashboardState, Double?>) -> Double {
        if viewMode == .rolling {
            // For rolling mode, try rolling_10m equivalents
            return s[keyPath: kp] ?? 0
        }
        return s[keyPath: kp] ?? 0
    }

    private func viewToggleButton(_ title: String, mode: ViewMode, isLeft: Bool) -> some View {
        Button { viewMode = mode } label: {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(viewMode == mode ? .white : DashColors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(viewMode == mode ? DashColors.teal : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func verticalDivider() -> some View {
        Rectangle()
            .fill(DashColors.cardBorder)
            .frame(width: 1, height: 80)
    }

    // MARK: - Content Grid

    private func contentGrid(_ s: DashboardState) -> some View {
        let tAgenda = s.therapist_agenda ?? []
        let cAgenda = s.client_agenda ?? []
        let themes = s.themes ?? []
        let people = s.people ?? []

        return HStack(alignment: .top, spacing: 12) {
            // Left column
            ScrollView {
                VStack(spacing: 12) {
                    if !tAgenda.isEmpty {
                        agendaCard("Therapist Focus", items: tAgenda)
                    }
                    if !cAgenda.isEmpty {
                        agendaCard("Client Agenda", items: cAgenda)
                    }
                    themesCard(themes)
                }
            }
            .frame(maxWidth: .infinity)

            // Right column
            ScrollView {
                peopleCard(people)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Agenda Card

    private func agendaCard(_ title: String, items: [DashboardState.AgendaItemModel]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            dashSectionLabel(title)
                .padding(.horizontal, 14)
                .padding(.top, 14)

            if items.isEmpty {
                Text("Detecting\u{2026}")
                    .font(.system(size: 12))
                    .foregroundColor(DashColors.textDim)
                    .italic()
                    .padding(.horizontal, 14)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items) { item in
                            agendaItemRow(item)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            }
        }
        .dashCard()
    }

    private func agendaItemRow(_ item: DashboardState.AgendaItemModel) -> some View {
        let isExpanded = expandedAgendaIds.contains(item.id)
        let evidenceList = item.evidence ?? []
        let hasEvidence = !evidenceList.isEmpty

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                agendaStatusIcon(item.status ?? "not_discussed")
                Text(sub(item.text ?? ""))
                    .font(.system(size: 13))
                    .foregroundColor(DashColors.textPrimary)
                    .lineLimit(isExpanded ? nil : 2)
                Spacer(minLength: 4)
                if hasEvidence {
                    HStack(spacing: 3) {
                        Text("\(evidenceList.count)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(DashColors.textDim)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(DashColors.trackGray)
                            .clipShape(Capsule())
                        Text(isExpanded ? "\u{25B4}" : "\u{25BE}")
                            .font(.system(size: 10))
                            .foregroundColor(DashColors.textDim)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard hasEvidence else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded { expandedAgendaIds.remove(item.id) }
                    else { expandedAgendaIds.insert(item.id) }
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(evidenceList.enumerated()), id: \.offset) { _, ev in
                        let isGap = ev.type == "gap"
                        HStack(alignment: .top, spacing: 0) {
                            Rectangle()
                                .fill(isGap ? DashColors.orange : DashColors.teal)
                                .frame(width: 3)
                            Text(sub(ev.text ?? ""))
                                .font(.system(size: 11))
                                .foregroundColor(isGap ? DashColors.orange : DashColors.textSecondary)
                                .italic(isGap)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(isGap ? DashColors.orange.opacity(0.06) : DashColors.panelBg)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.leading, 24)
                .padding(.top, 4)
            }
        }
    }

    private func agendaStatusIcon(_ status: String) -> some View {
        Group {
            switch status {
            case "fully_discussed":
                Text("\u{25CF}")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(DashColors.green)
                    .clipShape(Circle())
            case "partially_discussed":
                Text("\u{25D1}")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(DashColors.orange)
                    .clipShape(Circle())
            default:
                Text("\u{25CB}")
                    .font(.system(size: 14))
                    .foregroundColor(DashColors.textDim)
                    .frame(width: 18, height: 18)
            }
        }
    }

    // MARK: - Themes Card

    private func themesCard(_ themes: [DashboardState.ThemeModel]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            dashSectionLabel("Themes")
                .padding(.horizontal, 14)
                .padding(.top, 14)

            if themes.isEmpty {
                Text("Synthesising\u{2026}")
                    .font(.system(size: 12))
                    .foregroundColor(DashColors.textDim)
                    .italic()
                    .padding(.horizontal, 14)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(themes.enumerated()), id: \.element.id) { idx, theme in
                            themeRow(theme, color: themeColors[idx % themeColors.count])
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            }
        }
        .dashCard()
    }

    private func themeRow(_ theme: DashboardState.ThemeModel, color: Color) -> some View {
        let isExpanded = expandedThemeIds.contains(theme.id)
        let phrases = theme.phrases ?? []

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(sub(theme.text ?? ""))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(color)
                Text("\(phrases.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(color.opacity(0.6))
                Spacer()
                if !phrases.isEmpty {
                    Text(isExpanded ? "\u{25B4}" : "\u{25BE}")
                        .font(.system(size: 10))
                        .foregroundColor(DashColors.textDim)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !phrases.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded { expandedThemeIds.remove(theme.id) }
                    else { expandedThemeIds.insert(theme.id) }
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(phrases.enumerated()), id: \.offset) { _, phrase in
                        HStack(alignment: .top, spacing: 0) {
                            Rectangle()
                                .fill(DashColors.teal)
                                .frame(width: 3)
                            Text("\u{201C}\(sub(phrase))\u{201D}")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(DashColors.teal)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                        }
                    }
                }
                .padding(.leading, 14)
                .padding(.top, 2)
            }
        }
    }

    // MARK: - People Card

    private func peopleCard(_ people: [DashboardState.PersonModel]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            dashSectionLabel("People & Details")
                .padding(.horizontal, 14)
                .padding(.top, 14)

            if people.isEmpty {
                Text("Detecting\u{2026}")
                    .font(.system(size: 12))
                    .foregroundColor(DashColors.textDim)
                    .italic()
                    .padding(.horizontal, 14)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(people) { person in
                            personRow(person)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            }
        }
        .dashCard()
    }

    private func personRow(_ person: DashboardState.PersonModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Name + role
            HStack(spacing: 6) {
                Text(sub(person.token ?? "Unknown"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DashColors.teal)
                if let role = person.role, !role.isEmpty {
                    Text(role)
                        .font(.system(size: 12))
                        .foregroundColor(DashColors.textSecondary)
                }
            }

            // Details
            if let details = person.details, !details.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(details.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                        HStack(alignment: .top, spacing: 4) {
                            Text(key.replacingOccurrences(of: "_", with: " ") + ":")
                                .font(.system(size: 11))
                                .foregroundColor(DashColors.textDim)
                            Text(sub(value.displayString))
                                .font(.system(size: 11))
                                .foregroundColor(DashColors.textSecondary)
                        }
                    }
                }
                .padding(.leading, 2)
            }

            // Events with left border accent
            if let events = person.events, !events.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                        HStack(alignment: .top, spacing: 0) {
                            Rectangle()
                                .fill(DashColors.teal.opacity(0.4))
                                .frame(width: 2)
                            Text(sub(event))
                                .font(.system(size: 11))
                                .foregroundColor(DashColors.textSecondary)
                                .padding(.leading, 8)
                        }
                    }
                }
                .padding(.leading, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashColors.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Shared Components

    private func dashSectionLabel(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(DashColors.teal)
                .tracking(1.5)
            Rectangle()
                .fill(DashColors.teal)
                .frame(height: 2)
                .frame(width: CGFloat(title.count) * 7 + 8)
        }
    }

    private func formatTime(_ totalSeconds: Int) -> String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Dashboard Card Modifier

private extension View {
    func dashCard() -> some View {
        self
            .background(DashColors.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(DashColors.cardBorder, lineWidth: 1)
            )
            .shadow(color: DashColors.cardShadow, radius: 8, x: 0, y: 2)
    }
}

// MARK: - Arc Gauge

private struct DashArcGauge: View {
    let value: Double
    let maxValue: Double
    let label: String
    let unit: String
    let zones: [(Double, Double, Color)]  // (start, end, color) in value space

    private let sweepDegrees: Double = 284
    private let startAngle: Double = 218  // degrees from 12 o'clock (clockwise)

    private var fraction: Double { min(1.0, max(0, value / maxValue)) }

    private var needleColor: Color {
        let v = value
        for (lo, hi, color) in zones {
            if v >= lo && v <= hi { return color }
        }
        return zones.last?.2 ?? DashColors.teal
    }

    private var displayValue: String {
        if unit == ":1" { return String(format: "%.1f", value) + ":1" }
        return String(format: "%.0f", value) + unit
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                // Zone arcs at 18% opacity
                ForEach(Array(zones.enumerated()), id: \.offset) { _, zone in
                    ArcSegment(
                        startFraction: zone.0 / maxValue,
                        endFraction: zone.1 / maxValue,
                        sweepDegrees: sweepDegrees,
                        startAngle: startAngle
                    )
                    .stroke(zone.2.opacity(0.18), style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                }

                // Thin track line
                ArcSegment(
                    startFraction: 0,
                    endFraction: 1,
                    sweepDegrees: sweepDegrees,
                    startAngle: startAngle
                )
                .stroke(DashColors.trackGray, style: StrokeStyle(lineWidth: 2, lineCap: .round))

                // Needle
                NeedleLine(
                    fraction: fraction,
                    sweepDegrees: sweepDegrees,
                    startAngle: startAngle
                )
                .stroke(needleColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .animation(.easeInOut(duration: 0.5), value: fraction)

                // Center dot
                Circle()
                    .fill(needleColor)
                    .frame(width: 10, height: 10)
                Circle()
                    .fill(Color.white)
                    .frame(width: 5, height: 5)

                // Value text below center
                Text(displayValue)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(needleColor)
                    .offset(y: 28)
            }
            .frame(width: 140, height: 140)

            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DashColors.textSecondary)
                .tracking(0.8)
        }
    }
}

// MARK: - Arc Shape

private struct ArcSegment: Shape {
    let startFraction: Double
    let endFraction: Double
    let sweepDegrees: Double
    let startAngle: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 8

        let angleStart = Angle.degrees(startAngle + startFraction * sweepDegrees)
        let angleEnd = Angle.degrees(startAngle + endFraction * sweepDegrees)

        var path = Path()
        path.addArc(center: center, radius: radius,
                     startAngle: angleStart, endAngle: angleEnd, clockwise: false)
        return path
    }
}

// MARK: - Needle Shape

private struct NeedleLine: Shape {
    var fraction: Double
    let sweepDegrees: Double
    let startAngle: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 12

        let angle = Angle.degrees(startAngle + fraction * sweepDegrees)
        let endX = center.x + radius * cos(CGFloat(angle.radians))
        let endY = center.y + radius * sin(CGFloat(angle.radians))

        var path = Path()
        path.move(to: center)
        path.addLine(to: CGPoint(x: endX, y: endY))
        return path
    }
}

// MARK: - Signal Card

private struct DashSignalCard: View {
    let isActive: Bool
    let label: String
    let activeColor: Color
    let icon: String
    let detail: String?

    var body: some View {
        VStack(spacing: 4) {
            Text(isActive ? icon : "\u{2714}")
                .font(.system(size: 14))
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundColor(isActive ? activeColor : DashColors.textDim)
            if isActive, let detail = detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundColor(activeColor.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .frame(width: 72, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? activeColor.opacity(0.12) : DashColors.panelBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? activeColor.opacity(0.6) : DashColors.cardBorder, lineWidth: isActive ? 2 : 1)
        )
    }
}
