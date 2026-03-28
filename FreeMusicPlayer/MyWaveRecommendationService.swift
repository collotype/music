//
//  MyWaveRecommendationService.swift
//  FreeMusicPlayer
//
//  Taste profile building, candidate generation, ranking, and caching for My Wave.
//

import Foundation

struct TasteProfileBuilderConfiguration {
    var libraryTrackWeight: Double = 3.2
    var favoriteArtistWeight: Double = 5.0
    var playWeight: Double = 0.7
    var libraryAddWeight: Double = 4.2
    var finishedPlaybackWeight: Double = 1.8
    var quickSkipWeight: Double = -3.0
    var repeatListenWeight: Double = 0.45
    var recentListenWeight: Double = 1.2
    var eventHalfLife: TimeInterval = 60 * 60 * 24 * 21
    var recentWindow: TimeInterval = 60 * 60 * 24 * 10
    var impressionWindow: TimeInterval = 60 * 60 * 10
    var blockedQuickSkipCount: Int = 2
    var maxSeedTracks: Int = 12
    var maxPreferredArtists: Int = 8
    var maxMetadataTerms: Int = 8
    var genreContribution: Double = 0.6
    var tagContribution: Double = 0.5
    var moodContribution: Double = 0.45
}

struct UserTasteProfileBuilder {
    var configuration = TasteProfileBuilderConfiguration()

