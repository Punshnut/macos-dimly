import SwiftUI

// MARK: - Settings Search
// Powers the live search bar pinned above the Settings sidebar's tab list: a flat index of
// individually-searchable, fully interactive tiles (built in SettingsRootView from both the
// static tabs and the per-display controls), matched with a relevance-scored, typo-tolerant
// search that always considers both the system language and English.

/// Looks up a `Localizable.strings` key in a fixed locale, regardless of the app's current
/// language — used so search always also matches the English term for a setting even when
/// the UI is displayed in another language.
func localized(_ key: String, locale: Locale) -> String {
    String(localized: String.LocalizationValue(key), locale: locale)
}

let englishLocale = Locale(identifier: "en")

struct SettingsSearchEntry: Identifiable {
    let id: String
    let tab: SettingsRootView.SettingsDestination
    /// Localizable.strings key for the title — resolved in the system language for display,
    /// and separately in English so search always works in both.
    let titleKey: String
    /// Localizable.strings key for the subtitle, when the subtitle is itself localized text
    /// (e.g. a setting's description). Mutually exclusive with `subtitleLiteral`.
    let subtitleKey: String?
    /// A subtitle that isn't localized text — e.g. a display's name. Shown as-is and matched
    /// as-is (no English variant needed).
    let subtitleLiteral: String?
    let systemImage: String
    /// Extra literal match terms beyond title/subtitle/tab name — e.g. a display's name, or
    /// English synonyms for a setting that isn't literally named that in the UI.
    let keywords: [String]
    let content: () -> AnyView

    init(
        id: String,
        tab: SettingsRootView.SettingsDestination,
        titleKey: String,
        subtitleKey: String? = nil,
        subtitleLiteral: String? = nil,
        systemImage: String,
        keywords: [String] = [],
        content: @escaping () -> AnyView
    ) {
        self.id = id
        self.tab = tab
        self.titleKey = titleKey
        self.subtitleKey = subtitleKey
        self.subtitleLiteral = subtitleLiteral
        self.systemImage = systemImage
        self.keywords = keywords
        self.content = content
    }

    /// Title resolved in the system's current display language.
    var title: String { String(localized: String.LocalizationValue(titleKey)) }

    /// Subtitle resolved in the system's current display language, if any.
    var subtitle: String? {
        if let subtitleLiteral { return subtitleLiteral }
        if let subtitleKey { return String(localized: String.LocalizationValue(subtitleKey)) }
        return nil
    }

    /// All text this entry can be found by: displayed-language + English title/subtitle/tab
    /// name, plus literal keywords. Used for matching, not display.
    fileprivate var searchableFields: [String] {
        var fields = [title, tab.localizedLabel, localized(titleKey, locale: englishLocale), tab.englishLabel]
        if let subtitleLiteral {
            fields.append(subtitleLiteral)
        } else if let subtitleKey {
            fields.append(String(localized: String.LocalizationValue(subtitleKey)))
            fields.append(localized(subtitleKey, locale: englishLocale))
        }
        fields.append(contentsOf: keywords)
        return fields.map { $0.lowercased() }
    }
}

/// Levenshtein edit distance, capped early once it exceeds `maxDistance` (both strings here
/// are short UI labels, so this stays cheap).
private func editDistance(_ a: String, _ b: String, maxDistance: Int) -> Int {
    if a == b { return 0 }
    let a = Array(a), b = Array(b)
    if abs(a.count - b.count) > maxDistance { return maxDistance + 1 }
    var previous = Array(0...b.count)
    var current = [Int](repeating: 0, count: b.count + 1)
    for i in 1...max(a.count, 1) where a.count > 0 {
        current[0] = i
        var rowMin = current[0]
        for j in 1...b.count {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            rowMin = min(rowMin, current[j])
        }
        if rowMin > maxDistance { return maxDistance + 1 }
        swap(&previous, &current)
    }
    return previous[b.count]
}

