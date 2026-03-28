//
//  MyWaveModels.swift
//  FreeMusicPlayer
//
//  Recommendation models shared by history, ranking, and UI.
//

import Foundation

extension Notification.Name {
    static let myWaveSignalsDidChange = Notification.Name("myWaveSignalsDidChange")
}

struct MyWaveSettings: Codable, Equatable, Sendable {
    var activity: Activity?
    var vibe: Vibe?
    var mood: Mood?
    var language: Language?

    static let `default` = MyWaveSettings()

    var isCustomized: Bool {
        activity != nil || vibe != nil || mood != nil || language != nil
    }

    var selectedLabels: [String] {
        [activity?.title, vibe?.title, mood?.title, language?.title].compactMap { $0 }
    }

    var searchSeedQueries: [String] {
        deduplicatedQueries(
            (activity?.searchQueries ?? []) +
            (mood?.searchQueries ?? []) +
            (language?.searchQueries ?? [])
        )
    }

    private func deduplicatedQueries(_ queries: [String]) -> [String] {
        var seenKeys: Set<String> = []
        var resolvedQueries: [String] = []

        for query in queries {
            let normalizedKey = RecommendationTextNormalizer.normalizedKey(query)
            guard !normalizedKey.isEmpty,
                  seenKeys.insert(normalizedKey).inserted else {
                continue
            }

            resolvedQueries.append(query)
        }

        return resolvedQueries
    }

    enum Activity: String, Codable, CaseIterable, Identifiable, Sendable {
        case wakingUp
        case commute
        case work

        var id: String { rawValue }

        var title: String {
            switch self {
            case .wakingUp:
                return "Просыпаюсь"
            case .commute:
                return "В дороге"
            case .work:
                return "Работаю"
            }
        }

        var searchQueries: [String] {
            switch self {
            case .wakingUp:
                return ["morning chill"]
            case .commute:
                return ["night drive"]
            case .work:
                return ["focus instrumental"]
            }
        }

        var matchTerms: [String] {
            switch self {
            case .wakingUp:
                return ["morning", "sunrise", "fresh", "soft", "uplifting", "wake up", "gentle"]
            case .commute:
                return ["drive", "road", "night", "energetic", "upbeat", "motion", "run"]
            case .work:
                return ["focus", "study", "ambient", "instrumental", "lofi", "calm", "coding"]
            }
        }
    }

    enum Vibe: String, Codable, CaseIterable, Identifiable, Sendable {
        case favorite
        case unknown
        case popular

        var id: String { rawValue }

        var title: String {
            switch self {
            case .favorite:
                return "Любимое"
            case .unknown:
                return "Незнакомое"
            case .popular:
                return "Популярное"
            }
        }
    }

    enum Mood: String, Codable, CaseIterable, Identifiable, Sendable {
        case energetic
        case happy
        case calm
        case sad

        var id: String { rawValue }

        var title: String {
            switch self {
            case .energetic:
                return "Бодрое"
            case .happy:
                return "Весёлое"
            case .calm:
                return "Спокойное"
            case .sad:
                return "Грустное"
            }
        }

        var searchQueries: [String] {
            switch self {
            case .energetic:
                return ["energetic mix"]
            case .happy:
                return ["feel good"]
            case .calm:
                return ["calm ambient"]
            case .sad:
                return ["melancholic"]
            }
        }

        var matchTerms: [String] {
            switch self {
            case .energetic:
                return ["energetic", "upbeat", "dance", "power", "workout", "fast"]
            case .happy:
                return ["happy", "fun", "feel good", "bright", "sunny", "joy"]
            case .calm:
                return ["calm", "chill", "ambient", "relax", "soft", "peaceful"]
            case .sad:
                return ["sad", "melancholy", "emotional", "slow", "blue", "lonely"]
            }
        }
    }

    enum Language: String, Codable, CaseIterable, Identifiable, Sendable {
        case russian
        case foreign
        case instrumental

        var id: String { rawValue }

        var title: String {
            switch self {
            case .russian:
                return "Русский"
            case .foreign:
                return "Иностранный"
            case .instrumental:
                return "Без слов"
            }
        }

        var searchQueries: [String] {
            switch self {
            case .russian:
                return ["russian music"]
            case .foreign:
                return ["english pop"]
            case .instrumental:
                return ["instrumental"]
            }
        }

        var matchTerms: [String] {
            switch self {
            case .russian:
                return ["russian", "русский", "русская", "русские"]
            case .foreign:
                return ["english", "international", "global", "foreign"]
            case .instrumental:
                return ["instrumental", "ambient", "beats", "lofi", "piano", "without words"]
            }
        }
    }
}

enum ListeningEventKind: String, Codable, CaseIterable, Sendable {
    case play
    case libraryAdd
    case finishedPlayback
    case quickSkip
}

