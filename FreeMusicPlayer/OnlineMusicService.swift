//
//  OnlineMusicService.swift
//  FreeMusicPlayer
//
//  Foreground-only online music search and retrieval that runs directly inside
//  the app process with provider-specific search and download handling.
//

import Foundation

enum OnlineTrackProvider: String, Equatable {
    case appleMusicPreview = "apple_music_preview"
    case youtubeMirror = "youtube_mirror"

    var displayName: String {
        switch self {
        case .appleMusicPreview:
            return "Apple Preview"
        case .youtubeMirror:
            return "YouTube"
        }
    }

    var trackSource: Track.TrackSource {
        switch self {
        case .appleMusicPreview:
            return .appleMusicPreview
        case .youtubeMirror:
            return .youtube
        }
    }
}

struct OnlineTrackResult: Identifiable, Equatable {
    let provider: OnlineTrackProvider
    let providerTrackID: String
    let title: String
    let artist: String
    let album: String?
    let duration: TimeInterval
    let coverArtURL: String?
    let webpageURL: String
    let directAudioURL: String?
    let directFileExtension: String?

    var id: String {
        "\(provider.rawValue):\(providerTrackID)"
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
}

enum OnlineMusicServiceError: LocalizedError, Equatable {
    case invalidQuery
    case noResults(String)
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
            return "No online results were found for \"\(query)\"."
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
            return "Online music sources are unavailable right now."
        }
    }
}

final class OnlineMusicService {
    static let shared = OnlineMusicService()

    private let fileManager = FileManager.default
    private let session: URLSession
    private let youtubeBaseURL = URL(string: "https://www.youtube.com")!
    private let pipedInstanceIndexURLs: [URL] = [
        URL(string: "https://github.com/TeamPiped/Piped/wiki/Instances")!,
        URL(string: "https://raw.githubusercontent.com/wiki/TeamPiped/Piped/Instances.md")!,
    ]
    private let fallbackPipedHosts: [URL] = [
        URL(string: "https://pipedapi.kavin.rocks")!,
        URL(string: "https://pipedapi.syncpundit.io")!,
        URL(string: "https://pipedapi.tokhmi.xyz")!,
        URL(string: "https://api-piped.mha.fi")!,
    ]
    private let fallbackInvidiousHosts: [URL] = [
        URL(string: "https://vid.puffyan.us")!,
        URL(string: "https://yewtu.be")!,
        URL(string: "https://invidious.fdn.fr")!,
        URL(string: "https://inv.nadeko.net")!,
    ]

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    func search(_ query: String) async throws -> [OnlineTrackResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw OnlineMusicServiceError.invalidQuery
        }

        debugLog("Online query entered: \(trimmedQuery)")

        var aggregatedResults: [OnlineTrackResult] = []
        var reachedHealthyProvider = false
        var failures: [String] = []

        do {
            let attempt = try await searchViaAppleMusicPreview(query: trimmedQuery)
            reachedHealthyProvider = reachedHealthyProvider || attempt.reachedProvider
            aggregatedResults = deduplicatedResults(from: aggregatedResults + attempt.results)
        } catch {
            failures.append(error.localizedDescription)
            debugLog("Apple preview search failed: \(error.localizedDescription)")
        }

        if aggregatedResults.count < 20 {
            do {
                let attempt = try await searchYouTubeHTML(query: trimmedQuery)
                reachedHealthyProvider = reachedHealthyProvider || attempt.reachedProvider
                aggregatedResults = deduplicatedResults(from: aggregatedResults + attempt.results)
            } catch {
                failures.append(error.localizedDescription)
                debugLog("YouTube HTML search failed: \(error.localizedDescription)")
            }
        }

        if aggregatedResults.count < 20 {
            do {
                let attempt = try await searchViaPiped(query: trimmedQuery)
                reachedHealthyProvider = reachedHealthyProvider || attempt.reachedProvider
                aggregatedResults = deduplicatedResults(from: aggregatedResults + attempt.results)
            } catch {
                failures.append(error.localizedDescription)
                debugLog("Piped search failed: \(error.localizedDescription)")
            }
        }

        if aggregatedResults.count < 20 {
            do {
                let attempt = try await searchViaInvidious(query: trimmedQuery)
                reachedHealthyProvider = reachedHealthyProvider || attempt.reachedProvider
                aggregatedResults = deduplicatedResults(from: aggregatedResults + attempt.results)
            } catch {
                failures.append(error.localizedDescription)
                debugLog("Invidious search failed: \(error.localizedDescription)")
            }
        }

        if !aggregatedResults.isEmpty {
            let finalResults = Array(aggregatedResults.prefix(20))
            debugLog("Online query finished with \(finalResults.count) total results")
            return finalResults
        }

        if reachedHealthyProvider {
            throw OnlineMusicServiceError.noResults(trimmedQuery)
        }

        if !failures.isEmpty {
            throw OnlineMusicServiceError.networkFailure(
                summarizedFailureMessage(
                    from: failures,
                    fallback: "Online search failed because the in-app providers could not be reached."
                )
            )
        }