/// Scores how well a single query token matches one field, or nil if it doesn't match at all
/// (allowing for a small number of typos on longer words).
private func tokenScore(_ token: String, in field: String) -> Int? {
    if field == token { return 100 }
    if field.hasPrefix(token) { return 70 }
    if field.contains(token) { return 50 }
    // Typo tolerance: compare against each word in the field individually so
    // "brigtness" still finds "Brightness" or "dispaly" still finds "Display".
    let allowedTypos = token.count >= 8 ? 2 : (token.count >= 4 ? 1 : 0)
    guard allowedTypos > 0 else { return nil }
    for word in field.split(separator: " ") {
        if editDistance(token, String(word), maxDistance: allowedTypos) <= allowedTypos {
            return 20
        }
    }
    return nil
}

/// Relevance score for an entry against a query, or nil if the query doesn't match at all.
/// Every whitespace-separated token must match some field (AND across tokens, OR across
/// fields) — this lets compound queries like "display1 brightness" scope down to a single
/// display's brightness tile, while still tolerating a typo in either half.
func settingsSearchScore(_ entry: SettingsSearchEntry, query: String) -> Int? {
    let tokens = query.lowercased().split(separator: " ").map(String.init)
    guard !tokens.isEmpty else { return 0 }
    let fields = entry.searchableFields
    var total = 0
    for token in tokens {
        guard let best = fields.compactMap({ tokenScore(token, in: $0) }).max() else { return nil }
        total += best
    }
    return total
}

func settingsSearchMatches(_ entry: SettingsSearchEntry, query: String) -> Bool {
    settingsSearchScore(entry, query: query) != nil
}

/// Search field pinned above the sidebar's tab list, styled to match the sidebar chrome.
struct SettingsSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField(String(localized: "SettingsSearchPlaceholder"), text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(isFocused ? 0.18 : 0.08), lineWidth: 1)
        )
    }
}

/// Renders matching search entries, grouped by their home tab, in the same tile chrome
/// used by that tab's normal content — each tile is the real, live control. Both entries
/// within a group and the groups themselves are ordered by relevance, so the best match is
/// always first.
struct SettingsSearchResultsView: View {
    let entries: [SettingsSearchEntry]
    let query: String

    private var groupedMatches: [(tab: SettingsRootView.SettingsDestination, entries: [SettingsSearchEntry])] {
        let scored = entries.compactMap { entry in
            settingsSearchScore(entry, query: query).map { (entry: entry, score: $0) }
        }
        var byTab: [SettingsRootView.SettingsDestination: [(entry: SettingsSearchEntry, score: Int)]] = [:]
        for scoredEntry in scored {
            byTab[scoredEntry.entry.tab, default: []].append(scoredEntry)
        }
        let groups = byTab.map { tab, scoredEntries -> (tab: SettingsRootView.SettingsDestination, entries: [SettingsSearchEntry], bestScore: Int) in
            let sorted = scoredEntries.sorted { $0.score > $1.score }
            return (tab: tab, entries: sorted.map(\.entry), bestScore: sorted.first?.score ?? 0)
        }
        return groups.sorted { $0.bestScore > $1.bestScore }.map { (tab: $0.tab, entries: $0.entries) }
    }

    var body: some View {
        SettingsScrollView(
            title: String(localized: "SettingsSearchResultsTitle"),
            subtitle: nil,
            contentMaxWidth: 980
        ) {
            let groups = groupedMatches
            if groups.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text(String(localized: "SettingsSearchNoResultsLabel"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                ForEach(groups, id: \.tab) { group in
                    SettingsCard(title: group.tab.localizedLabel, subtitle: nil) {
                        ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .center, spacing: 10) {
                                    SettingsIcon(systemName: entry.systemImage)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.title)
                                            .font(.callout.weight(.semibold))
                                        if let subtitle = entry.subtitle, !subtitle.isEmpty {
                                            Text(subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                entry.content()
                            }
                            .padding(.vertical, 2)
                            if index != group.entries.count - 1 {
                                SettingsDivider()
                            }
                        }
                    }
                }
            }
        }
    }
}