struct TrackTasteSnapshot: Identifiable, Codable, Equatable, Sendable {
    let trackID: String
    let sourceID: String?
    let title: String
    let artistName: String
    let artistKey: String
    let providerArtistID: String?
    let source: Track.TrackSource
    let album: String?
    let genres: [String]
    let tags: [String]
    let moods: [String]
    let duration: TimeInterval

    init(
        trackID: String,
        sourceID: String?,
        title: String,
        artistName: String,
        artistKey: String,
        providerArtistID: String?,
        source: Track.TrackSource,
        album: String?,
        genres: [String],
        tags: [String],
        moods: [String],
        duration: TimeInterval
    ) {
        self.trackID = trackID
        self.sourceID = sourceID
        self.title = title
        self.artistName = artistName
        self.artistKey = artistKey
        self.providerArtistID = providerArtistID
        self.source = source
        self.album = album
        self.genres = genres
        self.tags = tags
        self.moods = moods
        self.duration = duration
    }

    init(track: Track) {
        self.trackID = track.id
        self.sourceID = RecommendationTextNormalizer.cleanedIdentifier(track.sourceID)
        self.title = track.displayTitle
        self.artistName = track.displayArtist
        self.providerArtistID = RecommendationTextNormalizer.cleanedIdentifier(track.providerArtistID)
        self.artistKey = RecommendationTextNormalizer.artistKey(
            artistName: track.displayArtist,
            providerArtistID: track.providerArtistID
        )
        self.source = track.source
        self.album = RecommendationTextNormalizer.cleanedText(track.album)
        self.genres = RecommendationTextNormalizer.normalizedTerms(track.genres)
        self.tags = RecommendationTextNormalizer.normalizedTerms(track.tags)
        self.moods = RecommendationTextNormalizer.normalizedTerms(track.moods)
        self.duration = max(track.duration, 0)
    }

    init(result: OnlineTrackResult) {
        self.trackID = result.id
        self.sourceID = RecommendationTextNormalizer.cleanedIdentifier(result.id)
        self.title = RecommendationTextNormalizer.cleanedText(result.title) ?? "Unknown Track"
        self.artistName = RecommendationTextNormalizer.cleanedText(result.artist) ?? "Unknown Artist"
        self.providerArtistID = RecommendationTextNormalizer.cleanedIdentifier(result.providerArtistID)
        self.artistKey = RecommendationTextNormalizer.artistKey(
            artistName: result.artist,
            providerArtistID: result.providerArtistID
        )
        self.source = result.trackSource
        self.album = RecommendationTextNormalizer.cleanedText(result.album)
        self.genres = RecommendationTextNormalizer.normalizedTerms(result.genres)
        self.tags = RecommendationTextNormalizer.normalizedTerms(result.tags)
        self.moods = RecommendationTextNormalizer.normalizedTerms(result.moods)
        self.duration = max(result.duration, 0)
    }

    var id: String {
        identityKey
    }

    var identityKey: String {
        RecommendationTextNormalizer.cleanedIdentifier(sourceID) ?? trackID
    }

    var titleKey: String {
        RecommendationTextNormalizer.normalizedKey(title)
    }

    var contentSignature: String {
        "\(artistKey)::\(titleKey)"
    }

    var metadataTerms: [String] {
        RecommendationTextNormalizer.normalizedTerms(genres + tags + moods)
    }
}

struct ListeningEvent: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let kind: ListeningEventKind
    let occurredAt: Date
    let track: TrackTasteSnapshot
    let sourceContext: String?
    let playbackPosition: TimeInterval?
    let playbackDuration: TimeInterval?
    let completionRatio: Double?

    init(
        id: String = UUID().uuidString,
        kind: ListeningEventKind,
        occurredAt: Date = Date(),
        track: TrackTasteSnapshot,
        sourceContext: String? = nil,
        playbackPosition: TimeInterval? = nil,
        playbackDuration: TimeInterval? = nil,
        completionRatio: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.occurredAt = occurredAt
        self.track = track
        self.sourceContext = sourceContext
        self.playbackPosition = playbackPosition
        self.playbackDuration = playbackDuration
        self.completionRatio = completionRatio
    }
}

struct MyWaveImpression: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let shownAt: Date
    let track: TrackTasteSnapshot

    init(id: String = UUID().uuidString, shownAt: Date = Date(), track: TrackTasteSnapshot) {
        self.id = id
        self.shownAt = shownAt
        self.track = track
    }
}

struct ListeningHistorySnapshot: Equatable, Sendable {
    let events: [ListeningEvent]
    let impressions: [MyWaveImpression]

    static let empty = ListeningHistorySnapshot(events: [], impressions: [])
}

