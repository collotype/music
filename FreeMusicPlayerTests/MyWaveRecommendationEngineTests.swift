import XCTest
@testable import FreeMusicPlayer

final class MyWaveRecommendationEngineTests: XCTestCase {
    func testTasteProfileBuildsPositiveAndNegativeSignalsFromHistory() {
        let favoriteTrack = makeTrack(
            id: "library-1",
            sourceID: "soundcloud:track:1",
            title: "Night Drive",
            artist: "Aurora Lane",
            genres: ["Indie Pop"],
            tags: ["chill", "night"],
            playCount: 3
        )
        let skippedTrack = makeTrack(
            id: "library-2",
            sourceID: "soundcloud:track:2",
            title: "Static Rush",
            artist: "Noise Unit",
            genres: ["Industrial"],
            tags: ["harsh"],
            playCount: 0
        )

        let history = ListeningHistorySnapshot(
            events: [
                ListeningEvent(kind: .finishedPlayback, track: TrackTasteSnapshot(track: favoriteTrack)),
                ListeningEvent(kind: .quickSkip, track: TrackTasteSnapshot(track: skippedTrack)),
                ListeningEvent(kind: .quickSkip, track: TrackTasteSnapshot(track: skippedTrack)),
            ],
            impressions: []
        )

        let profile = UserTasteProfileBuilder().build(
            context: MyWaveRecommendationContext(
                libraryTracks: [favoriteTrack],
                favoriteArtists: [],
                currentTrack: nil,
                settings: .default
            ),
            history: history,
            now: Date()
        )

        XCTAssertGreaterThan(profile.artistAffinities[TrackTasteSnapshot(track: favoriteTrack).artistKey] ?? 0, 0)
        XCTAssertTrue(profile.topTagTerms.contains("chill"))
        XCTAssertTrue(profile.blockedTrackKeys.contains(TrackTasteSnapshot(track: skippedTrack).identityKey))
    }

    func testScorePrefersFavoriteArtistAndMatchingTags() {
        let seedTrack = makeTrack(
            id: "seed-1",
            sourceID: "soundcloud:seed:1",
            title: "Afterglow",
            artist: "Solar Echo",
            genres: ["Synthwave"],
            tags: ["retro", "night"],
            playCount: 4
        )
        let profile = UserTasteProfileBuilder().build(
            context: MyWaveRecommendationContext(
                libraryTracks: [seedTrack],
                favoriteArtists: [],
                currentTrack: nil,
                settings: .default
            ),
            history: ListeningHistorySnapshot(
                events: [ListeningEvent(kind: .finishedPlayback, track: TrackTasteSnapshot(track: seedTrack))],
                impressions: []
            ),
            now: Date()
        )

        let strongCandidate = makeOnlineCandidate(
            id: "online-1",
            title: "Midnight Circuit",
            artist: "Solar Echo",
            genres: ["synthwave"],
            tags: ["retro", "night"],
            origin: .favoriteArtist,
            sourceRank: 0
        )
        let weakCandidate = makeOnlineCandidate(
            id: "online-2",
            title: "Dust Plains",
            artist: "Cactus Motel",
            genres: ["country"],
            tags: ["road"],
            origin: .exploration,
            sourceRank: 1
        )

        let engine = RecommendationEngine()
        let strongScore = engine.score(candidate: strongCandidate, profile: profile, settings: .default).totalScore
        let weakScore = engine.score(candidate: weakCandidate, profile: profile, settings: .default).totalScore

        XCTAssertGreaterThan(strongScore, weakScore)
    }

