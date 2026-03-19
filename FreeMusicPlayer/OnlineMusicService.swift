//
//  OnlineMusicService.swift
//  FreeMusicPlayer
//
//  Foreground-only online music search and retrieval that runs directly inside
//  the app process without an external backend.
//

import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

enum OnlineTrackProvider: String, Equatable, CaseIterable, Identifiable {
    case soundcloud = "soundcloud"
    case spotify = "spotify"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .soundcloud:
            return "SoundCloud"
        case .spotify:
            return "Spotify"
        }
    }

    var trackSource: Track.TrackSource {
        switch self {
        case .soundcloud:
            return .soundcloud
        case .spotify:
            return .spotify
        }
    }
}

struct SoundCloudStreamCandidate: Equatable {
    enum StreamKind: String, Equatable {
        case hlsAAC160 = "hls_aac_160_url"
        case hlsAAC96 = "hls_aac_96_url"
        case hlsAAC = "hls_aac_url"
        case hlsMP3 = "hls_mp3_url"
        case progressiveMP3 = "progressive_mp3_url"
        case hlsOpus = "hls_opus_url"
    }

    let kind: StreamKind
    let transcodingURL: String
    let protocolName: String
    let mimeType: String
    let isLegacy: Bool

    var requiresDRM: Bool {
        let normalizedProtocol = protocolName.lowercased()
        return normalizedProtocol.contains("encrypted") ||
            normalizedProtocol.contains("ctr") ||
            normalizedProtocol.contains("cbc")
    }

    var isPlainHLS: Bool {
        protocolName.lowercased() == "hls"
    }

    var isProgressive: Bool {
        protocolName.lowercased() == "progressive"
    }
}

struct OnlineSearchResults: Equatable {
    let tracks: [OnlineTrackResult]
    let artists: [OnlineArtistResult]
    let albums: [OnlineAlbumResult]
    let playlists: [OnlinePlaylistResult]

    static let empty = OnlineSearchResults(
        tracks: [],
        artists: [],
        albums: [],
        playlists: []
    )

    var isEmpty: Bool {
        tracks.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty
    }
}

struct OnlineTrackResult: Identifiable, Equatable {
    let provider: OnlineTrackProvider
    let providerTrackURN: String
    let title: String
    let artist: String
    let album: String?
    let duration: TimeInterval
    let coverArtURL: String?
    let webpageURL: String
    let directAudioURL: String?
    let directFileExtension: String?
    let trackAuthorization: String?
    let playbackStreams: [SoundCloudStreamCandidate]

    var providerTrackID: String {
        providerTrackURN
    }

    var id: String {
        "\(provider.rawValue):\(providerTrackURN)"
    }

    var formattedDuration: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var providerDisplayName: String {
        provider.displayName
    }

    var trackSource: Track.TrackSource {
        provider.trackSource
    }

    var supportsInAppPlayback: Bool {
        switch provider {
        case .soundcloud:
            return !playbackStreams.isEmpty
        case .spotify:
            return false
        }
    }

    var supportsOfflineDownload: Bool {
        switch provider {
        case .soundcloud:
            return playbackStreams.contains { $0.kind == .progressiveMP3 }
        case .spotify:
            return false
        }
    }

    var detailLine: String {
        let pieces = [
            cleanedDisplayText(artist),
            cleanedDisplayText(album),
            providerDisplayName
        ].compactMap { $0 }

        return pieces.joined(separator: " | ")
    }

    var externalURL: URL? {
        guard let parsedURL = URL(string: webpageURL),
              let scheme = parsedURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return parsedURL
    }

    var playbackUnavailableMessage: String {
        switch provider {
        case .soundcloud:
            return "Playback is not available for this SoundCloud track right now."
        case .spotify:
            return "Spotify results are metadata-only here. Open the track in Spotify instead."
        }
    }

    var offlineDownloadUnavailableMessage: String {
        switch provider {
        case .soundcloud:
            return "Offline saving is not available for this SoundCloud track."
        case .spotify:
            return "Spotify tracks cannot be downloaded or saved into the local library from this app."
        }
    }

    private func cleanedDisplayText(_ value: String?) -> String? {
        guard let value else { return nil }

        let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedValue.isEmpty ? nil : cleanedValue
    }
}

struct OnlineArtistResult: Identifiable, Equatable {
    let provider: OnlineTrackProvider
    let providerArtistID: String
    let name: String
    let imageURL: String?
    let webpageURL: String

    var id: String {
        "\(provider.rawValue):artist:\(providerArtistID)"
    }

    var providerDisplayName: String {
        provider.displayName
    }

    var externalURL: URL? {
        guard let parsedURL = URL(string: webpageURL),
              let scheme = parsedURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return parsedURL
    }
}

struct OnlineAlbumResult: Identifiable, Equatable {
    let provider: OnlineTrackProvider
    let providerAlbumID: String
    let title: String
    let artist: String
    let coverArtURL: String?
    let webpageURL: String

    var id: String {
        "\(provider.rawValue):album:\(providerAlbumID)"
    }

    var providerDisplayName: String {
        provider.displayName
    }

    var externalURL: URL? {
        guard let parsedURL = URL(string: webpageURL),
              let scheme = parsedURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return parsedURL
    }
}

struct OnlinePlaylistResult: Identifiable, Equatable {
    let provider: OnlineTrackProvider
    let providerPlaylistID: String
    let title: String
    let ownerName: String?
    let coverArtURL: String?
    let webpageURL: String
    let trackCount: Int?

    var id: String {
        "\(provider.rawValue):playlist:\(providerPlaylistID)"
    }

    var providerDisplayName: String {
        provider.displayName
    }

    var externalURL: URL? {
        guard let parsedURL = URL(string: webpageURL),
              let scheme = parsedURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return parsedURL
    }
}

struct ResolvedAudioStream {
    let url: URL
    let providerName: String
    let streamType: String
}

enum OnlineMusicServiceError: LocalizedError, Equatable {
    case invalidQuery
    case noResults(String)
    case timedOut(String)
    case networkFailure(String)
    case unsupportedSource(String)
    case invalidAudioURL(String)
    case extractionFailure(String)
    case tempFileWriteFailure(String)
    case unavailableSources
    case authenticationRequired(String)
    case configurationMissing(String)

    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "Enter a search query first."
        case .noResults(let message):
            return message
        case .timedOut(let message):
            return message
        case .networkFailure(let message):
            return message
        case .unsupportedSource(let message):
            return message
        case .invalidAudioURL(let message):
            return message
        case .extractionFailure(let message):
            return message
        case .tempFileWriteFailure(let message):
            return message
        case .unavailableSources:
            return "The selected online provider is unavailable right now."
        case .authenticationRequired(let message):
            return message
        case .configurationMissing(let message):
            return message
        }
    }
}

final class OnlineMusicService {
    static let shared = OnlineMusicService()

    private let fileManager = FileManager.default
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let soundCloudRuntimeState = SoundCloudRuntimeState()
    private let spotifyRuntimeState = SpotifyRuntimeState()

    private let soundCloudHomepageURL = URL(string: "https://soundcloud.com")!
    private let soundCloudSearchURL = URL(string: "https://api-v2.soundcloud.com/search/tracks")!
    private let bundledFallbackClientIDs = [
        "GXG1PaJ1dcHGVX1lHIIbldZN7ZiUBJP7",
    ]

    private let spotifyAuthorizationURL = URL(string: "https://accounts.spotify.com/authorize")!
    private let spotifyTokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    private let spotifySearchURL = URL(string: "https://api.spotify.com/v1/search")!
    private let defaultSpotifyRedirectURI = "com.collotype.freemusic://spotify-auth-callback"
    private let spotifySearchLimit = 12