struct MyWaveRecommendationContext: Equatable, Sendable {
    let libraryTracks: [Track]
    let favoriteArtists: [FavoriteArtist]
    let currentTrack: Track?
    let settings: MyWaveSettings
}

struct TasteSeedTrack: Equatable, Sendable {
    let track: TrackTasteSnapshot
    let weight: Double
}

struct PreferredArtistSeed: Equatable, Sendable {
    let artistKey: String
    let displayName: String
    let provider: OnlineTrackProvider?
    let providerArtistID: String?
    let origin: RecommendationCandidateOrigin
    let weight: Double
}

struct UserTasteProfile: Equatable, Sendable {
    let artistAffinities: [String: Double]
    let genreAffinities: [String: Double]
    let tagAffinities: [String: Double]
    let moodAffinities: [String: Double]
    let recentArtistAffinities: [String: Double]
    let recentGenreAffinities: [String: Double]
    let libraryTrackKeys: Set<String>
    let blockedTrackKeys: Set<String>
    let recentlyShownTrackKeys: Set<String>
    let recentlyPlayedTrackKeys: Set<String>
    let quickSkipCounts: [String: Int]
    let positiveSeedTracks: [TasteSeedTrack]
    let recentSeedTracks: [TasteSeedTrack]
    let preferredArtists: [PreferredArtistSeed]
    let topGenreTerms: [String]
    let topTagTerms: [String]
    let topMoodTerms: [String]

    var summaryLine: String {
        let artistNames = preferredArtists.prefix(2).map(\.displayName)
        if !artistNames.isEmpty {
            return "Personalized from \(artistNames.joined(separator: ", ")) and your recent listens."
        }

        let topTerms = Array((topGenreTerms + topTagTerms + topMoodTerms).prefix(2))
        if !topTerms.isEmpty {
            return "Personalized from your library and \(topTerms.joined(separator: ", "))."
        }

        return "Personalized from your library, saves, and playback history."
    }
}

enum RecommendationCandidateOrigin: String, Codable, CaseIterable, Hashable, Sendable {
    case library
    case favoriteArtist
    case frequentArtist
    case recentArtist
    case genreSearch
    case tagSearch
    case moodSearch
    case likedTrackSearch
    case settingsSearch
    case exploration
}

struct RecommendationCandidate: Identifiable, Equatable, Sendable {
    let track: TrackTasteSnapshot
    let libraryTrack: Track?
    let onlineResult: OnlineTrackResult?
    let isInLibrary: Bool
    let playCount: Int
    let lastPlayed: Date?
    let popularityHint: Double
    let discoveryBias: Double
    let sourceRank: Int
    var origins: Set<RecommendationCandidateOrigin>

    var id: String {
        track.identityKey
    }

    var contentSignature: String {
        track.contentSignature
    }

    var similaritySignature: String {
        let firstMetadataTerm = track.metadataTerms.first ?? "no-metadata"
        return "\(track.artistKey)::\(firstMetadataTerm)"
    }
}

struct RecommendationScoreBreakdown: Equatable, Sendable {
    let artistAffinity: Double
    let genreAffinity: Double
    let tagAffinity: Double
    let moodAffinity: Double
    let likedSeedAffinity: Double
    let recentSeedAffinity: Double
    let recentArtistAffinity: Double
    let popularityBoost: Double
    let originBoost: Double
    let discoveryBoost: Double
    let settingsBoost: Double
    let quickSkipPenalty: Double
    let inLibraryPenalty: Double
    let recentImpressionPenalty: Double

    var total: Double {
        artistAffinity +
            genreAffinity +
            tagAffinity +
            moodAffinity +
            likedSeedAffinity +
            recentSeedAffinity +
            recentArtistAffinity +
            popularityBoost +
            originBoost +
            discoveryBoost +
            settingsBoost -
            quickSkipPenalty -
            inLibraryPenalty -
            recentImpressionPenalty
    }
}

struct ScoredRecommendationCandidate: Equatable, Sendable {
    let candidate: RecommendationCandidate
    let breakdown: RecommendationScoreBreakdown

    var totalScore: Double {
        breakdown.total
    }
}

enum MyWaveRecommendationItemSource: String, Codable, Sendable {
    case libraryTrack
    case onlineResult
}