    func build(
        context: MyWaveRecommendationContext,
        history: ListeningHistorySnapshot,
        now: Date = Date()
    ) -> UserTasteProfile {
        var artistAffinities: [String: Double] = [:]
        var genreAffinities: [String: Double] = [:]
        var tagAffinities: [String: Double] = [:]
        var moodAffinities: [String: Double] = [:]
        var recentArtistAffinities: [String: Double] = [:]
        var recentGenreAffinities: [String: Double] = [:]
        var quickSkipCounts: [String: Int] = [:]
        var recentlyPlayedTrackKeys: Set<String> = []
        var positiveSeedsByTrackKey: [String: TasteSeedTrack] = [:]
        var recentSeedsByTrackKey: [String: TasteSeedTrack] = [:]
        var preferredArtistsByKey: [String: PreferredArtistSeed] = [:]

        let libraryTracks = context.libraryTracks.filter { $0.storageLocation == .library }
        let libraryTrackKeys = Set(libraryTracks.map { TrackTasteSnapshot(track: $0).identityKey })

        func addScore(_ value: Double, to dictionary: inout [String: Double], key: String) {
            guard !key.isEmpty else { return }
            dictionary[key, default: 0] += value
        }

        func registerMetadataTerms(
            for snapshot: TrackTasteSnapshot,
            weight: Double,
            artistScores: inout [String: Double],
            genreScores: inout [String: Double],
            tagScores: inout [String: Double],
            moodScores: inout [String: Double]
        ) {
            guard weight != 0 else { return }

            addScore(weight, to: &artistScores, key: snapshot.artistKey)

            for genre in snapshot.genres {
                addScore(weight * configuration.genreContribution, to: &genreScores, key: genre)
            }

            for tag in snapshot.tags {
                addScore(weight * configuration.tagContribution, to: &tagScores, key: tag)
            }

            for mood in snapshot.moods {
                addScore(weight * configuration.moodContribution, to: &moodScores, key: mood)
            }
        }

        func registerSeed(
            dictionary: inout [String: TasteSeedTrack],
            snapshot: TrackTasteSnapshot,
            weight: Double
        ) {
            guard weight > 0 else { return }

            let key = snapshot.identityKey
            let previousWeight = dictionary[key]?.weight ?? 0
            dictionary[key] = TasteSeedTrack(track: snapshot, weight: previousWeight + weight)
        }

        func registerPreferredArtist(
            snapshot: TrackTasteSnapshot,
            provider: OnlineTrackProvider?,
            origin: RecommendationCandidateOrigin,
            weight: Double
        ) {
            guard weight > 0 else { return }

            let existingWeight = preferredArtistsByKey[snapshot.artistKey]?.weight ?? 0
            preferredArtistsByKey[snapshot.artistKey] = PreferredArtistSeed(
                artistKey: snapshot.artistKey,
                displayName: snapshot.artistName,
                provider: provider,
                providerArtistID: snapshot.providerArtistID,
                origin: origin,
                weight: existingWeight + weight
            )
        }

        func recencyDecay(for date: Date) -> Double {
            let age = max(now.timeIntervalSince(date), 0)
            guard configuration.eventHalfLife > 0 else { return 1 }
            return exp(-age / configuration.eventHalfLife)
        }

        for track in libraryTracks {
            let snapshot = TrackTasteSnapshot(track: track)
            registerMetadataTerms(
                for: snapshot,
                weight: configuration.libraryTrackWeight,
                artistScores: &artistAffinities,
                genreScores: &genreAffinities,
                tagScores: &tagAffinities,
                moodScores: &moodAffinities
            )
            registerSeed(
                dictionary: &positiveSeedsByTrackKey,
                snapshot: snapshot,
                weight: configuration.libraryTrackWeight
            )
            registerPreferredArtist(
                snapshot: snapshot,
                provider: track.source.onlineProvider,
                origin: .frequentArtist,
                weight: configuration.libraryTrackWeight
            )

            if track.playCount > 1 {
                let repeatWeight = Double(track.playCount - 1) * configuration.repeatListenWeight
                registerMetadataTerms(
                    for: snapshot,
                    weight: repeatWeight,
                    artistScores: &artistAffinities,
                    genreScores: &genreAffinities,
                    tagScores: &tagAffinities,
                    moodScores: &moodAffinities
                )
                registerSeed(
                    dictionary: &positiveSeedsByTrackKey,
                    snapshot: snapshot,
                    weight: repeatWeight
                )
            }

            if let lastPlayed = track.lastPlayed,
               now.timeIntervalSince(lastPlayed) <= configuration.recentWindow {
                recentlyPlayedTrackKeys.insert(snapshot.identityKey)
                registerSeed(
                    dictionary: &recentSeedsByTrackKey,
                    snapshot: snapshot,
                    weight: configuration.recentListenWeight
                )
                registerMetadataTerms(
                    for: snapshot,
                    weight: configuration.recentListenWeight,
                    artistScores: &recentArtistAffinities,
                    genreScores: &recentGenreAffinities,
                    tagScores: &tagAffinities,
                    moodScores: &moodAffinities
                )
            }
        }

        for artist in context.favoriteArtists {
            let artistKey = RecommendationTextNormalizer.artistKey(
                artistName: artist.artistName,
                providerArtistID: artist.providerArtistID
            )
            addScore(configuration.favoriteArtistWeight, to: &artistAffinities, key: artistKey)
            preferredArtistsByKey[artistKey] = PreferredArtistSeed(
                artistKey: artistKey,
                displayName: artist.artistName,
                provider: artist.provider,
                providerArtistID: artist.providerArtistID,
                origin: .favoriteArtist,
                weight: (preferredArtistsByKey[artistKey]?.weight ?? 0) + configuration.favoriteArtistWeight
            )
        }

        for event in history.events {
            let eventWeight: Double
            switch event.kind {
            case .play:
                eventWeight = configuration.playWeight
            case .libraryAdd:
                eventWeight = configuration.libraryAddWeight
            case .finishedPlayback:
                eventWeight = configuration.finishedPlaybackWeight
            case .quickSkip:
                eventWeight = configuration.quickSkipWeight
            }

            let decayedWeight = eventWeight * recencyDecay(for: event.occurredAt)
            registerMetadataTerms(
                for: event.track,
                weight: decayedWeight,
                artistScores: &artistAffinities,
                genreScores: &genreAffinities,
                tagScores: &tagAffinities,
                moodScores: &moodAffinities
            )

            if event.kind == .quickSkip {
                quickSkipCounts[event.track.identityKey, default: 0] += 1
            } else {
                registerSeed(
                    dictionary: &positiveSeedsByTrackKey,
                    snapshot: event.track,
                    weight: max(decayedWeight, 0)
                )
                registerPreferredArtist(
                    snapshot: event.track,
                    provider: event.track.source.onlineProvider,
                    origin: .recentArtist,
                    weight: max(decayedWeight, 0)
                )
            }

            if now.timeIntervalSince(event.occurredAt) <= configuration.recentWindow,
               event.kind != .quickSkip {
                recentlyPlayedTrackKeys.insert(event.track.identityKey)
                registerSeed(
                    dictionary: &recentSeedsByTrackKey,
                    snapshot: event.track,
                    weight: max(decayedWeight, 0)
                )
                registerMetadataTerms(
                    for: event.track,
                    weight: max(decayedWeight, 0),
                    artistScores: &recentArtistAffinities,
                    genreScores: &recentGenreAffinities,
                    tagScores: &tagAffinities,
                    moodScores: &moodAffinities
                )
            }
        }

        let blockedTrackKeys = Set(
            quickSkipCounts.compactMap { key, count in
                count >= configuration.blockedQuickSkipCount ? key : nil
            }
        )

        let recentlyShownTrackKeys = Set(
            history.impressions.compactMap { impression in
                now.timeIntervalSince(impression.shownAt) <= configuration.impressionWindow
                    ? impression.track.identityKey
                    : nil
            }
        )

        let positiveSeeds = positiveSeedsByTrackKey.values.sorted { $0.weight > $1.weight }
        let recentSeeds = recentSeedsByTrackKey.values.sorted { $0.weight > $1.weight }
        let preferredArtists = preferredArtistsByKey.values.sorted { $0.weight > $1.weight }

        return UserTasteProfile(
            artistAffinities: artistAffinities,
            genreAffinities: filteredMetadata(from: genreAffinities),
            tagAffinities: filteredMetadata(from: tagAffinities),
            moodAffinities: filteredMetadata(from: moodAffinities),
            recentArtistAffinities: recentArtistAffinities,
            recentGenreAffinities: filteredMetadata(from: recentGenreAffinities),
            libraryTrackKeys: libraryTrackKeys,
            blockedTrackKeys: blockedTrackKeys,
            recentlyShownTrackKeys: recentlyShownTrackKeys,
            recentlyPlayedTrackKeys: recentlyPlayedTrackKeys,
            quickSkipCounts: quickSkipCounts,
            positiveSeedTracks: Array(positiveSeeds.prefix(configuration.maxSeedTracks)),
            recentSeedTracks: Array(recentSeeds.prefix(configuration.maxSeedTracks)),
            preferredArtists: Array(preferredArtists.prefix(configuration.maxPreferredArtists)),
            topGenreTerms: topTerms(from: genreAffinities, limit: configuration.maxMetadataTerms),
            topTagTerms: topTerms(from: tagAffinities, limit: configuration.maxMetadataTerms),
            topMoodTerms: topTerms(from: moodAffinities, limit: configuration.maxMetadataTerms)
        )
    }