    // Required Info.plist setup for Spotify search:
    // SpotifyClientID = <your client id>
    //
    // Optional Info.plist overrides:
    // SpotifyRedirectURI = com.collotype.freemusic://spotify-auth-callback
    // SpotifyMarket = US
    private enum SpotifyInfoPlistKeys {
        static let clientID = "SpotifyClientID"
        static let redirectURI = "SpotifyRedirectURI"
        static let market = "SpotifyMarket"
    }

    private let browserUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    private let soundCloudAssetPattern = #"https://a-v2\.sndcdn\.com/assets/[^"']+\.js"#
    private let soundCloudClientIDPatterns = [
        #"client_id:"([A-Za-z0-9]{8,})""#,
        #"client_id\s*:\s*"([A-Za-z0-9]{8,})""#,
        #"client_id\s*=\s*"([A-Za-z0-9]{8,})""#,
    ]

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 25
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    var isSpotifyConfigured: Bool {
        spotifyConfigurationStatus.isEnabled
    }

    func search(_ query: String, provider: OnlineTrackProvider) async throws -> OnlineSearchResults {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw OnlineMusicServiceError.invalidQuery
        }

        debugLog("Selected provider: \(provider.displayName)")
        debugLog("Online query entered: \(trimmedQuery)")

        switch provider {
        case .soundcloud:
            return try await searchViaSoundCloud(query: trimmedQuery)
        case .spotify:
            return try await searchViaSpotify(query: trimmedQuery)
        }
    }

    func authorizeSpotify() async throws {
        let configuration = try spotifyConfigurationOrThrow()
        await logSpotifyConfigurationState(configuration)
        _ = try await spotifyAccessToken(configuration: configuration, interactive: true)
    }

    func resolvePlaybackStream(for result: OnlineTrackResult) async throws -> ResolvedAudioStream {
        guard result.provider == .soundcloud else {
            throw OnlineMusicServiceError.unsupportedSource(result.playbackUnavailableMessage)
        }

        guard !result.providerTrackURN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OnlineMusicServiceError.unsupportedSource(
                "Unsupported source. The selected SoundCloud result does not contain a valid track URN."
            )
        }

        debugLog("Selected track URN: \(result.providerTrackURN)")
        debugLog("Resolution start for \(result.providerTrackURN)")

        let clientID = try await soundCloudClientID()
        let playbackCandidates = orderedPlaybackCandidates(from: result.playbackStreams)

        if let chosenCandidate = playbackCandidates.first {
            if chosenCandidate.kind == .progressiveMP3 {
                debugLog("Chosen stream URL type: \(chosenCandidate.kind.rawValue) (SoundCloud fallback)")
            } else {
                debugLog("Chosen stream URL type: \(chosenCandidate.kind.rawValue)")
            }

            let finalURL = try await resolveSoundCloudStreamURL(
                for: chosenCandidate,
                trackAuthorization: result.trackAuthorization,
                clientID: clientID
            )

            debugLog("Resolution end for \(result.providerTrackURN): \(finalURL.absoluteString)")

            return ResolvedAudioStream(
                url: finalURL,
                providerName: result.providerDisplayName,
                streamType: chosenCandidate.kind.rawValue
            )
        }

        if result.playbackStreams.contains(where: { $0.kind == .hlsAAC160 || $0.kind == .hlsAAC96 || $0.kind == .hlsAAC }) {
            debugLog("Stream resolution error: only DRM-protected AAC HLS variants available for \(result.providerTrackURN)")
            throw OnlineMusicServiceError.unsupportedSource(
                "This SoundCloud track only exposes DRM-protected AAC HLS streams, and the app cannot play them directly yet."
            )
        }

        debugLog("Stream resolution error: no playable SoundCloud stream for \(result.providerTrackURN)")
        throw OnlineMusicServiceError.extractionFailure(
            "SoundCloud returned no playable streams for this track."
        )
    }

    func downloadAudio(for result: OnlineTrackResult) async throws -> URL {
        guard result.provider == .soundcloud else {
            throw OnlineMusicServiceError.unsupportedSource(result.offlineDownloadUnavailableMessage)
        }

        guard !result.providerTrackURN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OnlineMusicServiceError.unsupportedSource(
                "Unsupported source. The selected SoundCloud result does not contain a valid track URN."
            )
        }

        if let cachedURL = cachedTemporaryFile(for: result.id) {
            debugLog("Using cached temp audio for \(result.id): \(cachedURL.path)")
            return cachedURL
        }

        let clientID = try await soundCloudClientID()
        let downloadCandidates = orderedDownloadCandidates(from: result.playbackStreams)

        guard let chosenCandidate = downloadCandidates.first else {
            debugLog("Download limitation for \(result.providerTrackURN): no offline-downloadable stream")
            throw OnlineMusicServiceError.unsupportedSource(
                "Offline saving is not available for this SoundCloud track because it only exposes streaming-only HLS audio right now."
            )
        }

        debugLog("Resolution start for \(result.providerTrackURN)")
        debugLog("Chosen stream URL type: \(chosenCandidate.kind.rawValue)")

        let finalURL = try await resolveSoundCloudStreamURL(
            for: chosenCandidate,
            trackAuthorization: result.trackAuthorization,
            clientID: clientID
        )

        debugLog("Resolution end for \(result.providerTrackURN): \(finalURL.absoluteString)")
        debugLog("Download start for \(result.providerTrackURN): \(finalURL.absoluteString)")

        var request = URLRequest(url: finalURL)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("audio/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(soundCloudHomepageURL.absoluteString, forHTTPHeaderField: "Referer")

        let temporaryDownloadURL: URL
        let response: URLResponse

        do {
            (temporaryDownloadURL, response) = try await session.download(for: request)
        } catch {
            debugLog("Download error for \(result.providerTrackURN): \(error.localizedDescription)")
            throw OnlineMusicServiceError.networkFailure(
                "Audio download failed because the SoundCloud file request could not be completed."
            )
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw OnlineMusicServiceError.networkFailure(
                "Audio download failed because SoundCloud returned HTTP \(httpResponse.statusCode)."
            )
        }

        let fileExtension = preferredFileExtension(
            mimeType: response.mimeType ?? chosenCandidate.mimeType,
            resolvedURL: finalURL
        )
        let destinationURL = AppFileManager.shared.temporaryAudioURL(for: result.id, fileExtension: fileExtension)

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            try fileManager.moveItem(at: temporaryDownloadURL, to: destinationURL)
        } catch {
            throw OnlineMusicServiceError.tempFileWriteFailure(
                "The downloaded SoundCloud audio could not be stored in temporary app storage."
            )
        }

        let fileSize = (try? fileManager.attributesOfItem(atPath: destinationURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        debugLog("Download end for \(result.providerTrackURN): \(fileSize) bytes")
        debugLog("Temp file path: \(destinationURL.path)")

        return destinationURL
    }

    private func searchViaSoundCloud(query: String) async throws -> OnlineSearchResults {
        let initialCandidates = await initialSoundCloudClientIDs()
        var attemptedClientIDs: [String] = []
        var lastExplicitError: OnlineMusicServiceError?

        for clientID in initialCandidates {
            do {
                return try await executeSoundCloudSearch(query: query, clientID: clientID)
            } catch let error as OnlineMusicServiceError {
                attemptedClientIDs.append(clientID)
                lastExplicitError = error
                debugLog("Provider error: SoundCloud using client_id \(maskedClientID(clientID)) - \(error.localizedDescription)")
            } catch {
                attemptedClientIDs.append(clientID)
                let wrappedError = OnlineMusicServiceError.networkFailure(
                    "SoundCloud search failed because the provider request could not be completed."
                )
                lastExplicitError = wrappedError
                debugLog("Provider error: SoundCloud using client_id \(maskedClientID(clientID)) - \(error.localizedDescription)")
            }
        }

        if let discoveredClientID = try? await discoverSoundCloudClientID(),
           !attemptedClientIDs.contains(discoveredClientID) {
            do {
                return try await executeSoundCloudSearch(query: query, clientID: discoveredClientID)
            } catch let error as OnlineMusicServiceError {
                lastExplicitError = error
                debugLog("Provider error: SoundCloud using discovered client_id \(maskedClientID(discoveredClientID)) - \(error.localizedDescription)")
            } catch {
                let wrappedError = OnlineMusicServiceError.networkFailure(
                    "SoundCloud search failed because the provider request could not be completed."
                )
                lastExplicitError = wrappedError
                debugLog("Provider error: SoundCloud using discovered client_id \(maskedClientID(discoveredClientID)) - \(error.localizedDescription)")
            }
        }

        if let lastExplicitError {
            throw lastExplicitError
        }

        debugLog("Provider error: SoundCloud - unavailable sources")
        throw OnlineMusicServiceError.unavailableSources
    }

    private func executeSoundCloudSearch(query: String, clientID: String) async throws -> OnlineSearchResults {
        debugLog("Provider start: SoundCloud for query \(query) using client_id \(maskedClientID(clientID))")

        let tracks = try await searchTracksViaSoundCloud(query: query, clientID: clientID)
        let finalTracks = Array(tracks.prefix(20))
        let results = makeSoundCloudSearchResults(from: finalTracks)
        await soundCloudRuntimeState.setClientID(clientID)

        logMappedResultCounts(provider: .soundcloud, results: results)
        debugLog(
            "Provider finish: SoundCloud with tracks=\(results.tracks.count), artists=\(results.artists.count), albums=\(results.albums.count), playlists=\(results.playlists.count)"
        )

        guard !results.isEmpty else {
            throw OnlineMusicServiceError.noResults("No SoundCloud results were found for \"\(query)\".")
        }

        return results
    }

    private func searchTracksViaSoundCloud(query: String, clientID: String) async throws -> [OnlineTrackResult] {
        var components = URLComponents(url: soundCloudSearchURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "offset", value: "0")
        ]

        guard let requestURL = components?.url else {
            throw OnlineMusicServiceError.networkFailure("SoundCloud search URL could not be created.")
        }

        let data = try await fetchSoundCloudData(from: requestURL, accept: "application/json, text/plain, */*")

        let response: SoundCloudSearchResponse
        do {
            response = try decoder.decode(SoundCloudSearchResponse.self, from: data)
        } catch {
            throw OnlineMusicServiceError.extractionFailure("SoundCloud search returned malformed JSON.")
        }

        return deduplicatedTrackResults(
            response.collection.compactMap { makeOnlineTrackResult(from: $0) }
        )
    }

    private func searchViaSpotify(query: String) async throws -> OnlineSearchResults {
        let configuration = try spotifyConfigurationOrThrow()
        await logSpotifyConfigurationState(configuration)
        let accessToken = try await spotifyAccessToken(configuration: configuration, interactive: false)

        debugLog("Provider start: Spotify for query \(query)")

        var components = URLComponents(url: spotifySearchURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track,artist,album,playlist"),
            URLQueryItem(name: "limit", value: String(spotifySearchLimit)),
            URLQueryItem(name: "market", value: configuration.market)
        ]

        guard let requestURL = components?.url else {
            throw OnlineMusicServiceError.networkFailure("Spotify search URL could not be created.")
        }

        let data = try await fetchSpotifyData(from: requestURL, accessToken: accessToken)

        let response: SpotifySearchResponse
        do {
            response = try decoder.decode(SpotifySearchResponse.self, from: data)
        } catch {
            throw OnlineMusicServiceError.extractionFailure("Spotify search returned malformed JSON.")
        }

        let results = OnlineSearchResults(
            tracks: deduplicatedTrackResults(
                response.tracks?.items.compactMap { makeOnlineTrackResult(from: $0) } ?? []
            ),
            artists: deduplicatedArtistResults(
                response.artists?.items.compactMap { makeOnlineArtistResult(from: $0) } ?? []
            ),
            albums: deduplicatedAlbumResults(
                response.albums?.items.compactMap { makeOnlineAlbumResult(from: $0) } ?? []
            ),
            playlists: deduplicatedPlaylistResults(
                response.playlists?.items.compactMap { makeOnlinePlaylistResult(from: $0) } ?? []
            )
        )

        logMappedResultCounts(provider: .spotify, results: results)
        debugLog(
            "Provider finish: Spotify with tracks=\(results.tracks.count), artists=\(results.artists.count), albums=\(results.albums.count), playlists=\(results.playlists.count)"
        )

        guard !results.isEmpty else {
            throw OnlineMusicServiceError.noResults("No Spotify results were found for \"\(query)\".")
        }

        return results
    }

    private func spotifyAccessToken(
        configuration: SpotifyConfiguration,
        interactive: Bool
    ) async throws -> String {
        if let accessToken = await spotifyRuntimeState.validAccessToken(referenceDate: Date()) {
            debugLog("Spotify auth state: using cached access token")
            return accessToken
        }

        if let refreshToken = await spotifyRuntimeState.refreshToken {
            debugLog("Spotify auth state: refreshing access token")

            do {
                let refreshedCredentials = try await refreshSpotifyAccessToken(
                    refreshToken: refreshToken,
                    configuration: configuration
                )
                await spotifyRuntimeState.setCredentials(refreshedCredentials)
                return refreshedCredentials.accessToken
            } catch {
                debugLog("Spotify token refresh failed: \(error.localizedDescription)")
                await spotifyRuntimeState.clearCredentials()
            }
        }

        guard interactive else {
            throw OnlineMusicServiceError.authenticationRequired(
                "Connect Spotify to search its catalog."
            )
        }

        let credentials = try await authorizeSpotifyInteractively(configuration: configuration)
        return credentials.accessToken
    }

    @MainActor
    private func authorizeSpotifyInteractively(
        configuration: SpotifyConfiguration
    ) async throws -> SpotifyCredentials {
        debugLog("Spotify auth start")

        let codeVerifier = makePKCECodeVerifier()
        let codeChallenge = makeCodeChallenge(from: codeVerifier)
        let state = makeOpaqueState()
        let authorizationRequestURL = try makeSpotifyAuthorizationRequestURL(
            configuration: configuration,
            codeChallenge: codeChallenge,
            state: state
        )

        let spotifyAuthCoordinator = SpotifyAuthCoordinator()
        let callbackURL = try await spotifyAuthCoordinator.authenticate(
            using: authorizationRequestURL,
            callbackURLScheme: configuration.callbackURLScheme
        )

        guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw OnlineMusicServiceError.authenticationRequired(
                "Spotify sign-in finished with an unreadable callback URL."
            )
        }

        if let errorValue = callbackComponents.queryItems?.first(where: { $0.name == "error" })?.value {
            throw OnlineMusicServiceError.authenticationRequired(
                "Spotify sign-in did not complete: \(errorValue)."
            )
        }

        guard let returnedState = callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == state else {
            throw OnlineMusicServiceError.authenticationRequired(
                "Spotify sign-in could not be verified."
            )
        }

        guard let authorizationCode = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value,
              let cleanedAuthorizationCode = cleanedText(authorizationCode) else {
            throw OnlineMusicServiceError.authenticationRequired(
                "Spotify sign-in finished without an authorization code."
            )
        }

        let credentials = try await exchangeSpotifyAuthorizationCode(
            authorizationCode: cleanedAuthorizationCode,
            codeVerifier: codeVerifier,
            configuration: configuration
        )
        await spotifyRuntimeState.setCredentials(credentials)

        debugLog("Spotify auth finish")
        return credentials
    }

    private func exchangeSpotifyAuthorizationCode(
        authorizationCode: String,
        codeVerifier: String,
        configuration: SpotifyConfiguration
    ) async throws -> SpotifyCredentials {
        let response = try await performSpotifyTokenRequest(
            bodyItems: [
                URLQueryItem(name: "grant_type", value: "authorization_code"),
                URLQueryItem(name: "code", value: authorizationCode),
                URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
                URLQueryItem(name: "client_id", value: configuration.clientID),
                URLQueryItem(name: "code_verifier", value: codeVerifier)
            ]
        )

        return SpotifyCredentials(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expirationDate: Date().addingTimeInterval(TimeInterval(max(response.expiresIn - 60, 0)))
        )
    }

    private func refreshSpotifyAccessToken(
        refreshToken: String,
        configuration: SpotifyConfiguration
    ) async throws -> SpotifyCredentials {
        let response = try await performSpotifyTokenRequest(
            bodyItems: [
                URLQueryItem(name: "grant_type", value: "refresh_token"),
                URLQueryItem(name: "refresh_token", value: refreshToken),
                URLQueryItem(name: "client_id", value: configuration.clientID)
            ]
        )

        debugLog("Spotify auth state: refresh token succeeded")

        return SpotifyCredentials(
            accessToken: response.accessToken,
            refreshToken: cleanedText(response.refreshToken) ?? refreshToken,
            expirationDate: Date().addingTimeInterval(TimeInterval(max(response.expiresIn - 60, 0)))
        )
    }

    private func performSpotifyTokenRequest(
        bodyItems: [URLQueryItem]
    ) async throws -> SpotifyTokenResponse {
        var components = URLComponents()
        components.queryItems = bodyItems

        guard let body = components.percentEncodedQuery?.data(using: .utf8) else {
            throw OnlineMusicServiceError.networkFailure("Spotify token request could not be created.")
        }

        var request = URLRequest(url: spotifyTokenURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OnlineMusicServiceError.networkFailure(
                "The Spotify token request could not be completed."
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnlineMusicServiceError.networkFailure("Spotify returned an invalid response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = spotifyTokenErrorMessage(from: data) ??
                "Spotify token exchange returned HTTP \(httpResponse.statusCode)."

            if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
                throw OnlineMusicServiceError.authenticationRequired(errorMessage)
            }

            throw OnlineMusicServiceError.networkFailure(errorMessage)
        }

        do {
            return try decoder.decode(SpotifyTokenResponse.self, from: data)
        } catch {
            throw OnlineMusicServiceError.extractionFailure("Spotify token exchange returned malformed JSON.")
        }
    }

    private func fetchSpotifyData(from url: URL, accessToken: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OnlineMusicServiceError.networkFailure(
                "The Spotify request could not be completed."
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnlineMusicServiceError.networkFailure("Spotify returned an invalid response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let providerMessage = spotifyAPIErrorMessage(from: data) ??
                "Spotify returned HTTP \(httpResponse.statusCode)."

            if httpResponse.statusCode == 401 {
                await spotifyRuntimeState.clearCredentials()
                throw OnlineMusicServiceError.authenticationRequired(
                    "Spotify authorization expired. Connect Spotify again to continue."
                )
            }

            throw OnlineMusicServiceError.networkFailure(providerMessage)
        }

        return data
    }

    private func makeSpotifyAuthorizationRequestURL(
        configuration: SpotifyConfiguration,
        codeChallenge: String,
        state: String
    ) throws -> URL {
        var components = URLComponents(url: spotifyAuthorizationURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "state", value: state)
        ]

        guard let requestURL = components?.url else {
            throw OnlineMusicServiceError.networkFailure("Spotify authorization URL could not be created.")
        }

        return requestURL
    }

    private func spotifyConfigurationOrThrow() throws -> SpotifyConfiguration {
        let status = spotifyConfigurationStatus
        logSpotifyConfigurationDiagnostics(status)

        guard let configuration = status.configuration else {
            throw OnlineMusicServiceError.configurationMissing(status.userFacingErrorMessage)
        }

        return configuration
    }

    private var spotifyConfiguration: SpotifyConfiguration? {
        spotifyConfigurationStatus.configuration
    }

    private var spotifyConfigurationStatus: SpotifyConfigurationStatus {
        let rawClientID = Bundle.main.object(forInfoDictionaryKey: SpotifyInfoPlistKeys.clientID) as? String
        let clientID = sanitizedSpotifyClientID(rawClientID)
        let rawRedirectURI = Bundle.main.object(forInfoDictionaryKey: SpotifyInfoPlistKeys.redirectURI) as? String
        let explicitRedirectURI = sanitizedSpotifyRedirectURI(rawRedirectURI)
        let resolvedRedirectURI = explicitRedirectURI ?? defaultSpotifyRedirectURI

        return SpotifyConfigurationStatus(
            clientIDKey: SpotifyInfoPlistKeys.clientID,
            redirectURIKey: SpotifyInfoPlistKeys.redirectURI,
            clientID: clientID,
            explicitRedirectURI: explicitRedirectURI,
            defaultRedirectURI: defaultSpotifyRedirectURI,
            resolvedRedirectURI: resolvedRedirectURI,
            callbackURLScheme: URL(string: resolvedRedirectURI)?.scheme,
            market: resolvedSpotifyMarket()
        )
    }

    private func resolvedSpotifyMarket() -> String {
        if let configuredMarket = Bundle.main.object(forInfoDictionaryKey: SpotifyInfoPlistKeys.market) as? String,
           let cleanedConfiguredMarket = cleanedText(configuredMarket) {
            return cleanedConfiguredMarket.uppercased()
        }

        if let regionCode = Locale.current.regionCode,
           !regionCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return regionCode.uppercased()
        }

        return "US"
    }

    private func logSpotifyConfigurationState(_ configuration: SpotifyConfiguration) async {
        logSpotifyConfigurationDiagnostics(spotifyConfigurationStatus)
        let authState = await spotifyRuntimeState.debugDescription(referenceDate: Date())
        debugLog(
            "Spotify config state: clientID=configured, redirectURI=\(configuration.redirectURI), market=\(configuration.market), auth=\(authState)"
        )
    }

    private func logSpotifyConfigurationDiagnostics(_ status: SpotifyConfigurationStatus) {
        debugLog("Spotify Info.plist client ID key checked: \(status.clientIDKey)")
        debugLog("SpotifyClientID found: \(status.isClientIDConfigured ? "yes" : "no")")
        debugLog("Spotify Info.plist redirect key checked: \(status.redirectURIKey)")
        debugLog(
            "Spotify redirect URI configured: \(status.isRedirectURIConfigured ? "yes" : "no") (\(status.usesDefaultRedirectURI ? "default" : "Info.plist"))"
        )
        debugLog("Spotify redirect URI valid: \(status.isRedirectURIValid ? "yes" : "no")")
        debugLog("Spotify redirect URI resolved: \(status.resolvedRedirectURI)")
        debugLog("Spotify provider enabled: \(status.isEnabled ? "yes" : "no")")
    }

    private func sanitizedSpotifyClientID(_ rawValue: String?) -> String? {
        guard let cleanedValue = cleanedText(rawValue) else { return nil }

        let normalizedValue = cleanedValue.lowercased()
        let placeholderMarkers = [
            "your_spotify_client_id",
            "<your client id>",
            "<your spotify client id>",
            "insert_spotify_client_id"
        ]

        if placeholderMarkers.contains(where: normalizedValue.contains) {
            return nil
        }

        if cleanedValue.hasPrefix("$(") && cleanedValue.hasSuffix(")") {
            return nil
        }

        return cleanedValue
    }

    private func sanitizedSpotifyRedirectURI(_ rawValue: String?) -> String? {
        guard let cleanedValue = cleanedText(rawValue) else { return nil }

        let normalizedValue = cleanedValue.lowercased()
        let placeholderMarkers = [
            "your_spotify_redirect_uri",
            "<your redirect uri>",
            "<your spotify redirect uri>",
            "insert_spotify_redirect_uri"
        ]

        if placeholderMarkers.contains(where: normalizedValue.contains) {
            return nil
        }

        if cleanedValue.hasPrefix("$(") && cleanedValue.hasSuffix(")") {
            return nil
        }

        return cleanedValue
    }

    private func spotifyTokenErrorMessage(from data: Data) -> String? {
        let tokenError = try? decoder.decode(SpotifyTokenErrorResponse.self, from: data)
        let errorCode = tokenError?.error?.trimmingCharacters(in: .whitespacesAndNewlines)
        let errorDescription = tokenError?.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let errorDescription, !errorDescription.isEmpty {
            return "Spotify authorization failed: \(errorDescription)"
        }

        if let errorCode, !errorCode.isEmpty {
            return "Spotify authorization failed: \(errorCode)"
        }

        return nil
    }

    private func spotifyAPIErrorMessage(from data: Data) -> String? {
        let apiError = try? decoder.decode(SpotifyAPIErrorEnvelope.self, from: data)
        guard let message = apiError?.error.message.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return nil
        }

        return "Spotify search failed: \(message)"
    }

    private func makeSoundCloudSearchResults(from tracks: [OnlineTrackResult]) -> OnlineSearchResults {
        OnlineSearchResults(
            tracks: tracks,
            artists: makeSoundCloudArtistResults(from: tracks),
            albums: makeSoundCloudAlbumResults(from: tracks),
            playlists: []
        )
    }

    private func makeSoundCloudArtistResults(from tracks: [OnlineTrackResult]) -> [OnlineArtistResult] {
        let groupedResults = Dictionary(grouping: tracks) { track in
            track.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        return groupedResults.compactMap { normalizedArtistName, groupedTracks in
            guard let representativeTrack = groupedTracks.first(where: hasRemoteArtwork) ?? groupedTracks.first,
                  let artistName = cleanedText(representativeTrack.artist),
                  let webpageURL = cleanedText(representativeTrack.webpageURL) else {
                return nil
            }

            return OnlineArtistResult(
                provider: .soundcloud,
                providerArtistID: normalizedArtistName,
                name: artistName,
                imageURL: representativeTrack.coverArtURL,
                webpageURL: webpageURL
            )
        }
        .sorted { left, right in
            left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    private func makeSoundCloudAlbumResults(from tracks: [OnlineTrackResult]) -> [OnlineAlbumResult] {
        let albumTracks = tracks.filter { track in
            cleanedText(track.album) != nil
        }

        let groupedResults = Dictionary(grouping: albumTracks) { track in
            let normalizedAlbum = track.album?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            let normalizedArtist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return "\(normalizedAlbum)::\(normalizedArtist)"
        }

        return groupedResults.compactMap { groupedID, groupedTracks in
            guard let representativeTrack = groupedTracks.first(where: hasRemoteArtwork) ?? groupedTracks.first,
                  let albumTitle = cleanedText(representativeTrack.album),
                  let artistName = cleanedText(representativeTrack.artist),
                  let webpageURL = cleanedText(representativeTrack.webpageURL) else {
                return nil
            }

            return OnlineAlbumResult(
                provider: .soundcloud,
                providerAlbumID: groupedID,
                title: albumTitle,
                artist: artistName,
                coverArtURL: representativeTrack.coverArtURL,
                webpageURL: webpageURL
            )
        }
        .sorted { left, right in
            if left.title.caseInsensitiveCompare(right.title) == .orderedSame {
                return left.artist.localizedCaseInsensitiveCompare(right.artist) == .orderedAscending
            }

            return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        }
    }

    private func makeOnlineTrackResult(from track: SoundCloudSearchTrack) -> OnlineTrackResult? {
        guard let urn = cleanedText(track.urn),
              let webpageURL = cleanedText(track.permalinkURL),
              let title = cleanedText(track.title) else {
            return nil
        }

        let streams = (track.media?.transcodings ?? []).compactMap { makeStreamCandidate(from: $0) }
        guard !streams.isEmpty else {
            return nil
        }

        let artist = cleanedText(track.publisherMetadata?.artist) ??
            cleanedText(track.user?.username) ??
            "Unknown Artist"
        let album = cleanedText(track.publisherMetadata?.albumTitle) ??
            cleanedText(track.publisherMetadata?.releaseTitle)
        let coverArtURL = normalizedArtworkURL(track.artworkURL) ??
            normalizedArtworkURL(track.user?.avatarURL)
        let resolvedDurationMilliseconds = max(track.fullDuration ?? 0, track.duration ?? 0)

        return OnlineTrackResult(
            provider: .soundcloud,
            providerTrackURN: urn,
            title: title,
            artist: artist,
            album: album,
            duration: TimeInterval(resolvedDurationMilliseconds) / 1000,
            coverArtURL: coverArtURL,
            webpageURL: webpageURL,
            directAudioURL: nil,
            directFileExtension: nil,
            trackAuthorization: cleanedText(track.trackAuthorization),
            playbackStreams: streams
        )
    }

    private func makeOnlineTrackResult(from track: SpotifyTrack) -> OnlineTrackResult? {
        guard let trackID = cleanedText(track.id),
              let title = cleanedText(track.name) else {
            return nil
        }

        let artistNames = track.artists.compactMap { cleanedText($0.name) }
        let albumName = cleanedText(track.album?.name)
        let artworkURL = spotifyArtworkURL(from: track.album?.images)
        let webpageURL = cleanedText(track.externalURLs?.spotify) ??
            "https://open.spotify.com/track/\(trackID)"

        return OnlineTrackResult(
            provider: .spotify,
            providerTrackURN: trackID,
            title: title,
            artist: artistNames.isEmpty ? "Unknown Artist" : artistNames.joined(separator: ", "),
            album: albumName,
            duration: TimeInterval(track.durationMS ?? 0) / 1000,
            coverArtURL: artworkURL,
            webpageURL: webpageURL,
            directAudioURL: nil,
            directFileExtension: nil,
            trackAuthorization: nil,
            playbackStreams: []
        )
    }

    private func makeOnlineArtistResult(from artist: SpotifyArtist) -> OnlineArtistResult? {
        guard let artistID = cleanedText(artist.id),
              let artistName = cleanedText(artist.name) else {
            return nil
        }

        let webpageURL = cleanedText(artist.externalURLs?.spotify) ??
            "https://open.spotify.com/artist/\(artistID)"

        return OnlineArtistResult(
            provider: .spotify,
            providerArtistID: artistID,
            name: artistName,
            imageURL: spotifyArtworkURL(from: artist.images),
            webpageURL: webpageURL
        )
    }

    private func makeOnlineAlbumResult(from album: SpotifyAlbum) -> OnlineAlbumResult? {
        guard let albumID = cleanedText(album.id),
              let title = cleanedText(album.name) else {
            return nil
        }

        let primaryArtist = album.artists.compactMap { cleanedText($0.name) }.first ?? "Unknown Artist"
        let webpageURL = cleanedText(album.externalURLs?.spotify) ??
            "https://open.spotify.com/album/\(albumID)"

        return OnlineAlbumResult(
            provider: .spotify,
            providerAlbumID: albumID,
            title: title,
            artist: primaryArtist,
            coverArtURL: spotifyArtworkURL(from: album.images),
            webpageURL: webpageURL
        )
    }

    private func makeOnlinePlaylistResult(from playlist: SpotifyPlaylist) -> OnlinePlaylistResult? {
        guard let playlistID = cleanedText(playlist.id),
              let title = cleanedText(playlist.name) else {
            return nil
        }

        let webpageURL = cleanedText(playlist.externalURLs?.spotify) ??
            "https://open.spotify.com/playlist/\(playlistID)"

        return OnlinePlaylistResult(
            provider: .spotify,
            providerPlaylistID: playlistID,
            title: title,
            ownerName: cleanedText(playlist.owner?.displayName) ?? cleanedText(playlist.owner?.id),
            coverArtURL: spotifyArtworkURL(from: playlist.images),
            webpageURL: webpageURL,
            trackCount: playlist.tracks?.total
        )
    }

    private func spotifyArtworkURL(from images: [SpotifyImage]?) -> String? {
        guard let images, !images.isEmpty else { return nil }

        let sortedImages = images.sorted { left, right in
            (left.width ?? 0) > (right.width ?? 0)
        }

        return sortedImages.compactMap { cleanedText($0.url) }.first
    }

    private func makeStreamCandidate(from transcoding: SoundCloudTranscoding) -> SoundCloudStreamCandidate? {
        guard let url = cleanedText(transcoding.url),
              let preset = cleanedText(transcoding.preset),
              let protocolName = cleanedText(transcoding.format?.protocolName),
              let mimeType = cleanedText(transcoding.format?.mimeType) else {
            return nil
        }

        let normalizedPreset = preset.lowercased()
        let normalizedProtocol = protocolName.lowercased()
        let normalizedMimeType = mimeType.lowercased()

        let kind: SoundCloudStreamCandidate.StreamKind
        if normalizedPreset.contains("aac_160") && normalizedProtocol.contains("hls") {
            kind = .hlsAAC160
        } else if normalizedPreset.contains("aac_96") && normalizedProtocol.contains("hls") {
            kind = .hlsAAC96
        } else if normalizedPreset.contains("aac") && normalizedProtocol.contains("hls") {
            kind = .hlsAAC
        } else if normalizedPreset.contains("mp3") && normalizedProtocol == "progressive" {
            kind = .progressiveMP3
        } else if normalizedPreset.contains("mp3") && normalizedProtocol.contains("hls") {
            kind = .hlsMP3
        } else if normalizedMimeType.contains("opus") && normalizedProtocol.contains("hls") {
            kind = .hlsOpus
        } else {
            return nil
        }

        return SoundCloudStreamCandidate(
            kind: kind,
            transcodingURL: url,
            protocolName: protocolName,
            mimeType: mimeType,
            isLegacy: transcoding.isLegacyTranscoding ?? false
        )
    }

    private func orderedPlaybackCandidates(from candidates: [SoundCloudStreamCandidate]) -> [SoundCloudStreamCandidate] {
        let directCandidates = candidates.filter { ($0.isPlainHLS || $0.isProgressive) && !$0.requiresDRM }

        let preferredOrder: [SoundCloudStreamCandidate.StreamKind] = [
            .hlsAAC160,
            .hlsAAC96,
            .hlsAAC,
            .hlsMP3,
            .progressiveMP3,
            .hlsOpus,
        ]

        return orderedCandidates(from: directCandidates, preferredOrder: preferredOrder)
    }

    private func orderedDownloadCandidates(from candidates: [SoundCloudStreamCandidate]) -> [SoundCloudStreamCandidate] {
        let directCandidates = candidates.filter { $0.isProgressive && !$0.requiresDRM }
        return orderedCandidates(from: directCandidates, preferredOrder: [.progressiveMP3])
    }

    private func orderedCandidates(
        from candidates: [SoundCloudStreamCandidate],
        preferredOrder: [SoundCloudStreamCandidate.StreamKind]
    ) -> [SoundCloudStreamCandidate] {
        var ordered: [SoundCloudStreamCandidate] = []
        var seenURLs: Set<String> = []

        for kind in preferredOrder {
            for candidate in candidates where candidate.kind == kind {
                guard seenURLs.insert(candidate.transcodingURL).inserted else { continue }
                ordered.append(candidate)
            }
        }

        return ordered
    }

    private func resolveSoundCloudStreamURL(
        for candidate: SoundCloudStreamCandidate,
        trackAuthorization: String?,
        clientID: String
    ) async throws -> URL {
        guard let transcodingURL = URL(string: candidate.transcodingURL) else {
            throw OnlineMusicServiceError.invalidAudioURL(
                "SoundCloud returned an invalid stream resolution URL."
            )
        }

        guard var components = URLComponents(url: transcodingURL, resolvingAgainstBaseURL: false) else {
            throw OnlineMusicServiceError.invalidAudioURL(
                "SoundCloud returned an invalid stream resolution URL."
            )
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "client_id", value: clientID))
        if let trackAuthorization = cleanedText(trackAuthorization) {
            queryItems.append(URLQueryItem(name: "track_authorization", value: trackAuthorization))
        }
        components.queryItems = queryItems

        guard let requestURL = components.url else {
            throw OnlineMusicServiceError.invalidAudioURL(
                "SoundCloud returned an invalid stream resolution URL."
            )
        }

        let data = try await fetchSoundCloudData(from: requestURL, accept: "application/json, text/plain, */*")

        let response: SoundCloudResolvedStream
        do {
            response = try decoder.decode(SoundCloudResolvedStream.self, from: data)
        } catch {
            throw OnlineMusicServiceError.extractionFailure("SoundCloud stream resolution returned malformed JSON.")
        }

        guard let resolvedURLString = cleanedText(response.url),
              let resolvedURL = URL(string: resolvedURLString),
              isValidAudioURL(resolvedURL) else {
            throw OnlineMusicServiceError.invalidAudioURL(
                "SoundCloud returned an invalid audio stream URL."
            )
        }

        return resolvedURL
    }

    private func soundCloudClientID() async throws -> String {
        if let cachedClientID = await soundCloudRuntimeState.clientID {
            return cachedClientID
        }

        if let configuredClientID = Bundle.main.object(forInfoDictionaryKey: "SoundCloudClientID") as? String,
           let cleanedConfiguredClientID = cleanedText(configuredClientID) {
            await soundCloudRuntimeState.setClientID(cleanedConfiguredClientID)
            debugLog("Using configured SoundCloud client_id from Info.plist")
            return cleanedConfiguredClientID
        }

        if let bundledClientID = bundledFallbackClientIDs.compactMap(cleanedText).first {
            await soundCloudRuntimeState.setClientID(bundledClientID)
            debugLog("Using bundled SoundCloud client_id fallback")
            return bundledClientID
        }

        let discoveredClientID = try await discoverSoundCloudClientID()
        await soundCloudRuntimeState.setClientID(discoveredClientID)
        return discoveredClientID
    }

    private func initialSoundCloudClientIDs() async -> [String] {
        var candidateIDs: [String] = []

        if let cachedClientID = await soundCloudRuntimeState.clientID {
            candidateIDs.append(cachedClientID)
        }

        if let configuredClientID = Bundle.main.object(forInfoDictionaryKey: "SoundCloudClientID") as? String,
           let cleanedConfiguredClientID = cleanedText(configuredClientID) {
            candidateIDs.append(cleanedConfiguredClientID)
        }

        candidateIDs.append(contentsOf: bundledFallbackClientIDs)

        return orderedUniqueValues(candidateIDs.compactMap(cleanedText))
    }

    private func discoverSoundCloudClientID() async throws -> String {
        debugLog("Provider start: SoundCloud client_id discovery")

        let homepageHTML = try await fetchText(
            from: soundCloudHomepageURL,
            accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        )

        if let inlineClientID = extractFirstMatch(in: homepageHTML, patterns: soundCloudClientIDPatterns) {
            debugLog("Resolved SoundCloud client_id from homepage markup")
            return inlineClientID
        }

        let assetURLs = orderedUniqueValues(
            extractAllMatches(in: homepageHTML, pattern: soundCloudAssetPattern)
        )

        for assetURLString in assetURLs.prefix(12) {
            guard let assetURL = URL(string: assetURLString) else { continue }

            do {
                let assetText = try await fetchText(from: assetURL, accept: "*/*")
                if let extractedClientID = extractFirstMatch(in: assetText, patterns: soundCloudClientIDPatterns) {
                    debugLog("Resolved SoundCloud client_id from \(assetURL.lastPathComponent)")
                    return extractedClientID
                }
            } catch {
                debugLog("SoundCloud asset inspection failed for \(assetURL.absoluteString): \(error.localizedDescription)")
            }
        }

        throw OnlineMusicServiceError.unavailableSources
    }

    private func cachedTemporaryFile(for sourceID: String) -> URL? {
        let candidateExtensions = ["mp3", "m4a", "aac"]
        for pathExtension in candidateExtensions {
            let candidateURL = AppFileManager.shared.temporaryAudioURL(for: sourceID, fileExtension: pathExtension)
            if fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return nil
    }

    private func fetchText(from url: URL, accept: String) async throws -> String {
        let data = try await fetchSoundCloudData(from: url, accept: accept)

        if let text = String(data: data, encoding: .utf8) {
            return text
        }

        if let text = String(data: data, encoding: .unicode) {
            return text
        }

        throw OnlineMusicServiceError.extractionFailure("The online provider returned unreadable text.")
    }

    private func fetchSoundCloudData(from url: URL, accept: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(soundCloudHomepageURL.absoluteString, forHTTPHeaderField: "Referer")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OnlineMusicServiceError.networkFailure(
                "The SoundCloud request could not be completed."
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnlineMusicServiceError.networkFailure("The online provider returned an invalid response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw OnlineMusicServiceError.networkFailure(
                "The SoundCloud provider returned HTTP \(httpResponse.statusCode)."
            )
        }

        return data
    }

    private func isValidAudioURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }

    private func preferredFileExtension(mimeType: String, resolvedURL: URL) -> String {
        let normalizedMimeType = mimeType.lowercased()

        if normalizedMimeType.contains("mpeg") {
            return "mp3"
        }

        if normalizedMimeType.contains("mp4") || normalizedMimeType.contains("aac") {
            return "m4a"
        }

        let pathExtension = resolvedURL.pathExtension.lowercased()
        return pathExtension.isEmpty ? "m4a" : pathExtension
    }

    private func normalizedArtworkURL(_ rawValue: String?) -> String? {
        guard let cleanedValue = cleanedText(rawValue) else { return nil }

        return cleanedValue
            .replacingOccurrences(of: "-large.", with: "-t500x500.")
            .replacingOccurrences(of: "-crop.", with: "-t500x500.")
    }

    private func deduplicatedTrackResults(_ results: [OnlineTrackResult]) -> [OnlineTrackResult] {
        var seenIDs: Set<String> = []

        return results.filter { result in
            guard seenIDs.insert(result.id).inserted else { return false }
            return true
        }
    }

    private func deduplicatedArtistResults(_ results: [OnlineArtistResult]) -> [OnlineArtistResult] {
        var seenIDs: Set<String> = []

        return results.filter { result in
            guard seenIDs.insert(result.id).inserted else { return false }
            return true
        }
    }

    private func deduplicatedAlbumResults(_ results: [OnlineAlbumResult]) -> [OnlineAlbumResult] {
        var seenIDs: Set<String> = []

        return results.filter { result in
            guard seenIDs.insert(result.id).inserted else { return false }
            return true
        }
    }

    private func deduplicatedPlaylistResults(_ results: [OnlinePlaylistResult]) -> [OnlinePlaylistResult] {
        var seenIDs: Set<String> = []

        return results.filter { result in
            guard seenIDs.insert(result.id).inserted else { return false }
            return true
        }
    }

    private func cleanedText(_ value: String?) -> String? {
        guard let value else { return nil }

        let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedValue.isEmpty ? nil : cleanedValue
    }

    private func extractFirstMatch(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            if let match = extractFirstMatch(in: text, pattern: pattern) {
                return match
            }
        }

        return nil
    }

    private func extractFirstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[captureRange])
    }

    private func extractAllMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return String(text[matchRange])
        }
    }

    private func orderedUniqueValues(_ values: [String]) -> [String] {
        var seenValues: Set<String> = []
        var orderedValues: [String] = []

        for value in values where seenValues.insert(value).inserted {
            orderedValues.append(value)
        }

        return orderedValues
    }

    private func maskedClientID(_ clientID: String) -> String {
        guard clientID.count > 8 else { return clientID }
        let prefix = clientID.prefix(4)
        let suffix = clientID.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    private func makePKCECodeVerifier() -> String {
        let data = secureRandomData(length: 64)
        return data.base64URLEncodedString
    }

    private func makeCodeChallenge(from verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString
    }

    private func makeOpaqueState() -> String {
        secureRandomData(length: 24).base64URLEncodedString
    }

    private func secureRandomData(length: Int) -> Data {
        var data = Data(count: length)
        let status = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, length, bytes.baseAddress!)
        }

        guard status == errSecSuccess else {
            return Data(UUID().uuidString.utf8)
        }

        return data
    }

    private func logMappedResultCounts(provider: OnlineTrackProvider, results: OnlineSearchResults) {
        debugLog(
            "Mapped result counts for \(provider.displayName): tracks=\(results.tracks.count), artists=\(results.artists.count), albums=\(results.albums.count), playlists=\(results.playlists.count)"
        )
    }

    private func hasRemoteArtwork(_ track: OnlineTrackResult) -> Bool {
        guard let coverArtURL = track.coverArtURL else { return false }
        return !coverArtURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@MainActor
private final class SpotifyAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authenticate(using url: URL, callbackURLScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let authenticationSession = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackURLScheme
            ) { [weak self] callbackURL, error in
                self?.session = nil

                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(
                        throwing: OnlineMusicServiceError.authenticationRequired(
                            "Spotify sign-in was cancelled."
                        )
                    )
                    return
                }

                if let error {
                    continuation.resume(
                        throwing: OnlineMusicServiceError.authenticationRequired(
                            "Spotify sign-in failed: \(error.localizedDescription)"
                        )
                    )
                    return
                }

                guard let callbackURL else {
                    continuation.resume(
                        throwing: OnlineMusicServiceError.authenticationRequired(
                            "Spotify sign-in finished without a callback URL."
                        )
                    )
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            authenticationSession.presentationContextProvider = self
            authenticationSession.prefersEphemeralWebBrowserSession = false
            self.session = authenticationSession

            guard authenticationSession.start() else {
                self.session = nil
                continuation.resume(
                    throwing: OnlineMusicServiceError.authenticationRequired(
                        "Spotify sign-in could not start."
                    )
                )
                return
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

private actor SoundCloudRuntimeState {
    var clientID: String?

    func setClientID(_ clientID: String) {
        self.clientID = clientID
    }
}

private actor SpotifyRuntimeState {
    private var credentials: SpotifyCredentials?

    func validAccessToken(referenceDate: Date) -> String? {
        guard let credentials,
              credentials.expirationDate > referenceDate else {
            return nil
        }

        return credentials.accessToken
    }

    var refreshToken: String? {
        credentials?.refreshToken
    }

    func setCredentials(_ credentials: SpotifyCredentials) {
        self.credentials = credentials
    }

    func clearCredentials() {
        credentials = nil
    }

    func debugDescription(referenceDate: Date) -> String {
        guard let credentials else {
            return "missing-user-token"
        }

        return credentials.expirationDate > referenceDate ? "authorized" : "expired"
    }
}

private struct SpotifyConfiguration {
    let clientID: String
    let redirectURI: String
    let callbackURLScheme: String
    let market: String
}

private struct SpotifyConfigurationStatus {
    let clientIDKey: String
    let redirectURIKey: String
    let clientID: String?
    let explicitRedirectURI: String?
    let defaultRedirectURI: String
    let resolvedRedirectURI: String
    let callbackURLScheme: String?
    let market: String

    var isClientIDConfigured: Bool {
        clientID != nil
    }

    var isRedirectURIConfigured: Bool {
        explicitRedirectURI != nil
    }

    var isRedirectURIValid: Bool {
        callbackURLScheme != nil
    }

    var usesDefaultRedirectURI: Bool {
        explicitRedirectURI == nil
    }

    var isEnabled: Bool {
        configuration != nil
    }

    var configuration: SpotifyConfiguration? {
        guard let clientID,
              let callbackURLScheme else {
            return nil
        }

        return SpotifyConfiguration(
            clientID: clientID,
            redirectURI: resolvedRedirectURI,
            callbackURLScheme: callbackURLScheme,
            market: market
        )
    }

    var userFacingErrorMessage: String {
        if !isClientIDConfigured {
            return "Spotify search requires the Info.plist key SpotifyClientID with your Spotify app client ID."
        }

        if !isRedirectURIValid {
            return "Spotify search requires a valid Info.plist key SpotifyRedirectURI, or remove that key to use the default callback \(defaultRedirectURI)."
        }

        return "Spotify search is unavailable because its configuration is incomplete."
    }
}

private struct SpotifyCredentials {
    let accessToken: String
    let refreshToken: String?
    let expirationDate: Date
}

private struct SoundCloudSearchResponse: Decodable {
    let collection: [SoundCloudSearchTrack]
}

private struct SoundCloudSearchTrack: Decodable {
    let artworkURL: String?
    let duration: Int?
    let fullDuration: Int?
    let media: SoundCloudMedia?
    let permalinkURL: String?
    let publisherMetadata: SoundCloudPublisherMetadata?
    let title: String?
    let trackAuthorization: String?
    let urn: String?
    let user: SoundCloudUser?

    enum CodingKeys: String, CodingKey {
        case artworkURL = "artwork_url"
        case duration
        case fullDuration = "full_duration"
        case media
        case permalinkURL = "permalink_url"
        case publisherMetadata = "publisher_metadata"
        case title
        case trackAuthorization = "track_authorization"
        case urn
        case user
    }
}

private struct SoundCloudPublisherMetadata: Decodable {
    let albumTitle: String?
    let artist: String?
    let releaseTitle: String?

    enum CodingKeys: String, CodingKey {
        case albumTitle = "album_title"
        case artist
        case releaseTitle = "release_title"
    }
}

private struct SoundCloudUser: Decodable {
    let avatarURL: String?
    let username: String?

    enum CodingKeys: String, CodingKey {
        case avatarURL = "avatar_url"
        case username
    }
}

private struct SoundCloudMedia: Decodable {
    let transcodings: [SoundCloudTranscoding]
}

private struct SoundCloudTranscoding: Decodable {
    let format: SoundCloudTranscodingFormat?
    let isLegacyTranscoding: Bool?
    let preset: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case format
        case isLegacyTranscoding = "is_legacy_transcoding"
        case preset
        case url
    }
}

private struct SoundCloudTranscodingFormat: Decodable {
    let mimeType: String?
    let protocolName: String?

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case protocolName = "protocol"
    }
}

private struct SoundCloudResolvedStream: Decodable {
    let url: String?
}

private struct SpotifySearchResponse: Decodable {
    let tracks: SpotifyTracksContainer?
    let artists: SpotifyArtistsContainer?
    let albums: SpotifyAlbumsContainer?
    let playlists: SpotifyPlaylistsContainer?
}

private struct SpotifyTracksContainer: Decodable {
    let items: [SpotifyTrack]
}

private struct SpotifyArtistsContainer: Decodable {
    let items: [SpotifyArtist]
}

private struct SpotifyAlbumsContainer: Decodable {
    let items: [SpotifyAlbum]
}

private struct SpotifyPlaylistsContainer: Decodable {
    let items: [SpotifyPlaylist]
}

private struct SpotifyTrack: Decodable {
    let id: String?
    let name: String?
    let durationMS: Int?
    let externalURLs: SpotifyExternalURLs?
    let album: SpotifyAlbum?
    let artists: [SpotifyArtist]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case durationMS = "duration_ms"
        case externalURLs = "external_urls"
        case album
        case artists
    }
}