struct MyWaveRecommendationItem: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let source: MyWaveRecommendationItemSource
    let track: Track?
    let onlineResult: OnlineTrackResult?
    let score: Double
    let reasons: [String]
    let reasonSummary: String

    init(scoredCandidate: ScoredRecommendationCandidate) {
        let candidate = scoredCandidate.candidate
        self.id = candidate.id
        self.source = candidate.libraryTrack == nil ? .onlineResult : .libraryTrack
        self.track = candidate.libraryTrack
        self.onlineResult = candidate.onlineResult
        self.score = scoredCandidate.totalScore
        self.reasons = RecommendationReasonFormatter.reasons(for: scoredCandidate)
        self.reasonSummary = RecommendationReasonFormatter.summary(for: scoredCandidate)
    }

    var displayTitle: String {
        track?.displayTitle ?? onlineResult?.title ?? "Unknown Track"
    }

    var displayArtist: String {
        track?.displayArtist ?? onlineResult?.artist ?? "Unknown Artist"
    }

    var formattedDuration: String {
        let resolvedDuration = track?.duration ?? onlineResult?.duration ?? 0
        let minutes = Int(resolvedDuration) / 60
        let seconds = Int(resolvedDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var provider: OnlineTrackProvider? {
        if let onlineResult {
            return onlineResult.provider
        }

        return track?.source.onlineProvider
    }

    var tasteSnapshot: TrackTasteSnapshot {
        if let track {
            return TrackTasteSnapshot(track: track)
        }

        if let onlineResult {
            return TrackTasteSnapshot(result: onlineResult)
        }

        return TrackTasteSnapshot(
            trackID: id,
            sourceID: id,
            title: displayTitle,
            artistName: displayArtist,
            artistKey: RecommendationTextNormalizer.artistKey(artistName: displayArtist, providerArtistID: nil),
            providerArtistID: nil,
            source: .local,
            album: nil,
            genres: [],
            tags: [],
            moods: [],
            duration: 0
        )
    }
}

struct MyWaveRecommendationSnapshot: Equatable, Sendable {
    let items: [MyWaveRecommendationItem]
    let summaryLine: String
    let generatedAt: Date
    let settings: MyWaveSettings
}

extension MyWaveRecommendationSnapshot: Codable {
    enum CodingKeys: String, CodingKey {
        case items
        case summaryLine
        case generatedAt
        case settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([MyWaveRecommendationItem].self, forKey: .items)
        summaryLine = try container.decode(String.self, forKey: .summaryLine)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        settings = try container.decodeIfPresent(MyWaveSettings.self, forKey: .settings) ?? .default
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
        try container.encode(summaryLine, forKey: .summaryLine)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(settings, forKey: .settings)
    }
}

enum RecommendationTextNormalizer {
    static func cleanedText(_ value: String?) -> String? {
        guard let value else { return nil }

        let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedValue.isEmpty ? nil : cleanedValue
    }

    static func cleanedIdentifier(_ value: String?) -> String? {
        cleanedText(value)
    }

    static func normalizedKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func normalizedTerms(_ values: [String]) -> [String] {
        var seenTerms: Set<String> = []
        var resolvedTerms: [String] = []

        for value in values {
            guard let cleanedValue = cleanedText(value) else { continue }
            let normalizedValue = normalizedKey(cleanedValue)
            guard !normalizedValue.isEmpty,
                  seenTerms.insert(normalizedValue).inserted else {
                continue
            }

            resolvedTerms.append(normalizedValue)
        }

        return resolvedTerms
    }

    static func tokenizedTerms(_ value: String?) -> [String] {
        guard let cleanedValue = cleanedText(value) else { return [] }

        return normalizedKey(cleanedValue)
            .split(separator: " ")
            .map(String.init)
    }

    static func artistKey(artistName: String?, providerArtistID: String?) -> String {
        if let providerArtistID = cleanedIdentifier(providerArtistID) {
            return providerArtistID
        }

        return normalizedKey(cleanedText(artistName) ?? "unknown-artist")
    }
}

enum RecommendationReasonFormatter {
    static func reasons(for scoredCandidate: ScoredRecommendationCandidate) -> [String] {
        let breakdown = scoredCandidate.breakdown
        var reasons: [String] = []

        if breakdown.artistAffinity > 0.75 {
            reasons.append("favorite artist")
        }
        if breakdown.tagAffinity + breakdown.genreAffinity + breakdown.moodAffinity > 0.8 {
            reasons.append("matching tags")
        }
        if breakdown.settingsBoost > 0.45 {
            reasons.append("matches My Wave filters")
        }
        if breakdown.recentArtistAffinity + breakdown.recentSeedAffinity > 0.75 {
            reasons.append("recently in rotation")
        }
        if breakdown.discoveryBoost > 0.2 {
            reasons.append("discovery pick")
        }
        if breakdown.popularityBoost > 0.2 {
            reasons.append("strong catalog match")
        }

        if reasons.isEmpty {
            reasons.append("fits your listening profile")
        }

        return reasons
    }

    static func summary(for scoredCandidate: ScoredRecommendationCandidate) -> String {
        let reasons = reasons(for: scoredCandidate)
        return reasons.prefix(2).joined(separator: " • ")
    }
}