    private func topTerms(from dictionary: [String: Double], limit: Int) -> [String] {
        dictionary
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }

    private func filteredMetadata(from dictionary: [String: Double]) -> [String: Double] {
        dictionary.filter { !$0.key.isEmpty && $0.value != 0 }
    }
}

struct RecommendationEngineConfiguration {
    var targetCount: Int = 20
    var maxConsecutiveArtistTracks: Int = 1
    var discoveryInterval: Int = 3
    var familiarThreshold: Double = 1.25
    var originBoosts: [RecommendationCandidateOrigin: Double] = [
        .favoriteArtist: 0.9,
        .frequentArtist: 0.65,
        .recentArtist: 0.55,
        .likedTrackSearch: 0.5,
        .genreSearch: 0.4,
        .tagSearch: 0.35,
        .moodSearch: 0.3,
        .settingsSearch: 0.32,
        .exploration: 0.25,
        .library: 0.15,
    ]
    var popularityWeight: Double = 0.35
    var discoveryWeight: Double = 0.6
    var settingsActivityWeight: Double = 0.9
    var settingsMoodWeight: Double = 0.95
    var settingsLanguageWeight: Double = 0.9
    var favoriteVibeWeight: Double = 0.7
    var unknownVibeWeight: Double = 0.9
    var popularVibeWeight: Double = 0.85
    var quickSkipPenalty: Double = 2.2
    var inLibraryPenalty: Double = 2.8
    var recentImpressionPenalty: Double = 2.0
}

struct RecommendationEngine {
    var configuration = RecommendationEngineConfiguration()

    func rank(
        candidates: [RecommendationCandidate],
        profile: UserTasteProfile,
        currentTrackKey: String?,
        settings: MyWaveSettings
    ) -> [ScoredRecommendationCandidate] {
        let scoredCandidates = candidates
            .filter { candidate in
                candidate.id != currentTrackKey &&
                    !profile.blockedTrackKeys.contains(candidate.id)
            }
            .map { score(candidate: $0, profile: profile, settings: settings) }
            .sorted { left, right in
                if left.totalScore != right.totalScore {
                    return left.totalScore > right.totalScore
                }

                return left.candidate.sourceRank < right.candidate.sourceRank
            }

        guard !scoredCandidates.isEmpty else { return [] }

        var selected: [ScoredRecommendationCandidate] = []
        var selectedIDs: Set<String> = []
        var selectedSignatures: Set<String> = []

        let phases: [(allowLibrary: Bool, allowRecentImpressions: Bool)] = [
            (allowLibrary: false, allowRecentImpressions: false),
            (allowLibrary: true, allowRecentImpressions: false),
            (allowLibrary: true, allowRecentImpressions: true),
        ]

        for phase in phases {
            let phaseCandidates = scoredCandidates.filter { candidate in
                if !phase.allowLibrary && candidate.candidate.isInLibrary {
                    return false
                }

                if !phase.allowRecentImpressions && profile.recentlyShownTrackKeys.contains(candidate.candidate.id) {
                    return false
                }

                return !selectedIDs.contains(candidate.candidate.id)
            }

            let remaining = configuration.targetCount - selected.count
            guard remaining > 0 else { break }

            let diversified = diversify(
                candidates: phaseCandidates,
                desiredCount: remaining,
                selectedIDs: &selectedIDs,
                selectedSignatures: &selectedSignatures,
                alreadySelected: selected
            )
            selected.append(contentsOf: diversified)
        }

        return Array(selected.prefix(configuration.targetCount))
    }

    func score(
        candidate: RecommendationCandidate,
        profile: UserTasteProfile,
        settings: MyWaveSettings = .default
    ) -> ScoredRecommendationCandidate {
        let artistAffinity = max(profile.artistAffinities[candidate.track.artistKey] ?? 0, 0)
        let genreAffinity = candidate.track.genres.reduce(0) { partial, genre in
            partial + max(profile.genreAffinities[genre] ?? 0, 0)
        }
        let tagAffinity = candidate.track.tags.reduce(0) { partial, tag in
            partial + max(profile.tagAffinities[tag] ?? 0, 0)
        }
        let moodAffinity = candidate.track.moods.reduce(0) { partial, mood in
            partial + max(profile.moodAffinities[mood] ?? 0, 0)
        }
        let likedSeedAffinity = seedAffinity(for: candidate.track, seeds: profile.positiveSeedTracks)
        let recentSeedAffinity = seedAffinity(for: candidate.track, seeds: profile.recentSeedTracks)
        let recentArtistAffinity = max(profile.recentArtistAffinities[candidate.track.artistKey] ?? 0, 0) +
            candidate.track.genres.reduce(0) { partial, genre in
                partial + max(profile.recentGenreAffinities[genre] ?? 0, 0)
            }
        let popularityBoost = min(candidate.popularityHint, 1.0) * configuration.popularityWeight
        let originBoost = candidate.origins.reduce(0) { partial, origin in
            partial + (configuration.originBoosts[origin] ?? 0)
        }
        let discoveryBoost = candidate.discoveryBias * configuration.discoveryWeight
        let familiarityScore = artistAffinity +
            genreAffinity +
            tagAffinity +
            moodAffinity +
            likedSeedAffinity +
            recentSeedAffinity +
            recentArtistAffinity
        let settingsBoost = settingsBoost(
            for: candidate,
            familiarityScore: familiarityScore,
            settings: settings
        )
        let quickSkipPenalty = Double(profile.quickSkipCounts[candidate.id] ?? 0) * configuration.quickSkipPenalty
        let inLibraryPenalty = candidate.isInLibrary ? configuration.inLibraryPenalty : 0
        let recentImpressionPenalty = profile.recentlyShownTrackKeys.contains(candidate.id)
            ? configuration.recentImpressionPenalty
            : 0

        let breakdown = RecommendationScoreBreakdown(
            artistAffinity: artistAffinity,
            genreAffinity: genreAffinity,
            tagAffinity: tagAffinity,
            moodAffinity: moodAffinity,
            likedSeedAffinity: likedSeedAffinity,
            recentSeedAffinity: recentSeedAffinity,
            recentArtistAffinity: recentArtistAffinity,
            popularityBoost: popularityBoost,
            originBoost: originBoost,
            discoveryBoost: discoveryBoost,
            settingsBoost: settingsBoost,
            quickSkipPenalty: quickSkipPenalty,
            inLibraryPenalty: inLibraryPenalty,
            recentImpressionPenalty: recentImpressionPenalty
        )

        return ScoredRecommendationCandidate(candidate: candidate, breakdown: breakdown)
    }