private struct SpotifyArtist: Decodable {
    let id: String?
    let name: String?
    let images: [SpotifyImage]?
    let externalURLs: SpotifyExternalURLs?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case images
        case externalURLs = "external_urls"
    }
}

private struct SpotifyAlbum: Decodable {
    let id: String?
    let name: String?
    let images: [SpotifyImage]?
    let artists: [SpotifyArtist]
    let externalURLs: SpotifyExternalURLs?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case images
        case artists
        case externalURLs = "external_urls"
    }
}

private struct SpotifyPlaylist: Decodable {
    let id: String?
    let name: String?
    let images: [SpotifyImage]?
    let owner: SpotifyUser?
    let externalURLs: SpotifyExternalURLs?
    let tracks: SpotifyPlaylistTracksSummary?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case images
        case owner
        case externalURLs = "external_urls"
        case tracks
    }
}

private struct SpotifyPlaylistTracksSummary: Decodable {
    let total: Int?
}

private struct SpotifyUser: Decodable {
    let displayName: String?
    let id: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case id
    }
}

private struct SpotifyExternalURLs: Decodable {
    let spotify: String?
}

private struct SpotifyImage: Decodable {
    let url: String?
    let width: Int?
    let height: Int?
}

private struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private struct SpotifyTokenErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private struct SpotifyAPIErrorEnvelope: Decodable {
    let error: SpotifyAPIError
}

private struct SpotifyAPIError: Decodable {
    let status: Int?
    let message: String
}

private extension Data {
    var base64URLEncodedString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
