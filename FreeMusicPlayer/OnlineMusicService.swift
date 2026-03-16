//
//  OnlineMusicService.swift
//  FreeMusicPlayer
//
//  Online search and audio retrieval inspired by Yukki's YouTube-first flow,
//  adapted for a native iOS app without Telegram or Python bot layers.
//

import Foundation

struct OnlineTrackResult: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let duration: TimeInterval
    let coverArtURL: String?
    let webpageURL: String
    
    var formattedDuration: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

enum OnlineMusicServiceError: LocalizedError {
    case invalidQuery
    case unavailableSources
    case invalidResponse
    case noPlayableAudio
    case downloadFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "Enter a search query first."
        case .unavailableSources:
            return "Online music sources are unavailable right now."
        case .invalidResponse:
            return "The online source returned an invalid response."
        case .noPlayableAudio:
            return "No playable audio stream was found for this track."
        case .downloadFailed:
            return "The audio download failed."
        }
    }
}

final class OnlineMusicService {
    static let shared = OnlineMusicService()
    
    private let fileManager = FileManager.default
    private let session: URLSession
    private let apiHosts: [URL] = [
        URL(string: "https://vid.puffyan.us")!,
        URL(string: "https://invidious.fdn.fr")!,
        URL(string: "https://yewtu.be")!,
        URL(string: "https://inv.nadeko.net")!,
    ]
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 120
        session = URLSession(configuration: configuration)
    }
    
    func search(_ query: String) async throws -> [OnlineTrackResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw OnlineMusicServiceError.invalidQuery
        }
        
        var reachedHealthySource = false
        
        for host in apiHosts {
            do {
                let results = try await search(query: trimmedQuery, host: host)
                reachedHealthySource = true
                if !results.isEmpty {
                    return results
                }
            } catch {
                debugLog("Online search failed for host \(host.absoluteString): \(error.localizedDescription)")
            }
        }
        
        if reachedHealthySource {
            return []
        }
        
        throw OnlineMusicServiceError.unavailableSources
    }
    
    func downloadAudio(for result: OnlineTrackResult) async throws -> URL {
        let existingExtensions = ["m4a", "mp4", "webm", "mp3"]
        for fileExtension in existingExtensions {
            let candidateURL = AppFileManager.shared.temporaryAudioURL(for: result.id, fileExtension: fileExtension)
            if fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }
        
        let stream = try await resolveAudioStream(for: result.id)
        let (downloadURL, response) = try await session.download(from: stream.url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw OnlineMusicServiceError.downloadFailed
        }
        
        let destinationURL = AppFileManager.shared.temporaryAudioURL(
            for: result.id,
            fileExtension: stream.fileExtension
        )
        
        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }
        
        do {
            try fileManager.copyItem(at: downloadURL, to: destinationURL)
            return destinationURL
        } catch {
            debugLog("Failed to copy downloaded audio: \(error.localizedDescription)")
            throw OnlineMusicServiceError.downloadFailed
        }
    }
    
    private func search(query: String, host: URL) async throws -> [OnlineTrackResult] {
        var components = URLComponents(url: host.appendingPathComponent("api/v1/search"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "video"),
        ]
        
        guard let url = components?.url else {
            throw OnlineMusicServiceError.invalidResponse
        }
        
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw OnlineMusicServiceError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        let payload = try decoder.decode([InvidiousSearchItem].self, from: data)
        
        return payload
            .filter { $0.type.lowercased() == "video" && !$0.videoID.isEmpty }
            .prefix(20)
            .map { item in
                OnlineTrackResult(
                    id: item.videoID,
                    title: item.title,
                    artist: item.author,
                    duration: item.lengthSeconds,
                    coverArtURL: normalizedArtworkURL(item.thumbnails.last?.url, host: host)?.absoluteString,
                    webpageURL: "https://www.youtube.com/watch?v=\(item.videoID)"
                )
            }
    }
    
    private func resolveAudioStream(for videoID: String) async throws -> ResolvedAudioStream {
        for host in apiHosts {
            do {
                return try await resolveAudioStream(for: videoID, host: host)
            } catch {
                debugLog("Audio resolve failed for host \(host.absoluteString): \(error.localizedDescription)")
            }
        }
        
        throw OnlineMusicServiceError.noPlayableAudio
    }
    
    private func resolveAudioStream(for videoID: String, host: URL) async throws -> ResolvedAudioStream {
        let url = host.appendingPathComponent("api/v1/videos").appendingPathComponent(videoID)
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw OnlineMusicServiceError.invalidResponse
        }
        
        let payload = try JSONDecoder().decode(InvidiousVideoInfo.self, from: data)
        
        let candidateStreams = payload.adaptiveFormats.compactMap { format -> ResolvedAudioStream? in
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
                mimeType: mimeType
            )
        }
        
        guard let preferredStream = candidateStreams
            .sorted(by: { left, right in
                audioPreferenceScore(for: left) > audioPreferenceScore(for: right)
            })
            .first else {
            throw OnlineMusicServiceError.noPlayableAudio
        }
        
        return preferredStream
    }
    
    private func audioPreferenceScore(for stream: ResolvedAudioStream) -> Int {
        var score = stream.bitrate
        
        if stream.mimeType.contains("audio/mp4") || stream.fileExtension == "m4a" || stream.fileExtension == "mp4" {
            score += 100_000
        }
        
        if stream.mimeType.contains("aac") || stream.mimeType.contains("mp4a") {
            score += 50_000
        }
        
        return score
    }
    
    private func preferredFileExtension(mimeType: String, container: String?) -> String {
        if let container, !container.isEmpty {
            return container == "mp4" ? "m4a" : container
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
    
    private func normalizedArtworkURL(_ rawValue: String?, host: URL) -> URL? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        return normalizedMediaURL(rawValue, host: host)
    }
    
    private func normalizedMediaURL(_ rawValue: String, host: URL) -> URL? {
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
}

private struct ResolvedAudioStream {
    let url: URL
    let fileExtension: String
    let bitrate: Int
    let mimeType: String
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