    private func seedAffinity(for track: TrackTasteSnapshot, seeds: [TasteSeedTrack]) -> Double {
        seeds.prefix(10).reduce(0) { partial, seed in
            max(partial, similarity(between: track, and: seed.track) * seed.weight)
        }
    }

    private func similarity(
        between left: TrackTasteSnapshot,
        and right: TrackTasteSnapshot
    ) -> Double {
        var score = 0.0

        if left.artistKey == right.artistKey {
            score += 1.0
        }

        if left.titleKey == right.titleKey {
            score += 0.3
        }

        let leftTerms = Set(left.metadataTerms)
        let rightTerms = Set(right.metadataTerms)
        if !leftTerms.isEmpty && !rightTerms.isEmpty {
            let overlap = Double(leftTerms.intersection(rightTerms).count)
            let denominator = Double(max(leftTerms.count, rightTerms.count))
            score += overlap / denominator
        }

        return min(score, 1.75)
    }

    private func settingsBoost(
        for candidate: RecommendationCandidate,
        familiarityScore: Double,
        settings: MyWaveSettings
    ) -> Double {
        guard settings.isCustomized else { return 0 }

        var boost = 0.0
        let searchableTerms = searchableTerms(for: candidate.track)

        if let activity = settings.activity {
            boost += metadataMatchScore(
                searchableTerms: searchableTerms,
                preferredTerms: activity.matchTerms
            ) * configuration.settingsActivityWeight
        }

        if let mood = settings.mood {
            boost += metadataMatchScore(
                searchableTerms: searchableTerms,
                preferredTerms: mood.matchTerms
            ) * configuration.settingsMoodWeight
        }

        if let language = settings.language {
            boost += languageMatchScore(
                for: candidate.track,
                language: language,
                searchableTerms: searchableTerms
            ) * configuration.settingsLanguageWeight
        }

        if let vibe = settings.vibe {
            boost += vibeBoost(
                vibe,
                candidate: candidate,
                familiarityScore: familiarityScore
            )
        }

        return boost
    }

    private func searchableTerms(for track: TrackTasteSnapshot) -> Set<String> {
        Set(
            track.metadataTerms +
            RecommendationTextNormalizer.tokenizedTerms(track.title) +
            RecommendationTextNormalizer.tokenizedTerms(track.artistName) +
            RecommendationTextNormalizer.tokenizedTerms(track.album)
        )
    }

    private func metadataMatchScore(
        searchableTerms: Set<String>,
        preferredTerms: [String]
    ) -> Double {
        let normalizedPreferredTerms = Set(
            RecommendationTextNormalizer.normalizedTerms(preferredTerms) +
            preferredTerms.flatMap { RecommendationTextNormalizer.tokenizedTerms($0) }
        )
        guard !searchableTerms.isEmpty,
              !normalizedPreferredTerms.isEmpty else {
            return 0
        }

        let overlapCount = searchableTerms.intersection(normalizedPreferredTerms).count
        guard overlapCount > 0 else { return 0 }
        return min(Double(overlapCount) / Double(normalizedPreferredTerms.count), 1.0)
    }

    private func languageMatchScore(
        for track: TrackTasteSnapshot,
        language: MyWaveSettings.Language,
        searchableTerms: Set<String>
    ) -> Double {
        let titleAndArtist = "\(track.title) \(track.artistName) \(track.album ?? "")"
        let containsCyrillic = titleAndArtist.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil
        let instrumentalTerms = Set(
            RecommendationTextNormalizer.normalizedTerms(
                MyWaveSettings.Language.instrumental.matchTerms +
                ["instrumental", "instrumental mix", "instrumental version", "no vocals"]
            )
        )
        let looksInstrumental = !searchableTerms.intersection(instrumentalTerms).isEmpty

        switch language {
        case .russian:
            if containsCyrillic {
                return 1.0
            }
            return metadataMatchScore(
                searchableTerms: searchableTerms,
                preferredTerms: language.matchTerms
            )
        case .foreign:
            if looksInstrumental {
                return 0.1
            }
            return containsCyrillic ? 0 : 0.85
        case .instrumental:
            return looksInstrumental ? 1.0 : 0
        }
    }

