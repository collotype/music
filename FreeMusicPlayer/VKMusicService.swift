//
//  VKMusicService.swift
//  FreeMusicPlayer
//
//  VK audio search and direct audio download integration.
//

import Foundation

struct VKTrack: Decodable, Equatable, Sendable {
    let id: Int?
    let ownerID: Int?
    let artist: String?
    let title: String?
    let duration: Int?
    let url: String?
    let accessKey: String?
    let album: VKAlbum?
    let mainArtists: [VKArtist]?
    let date: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case artist
        case title
        case duration
        case url
        case accessKey = "access_key"
        case album
        case mainArtists = "main_artists"
        case date
    }
}

struct VKArtist: Decodable, Equatable, Sendable {
    let name: String?
    let domain: String?
}

struct VKAlbum: Decodable, Equatable, Sendable {
    let id: Int?
    let ownerID: Int?
    let title: String?
    let accessKey: String?
    let thumb: VKAudioThumb?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case title
        case accessKey = "access_key"
        case thumb
    }
}

struct VKAudioThumb: Decodable, Equatable, Sendable {
    let photo34: String?
    let photo68: String?
    let photo135: String?
    let photo270: String?
    let photo300: String?
    let photo600: String?
    let photo1200: String?

    enum CodingKeys: String, CodingKey {
        case photo34 = "photo_34"
        case photo68 = "photo_68"
        case photo135 = "photo_135"
        case photo270 = "photo_270"
        case photo300 = "photo_300"
        case photo600 = "photo_600"
        case photo1200 = "photo_1200"
    }
}

final class VKMusicService {
    private let fileManager = FileManager.default
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let logger: @Sendable (String) -> Void

    private let searchURL = URL(string: "https://api.vk.com/method/audio.search")!
    private let vkHomepageURL = URL(string: "https://vk.com/")!
    private let defaultAPIVersion = "5.131"
    private let searchLimit = 50
    private let browserUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    init(
        session: URLSession,
        logger: @escaping @Sendable (String) -> Void
    ) {
        self.session = session
        self.logger = logger
    }

    var isConfigured: Bool {
        configuration != nil
    }

    func search(query: String) async throws -> [Track] {
        try await searchResults(query: query).map { makeTrack(from: $0) }
    }

    func searchResults(
        query: String,
        count: Int? = nil,
        offset: Int = 0
    ) async throws -> [OnlineTrackResult] {
        guard let cleanedQuery = cleanedText(query) else {
            throw OnlineMusicServiceError.invalidQuery
        }

        let configuration = try configurationOrThrow()
        let resolvedCount = min(max(count ?? searchLimit, 1), 200)
        let resolvedOffset = max(offset, 0)

        var components = URLComponents(url: searchURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: cleanedQuery),
            URLQueryItem(name: "count", value: String(resolvedCount)),
            URLQueryItem(name: "offset", value: String(resolvedOffset)),
            URLQueryItem(name: "access_token", value: configuration.accessToken),
            URLQueryItem(name: "v", value: configuration.apiVersion)
        ]

        guard let requestURL = components?.url else {
            throw OnlineMusicServiceError.networkFailure("VK search URL could not be created.")
        }

        logger("VK URL: \(redactedURLString(requestURL))")
        let data = try await fetchVKData(from: requestURL)

        let envelope: VKAudioSearchEnvelope
        do {
            envelope = try decoder.decode(VKAudioSearchEnvelope.self, from: data)
        } catch {
            logger("VK decode error: \(error.localizedDescription)")
            throw OnlineMusicServiceError.extractionFailure("VK search returned malformed JSON.")
        }

        if let apiError = envelope.error {
            throw serviceError(from: apiError)
        }

        guard let response = envelope.response else {
            throw OnlineMusicServiceError.extractionFailure("VK search returned no response payload.")
        }