        throw OnlineMusicServiceError.unavailableSources
    }

    func downloadAudio(for result: OnlineTrackResult) async throws -> URL {
        guard !result.providerTrackID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OnlineMusicServiceError.unsupportedSource(
                "Unsupported source. The selected result does not contain a valid provider identifier."
            )
        }

        if let cachedURL = cachedTemporaryFile(for: result.id) {
            debugLog("Using cached temp audio for \(result.id): \(cachedURL.path)")
            return cachedURL
        }

        debugLog("Resolution start for \(result.id) via \(result.providerDisplayName)")

        let stream = try await resolveAudioStream(for: result)
        guard isValidDownloadURL(stream.url) else {
            throw OnlineMusicServiceError.invalidAudioURL(
                "The selected audio source returned an invalid media URL."
            )
        }

        debugLog("Resolution end for \(result.id) via \(stream.providerName): \(stream.url.absoluteString)")
        debugLog("Download start for \(result.id) via \(stream.providerName): \(stream.url.absoluteString)")

        var request = URLRequest(url: stream.url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("audio/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let temporaryDownloadURL: URL
        let response: URLResponse

        do {
            (temporaryDownloadURL, response) = try await session.download(for: request)
        } catch {
            throw OnlineMusicServiceError.networkFailure(
                "Audio download failed because the network request could not be completed."
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnlineMusicServiceError.networkFailure("Audio download failed because the server response was invalid.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OnlineMusicServiceError.networkFailure(
                "Audio download failed with HTTP \(httpResponse.statusCode)."
            )
        }

        let destinationURL = AppFileManager.shared.temporaryAudioURL(
            for: result.id,
            fileExtension: stream.fileExtension
        )

        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }

        do {
            try fileManager.moveItem(at: temporaryDownloadURL, to: destinationURL)
        } catch {
            do {
                try fileManager.copyItem(at: temporaryDownloadURL, to: destinationURL)
            } catch {
                throw OnlineMusicServiceError.tempFileWriteFailure(
                    "Audio was downloaded but could not be written into temp_music."
                )
            }
        }

        guard fileManager.fileExists(atPath: destinationURL.path) else {
            throw OnlineMusicServiceError.tempFileWriteFailure(
                "Audio download completed, but the temp file was not created."
            )
        }

        let fileSize = (try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard fileSize > 0 else {
            try? fileManager.removeItem(at: destinationURL)
            throw OnlineMusicServiceError.extractionFailure(
                "Audio download completed, but the resulting temp file was empty."
            )
        }

        debugLog("Download end for \(result.id): \(fileSize) bytes")
        debugLog("Temp file path: \(destinationURL.path)")

        return destinationURL
    }

    private func searchViaAppleMusicPreview(query: String) async throws -> SearchAttempt {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "country", value: "US"),
        ]

        guard let url = components?.url else {
            throw OnlineMusicServiceError.extractionFailure("The Apple preview search URL could not be created.")
        }

        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await fetchData(for: request)

        let payload: AppleMusicPreviewSearchResponse
        do {
            payload = try JSONDecoder().decode(AppleMusicPreviewSearchResponse.self, from: data)
        } catch {
            throw OnlineMusicServiceError.extractionFailure("Apple preview search returned malformed JSON.")
        }

        let results = deduplicatedResults(
            from: payload.results.compactMap { item in
                onlineResult(fromApplePreviewItem: item)
            }
        )

        debugLog("Provider selected: Apple Music Preview with \(results.count) results")

        return SearchAttempt(results: results, reachedProvider: true)
    }

    private func onlineResult(fromApplePreviewItem item: AppleMusicPreviewItem) -> OnlineTrackResult? {
        guard let trackID = item.trackID,
              let previewURL = cleanedText(item.previewURL),
              !previewURL.isEmpty else {
            return nil
        }

        let title = cleanedText(item.trackName) ?? "Unknown Track"
        let artist = cleanedText(item.artistName) ?? "Unknown Artist"
        let album = cleanedText(item.collectionName)
        let coverArtURL = normalizedAppleArtworkURL(from: item.artworkURL100)
        let webpageURL = cleanedText(item.trackViewURL) ?? previewURL
        let duration = preferredApplePreviewDuration(trackTimeMillis: item.trackTimeMillis)

        return OnlineTrackResult(
            provider: .appleMusicPreview,
            providerTrackID: String(trackID),
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            coverArtURL: coverArtURL,
            webpageURL: webpageURL,
            directAudioURL: previewURL,
            directFileExtension: fileExtension(fromDownloadURLString: previewURL, fallback: "m4a")
        )
    }

    private func searchYouTubeHTML(query: String) async throws -> SearchAttempt {
        var components = URLComponents(url: youtubeBaseURL.appendingPathComponent("results"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "search_query", value: query),
            URLQueryItem(name: "hl", value: "en"),
            URLQueryItem(name: "gl", value: "US"),
        ]

        guard let url = components?.url else {
            throw OnlineMusicServiceError.extractionFailure("The YouTube search URL could not be created.")
        }

        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let data = try await fetchData(for: request)

        guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
            throw OnlineMusicServiceError.networkFailure("YouTube search failed because the response body was empty.")
        }

        guard let payloadString = extractJSONAssignment(
            in: html,
            markers: [
                "var ytInitialData = ",
                "window[\"ytInitialData\"] = ",
                "ytInitialData = ",
            ]
        ) else {
            throw OnlineMusicServiceError.extractionFailure(
                "YouTube search changed and the app could not extract the result payload."
            )
        }

        let payloadData = Data(payloadString.utf8)
        let payload = try decodeJSONObject(from: payloadData)
        let renderers = collectDictionaries(forKey: "videoRenderer", in: payload)

        let results = deduplicatedResults(
            from: renderers.compactMap { videoRenderer in
                onlineResult(fromYouTubeRenderer: videoRenderer)
            }
        )

        debugLog("Provider selected: YouTube HTML with \(results.count) results")

        return SearchAttempt(results: results, reachedProvider: true)
    }

    private func searchViaPiped(query: String) async throws -> SearchAttempt {
        var lastErrors: [String] = []

        for host in await pipedHosts() {
            do {
                let results = try await searchPiped(query: query, host: host)
                debugLog("Provider selected: Piped \(host.host ?? host.absoluteString) with \(results.count) results")
                return SearchAttempt(results: results, reachedProvider: true)
            } catch {
                lastErrors.append(error.localizedDescription)
                debugLog("Piped host \(host.absoluteString) search error: \(error.localizedDescription)")
            }
        }

        if !lastErrors.isEmpty {
            throw OnlineMusicServiceError.networkFailure(
                summarizedFailureMessage(
                    from: lastErrors,
                    fallback: "Online search failed because the Piped providers were unavailable."
                )
            )
        }

        throw OnlineMusicServiceError.unavailableSources
    }

    private func searchPiped(query: String, host: URL) async throws -> [OnlineTrackResult] {
        var components = URLComponents(url: host.appendingPathComponent("search"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "filter", value: "videos"),
        ]

        guard let url = components?.url else {
            throw OnlineMusicServiceError.extractionFailure("The Piped search URL could not be created.")
        }

        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await fetchData(for: request)
        let payload = try decodeJSONValue(from: data)

        let items: [Any]
        if let array = payload as? [Any] {
            items = array
        } else if let dictionary = payload as? [String: Any],
                  let array = dictionary["items"] as? [Any] {
            items = array
        } else {
            throw OnlineMusicServiceError.extractionFailure("Piped search returned an unexpected response format.")
        }

        return deduplicatedResults(
            from: items.compactMap { item in
                onlineResult(fromPipedItem: item, host: host)
            }
        )
    }

    private func searchViaInvidious(query: String) async throws -> SearchAttempt {
        var lastErrors: [String] = []

        for host in fallbackInvidiousHosts {
            do {
                let results = try await searchInvidious(query: query, host: host)
                debugLog("Provider selected: Invidious \(host.host ?? host.absoluteString) with \(results.count) results")
                return SearchAttempt(results: results, reachedProvider: true)
            } catch {
                lastErrors.append(error.localizedDescription)
                debugLog("Invidious host \(host.absoluteString) search error: \(error.localizedDescription)")
            }
        }

        if !lastErrors.isEmpty {
            throw OnlineMusicServiceError.networkFailure(
                summarizedFailureMessage(
                    from: lastErrors,
                    fallback: "Online search failed because the Invidious providers were unavailable."
                )
            )
        }

        throw OnlineMusicServiceError.unavailableSources
    }

    private func searchInvidious(query: String, host: URL) async throws -> [OnlineTrackResult] {
        var components = URLComponents(url: host.appendingPathComponent("api/v1/search"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "video"),
        ]

        guard let url = components?.url else {
            throw OnlineMusicServiceError.extractionFailure("The Invidious search URL could not be created.")
        }

        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await fetchData(for: request)
        let payload = try JSONDecoder().decode([InvidiousSearchItem].self, from: data)

        return deduplicatedResults(
            from: payload.compactMap { item in
                guard item.type.lowercased() == "video", !item.videoID.isEmpty else { return nil }

                return OnlineTrackResult(
                    provider: .youtubeMirror,
                    providerTrackID: item.videoID,
                    title: cleanedText(item.title) ?? "Unknown Track",
                    artist: cleanedText(item.author) ?? "Unknown Artist",
                    album: nil,
                    duration: item.lengthSeconds,
                    coverArtURL: normalizedMediaURL(item.thumbnails.last?.url, host: host)?.absoluteString,
                    webpageURL: "https://www.youtube.com/watch?v=\(item.videoID)",
                    directAudioURL: nil,
                    directFileExtension: nil
                )
            }
        )
    }

    private func resolveAudioStream(for result: OnlineTrackResult) async throws -> ResolvedAudioStream {
        switch result.provider {
        case .appleMusicPreview:
            return try resolveApplePreviewStream(for: result)
        case .youtubeMirror:
            return try await resolveYouTubeAudioStream(for: result.providerTrackID)
        }
    }

    private func resolveApplePreviewStream(for result: OnlineTrackResult) throws -> ResolvedAudioStream {
        guard let rawURL = cleanedText(result.directAudioURL),
              let streamURL = URL(string: rawURL) else {
            throw OnlineMusicServiceError.invalidAudioURL(
                "The Apple preview result did not contain a valid audio URL."
            )
        }

        return ResolvedAudioStream(
            url: streamURL,
            fileExtension: result.directFileExtension ?? fileExtension(fromDownloadURLString: rawURL, fallback: "m4a"),
            bitrate: 256_000,
            mimeType: "audio/mp4",
            providerName: result.providerDisplayName
        )
    }

    private func resolveYouTubeAudioStream(for videoID: String) async throws -> ResolvedAudioStream {
        var errors: [OnlineMusicServiceError] = []

        do {
            return try await resolveAudioStreamViaPiped(videoID: videoID)
        } catch let error as OnlineMusicServiceError {
            errors.append(error)
            debugLog("Piped audio resolve failed: \(error.localizedDescription)")
        } catch {
            let resolvedError = OnlineMusicServiceError.extractionFailure(
                "Audio stream extraction failed for the selected track."
            )
            errors.append(resolvedError)
            debugLog("Piped audio resolve failed: \(resolvedError.localizedDescription)")
        }

        do {
            return try await resolveAudioStreamViaInvidious(videoID: videoID)
        } catch let error as OnlineMusicServiceError {
            errors.append(error)
            debugLog("Invidious audio resolve failed: \(error.localizedDescription)")
        } catch {
            let resolvedError = OnlineMusicServiceError.extractionFailure(
                "Audio stream extraction failed for the selected track."
            )
            errors.append(resolvedError)
            debugLog("Invidious audio resolve failed: \(resolvedError.localizedDescription)")
        }

        throw bestResolutionError(from: errors)
    }

    private func resolveAudioStreamViaPiped(videoID: String) async throws -> ResolvedAudioStream {
        var errors: [OnlineMusicServiceError] = []

        for host in await pipedHosts() {
            do {
                return try await resolvePipedStream(videoID: videoID, host: host)
            } catch let error as OnlineMusicServiceError {
                errors.append(error)
                debugLog("Piped host \(host.absoluteString) stream error: \(error.localizedDescription)")
            } catch {
                let resolvedError = OnlineMusicServiceError.networkFailure(
                    "A Piped provider could not be reached while resolving audio."
                )
                errors.append(resolvedError)
                debugLog("Piped host \(host.absoluteString) stream error: \(resolvedError.localizedDescription)")
            }
        }

        throw bestResolutionError(from: errors)
    }

    private func resolvePipedStream(videoID: String, host: URL) async throws -> ResolvedAudioStream {
        var request = URLRequest(url: host.appendingPathComponent("streams").appendingPathComponent(videoID))
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await fetchData(for: request)
        let payload = try JSONDecoder().decode(PipedStreamPayload.self, from: data)

        if payload.livestream || payload.hls != nil {
            throw OnlineMusicServiceError.unsupportedSource(
                "This source is a livestream and cannot be downloaded as a normal audio file."
            )
        }

        let audioEntryCount = payload.audioStreams.count

        let candidates = payload.audioStreams.compactMap { stream -> ResolvedAudioStream? in
            guard let rawURL = stream.url,
                  let streamURL = normalizedMediaURL(rawURL, host: host) else {
                return nil
            }

            let mimeType = stream.mimeType?.lowercased() ?? ""
            return ResolvedAudioStream(
                url: streamURL,
                fileExtension: preferredFileExtension(
                    mimeType: mimeType,
                    container: stream.format?.lowercased()
                ),
                bitrate: stream.bitrate,
                mimeType: mimeType,
                providerName: "Piped \(host.host ?? host.absoluteString)"
            )
        }

        guard audioEntryCount > 0 else {
            throw OnlineMusicServiceError.extractionFailure(
                "Audio extraction failed because the provider returned no playable audio streams."
            )
        }

        guard !candidates.isEmpty else {
            throw OnlineMusicServiceError.invalidAudioURL(
                "The provider returned audio entries, but none had a valid downloadable URL."
            )
        }

        guard let preferredStream = preferredAudioStream(from: candidates) else {
            throw OnlineMusicServiceError.unsupportedSource(
                "The selected source only exposes audio formats that this player cannot decode."
            )
        }

        debugLog("Provider selected for audio: \(preferredStream.providerName)")

        return preferredStream
    }

    private func resolveAudioStreamViaInvidious(videoID: String) async throws -> ResolvedAudioStream {
        var errors: [OnlineMusicServiceError] = []

        for host in fallbackInvidiousHosts {
            do {
                return try await resolveInvidiousStream(videoID: videoID, host: host)
            } catch let error as OnlineMusicServiceError {
                errors.append(error)
                debugLog("Invidious host \(host.absoluteString) stream error: \(error.localizedDescription)")
            } catch {
                let resolvedError = OnlineMusicServiceError.networkFailure(
                    "An Invidious provider could not be reached while resolving audio."
                )
                errors.append(resolvedError)
                debugLog("Invidious host \(host.absoluteString) stream error: \(resolvedError.localizedDescription)")
            }
        }

        throw bestResolutionError(from: errors)
    }

    private func resolveInvidiousStream(videoID: String, host: URL) async throws -> ResolvedAudioStream {
        var request = URLRequest(url: host.appendingPathComponent("api/v1/videos").appendingPathComponent(videoID))
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await fetchData(for: request)
        let payload = try JSONDecoder().decode(InvidiousVideoInfo.self, from: data)
        let rawAudioEntryCount = payload.adaptiveFormats.filter { format in
            (format.type?.lowercased().contains("audio") ?? false)
        }.count

        let candidates = payload.adaptiveFormats.compactMap { format -> ResolvedAudioStream? in
            guard let mimeType = format.type?.lowercased(),
                  mimeType.contains("audio"),
                  let rawURL = format.url,
                  let streamURL = normalizedMediaURL(rawURL, host: host) else {
                return nil
            }

            return ResolvedAudioStream(
                url: streamURL,
                fileExtension: preferredFileExtension(mimeType: mimeType, container: format.container),
                bitrate: format.bitrate,
                mimeType: mimeType,
                providerName: "Invidious \(host.host ?? host.absoluteString)"
            )
        }

        guard rawAudioEntryCount > 0 else {
            throw OnlineMusicServiceError.extractionFailure(
                "Audio extraction failed because the provider returned no playable audio formats."
            )
        }

        guard !candidates.isEmpty else {
            throw OnlineMusicServiceError.invalidAudioURL(
                "The provider returned audio formats, but none had a valid downloadable URL."
            )
        }

        guard let preferredStream = preferredAudioStream(from: candidates) else {
            throw OnlineMusicServiceError.unsupportedSource(
                "The selected source only exposes audio formats that this player cannot decode."
            )
        }

        debugLog("Provider selected for audio: \(preferredStream.providerName)")

        return preferredStream
    }

    private func preferredAudioStream(from streams: [ResolvedAudioStream]) -> ResolvedAudioStream? {
        streams
            .filter { supportedFileExtensions.contains($0.fileExtension.lowercased()) }
            .sorted { left, right in
                audioPreferenceScore(for: left) > audioPreferenceScore(for: right)
            }
            .first
    }

    private func audioPreferenceScore(for stream: ResolvedAudioStream) -> Int {
        var score = stream.bitrate

        if stream.mimeType.contains("audio/mp4") || stream.fileExtension == "m4a" || stream.fileExtension == "mp4" {
            score += 100_000
        }

        if stream.mimeType.contains("aac") || stream.mimeType.contains("mp4a") {
            score += 50_000
        }

        if stream.mimeType.contains("audio/webm") || stream.fileExtension == "webm" {
            score += 10_000
        }

        return score
    }

    private func preferredFileExtension(mimeType: String, container: String?) -> String {
        let cleanedContainer = container?.lowercased() ?? ""

        if cleanedContainer == "m4a" {
            return "m4a"
        }

        if cleanedContainer == "mp4" || cleanedContainer == "mpeg_4" {
            return "m4a"
        }

        if cleanedContainer == "webm" {
            return "webm"
        }

        if cleanedContainer == "mp3" || cleanedContainer == "mpeg" {
            return "mp3"
        }

        if cleanedContainer == "aac" {
            return "aac"
        }

        if mimeType.contains("audio/mp4") || mimeType.contains("mp4a") {
            return "m4a"
        }

        if mimeType.contains("audio/webm") {
            return "webm"
        }

        if mimeType.contains("audio/mpeg") {
            return "mp3"
        }

        return "m4a"
    }

    private func onlineResult(fromYouTubeRenderer renderer: [String: Any]) -> OnlineTrackResult? {
        guard let videoID = cleanedText(renderer["videoId"] as? String), !videoID.isEmpty else {
            return nil
        }

        let title = cleanedText(textValue(from: renderer["title"])) ?? "Unknown Track"
        let artist = cleanedText(
            textValue(from: renderer["longBylineText"]) ??
            textValue(from: renderer["ownerText"]) ??
            textValue(from: renderer["shortBylineText"])
        ) ?? "Unknown Artist"
        let duration = parseDuration(textValue(from: renderer["lengthText"]))
        let coverArtURL = extractThumbnailURL(from: renderer["thumbnail"], host: youtubeBaseURL)?.absoluteString

        return OnlineTrackResult(
            provider: .youtubeMirror,
            providerTrackID: videoID,
            title: title,
            artist: artist,
            album: nil,
            duration: duration,
            coverArtURL: coverArtURL,
            webpageURL: "https://www.youtube.com/watch?v=\(videoID)",
            directAudioURL: nil,
            directFileExtension: nil
        )
    }

    private func onlineResult(fromPipedItem item: Any, host: URL) -> OnlineTrackResult? {
        guard let dictionary = item as? [String: Any] else { return nil }

        let itemType = cleanedText(dictionary["type"] as? String)?.lowercased() ?? "stream"
        guard itemType.isEmpty || itemType.contains("stream") || itemType.contains("video") else {
            return nil
        }

        let rawURL = cleanedText(dictionary["url"] as? String)
            ?? cleanedText(dictionary["videoId"] as? String)
            ?? cleanedText(dictionary["id"] as? String)

        guard let videoID = extractVideoID(from: rawURL), !videoID.isEmpty else {
            return nil
        }

        let title = cleanedText(textValue(from: dictionary["title"])) ?? "Unknown Track"
        let artist = cleanedText(
            textValue(from: dictionary["uploaderName"]) ??
            textValue(from: dictionary["uploader"]) ??
            textValue(from: dictionary["author"])
        ) ?? "Unknown Artist"
        let duration = timeIntervalValue(from: dictionary["duration"])
            ?? parseDuration(textValue(from: dictionary["durationText"]))
        let coverArtURL = normalizedMediaURL(
            cleanedText(dictionary["thumbnail"] as? String)
                ?? cleanedText(dictionary["thumbnailUrl"] as? String),
            host: host
        )?.absoluteString

        return OnlineTrackResult(
            provider: .youtubeMirror,
            providerTrackID: videoID,
            title: title,
            artist: artist,
            album: nil,
            duration: duration,
            coverArtURL: coverArtURL,
            webpageURL: "https://www.youtube.com/watch?v=\(videoID)",
            directAudioURL: nil,
            directFileExtension: nil
        )
    }

    private func deduplicatedResults(from results: [OnlineTrackResult]) -> [OnlineTrackResult] {
        var seenIDs = Set<String>()
        var seenMetadataKeys = Set<String>()

        return results.filter { result in
            guard !result.id.isEmpty else { return false }
            guard !seenIDs.contains(result.id) else { return false }
            let metadataKey = normalizedMetadataKey(for: result)
            if !metadataKey.isEmpty, seenMetadataKeys.contains(metadataKey) {
                return false
            }
            seenIDs.insert(result.id)
            if !metadataKey.isEmpty {
                seenMetadataKeys.insert(metadataKey)
            }
            return true
        }
    }

    private func cachedTemporaryFile(for sourceID: String) -> URL? {
        for fileExtension in supportedFileExtensions {
            let candidateURL = AppFileManager.shared.temporaryAudioURL(for: sourceID, fileExtension: fileExtension)
            if fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return nil
    }

    private func fetchData(for request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OnlineMusicServiceError.networkFailure(
                "Network request failed while contacting \(request.url?.host ?? "the online provider")."
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnlineMusicServiceError.networkFailure("The online provider returned an invalid response.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OnlineMusicServiceError.networkFailure(
                "The online provider returned HTTP \(httpResponse.statusCode)."
            )
        }

        return data
    }

    private func decodeJSONValue(from data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw OnlineMusicServiceError.extractionFailure("The online provider returned malformed JSON.")
        }
    }

    private func decodeJSONObject(from data: Data) throws -> [String: Any] {
        guard let dictionary = try decodeJSONValue(from: data) as? [String: Any] else {
            throw OnlineMusicServiceError.extractionFailure("The online provider returned an unexpected JSON payload.")
        }

        return dictionary
    }

    private func extractJSONAssignment(in html: String, markers: [String]) -> String? {
        for marker in markers {
            guard let markerRange = html.range(of: marker) else { continue }
            let tail = html[markerRange.upperBound...]

            guard let jsonStart = tail.firstIndex(of: "{") else { continue }
            if let json = balancedJSONObject(in: html, startingAt: jsonStart) {
                return json
            }
        }

        return nil
    }

    // YouTube embeds a JSON blob directly in the HTML, so we need to walk braces safely.
    private func balancedJSONObject(in text: String, startingAt startIndex: String.Index) -> String? {
        var depth = 0
        var isInsideString = false
        var isEscaping = false
        var index = startIndex

        while index < text.endIndex {
            let character = text[index]

            if isEscaping {
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else if character == "\"" {
                isInsideString.toggle()
            } else if !isInsideString {
                if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(text[startIndex...index])
                    }
                }
            }

            index = text.index(after: index)
        }

        return nil
    }

    private func collectDictionaries(forKey targetKey: String, in value: Any) -> [[String: Any]] {
        var matches: [[String: Any]] = []

        if let dictionary = value as? [String: Any] {
            for (key, nestedValue) in dictionary {
                if key == targetKey, let nestedDictionary = nestedValue as? [String: Any] {
                    matches.append(nestedDictionary)
                } else {
                    matches.append(contentsOf: collectDictionaries(forKey: targetKey, in: nestedValue))
                }
            }
        } else if let array = value as? [Any] {
            for item in array {
                matches.append(contentsOf: collectDictionaries(forKey: targetKey, in: item))
            }
        }

        return matches
    }

    private func textValue(from value: Any?) -> String? {
        if let string = value as? String {
            return string
        }

        if let number = value as? NSNumber {
            return number.stringValue
        }

        if let dictionary = value as? [String: Any] {
            if let simpleText = dictionary["simpleText"] as? String {
                return simpleText
            }

            if let text = dictionary["text"] as? String {
                return text
            }

            if let runs = dictionary["runs"] as? [Any] {
                let joined = runs.compactMap { textValue(from: $0) }.joined(separator: " ")
                if !joined.isEmpty {
                    return joined
                }
            }

            if let contents = dictionary["contents"] as? [Any] {
                let joined = contents.compactMap { textValue(from: $0) }.joined(separator: " ")
                if !joined.isEmpty {
                    return joined
                }
            }
        }

        if let array = value as? [Any] {
            let joined = array.compactMap { textValue(from: $0) }.joined(separator: " ")
            return joined.isEmpty ? nil : joined
        }

        return nil
    }

    private func extractThumbnailURL(from value: Any?, host: URL) -> URL? {
        if let dictionary = value as? [String: Any] {
            if let thumbnails = dictionary["thumbnails"] as? [Any],
               let lastURL = thumbnails.compactMap({ item -> URL? in
                   guard let thumbnail = item as? [String: Any],
                         let rawURL = cleanedText(thumbnail["url"] as? String) else {
                       return nil
                   }

                   return normalizedMediaURL(rawURL, host: host)
               }).last {
                return lastURL
            }

            if let rawURL = cleanedText(dictionary["url"] as? String) {
                return normalizedMediaURL(rawURL, host: host)
            }
        }

        return nil
    }

    private func normalizedMediaURL(_ rawValue: String?, host: URL) -> URL? {
        guard let rawValue = cleanedText(rawValue) else { return nil }

        if let absoluteURL = URL(string: rawValue), absoluteURL.scheme != nil {
            return absoluteURL
        }

        if rawValue.hasPrefix("//") {
            return URL(string: "https:\(rawValue)")
        }

        if rawValue.hasPrefix("/") {
            return URL(string: rawValue, relativeTo: host)?.absoluteURL
        }

        return host.appendingPathComponent(rawValue)
    }

    private func isValidDownloadURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }

    private func parseDuration(_ value: String?) -> TimeInterval {
        guard let cleaned = cleanedText(value) else { return 0 }

        let components = cleaned
            .split(separator: ":")
            .compactMap { Int($0) }

        guard !components.isEmpty else { return 0 }

        return TimeInterval(components.reversed().enumerated().reduce(0) { partial, pair in
            partial + pair.element * Int(pow(60.0, Double(pair.offset)))
        })
    }

    private func timeIntervalValue(from value: Any?) -> TimeInterval? {
        if let timeInterval = value as? TimeInterval {
            return timeInterval
        }

        if let intValue = value as? Int {
            return TimeInterval(intValue)
        }

        if let doubleValue = value as? Double {
            return TimeInterval(doubleValue)
        }

        if let stringValue = value as? String,
           let doubleValue = Double(stringValue) {
            return TimeInterval(doubleValue)
        }

        return nil
    }

    private func extractVideoID(from rawValue: String?) -> String? {
        guard let rawValue = cleanedText(rawValue), !rawValue.isEmpty else { return nil }

        if rawValue.count == 11, !rawValue.contains("/") && !rawValue.contains("?") {
            return rawValue
        }

        if rawValue.hasPrefix("/watch"),
           let components = URLComponents(string: "https://www.youtube.com\(rawValue)"),
           let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value,
           !videoID.isEmpty {
            return videoID
        }

        if let url = URL(string: rawValue),
           let host = url.host?.lowercased() {
            if host.contains("youtube.com") || host.contains("youtu.be") {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value,
                   !videoID.isEmpty {
                    return videoID
                }

                let lastPathComponent = url.lastPathComponent
                if !lastPathComponent.isEmpty, lastPathComponent != "watch" {
                    return lastPathComponent
                }
            }
        }

        return nil
    }

    private func summarizedFailureMessage(from failures: [String], fallback: String) -> String {
        let uniqueMessages = orderedUniqueValues(from: failures.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter { !$0.isEmpty }

        guard let firstMessage = uniqueMessages.first else {
            return fallback
        }

        if uniqueMessages.count == 1 {
            return firstMessage
        }

        return "\(firstMessage) \(uniqueMessages[1])"
    }

    private func orderedUniqueValues(from values: [String]) -> [String] {
        var seen = Set<String>()
        var uniqueValues: [String] = []

        for value in values where !seen.contains(value) {
            seen.insert(value)
            uniqueValues.append(value)
        }

        return uniqueValues
    }

    private func bestResolutionError(from errors: [OnlineMusicServiceError]) -> OnlineMusicServiceError {
        if let unsupportedError = errors.first(where: {
            if case .unsupportedSource(_) = $0 { return true }
            return false
        }) {
            return unsupportedError
        }

        if let invalidAudioURLError = errors.first(where: {
            if case .invalidAudioURL(_) = $0 { return true }
            return false
        }) {
            return invalidAudioURLError
        }

        if let extractionError = errors.first(where: {
            if case .extractionFailure(_) = $0 { return true }
            return false
        }) {
            return extractionError
        }

        if let tempWriteError = errors.first(where: {
            if case .tempFileWriteFailure(_) = $0 { return true }
            return false
        }) {
            return tempWriteError
        }

        if let networkError = errors.first(where: {
            if case .networkFailure(_) = $0 { return true }
            return false
        }) {
            return networkError
        }

        return errors.first ?? .unavailableSources
    }

    private func pipedHosts() async -> [URL] {
        let discoveredHosts = await fetchPipedHostsFromIndexes()
        return orderedUniqueURLs(from: discoveredHosts + fallbackPipedHosts)
    }

    private func fetchPipedHostsFromIndexes() async -> [URL] {
        var discoveredHosts: [URL] = []

        for indexURL in pipedInstanceIndexURLs {
            var request = URLRequest(url: indexURL)
            request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,text/plain;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

            do {
                let data = try await fetchData(for: request)
                guard let body = String(data: data, encoding: .utf8), !body.isEmpty else { continue }
                discoveredHosts.append(contentsOf: extractPipedHosts(from: body))
                if !discoveredHosts.isEmpty {
                    break
                }
            } catch {
                debugLog("Failed to load dynamic Piped hosts from \(indexURL.absoluteString): \(error.localizedDescription)")
            }
        }

        return discoveredHosts
    }

    private func extractPipedHosts(from text: String) -> [URL] {
        let pattern = #"https://(?:api-piped|pipedapi|piped-api)[A-Za-z0-9.\-]*"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)

        return orderedUniqueURLs(
            from: matches.compactMap { match in
                guard let matchRange = Range(match.range, in: text) else { return nil }
                return URL(string: String(text[matchRange]))
            }
        )
    }

    private func orderedUniqueURLs(from urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var uniqueURLs: [URL] = []

        for url in urls {
            let normalized = url.absoluteString.lowercased()
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            uniqueURLs.append(url)
        }

        return uniqueURLs
    }

    private func normalizedMetadataKey(for result: OnlineTrackResult) -> String {
        let title = normalizedComparisonValue(result.title)
        let artist = normalizedComparisonValue(result.artist)

        guard !title.isEmpty || !artist.isEmpty else { return "" }
        return "\(title)|\(artist)"
    }

    private func normalizedComparisonValue(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func normalizedAppleArtworkURL(from rawValue: String?) -> String? {
        guard let rawValue = cleanedText(rawValue) else { return nil }

        return rawValue
            .replacingOccurrences(of: "100x100bb", with: "600x600bb")
            .replacingOccurrences(of: "60x60bb", with: "600x600bb")
    }

    private func preferredApplePreviewDuration(trackTimeMillis: Int?) -> TimeInterval {
        guard let trackTimeMillis, trackTimeMillis > 0 else {
            return 30
        }

        return min(TimeInterval(trackTimeMillis) / 1000, 30)
    }

    private func fileExtension(fromDownloadURLString rawValue: String, fallback: String) -> String {
        guard let url = URL(string: rawValue) else {
            return fallback
        }

        let pathExtension = url.pathExtension.lowercased()
        return pathExtension.isEmpty ? fallback : preferredFileExtension(mimeType: "", container: pathExtension)
    }

    private func cleanedText(_ value: String?) -> String? {
        guard let value else { return nil }

        let normalized = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized.isEmpty ? nil : normalized
    }

    private var browserUserAgent: String {
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    }

    private var supportedFileExtensions: [String] {
        ["m4a", "mp4", "aac", "webm", "mp3"]
    }
}

private struct SearchAttempt {
    let results: [OnlineTrackResult]
    let reachedProvider: Bool
}

private struct ResolvedAudioStream {
    let url: URL
    let fileExtension: String
    let bitrate: Int
    let mimeType: String
    let providerName: String
}

private struct AppleMusicPreviewSearchResponse: Decodable {
    let results: [AppleMusicPreviewItem]
}

private struct AppleMusicPreviewItem: Decodable {
    let trackID: Int?
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let trackTimeMillis: Int?
    let artworkURL100: String?
    let trackViewURL: String?
    let previewURL: String?

    enum CodingKeys: String, CodingKey {
        case trackID = "trackId"
        case trackName
        case artistName
        case collectionName
        case trackTimeMillis
        case artworkURL100 = "artworkUrl100"
        case trackViewURL = "trackViewUrl"
        case previewURL = "previewUrl"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trackID = container.decodeLossyInt(forKey: .trackID)
        trackName = try container.decodeIfPresent(String.self, forKey: .trackName)
        artistName = try container.decodeIfPresent(String.self, forKey: .artistName)
        collectionName = try container.decodeIfPresent(String.self, forKey: .collectionName)
        trackTimeMillis = container.decodeLossyInt(forKey: .trackTimeMillis)
        artworkURL100 = try container.decodeIfPresent(String.self, forKey: .artworkURL100)
        trackViewURL = try container.decodeIfPresent(String.self, forKey: .trackViewURL)
        previewURL = try container.decodeIfPresent(String.self, forKey: .previewURL)
    }
}

private struct PipedStreamPayload: Decodable {
    let audioStreams: [PipedAudioStream]
    let livestream: Bool
    let hls: String?

    enum CodingKeys: String, CodingKey {
        case audioStreams
        case livestream
        case hls
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        audioStreams = try container.decodeIfPresent([PipedAudioStream].self, forKey: .audioStreams) ?? []
        livestream = try container.decodeIfPresent(Bool.self, forKey: .livestream) ?? false
        hls = try container.decodeIfPresent(String.self, forKey: .hls)
    }
}

private struct PipedAudioStream: Decodable {
    let bitrate: Int
    let format: String?
    let mimeType: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case bitrate
        case format
        case mimeType
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bitrate = container.decodeLossyInt(forKey: .bitrate) ?? 0
        format = try container.decodeIfPresent(String.self, forKey: .format)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        url = try container.decodeIfPresent(String.self, forKey: .url)
    }
}