    private func vibeBoost(
        _ vibe: MyWaveSettings.Vibe,
        candidate: RecommendationCandidate,
        familiarityScore: Double
    ) -> Double {
        switch vibe {
        case .favorite:
            let libraryBoost = candidate.isInLibrary ? 0.45 : 0
            let familiarityBoost = min(familiarityScore / 5.0, 1.0) * configuration.favoriteVibeWeight
            return libraryBoost + familiarityBoost
        case .unknown:
            let discoveryBoost = min(candidate.discoveryBias + (candidate.isInLibrary ? 0 : 0.3), 1.0)
            let familiarityPenalty = min(familiarityScore / 8.0, 0.35)
            return (discoveryBoost * configuration.unknownVibeWeight) - familiarityPenalty
        case .popular:
            return min(candidate.popularityHint, 1.0) * configuration.popularVibeWeight
        }
    }

    private func diversify(
        candidates: [ScoredRecommendationCandidate],
        desiredCount: Int,
        selectedIDs: inout Set<String>,
        selectedSignatures: inout Set<String>,
        alreadySelected: [ScoredRecommendationCandidate]
    ) -> [ScoredRecommendationCandidate] {
        var familiarPool: [ScoredRecommendationCandidate] = []
        var discoveryPool: [ScoredRecommendationCandidate] = []

        for candidate in candidates {
            if familiarityScore(for: candidate) >= configuration.familiarThreshold || candidate.candidate.isInLibrary {
                familiarPool.append(candidate)
            } else {
                discoveryPool.append(candidate)
            }
        }

        var results: [ScoredRecommendationCandidate] = []
        var runningSelection = alreadySelected

        while results.count < desiredCount && (!familiarPool.isEmpty || !discoveryPool.isEmpty) {
            let shouldPreferDiscovery = configuration.discoveryInterval > 0 &&
                !discoveryPool.isEmpty &&
                ((runningSelection.count + 1) % configuration.discoveryInterval == 0)

            if let nextCandidate = takeNextCandidate(
                preferDiscovery: shouldPreferDiscovery,
                familiarPool: &familiarPool,
                discoveryPool: &discoveryPool,
                runningSelection: runningSelection,
                selectedIDs: &selectedIDs,
                selectedSignatures: &selectedSignatures
            ) {
                results.append(nextCandidate)
                runningSelection.append(nextCandidate)
            } else {
                break
            }
        }

        return results
    }

    private func takeNextCandidate(
        preferDiscovery: Bool,
        familiarPool: inout [ScoredRecommendationCandidate],
        discoveryPool: inout [ScoredRecommendationCandidate],
        runningSelection: [ScoredRecommendationCandidate],
        selectedIDs: inout Set<String>,
        selectedSignatures: inout Set<String>
    ) -> ScoredRecommendationCandidate? {
        let preferredSelections = preferDiscovery
            ? [PoolSelection.discovery, .familiar]
            : [PoolSelection.familiar, .discovery]

        for selection in preferredSelections {
            switch selection {
            case .familiar:
                if let candidate = popNextValidCandidate(
                    from: &familiarPool,
                    runningSelection: runningSelection,
                    selectedIDs: &selectedIDs,
                    selectedSignatures: &selectedSignatures
                ) {
                    return candidate
                }
            case .discovery:
                if let candidate = popNextValidCandidate(
                    from: &discoveryPool,
                    runningSelection: runningSelection,
                    selectedIDs: &selectedIDs,
                    selectedSignatures: &selectedSignatures
                ) {
                    return candidate
                }
            }
        }

        return nil
    }

    private func popNextValidCandidate(
        from pool: inout [ScoredRecommendationCandidate],
        runningSelection: [ScoredRecommendationCandidate],
        selectedIDs: inout Set<String>,
        selectedSignatures: inout Set<String>
    ) -> ScoredRecommendationCandidate? {
        let relaxedPasses: [(Bool, Bool)] = [
            (true, true),
            (true, false),
            (false, false),
        ]

        for pass in relaxedPasses {
            if let index = pool.firstIndex(where: { candidate in
                isValid(
                    candidate: candidate,
                    runningSelection: runningSelection,
                    selectedIDs: selectedIDs,
                    selectedSignatures: selectedSignatures,
                    enforceArtistRun: pass.0,
                    enforceSimilarity: pass.1
                )
            }) {
                let candidate = pool.remove(at: index)
                selectedIDs.insert(candidate.candidate.id)
                selectedSignatures.insert(candidate.candidate.contentSignature)
                return candidate
            }
        }

        return nil
    }

    private func isValid(
        candidate: ScoredRecommendationCandidate,
        runningSelection: [ScoredRecommendationCandidate],
        selectedIDs: Set<String>,
        selectedSignatures: Set<String>,
        enforceArtistRun: Bool,
        enforceSimilarity: Bool
    ) -> Bool {
        guard !selectedIDs.contains(candidate.candidate.id),
              !selectedSignatures.contains(candidate.candidate.contentSignature) else {
            return false
        }

        if enforceArtistRun {
            let consecutiveArtistRun = runningSelection
                .suffix(configuration.maxConsecutiveArtistTracks)
                .filter { $0.candidate.track.artistKey == candidate.candidate.track.artistKey }
                .count
            if consecutiveArtistRun >= configuration.maxConsecutiveArtistTracks {
                return false
            }
        }

        if enforceSimilarity,
           runningSelection.last?.candidate.similaritySignature == candidate.candidate.similaritySignature {
            return false
        }

        return true
    }