    func testRankingExcludesLibraryTracksWhenEnoughRemoteAlternativesExist() {
        let libraryTrack = makeTrack(
            id: "library-a",
            sourceID: "soundcloud:library:a",
            title: "Blue Hour",
            artist: "Signal Bloom",
            genres: ["dream pop"],
            tags: ["hazy"],
            playCount: 2
        )
        let profile = UserTasteProfileBuilder().build(
            context: MyWaveRecommendationContext(
                libraryTracks: [libraryTrack],
                favoriteArtists: [],
                currentTrack: nil,
                settings: .default
            ),
            history: ListeningHistorySnapshot.empty,
            now: Date()
        )

        let inLibraryCandidate = RecommendationCandidate(
            track: TrackTasteSnapshot(track: libraryTrack),
            libraryTrack: libraryTrack,
            onlineResult: nil,
            isInLibrary: true,
            playCount: libraryTrack.playCount,
            lastPlayed: nil,
            popularityHint: 0.3,
            discoveryBias: 0,
            sourceRank: 0,
            origins: [.library]
        )
        let remoteA = makeOnlineCandidate(
            id: "remote-a",
            title: "Blue Nova",
            artist: "Signal Bloom",
            genres: ["dream pop"],
            tags: ["hazy"],
            origin: .favoriteArtist,
            sourceRank: 1
        )
        let remoteB = makeOnlineCandidate(
            id: "remote-b",
            title: "Echo Thread",
            artist: "Signal Bloom",
            genres: ["dream pop"],
            tags: ["night"],
            origin: .frequentArtist,
            sourceRank: 2
        )

        var engine = RecommendationEngine()
        engine.configuration.targetCount = 2

        let ranked = engine.rank(
            candidates: [inLibraryCandidate, remoteA, remoteB],
            profile: profile,
            currentTrackKey: nil,
            settings: .default
        )

        XCTAssertEqual(ranked.count, 2)
        XCTAssertTrue(ranked.allSatisfy { !$0.candidate.isInLibrary })
    }

    func testDiversificationAvoidsArtistRuns() {
        let profile = UserTasteProfile(
            artistAffinities: ["artist-a": 3, "artist-b": 2.4],
            genreAffinities: ["electronic": 1.2],
            tagAffinities: ["night": 0.8],
            moodAffinities: [:],
            recentArtistAffinities: [:],
            recentGenreAffinities: [:],
            libraryTrackKeys: [],
            blockedTrackKeys: [],
            recentlyShownTrackKeys: [],
            recentlyPlayedTrackKeys: [],
            quickSkipCounts: [:],
            positiveSeedTracks: [],
            recentSeedTracks: [],
            preferredArtists: [],
            topGenreTerms: [],
            topTagTerms: [],
            topMoodTerms: []
        )

        let artistA = (0..<4).map { index in
            makeOnlineCandidate(
                id: "artist-a-\(index)",
                title: "Artist A \(index)",
                artist: "Artist A",
                genres: ["electronic"],
                tags: ["night"],
                artistKey: "artist-a",
                origin: .favoriteArtist,
                sourceRank: index
            )
        }
        let artistB = (0..<3).map { index in
            makeOnlineCandidate(
                id: "artist-b-\(index)",
                title: "Artist B \(index)",
                artist: "Artist B",
                genres: ["electronic"],
                tags: ["night"],
                artistKey: "artist-b",
                origin: .frequentArtist,
                sourceRank: 10 + index
            )
        }

        var engine = RecommendationEngine()
        engine.configuration.targetCount = 4
        engine.configuration.maxConsecutiveArtistTracks = 1

        let ranked = engine.rank(
            candidates: artistA + artistB,
            profile: profile,
            currentTrackKey: nil,
            settings: .default
        )

        let artistKeys = ranked.map(\.candidate.track.artistKey)
        for pair in zip(artistKeys, artistKeys.dropFirst()) {
            XCTAssertNotEqual(pair.0, pair.1)
        }
    }

