//
//  OnlineMusicService.swift
//  FreeMusicPlayer
//
//  Foreground-only SoundCloud search and retrieval that runs directly inside
//  the app process without an external backend.
//

import Foundation

enum OnlineTrackProvider: String, Equatable {
    case soundcloud = "soundcloud"

    var displayName: String {
        "SoundCloud"
    }

    var trackSource: Track.TrackSource {
        .soundcloud
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

    var supportsOfflineDownload: Bool {
        playbackStreams.contains { $0.kind == .progressiveMP3 }
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

    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "Enter a search query first."
        case .noResults(let query):
            return "No SoundCloud results were found for \"\(query)\"."
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
            return "SoundCloud is unavailable right now."
        }
    }
}

final class OnlineMusicService {
    static let shared = OnlineMusicService()

    private let fileManager = FileManager.default
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let runtimeState = SoundCloudRuntimeState()
    private let soundCloudHomepageURL = URL(string: "https://soundcloud.com")!
    private let soundCloudSearchURL = URL(string: "https://api-v2.soundcloud.com/search/tracks")!

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

    func search(_ query: String) async throws -> [OnlineTrackResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw OnlineMusicServiceError.invalidQuery
        }

        debugLog("Online query entered: \(trimmedQuery)")
        debugLog("Provider start: SoundCloud for query \(trimmedQuery)")

        do {
            let clientID = try await soundCloudClientID()
            let results = try await searchViaSoundCloud(query: trimmedQuery, clientID: clientID)
            let finalResults = Array(results.prefix(20))

            debugLog("Provider finish: SoundCloud with \(finalResults.count) results")
            debugLog("Online result count: \(finalResults.count)")

            if finalResults.isEmpty {
                throw OnlineMusicServiceError.noResults(trimmedQuery)
            }

            return finalResults
        } catch let error as OnlineMusicServiceError {
            debugLog("Provider error: SoundCloud - \(error.localizedDescription)")
            throw error
        } catch {
            debugLog("Provider error: SoundCloud - \(error.localizedDescription)")
            throw OnlineMusicServiceError.networkFailure(
                "SoundCloud search failed because the provider request could not be completed."
            )
        }
    }

    func resolvePlaybackStream(for result: OnlineTrackResult) async throws -> ResolvedAudioStream {
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

    private func searchViaSoundCloud(query: String, clientID: String) async throws -> [OnlineTrackResult] {
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

        let data = try await fetchData(from: requestURL, accept: "application/json, text/plain, */*")

        let response: SoundCloudSearchResponse
        do {
            response = try decoder.decode(SoundCloudSearchResponse.self, from: data)
        } catch {
            throw OnlineMusicServiceError.extractionFailure("SoundCloud search returned malformed JSON.")
        }

        return deduplicatedResults(
            response.collection.compactMap { makeOnlineTrackResult(from: $0) }
        )
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

        let data = try await fetchData(from: requestURL, accept: "application/json, text/plain, */*")

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
        if let cachedClientID = await runtimeState.clientID {
            return cachedClientID
        }

        if let configuredClientID = Bundle.main.object(forInfoDictionaryKey: "SoundCloudClientID") as? String,
           let cleanedConfiguredClientID = cleanedText(configuredClientID) {
            await runtimeState.setClientID(cleanedConfiguredClientID)
            debugLog("Using configured SoundCloud client_id from Info.plist")
            return cleanedConfiguredClientID
        }

        let homepageHTML = try await fetchText(
            from: soundCloudHomepageURL,
            accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        )

        if let inlineClientID = extractFirstMatch(in: homepageHTML, patterns: soundCloudClientIDPatterns) {
            await runtimeState.setClientID(inlineClientID)
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
                    await runtimeState.setClientID(extractedClientID)
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
        let data = try await fetchData(from: url, accept: accept)

        if let text = String(data: data, encoding: .utf8) {
            return text
        }

        if let text = String(data: data, encoding: .unicode) {
            return text
        }

        throw OnlineMusicServiceError.extractionFailure("The online provider returned unreadable text.")
    }

    private func fetchData(from url: URL, accept: String) async throws -> Data {
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

    private func deduplicatedResults(_ results: [OnlineTrackResult]) -> [OnlineTrackResult] {
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
}

private actor SoundCloudRuntimeState {
    var clientID: String?

    func setClientID(_ clientID: String) {
        self.clientID = clientID
    }
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