        return deduplicatedTrackResults(
            response.items.compactMap { makeOnlineTrackResult(from: $0) }
        )
    }

    func download(track: Track) async throws -> URL {
        guard track.source == .vk else {
            throw OnlineMusicServiceError.unsupportedSource("Only VK tracks can be downloaded by VKMusicService.")
        }

        guard let sourceID = cleanedText(track.sourceID) else {
            throw OnlineMusicServiceError.unsupportedSource("This VK track is missing the metadata needed to download it.")
        }

        guard let directURL = validHTTPURL(from: track.fileURL) else {
            throw OnlineMusicServiceError.invalidAudioURL("VK did not return a direct audio URL for this track.")
        }

        return try await downloadAudio(
            from: directURL,
            sourceID: sourceID,
            expectedDuration: track.duration,
            fallbackFileExtension: directURL.pathExtension
        )
    }

    func download(result: OnlineTrackResult) async throws -> URL {
        guard result.provider == .vk else {
            throw OnlineMusicServiceError.unsupportedSource(result.offlineDownloadUnavailableMessage)
        }

        guard let directURL = validHTTPURL(from: result.directAudioURL) else {
            throw OnlineMusicServiceError.invalidAudioURL("VK did not return a direct audio URL for this track.")
        }

        return try await downloadAudio(
            from: directURL,
            sourceID: result.id,
            expectedDuration: result.duration,
            fallbackFileExtension: result.directFileExtension
        )
    }

    func resolvePlaybackStream(for result: OnlineTrackResult) async throws -> ResolvedAudioStream {
        guard result.provider == .vk else {
            throw OnlineMusicServiceError.unsupportedSource(result.playbackUnavailableMessage)
        }

        guard let directURL = validHTTPURL(from: result.directAudioURL) else {
            throw OnlineMusicServiceError.invalidAudioURL("VK did not return a direct audio URL for this track.")
        }

        return ResolvedAudioStream(
            url: directURL,
            providerName: result.providerDisplayName,
            streamType: "direct_url"
        )
    }

    func onlineTrackResult(from track: Track) throws -> OnlineTrackResult {
        guard track.source == .vk else {
            throw OnlineMusicServiceError.unsupportedSource("Only VK tracks can be converted to VK search results.")
        }

        guard let sourceID = cleanedText(track.sourceID),
              let providerTrackURN = providerTrackURN(fromSourceID: sourceID) else {
            throw OnlineMusicServiceError.unsupportedSource("This VK track is missing the metadata needed to add it to your library.")
        }

        let directAudioURL = validHTTPURLString(track.fileURL)
        let webpageURL = cleanedText(track.remotePageURL) ?? fallbackWebpageURL(for: providerTrackURN)

        return OnlineTrackResult(
            provider: .vk,
            providerTrackURN: providerTrackURN,
            providerArtistID: cleanedText(track.providerArtistID),
            title: track.displayTitle,
            artist: track.displayArtist,
            album: track.album,
            genres: track.genres,
            tags: track.tags,
            moods: track.moods,
            duration: track.duration,
            coverArtURL: track.preferredArtworkReference,
            artistImageURL: track.preferredArtistImageReference,
            webpageURL: webpageURL,
            artistWebpageURL: cleanedText(track.artistWebpageURL),
            playbackCount: nil,
            likesCount: nil,
            releaseDate: nil,
            directAudioURL: directAudioURL,
            directFileExtension: directAudioURL.flatMap { fileExtension(fromURLString: $0) },
            trackAuthorization: nil,
            playbackStreams: []
        )
    }

    private func makeOnlineTrackResult(from track: VKTrack) -> OnlineTrackResult? {
        guard let trackID = track.id,
              let ownerID = track.ownerID else {
            return nil
        }

        let accessKey = cleanedText(track.accessKey)
        let providerTrackURN = vkTrackURN(ownerID: ownerID, trackID: trackID, accessKey: accessKey)
        let directAudioURL = validHTTPURLString(track.url)
        let title = cleanedText(track.title) ?? "Untitled Track"
        let mainArtistNames = track.mainArtists?.compactMap { cleanedText($0.name) } ?? []
        let artist = cleanedText(track.artist) ??
            cleanedText(mainArtistNames.joined(separator: ", ")) ??
            "Unknown Artist"
        let webpageURL = vkAudioPageURL(ownerID: ownerID, trackID: trackID).absoluteString
        let artistWebpageURL = vkArtistWebpageURL(from: track.mainArtists?.first)
        let releaseDate = track.date.flatMap { timestamp -> Date? in
            guard timestamp > 0 else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(timestamp))
        }

        return OnlineTrackResult(
            provider: .vk,
            providerTrackURN: providerTrackURN,
            providerArtistID: nil,
            title: title,
            artist: artist,
            album: cleanedText(track.album?.title),
            genres: [],
            tags: [],
            moods: [],
            duration: TimeInterval(track.duration ?? 0),
            coverArtURL: bestArtworkURL(from: track.album?.thumb),
            artistImageURL: nil,
            webpageURL: webpageURL,
            artistWebpageURL: artistWebpageURL,
            playbackCount: nil,
            likesCount: nil,
            releaseDate: releaseDate,
            directAudioURL: directAudioURL,
            directFileExtension: directAudioURL.flatMap { fileExtension(fromURLString: $0) },
            trackAuthorization: accessKey,
            playbackStreams: []
        )
    }

    private func makeTrack(from result: OnlineTrackResult) -> Track {
        Track(
            title: result.title,
            artist: result.artist,
            album: result.album,
            genres: result.genres,
            tags: result.tags,
            moods: result.moods,
            duration: result.duration,
            fileURL: result.directAudioURL,
            coverArtURL: result.coverArtURL,
            source: .vk,
            isLiked: false,
            playCount: 0,
            lastPlayed: nil,
            addedAt: Date(),
            sourceID: result.id,
            remotePageURL: result.webpageURL,
            storageLocation: .remote,
            remoteCoverArtURL: result.coverArtURL,
            artistImageURL: result.artistImageURL,
            remoteArtistImageURL: result.artistImageURL,
            providerArtistID: result.providerArtistID,
            artistWebpageURL: result.artistWebpageURL
        )
    }

    private func fetchVKData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(vkHomepageURL.absoluteString, forHTTPHeaderField: "Referer")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger("VK request error: \(error.localizedDescription)")
            throw OnlineMusicServiceError.networkFailure("The VK request could not be completed.")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnlineMusicServiceError.networkFailure("VK returned an invalid response.")
        }

        logger("VK status: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            throw OnlineMusicServiceError.networkFailure("VK returned HTTP \(httpResponse.statusCode).")
        }

        return data
    }

    private func downloadAudio(
        from remoteURL: URL,
        sourceID: String,
        expectedDuration: TimeInterval,
        fallbackFileExtension: String?
    ) async throws -> URL {
        if expectedDuration > 7200 {
            throw OnlineMusicServiceError.unsupportedSource(
                "This track is too long to download. Tracks over 2 hours are not supported."
            )
        }

        if let cachedURL = cachedTemporaryFile(for: sourceID, fallbackFileExtension: fallbackFileExtension),
           (fileSize(at: cachedURL) ?? 0) > 0 {
            logger("Using cached VK temp audio for \(sourceID): \(cachedURL.path)")
            return cachedURL
        }

        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("audio/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(vkHomepageURL.absoluteString, forHTTPHeaderField: "Referer")

        let temporaryURL: URL
        let response: URLResponse

        do {
            (temporaryURL, response) = try await session.download(for: request)
        } catch {
            logger("VK download error for \(sourceID): \(error.localizedDescription)")
            throw OnlineMusicServiceError.networkFailure("The VK audio download could not be completed.")
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw OnlineMusicServiceError.networkFailure("VK audio download returned HTTP \(httpResponse.statusCode).")
        }

        let fileExtension = preferredFileExtension(
            mimeType: response.mimeType,
            resolvedURL: remoteURL,
            fallbackFileExtension: fallbackFileExtension
        )
        let destinationURL = AppFileManager.shared.temporaryAudioURL(
            for: sourceID,
            fileExtension: fileExtension
        )

        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            logger("VK temp audio move failed for \(sourceID): \(error.localizedDescription)")
            throw OnlineMusicServiceError.tempFileWriteFailure("The downloaded VK audio could not be stored in temporary app storage.")
        }

        guard (fileSize(at: destinationURL) ?? 0) > 0 else {
            try? fileManager.removeItem(at: destinationURL)
            throw OnlineMusicServiceError.extractionFailure("VK returned an empty audio file.")
        }

        logger("Stored VK download in app temp storage: \(destinationURL.path)")
        return destinationURL
    }

    private var configuration: VKConfiguration? {
        let rawAccessToken = Bundle.main.object(forInfoDictionaryKey: VKInfoPlistKeys.accessToken) as? String
        let rawAPIVersion = Bundle.main.object(forInfoDictionaryKey: VKInfoPlistKeys.apiVersion) as? String

        guard let accessToken = sanitizedVKAccessToken(rawAccessToken) else {
            return nil
        }

        return VKConfiguration(
            accessToken: accessToken,
            apiVersion: sanitizedVKAPIVersion(rawAPIVersion) ?? defaultAPIVersion
        )
    }

    private func configurationOrThrow() throws -> VKConfiguration {
        guard let configuration else {
            logger("VKAccessToken loaded: missing")
            throw OnlineMusicServiceError.configurationMissing(
                "VK search requires the Info.plist key VKAccessToken with a token that can call audio.search."
            )
        }

        logger("VKAccessToken loaded: \(maskedToken(configuration.accessToken))")
        logger("VK API version: \(configuration.apiVersion)")
        return configuration
    }

    private func sanitizedVKAccessToken(_ rawValue: String?) -> String? {
        guard let cleanedValue = cleanedText(rawValue) else { return nil }

        let normalizedValue = cleanedValue.lowercased()
        let placeholderMarkers = [
            "your_vk_access_token",
            "<your vk access token>",
            "insert_vk_access_token"
        ]

        if placeholderMarkers.contains(where: normalizedValue.contains) {
            return nil
        }

        if cleanedValue.hasPrefix("$(") && cleanedValue.hasSuffix(")") {
            return nil
        }

        return cleanedValue
    }

    private func sanitizedVKAPIVersion(_ rawValue: String?) -> String? {
        guard let cleanedValue = cleanedText(rawValue) else { return nil }
        return cleanedValue
    }

    private func serviceError(from apiError: VKAPIError) -> OnlineMusicServiceError {
        let providerMessage = cleanedText(apiError.errorMsg) ?? "VK returned API error \(apiError.errorCode)."

        if apiError.errorCode == 5 {
            return .authenticationRequired("VK access token was rejected. Update VKAccessToken and try again.")
        }

        return .networkFailure("VK returned API error \(apiError.errorCode): \(providerMessage)")
    }

    private func bestArtworkURL(from thumb: VKAudioThumb?) -> String? {
        [
            thumb?.photo1200,
            thumb?.photo600,
            thumb?.photo300,
            thumb?.photo270,
            thumb?.photo135,
            thumb?.photo68,
            thumb?.photo34
        ]
        .compactMap { validHTTPURLString($0) }
        .first
    }

    private func vkArtistWebpageURL(from artist: VKArtist?) -> String? {
        if let domain = cleanedText(artist?.domain) {
            return "https://vk.com/\(domain)"
        }

        return nil
    }

    private func vkAudioPageURL(ownerID: Int, trackID: Int) -> URL {
        URL(string: "https://vk.com/audio\(ownerID)_\(trackID)")!
    }

    private func vkTrackURN(ownerID: Int, trackID: Int, accessKey: String?) -> String {
        let baseURN = "audio\(ownerID)_\(trackID)"

        guard let accessKey else {
            return baseURN
        }

        return "\(baseURN)_\(accessKey)"
    }

    private func providerTrackURN(fromSourceID sourceID: String) -> String? {
        if sourceID.hasPrefix("\(OnlineTrackProvider.vk.rawValue):") {
            return cleanedText(String(sourceID.dropFirst(OnlineTrackProvider.vk.rawValue.count + 1)))
        }

        return cleanedText(sourceID)
    }

    private func fallbackWebpageURL(for providerTrackURN: String) -> String {
        let pieces = providerTrackURN.split(separator: "_")
        guard let firstPiece = pieces.first,
              firstPiece.hasPrefix("audio") else {
            return vkHomepageURL.absoluteString
        }

        if pieces.count > 1 {
            return "https://vk.com/\(firstPiece)_\(pieces[1])"
        }

        return "https://vk.com/\(firstPiece)"
    }

    private func validHTTPURL(from rawValue: String?) -> URL? {
        guard let cleanedValue = validHTTPURLString(rawValue) else {
            return nil
        }

        return URL(string: cleanedValue)
    }

    private func validHTTPURLString(_ rawValue: String?) -> String? {
        guard let cleanedValue = cleanedText(rawValue),
              let parsedURL = URL(string: cleanedValue),
              let scheme = parsedURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return cleanedValue
    }

    private func fileExtension(fromURLString urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        return sanitizedFileExtension(url.pathExtension)
    }

    private func preferredFileExtension(
        mimeType: String?,
        resolvedURL: URL,
        fallbackFileExtension: String?
    ) -> String {
        let normalizedMimeType = mimeType?.lowercased() ?? ""

        if normalizedMimeType.contains("mpeg") || normalizedMimeType.contains("mp3") {
            return "mp3"
        }

        if normalizedMimeType.contains("mp4") || normalizedMimeType.contains("aac") {
            return "m4a"
        }

        return sanitizedFileExtension(resolvedURL.pathExtension) ??
            sanitizedFileExtension(fallbackFileExtension) ??
            "m4a"
    }

    private func cachedTemporaryFile(
        for sourceID: String,
        fallbackFileExtension: String?
    ) -> URL? {
        let candidateExtensions = orderedUniqueValues(
            [
                sanitizedFileExtension(fallbackFileExtension),
                "mp3",
                "m4a",
                "aac"
            ].compactMap { $0 }
        )

        for fileExtension in candidateExtensions {
            let candidateURL = AppFileManager.shared.temporaryAudioURL(
                for: sourceID,
                fileExtension: fileExtension
            )
            if fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return nil
    }

    private func sanitizedFileExtension(_ rawValue: String?) -> String? {
        guard let cleanedValue = cleanedText(rawValue)?.lowercased() else {
            return nil
        }

        let allowedCharacters = CharacterSet.alphanumerics
        guard cleanedValue.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            return nil
        }

        return cleanedValue
    }

    private func fileSize(at url: URL) -> Int64? {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value
    }

    private func deduplicatedTrackResults(_ results: [OnlineTrackResult]) -> [OnlineTrackResult] {
        var seenIDs: Set<String> = []

        return results.filter { result in
            guard seenIDs.insert(result.id).inserted else { return false }
            return true
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

    private func cleanedText(_ value: String?) -> String? {
        guard let value else { return nil }

        let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedValue.isEmpty ? nil : cleanedValue
    }

    private func redactedURLString(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        components.queryItems = components.queryItems?.map { item in
            if item.name == "access_token" {
                return URLQueryItem(name: item.name, value: "<redacted>")
            }

            return item
        }

        return components.url?.absoluteString ?? url.absoluteString
    }

    private func maskedToken(_ token: String) -> String {
        guard token.count > 8 else { return token }
        return "\(token.prefix(4))...\(token.suffix(4))"
    }
}

private enum VKInfoPlistKeys {
    static let accessToken = "VKAccessToken"
    static let apiVersion = "VKAPIVersion"
}

private struct VKConfiguration {
    let accessToken: String
    let apiVersion: String
}

private struct VKAudioSearchEnvelope: Decodable {
    let response: VKAudioSearchResponse?
    let error: VKAPIError?
}

private struct VKAudioSearchResponse: Decodable {
    let count: Int?
    let items: [VKTrack]
}

private struct VKAPIError: Decodable {
    let errorCode: Int
    let errorMsg: String?

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case errorMsg = "error_msg"
    }
}