private struct InvidiousSearchItem: Decodable {
    let type: String
    let title: String
    let videoID: String
    let author: String
    let lengthSeconds: TimeInterval
    let thumbnails: [InvidiousThumbnail]

    enum CodingKeys: String, CodingKey {
        case type
        case title
        case videoID = "videoId"
        case author
        case lengthSeconds
        case thumbnails = "videoThumbnails"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        videoID = try container.decodeIfPresent(String.self, forKey: .videoID) ?? ""
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        lengthSeconds = container.decodeLossyDouble(forKey: .lengthSeconds) ?? 0
        thumbnails = try container.decodeIfPresent([InvidiousThumbnail].self, forKey: .thumbnails) ?? []
    }
}

private struct InvidiousThumbnail: Decodable {
    let url: String?
}

private struct InvidiousVideoInfo: Decodable {
    let adaptiveFormats: [InvidiousAdaptiveFormat]

    enum CodingKeys: String, CodingKey {
        case adaptiveFormats
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        adaptiveFormats = try container.decodeIfPresent([InvidiousAdaptiveFormat].self, forKey: .adaptiveFormats) ?? []
    }
}

private struct InvidiousAdaptiveFormat: Decodable {
    let type: String?
    let bitrate: Int
    let url: String?
    let container: String?

    enum CodingKeys: String, CodingKey {
        case type
        case bitrate
        case url
        case container
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        bitrate = container.decodeLossyInt(forKey: .bitrate) ?? 0
        url = try container.decodeIfPresent(String.self, forKey: .url)
        self.container = try container.decodeIfPresent(String.self, forKey: .container)
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }

        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }

        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }

        return nil
    }

    func decodeLossyInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }

        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }

        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }

        return nil
    }
}