    private func familiarityScore(for candidate: ScoredRecommendationCandidate) -> Double {
        candidate.breakdown.artistAffinity +
            candidate.breakdown.genreAffinity +
            candidate.breakdown.tagAffinity +
            candidate.breakdown.moodAffinity +
            candidate.breakdown.likedSeedAffinity +
            candidate.breakdown.recentSeedAffinity +
            candidate.breakdown.recentArtistAffinity
    }

    private enum PoolSelection {
        case familiar
        case discovery
    }
}

struct CandidateSourceConfiguration {
    var maxArtistSeeds: Int = 3
    var maxGenreQueries: Int = 2
    var maxTagQueries: Int = 2
    var maxMoodQueries: Int = 1
    var maxTrackQueries: Int = 2
    var maxSettingsQueries: Int = 2
    var maxCandidatesPerSource: Int = 18
}

actor MyWaveCandidateSource {
    var configuration = CandidateSourceConfiguration()

    func candidates(
        for context: MyWaveRecommendationContext,
        profile: UserTasteProfile
    ) async -> [RecommendationCandidate] {
        let libraryTrackKeys = Set(context.libraryTracks.map { TrackTasteSnapshot(track: $0).identityKey })
        let librarySignatures = Set(context.libraryTracks.map { TrackTasteSnapshot(track: $0).contentSignature })

        var mergedByID: [String: RecommendationCandidate] = [:]
        var idsBySignature: [String: String] = [:]

        merge(
            candidates: localLibraryCandidates(from: context.libraryTracks),
            into: &mergedByID,
            idsBySignature: &idsBySignature
        )

        let onlineCandidates = await onlineCandidates(
            profile: profile,
            settings: context.settings,
            libraryTrackKeys: libraryTrackKeys,
            librarySignatures: librarySignatures
        )
        merge(
            candidates: onlineCandidates,
            into: &mergedByID,
            idsBySignature: &idsBySignature
        )

        return mergedByID.values.sorted { left, right in
            if left.sourceRank != right.sourceRank {
                return left.sourceRank < right.sourceRank
            }

            return left.playCount > right.playCount
        }
    }

    private func localLibraryCandidates(from tracks: [Track]) -> [RecommendationCandidate] {
        tracks
            .filter { $0.storageLocation == .library }
            .enumerated()
            .map { index, track in
                RecommendationCandidate(
                    track: TrackTasteSnapshot(track: track),
                    libraryTrack: track,
                    onlineResult: nil,
                    isInLibrary: true,
                    playCount: track.playCount,
                    lastPlayed: track.lastPlayed,
                    popularityHint: min(log1p(Double(max(track.playCount, 0))) / 3.0, 1.0),
                    discoveryBias: 0,
                    sourceRank: index,
                    origins: [.library]
                )
            }
    }

    private func onlineCandidates(
        profile: UserTasteProfile,
        settings: MyWaveSettings,
        libraryTrackKeys: Set<String>,
        librarySignatures: Set<String>
    ) async -> [RecommendationCandidate] {
        await withTaskGroup(of: [RecommendationCandidate].self) { group in
            let artistSeeds = Array(profile.preferredArtists.prefix(configuration.maxArtistSeeds))
            for (index, seed) in artistSeeds.enumerated() {
                group.addTask { [configuration] in
                    await self.artistSeedCandidates(
                        for: seed,
                        sourceRank: index,
                        maxCandidates: configuration.maxCandidatesPerSource,
                        libraryTrackKeys: libraryTrackKeys,
                        librarySignatures: librarySignatures
                    )
                }
            }

            let genreQueries = Array(profile.topGenreTerms.prefix(configuration.maxGenreQueries))
            for (index, query) in genreQueries.enumerated() {
                group.addTask { [configuration] in
                    await self.searchQueryCandidates(
                        query: query,
                        origin: .genreSearch,
                        sourceRank: 100 + index,
                        discoveryBias: 0.35,
                        maxCandidates: configuration.maxCandidatesPerSource,
                        libraryTrackKeys: libraryTrackKeys,
                        librarySignatures: librarySignatures
                    )
                }
            }

            let tagQueries = Array(profile.topTagTerms.prefix(configuration.maxTagQueries))
            for (index, query) in tagQueries.enumerated() {
                group.addTask { [configuration] in
                    await self.searchQueryCandidates(
                        query: query,
                        origin: .tagSearch,
                        sourceRank: 150 + index,
                        discoveryBias: 0.42,
                        maxCandidates: configuration.maxCandidatesPerSource,
                        libraryTrackKeys: libraryTrackKeys,
                        librarySignatures: librarySignatures
                    )
                }
            }

            let moodQueries = Array(profile.topMoodTerms.prefix(configuration.maxMoodQueries))
            for (index, query) in moodQueries.enumerated() {
                group.addTask { [configuration] in
                    await self.searchQueryCandidates(
                        query: query,
                        origin: .moodSearch,
                        sourceRank: 180 + index,
                        discoveryBias: 0.45,
                        maxCandidates: configuration.maxCandidatesPerSource,
                        libraryTrackKeys: libraryTrackKeys,
                        librarySignatures: librarySignatures
                    )
                }
            }

            let trackQueries = Array(profile.positiveSeedTracks.prefix(configuration.maxTrackQueries))
            for (index, seedTrack) in trackQueries.enumerated() {
                let query = "\(seedTrack.track.artistName) \(seedTrack.track.title)"
                group.addTask { [configuration] in
                    await self.searchQueryCandidates(
                        query: query,
                        origin: .likedTrackSearch,
                        sourceRank: 220 + index,
                        discoveryBias: 0.28,
                        maxCandidates: configuration.maxCandidatesPerSource,
                        libraryTrackKeys: libraryTrackKeys,
                        librarySignatures: librarySignatures
                    )
                }
            }

            let settingsQueries = Array(settings.searchSeedQueries.prefix(configuration.maxSettingsQueries))
            for (index, query) in settingsQueries.enumerated() {
                group.addTask { [configuration] in
                    await self.searchQueryCandidates(
                        query: query,
                        origin: .settingsSearch,
                        sourceRank: 260 + index,
                        discoveryBias: 0.33,
                        maxCandidates: configuration.maxCandidatesPerSource,
                        libraryTrackKeys: libraryTrackKeys,
                        librarySignatures: librarySignatures
                    )
                }
            }

            var aggregated: [RecommendationCandidate] = []
            for await partialResult in group {
                aggregated.append(contentsOf: partialResult)
            }

            return aggregated
        }
    }

    private func artistSeedCandidates(
        for seed: PreferredArtistSeed,
        sourceRank: Int,
        maxCandidates: Int,
        libraryTrackKeys: Set<String>,
        librarySignatures: Set<String>
    ) async -> [RecommendationCandidate] {
        if seed.provider == .soundcloud,
           let providerArtistID = seed.providerArtistID {
            let route = OnlineArtistRoute(
                provider: .soundcloud,
                providerArtistID: providerArtistID,
                artistName: seed.displayName,
                imageURL: nil,
                webpageURL: nil
            )

            if let tracks = try? await OnlineMusicService.shared.fetchSoundCloudTracks(for: route) {
                return makeOnlineCandidates(
                    from: Array(tracks.prefix(maxCandidates)),
                    origin: seed.origin,
                    sourceRank: sourceRank,
                    discoveryBias: seed.origin == .favoriteArtist ? 0.15 : 0.2,
                    libraryTrackKeys: libraryTrackKeys,
                    librarySignatures: librarySignatures
                )
            }
        }

        guard let searchResults = try? await OnlineMusicService.shared.search(seed.displayName, provider: .soundcloud) else {
            return []
        }

        let normalizedArtistName = RecommendationTextNormalizer.normalizedKey(seed.displayName)
        let matchingTracks = searchResults.tracks.filter { result in
            let snapshot = TrackTasteSnapshot(result: result)
            return snapshot.artistKey == seed.artistKey ||
                RecommendationTextNormalizer.normalizedKey(result.artist) == normalizedArtistName
        }

        let candidateResults = matchingTracks.isEmpty ? searchResults.tracks : matchingTracks
        return makeOnlineCandidates(
            from: Array(candidateResults.prefix(maxCandidates)),
            origin: seed.origin,
            sourceRank: sourceRank,
            discoveryBias: seed.origin == .favoriteArtist ? 0.15 : 0.22,
            libraryTrackKeys: libraryTrackKeys,
            librarySignatures: librarySignatures
        )
    }

    private func searchQueryCandidates(
        query: String,
        origin: RecommendationCandidateOrigin,
        sourceRank: Int,
        discoveryBias: Double,
        maxCandidates: Int,
        libraryTrackKeys: Set<String>,
        librarySignatures: Set<String>
    ) async -> [RecommendationCandidate] {
        guard let searchResults = try? await OnlineMusicService.shared.search(query, provider: .soundcloud) else {
            return []
        }

        return makeOnlineCandidates(
            from: Array(searchResults.tracks.prefix(maxCandidates)),
            origin: origin,
            sourceRank: sourceRank,
            discoveryBias: discoveryBias,
            libraryTrackKeys: libraryTrackKeys,
            librarySignatures: librarySignatures
        )
    }

    private func makeOnlineCandidates(
        from results: [OnlineTrackResult],
        origin: RecommendationCandidateOrigin,
        sourceRank: Int,
        discoveryBias: Double,
        libraryTrackKeys: Set<String>,
        librarySignatures: Set<String>
    ) -> [RecommendationCandidate] {
        results.enumerated().map { offset, result in
            let snapshot = TrackTasteSnapshot(result: result)
            let isInLibrary = libraryTrackKeys.contains(snapshot.identityKey) ||
                librarySignatures.contains(snapshot.contentSignature)
            let popularitySignal = Double(result.playbackCount ?? 0) + Double(result.likesCount ?? 0)

            return RecommendationCandidate(
                track: snapshot,
                libraryTrack: nil,
                onlineResult: result,
                isInLibrary: isInLibrary,
                playCount: 0,
                lastPlayed: nil,
                popularityHint: min(log1p(max(popularitySignal, 0)) / 14.0, 1.0),
                discoveryBias: discoveryBias,
                sourceRank: sourceRank + offset,
                origins: [origin]
            )
        }
    }

    private func merge(
        candidates: [RecommendationCandidate],
        into mergedByID: inout [String: RecommendationCandidate],
        idsBySignature: inout [String: String]
    ) {
        for candidate in candidates {
            if let existingCandidate = mergedByID[candidate.id] {
                mergedByID[candidate.id] = preferredCandidate(between: existingCandidate, and: candidate)
                continue
            }

            if let existingID = idsBySignature[candidate.contentSignature],
               let existingCandidate = mergedByID[existingID] {
                mergedByID[existingID] = preferredCandidate(between: existingCandidate, and: candidate)
                continue
            }

            mergedByID[candidate.id] = candidate
            idsBySignature[candidate.contentSignature] = candidate.id
        }
    }

    private func preferredCandidate(
        between existing: RecommendationCandidate,
        and newValue: RecommendationCandidate
    ) -> RecommendationCandidate {
        var mergedCandidate = existing
        mergedCandidate.origins.formUnion(newValue.origins)

        if existing.isInLibrary != newValue.isInLibrary {
            return existing.isInLibrary ? mergedWithPrimary(newValue, mergedCandidate) : mergedCandidate
        }

        if existing.sourceRank != newValue.sourceRank {
            return existing.sourceRank < newValue.sourceRank
                ? mergedCandidate
                : mergedWithPrimary(newValue, mergedCandidate)
        }

        return existing.popularityHint >= newValue.popularityHint
            ? mergedCandidate
            : mergedWithPrimary(newValue, mergedCandidate)
    }

    private func mergedWithPrimary(
        _ primary: RecommendationCandidate,
        _ mergedCandidate: RecommendationCandidate
    ) -> RecommendationCandidate {
        RecommendationCandidate(
            track: primary.track,
            libraryTrack: primary.libraryTrack ?? mergedCandidate.libraryTrack,
            onlineResult: primary.onlineResult ?? mergedCandidate.onlineResult,
            isInLibrary: primary.isInLibrary || mergedCandidate.isInLibrary,
            playCount: max(primary.playCount, mergedCandidate.playCount),
            lastPlayed: primary.lastPlayed ?? mergedCandidate.lastPlayed,
            popularityHint: max(primary.popularityHint, mergedCandidate.popularityHint),
            discoveryBias: max(primary.discoveryBias, mergedCandidate.discoveryBias),
            sourceRank: min(primary.sourceRank, mergedCandidate.sourceRank),
            origins: mergedCandidate.origins
        )
    }
}