    func testSettingsBoostFocusesInstrumentalWorkCandidates() {
        let profile = UserTasteProfile(
            artistAffinities: [:],
            genreAffinities: [:],
            tagAffinities: [:],
            moodAffinities: [:],
            recentArtistAffinities: [:],
            recentGenreAffinities: [:],
            libraryTrackKeys: [],
            blockedTrackKeys: [],
            recentlyShownTrackKeys: [],
            recentlyPlayedTrackKeys: [],
            quickSkipCounts: [:],
            positiveSeedTracks: [],
            recentSeedTracks: [],
            preferredArtists: [],
            topGenreTerms: [],
            topTagTerms: [],
            topMoodTerms: []
        )

        let instrumentalCandidate = makeOnlineCandidate(
            id: "focus-1",
            title: "Focus Bloom",
            artist: "Night Signals",
            genres: ["ambient"],
            tags: ["instrumental", "focus"],
            origin: .settingsSearch,
            sourceRank: 0
        )
        let vocalCandidate = makeOnlineCandidate(
            id: "focus-2",
            title: "Summer Call",
            artist: "City Parade",
            genres: ["pop"],
            tags: ["vocal", "bright"],
            origin: .exploration,
            sourceRank: 1
        )

        let settings = MyWaveSettings(
            activity: .work,
            vibe: .unknown,
            mood: .calm,
            language: .instrumental
        )

        let engine = RecommendationEngine()
        let instrumentalScore = engine.score(candidate: instrumentalCandidate, profile: profile, settings: settings).totalScore
        let vocalScore = engine.score(candidate: vocalCandidate, profile: profile, settings: settings).totalScore

        XCTAssertGreaterThan(instrumentalScore, vocalScore)
    }

    private func makeTrack(
        id: String,
        sourceID: String,
        title: String,
        artist: String,
        genres: [String],
        tags: [String],
        playCount: Int
    ) -> Track {
        Track(
            id: id,
            title: title,
            artist: artist,
            album: nil,
            genres: genres,
            tags: tags,
            moods: [],
            duration: 180,
            source: .soundcloud,
            playCount: playCount,
            lastPlayed: Date(),
            sourceID: sourceID,
            storageLocation: .library,
            providerArtistID: "artist:\(artist)"
        )
    }

    private func makeOnlineCandidate(
        id: String,
        title: String,
        artist: String,
        genres: [String],
        tags: [String],
        artistKey: String? = nil,
        origin: RecommendationCandidateOrigin,
        sourceRank: Int
    ) -> RecommendationCandidate {
        let result = OnlineTrackResult(
            provider: .soundcloud,
            providerTrackURN: id,
            providerArtistID: artistKey ?? "artist:\(artist)",
            title: title,
            artist: artist,
            album: nil,
            genres: genres,
            tags: tags,
            moods: [],
            duration: 180,
            coverArtURL: nil,
            artistImageURL: nil,
            webpageURL: "https://soundcloud.com/\(id)",
            artistWebpageURL: nil,
            playbackCount: 10_000,
            likesCount: 600,
            releaseDate: nil,
            directAudioURL: nil,
            directFileExtension: nil,
            trackAuthorization: nil,
            playbackStreams: [
                SoundCloudStreamCandidate(
                    kind: .progressiveMP3,
                    transcodingURL: "https://example.com/\(id)",
                    protocolName: "progressive",
                    mimeType: "audio/mpeg",
                    isLegacy: false
                )
            ]
        )
        let snapshot = TrackTasteSnapshot(result: result)

        return RecommendationCandidate(
            track: TrackTasteSnapshot(
                trackID: snapshot.trackID,
                sourceID: snapshot.sourceID,
                title: snapshot.title,
                artistName: snapshot.artistName,
                artistKey: artistKey ?? snapshot.artistKey,
                providerArtistID: snapshot.providerArtistID,
                source: snapshot.source,
                album: snapshot.album,
                genres: snapshot.genres,
                tags: snapshot.tags,
                moods: snapshot.moods,
                duration: snapshot.duration
            ),
            libraryTrack: nil,
            onlineResult: result,
            isInLibrary: false,
            playCount: 0,
            lastPlayed: nil,
            popularityHint: 0.7,
            discoveryBias: origin == .exploration ? 0.5 : 0.2,
            sourceRank: sourceRank,
            origins: [origin]
        )
    }
}