actor MyWaveRecommendationService {
    static let shared = MyWaveRecommendationService()

    private let historyStore: ListeningHistoryStore
    private let candidateSource: MyWaveCandidateSource
    private let profileBuilder: UserTasteProfileBuilder
    private let recommendationEngine: RecommendationEngine
    private let cacheFileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var cachedSnapshot: MyWaveRecommendationSnapshot?

    init(
        historyStore: ListeningHistoryStore = .shared,
        candidateSource: MyWaveCandidateSource = MyWaveCandidateSource(),
        profileBuilder: UserTasteProfileBuilder = UserTasteProfileBuilder(),
        recommendationEngine: RecommendationEngine = RecommendationEngine(),
        cacheFileURL: URL = AppFileManager.shared.dataFileURL(named: "my_wave_cache.json")
    ) {
        self.historyStore = historyStore
        self.candidateSource = candidateSource
        self.profileBuilder = profileBuilder
        self.recommendationEngine = recommendationEngine
        self.cacheFileURL = cacheFileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        AppFileManager.shared.prepareDirectories()
    }

    func cachedRecommendations(matching settings: MyWaveSettings? = nil) -> MyWaveRecommendationSnapshot? {
        if let cachedSnapshot {
            guard settings == nil || cachedSnapshot.settings == settings else {
                return nil
            }
            return cachedSnapshot
        }

        guard let data = try? Data(contentsOf: cacheFileURL),
              let decodedSnapshot = try? decoder.decode(MyWaveRecommendationSnapshot.self, from: data) else {
            return nil
        }

        cachedSnapshot = decodedSnapshot
        guard settings == nil || decodedSnapshot.settings == settings else {
            return nil
        }
        return decodedSnapshot
    }

    func recommendations(
        for context: MyWaveRecommendationContext,
        now: Date = Date()
    ) async -> MyWaveRecommendationSnapshot {
        let history = await historyStore.snapshot()
        let profile = profileBuilder.build(context: context, history: history, now: now)
        let candidates = await candidateSource.candidates(for: context, profile: profile)
        let currentTrackKey = context.currentTrack.map { TrackTasteSnapshot(track: $0).identityKey }
        let rankedCandidates = recommendationEngine.rank(
            candidates: candidates,
            profile: profile,
            currentTrackKey: currentTrackKey,
            settings: context.settings
        )

        let items = rankedCandidates.map(MyWaveRecommendationItem.init)
        if items.isEmpty,
           !context.libraryTracks.isEmpty,
           let cachedSnapshot = cachedRecommendations(matching: context.settings) {
            return cachedSnapshot
        }

        let snapshot = MyWaveRecommendationSnapshot(
            items: items,
            summaryLine: summaryLine(profile: profile, settings: context.settings),
            generatedAt: now,
            settings: context.settings
        )

        cachedSnapshot = snapshot
        persistCache(snapshot)
        await historyStore.recordImpressions(for: Array(items.prefix(8)), shownAt: now)
        return snapshot
    }

    private func persistCache(_ snapshot: MyWaveRecommendationSnapshot) {
        guard let encodedSnapshot = try? encoder.encode(snapshot) else {
            return
        }

        try? encodedSnapshot.write(to: cacheFileURL, options: .atomic)
    }

    private func summaryLine(profile: UserTasteProfile, settings: MyWaveSettings) -> String {
        guard settings.isCustomized else {
            return profile.summaryLine
        }

        return "\(profile.summaryLine) Tuned to your My Wave filters."
    }
}
