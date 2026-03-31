//
//  Track.swift
//  FreeMusicPlayer
//
//  Track and navigation models.
//

import Foundation
import SwiftUI

struct Track: Identifiable, Codable, Equatable, Sendable {
    enum TrackSource: String, Codable, Sendable {
        case local
        case youtube
        case appleMusicPreview
        case soundcloud
        case spotify
    }

    enum StorageLocation: String, Codable, Sendable {
        case library
        case temp
        case remote
    }

    var id: String
    var title: String
    var artist: String
    var album: String?
    var genres: [String]
    var tags: [String]
    var moods: [String]
    var duration: TimeInterval
    var fileURL: String?
    var coverArtURL: String?
    var remoteCoverArtURL: String?
    var artistImageURL: String?
    var remoteArtistImageURL: String?
    var providerArtistID: String?
    var artistWebpageURL: String?
    var lyricsText: String?
    var lyricsSyncedText: String?
    var lyricsSource: String?
    var lyricsLastUpdated: Date?
    var lyricsURL: String?
    var source: TrackSource
    var isFavorite: Bool
    var playCount: Int
    var lastPlayed: Date?
    var addedAt: Date
    var sourceID: String?
    var remotePageURL: String?
    var storageLocation: StorageLocation
    var importOriginID: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        artist: String,
        album: String? = nil,
        genres: [String] = [],
        tags: [String] = [],
        moods: [String] = [],
        duration: TimeInterval,
        fileURL: String? = nil,
        coverArtURL: String? = nil,
        source: TrackSource = .local,
        isFavorite: Bool = false,
        playCount: Int = 0,
        lastPlayed: Date? = nil,
        addedAt: Date = Date(),
        sourceID: String? = nil,
        remotePageURL: String? = nil,
        storageLocation: StorageLocation = .library,
        importOriginID: String? = nil,
        remoteCoverArtURL: String? = nil,
        artistImageURL: String? = nil,
        remoteArtistImageURL: String? = nil,
        providerArtistID: String? = nil,
        artistWebpageURL: String? = nil,
        lyricsText: String? = nil,
        lyricsSyncedText: String? = nil,
        lyricsSource: String? = nil,
        lyricsLastUpdated: Date? = nil,
        lyricsURL: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.genres = genres
        self.tags = tags
        self.moods = moods
        self.duration = duration
        self.fileURL = fileURL
        self.coverArtURL = coverArtURL
        self.remoteCoverArtURL = remoteCoverArtURL
        self.artistImageURL = artistImageURL
        self.remoteArtistImageURL = remoteArtistImageURL
        self.providerArtistID = providerArtistID
        self.artistWebpageURL = artistWebpageURL
        self.lyricsText = lyricsText
        self.lyricsSyncedText = lyricsSyncedText
        self.lyricsSource = lyricsSource
        self.lyricsLastUpdated = lyricsLastUpdated
        self.lyricsURL = lyricsURL
        self.source = source
        self.isFavorite = isFavorite
        self.playCount = playCount
        self.lastPlayed = lastPlayed
        self.addedAt = addedAt
        self.sourceID = sourceID
        self.remotePageURL = remotePageURL
        self.storageLocation = storageLocation
        self.importOriginID = importOriginID
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case artist
        case album
        case genres
        case tags
        case moods
        case duration
        case fileURL
        case coverArtURL
        case remoteCoverArtURL
        case artistImageURL
        case remoteArtistImageURL
        case providerArtistID
        case artistWebpageURL
        case lyricsText
        case lyricsSyncedText
        case lyricsSource
        case lyricsLastUpdated
        case lyricsURL
        case source
        case isFavorite
        case playCount
        case lastPlayed
        case addedAt
        case sourceID
        case remotePageURL
        case storageLocation
        case importOriginID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        artist = try container.decodeIfPresent(String.self, forKey: .artist) ?? ""
        album = try container.decodeIfPresent(String.self, forKey: .album)
        genres = try container.decodeIfPresent([String].self, forKey: .genres) ?? []
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        moods = try container.decodeIfPresent([String].self, forKey: .moods) ?? []
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        fileURL = try container.decodeIfPresent(String.self, forKey: .fileURL)
        coverArtURL = try container.decodeIfPresent(String.self, forKey: .coverArtURL)
        remoteCoverArtURL = try container.decodeIfPresent(String.self, forKey: .remoteCoverArtURL)
        artistImageURL = try container.decodeIfPresent(String.self, forKey: .artistImageURL)
        remoteArtistImageURL = try container.decodeIfPresent(String.self, forKey: .remoteArtistImageURL)
        providerArtistID = try container.decodeIfPresent(String.self, forKey: .providerArtistID)
        artistWebpageURL = try container.decodeIfPresent(String.self, forKey: .artistWebpageURL)
        lyricsText = try container.decodeIfPresent(String.self, forKey: .lyricsText)
        lyricsSyncedText = try container.decodeIfPresent(String.self, forKey: .lyricsSyncedText)
        lyricsSource = try container.decodeIfPresent(String.self, forKey: .lyricsSource)
        lyricsLastUpdated = try container.decodeIfPresent(Date.self, forKey: .lyricsLastUpdated)
        lyricsURL = try container.decodeIfPresent(String.self, forKey: .lyricsURL)
        source = try container.decodeIfPresent(TrackSource.self, forKey: .source) ?? .local
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        playCount = try container.decodeIfPresent(Int.self, forKey: .playCount) ?? 0
        lastPlayed = try container.decodeIfPresent(Date.self, forKey: .lastPlayed)
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        sourceID = try container.decodeIfPresent(String.self, forKey: .sourceID)
        remotePageURL = try container.decodeIfPresent(String.self, forKey: .remotePageURL)
        storageLocation = try container.decodeIfPresent(StorageLocation.self, forKey: .storageLocation) ?? .library
        importOriginID = try container.decodeIfPresent(String.self, forKey: .importOriginID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(artist, forKey: .artist)
        try container.encodeIfPresent(album, forKey: .album)
        try container.encode(genres, forKey: .genres)
        try container.encode(tags, forKey: .tags)
        try container.encode(moods, forKey: .moods)
        try container.encode(duration, forKey: .duration)
        try container.encodeIfPresent(fileURL, forKey: .fileURL)
        try container.encodeIfPresent(coverArtURL, forKey: .coverArtURL)
        try container.encodeIfPresent(remoteCoverArtURL, forKey: .remoteCoverArtURL)
        try container.encodeIfPresent(artistImageURL, forKey: .artistImageURL)
        try container.encodeIfPresent(remoteArtistImageURL, forKey: .remoteArtistImageURL)
        try container.encodeIfPresent(providerArtistID, forKey: .providerArtistID)
        try container.encodeIfPresent(artistWebpageURL, forKey: .artistWebpageURL)
        try container.encodeIfPresent(lyricsText, forKey: .lyricsText)
        try container.encodeIfPresent(lyricsSyncedText, forKey: .lyricsSyncedText)
        try container.encodeIfPresent(lyricsSource, forKey: .lyricsSource)
        try container.encodeIfPresent(lyricsLastUpdated, forKey: .lyricsLastUpdated)
        try container.encodeIfPresent(lyricsURL, forKey: .lyricsURL)
        try container.encode(source, forKey: .source)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(playCount, forKey: .playCount)
        try container.encodeIfPresent(lastPlayed, forKey: .lastPlayed)
        try container.encode(addedAt, forKey: .addedAt)
        try container.encodeIfPresent(sourceID, forKey: .sourceID)
        try container.encodeIfPresent(remotePageURL, forKey: .remotePageURL)
        try container.encode(storageLocation, forKey: .storageLocation)
        try container.encodeIfPresent(importOriginID, forKey: .importOriginID)
    }

    var formattedDuration: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var displayTitle: String {
        title.isEmpty ? "Unknown Track" : title
    }

    var displayArtist: String {
        artist.isEmpty ? "Unknown Artist" : artist
    }
}

extension Track.TrackSource {
    var onlineProvider: OnlineTrackProvider? {
        switch self {
        case .soundcloud:
            return .soundcloud
        case .spotify:
            return .spotify
        case .local, .youtube, .appleMusicPreview:
            return nil
        }
    }
}

extension OnlineTrackProvider {
    var iconAssetName: String {
        switch self {
        case .soundcloud:
            return "SoundCloudProviderIcon"
        case .spotify:
            return "SpotifyProviderIcon"
        }
    }

    var accentColor: Color {
        switch self {
        case .soundcloud:
            return Color(red: 1.0, green: 0.43, blue: 0.0)
        case .spotify:
            return Color(red: 0.12, green: 0.82, blue: 0.38)
        }
    }

    var secondaryAccentColor: Color {
        switch self {
        case .soundcloud:
            return Color(red: 0.43, green: 0.12, blue: 0.02)
        case .spotify:
            return Color(red: 0.04, green: 0.19, blue: 0.09)
        }
    }
}

struct ProviderIconView: View {
    let provider: OnlineTrackProvider
    let size: CGFloat

    var body: some View {
        Image(provider.iconAssetName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct Playlist: Identifiable, Codable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var description: String?
    var trackIDs: [String] = []
    var coverArtURL: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isStarred: Bool = false

    var tracks: [Track] {
        trackIDs.compactMap { trackID in
            DataManager.shared.tracks.first(where: { $0.id == trackID })
        }
    }

    var trackCount: Int {
        tracks.count
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Playlist" : name
    }
}

struct ImportedMusicFolder: Identifiable, Codable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var bookmarkData: Data
    var addedAt: Date = Date()
    var lastRefreshedAt: Date?

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Music Folder" : name
    }
}

struct OnlineArtistRoute: Hashable, Sendable {
    let provider: OnlineTrackProvider
    let providerArtistID: String
    let artistName: String
    let imageURL: String?
    let webpageURL: String?

    var id: String {
        "\(provider.rawValue):artist:\(providerArtistID)"
    }
}

struct OnlineReleaseRoute: Hashable, Sendable {
    let provider: OnlineTrackProvider
    let providerReleaseID: String
    let title: String
    let artistName: String
    let imageURL: String?
    let webpageURL: String?
}

struct FavoriteArtist: Identifiable, Codable, Hashable, Sendable {
    let provider: OnlineTrackProvider
    let providerArtistID: String
    let artistName: String
    let imageURL: String?
    let localImagePath: String?
    let webpageURL: String?

    var id: String {
        "\(provider.rawValue):artist:\(providerArtistID)"
    }
}

extension OnlineArtistResult {
    var route: OnlineArtistRoute {
        OnlineArtistRoute(
            provider: provider,
            providerArtistID: providerArtistID,
            artistName: name,
            imageURL: imageURL,
            webpageURL: webpageURL
        )
    }
}

extension OnlineArtistRoute {
    var favoriteArtist: FavoriteArtist {
        FavoriteArtist(
            provider: provider,
            providerArtistID: providerArtistID,
            artistName: artistName,
            imageURL: imageURL,
            localImagePath: nil,
            webpageURL: webpageURL
        )
    }
}

extension FavoriteArtist {
    var route: OnlineArtistRoute {
        OnlineArtistRoute(
            provider: provider,
            providerArtistID: providerArtistID,
            artistName: artistName,
            imageURL: preferredImageReference,
            webpageURL: cleanedImageReference(webpageURL)
        )
    }

    var preferredImageReference: String? {
        cleanedImageReference(localImagePath) ?? cleanedImageReference(imageURL)
    }

    var localImageFileURL: URL? {
        resolvedLocalImageURL(from: localImagePath)
    }

    var resolvedRemoteImageURL: URL? {
        resolvedRemoteImageURL(from: localImagePath) ?? resolvedRemoteImageURL(from: imageURL)
    }

    private func cleanedImageReference(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedValue.isEmpty ? nil : cleanedValue
    }

    private func resolvedLocalImageURL(from reference: String?) -> URL? {
        guard let reference = cleanedImageReference(reference) else { return nil }

        if let parsedURL = URL(string: reference), parsedURL.scheme != nil {
            guard parsedURL.isFileURL,
                  FileManager.default.fileExists(atPath: parsedURL.path) else {
                return nil
            }

            return parsedURL
        }

        let resolvedURL = AppFileManager.shared.resolveStoredFileURL(for: reference)
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            return nil
        }

        return resolvedURL
    }

    private func resolvedRemoteImageURL(from reference: String?) -> URL? {
        guard let reference = cleanedImageReference(reference),
              let parsedURL = URL(string: reference),
              let scheme = parsedURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return parsedURL
    }
}

extension OnlineAlbumResult {
    var route: OnlineReleaseRoute {
        OnlineReleaseRoute(
            provider: provider,
            providerReleaseID: providerAlbumID,
            title: title,
            artistName: artist,
            imageURL: coverArtURL,
            webpageURL: webpageURL
        )
    }
}

extension Playlist {
    var preferredCoverReference: String? {
        cleanedImageReference(coverArtURL)
    }

    var localCoverFileURL: URL? {
        resolvedLocalImageURL(from: coverArtURL)
    }

    var resolvedRemoteCoverURL: URL? {
        resolvedRemoteImageURL(from: coverArtURL)
    }

    private func cleanedImageReference(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedValue.isEmpty ? nil : cleanedValue
    }

    private func resolvedLocalImageURL(from reference: String?) -> URL? {
        guard let reference = cleanedImageReference(reference) else { return nil }

        if let parsedURL = URL(string: reference), parsedURL.scheme != nil {
            guard parsedURL.isFileURL,
                  FileManager.default.fileExists(atPath: parsedURL.path) else {
                return nil
            }

            return parsedURL
        }

        let resolvedURL = AppFileManager.shared.resolveStoredFileURL(for: reference)
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            return nil
        }

        return resolvedURL
    }

    private func resolvedRemoteImageURL(from reference: String?) -> URL? {
        guard let reference = cleanedImageReference(reference),
              let parsedURL = URL(string: reference),
              let scheme = parsedURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return parsedURL
    }
}

extension Track {
    var onlineArtistRoute: OnlineArtistRoute? {
        guard let provider = source.onlineProvider,
              let providerArtistID = cleanedImageReference(providerArtistID),
              let artistName = cleanedImageReference(displayArtist),
              artistName != "Unknown Artist" else {
            return nil
        }

        return OnlineArtistRoute(
            provider: provider,
            providerArtistID: providerArtistID,
            artistName: artistName,
            imageURL: preferredArtistImageReference ?? preferredArtworkReference,
            webpageURL: cleanedImageReference(artistWebpageURL)
        )
    }

    var artworkCacheIdentity: String {
        preferredArtworkReference ?? sourceID ?? id
    }

    var preferredArtworkReference: String? {
        cleanedImageReference(coverArtURL) ?? cleanedImageReference(remoteCoverArtURL)
    }

    var localArtworkURL: URL? {
        resolvedLocalImageURL(from: coverArtURL)
    }

    var resolvedRemoteArtworkURL: URL? {
        resolvedRemoteImageURL(from: coverArtURL) ?? resolvedRemoteImageURL(from: remoteCoverArtURL)
    }

    var preferredArtistImageReference: String? {
        cleanedImageReference(artistImageURL) ?? cleanedImageReference(remoteArtistImageURL)
    }

    var localArtistImageFileURL: URL? {
        resolvedLocalImageURL(from: artistImageURL)
    }

    var resolvedRemoteArtistImageURL: URL? {
        resolvedRemoteImageURL(from: artistImageURL) ?? resolvedRemoteImageURL(from: remoteArtistImageURL)
    }

    private func cleanedImageReference(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedValue.isEmpty ? nil : cleanedValue
    }

    private func resolvedLocalImageURL(from reference: String?) -> URL? {
        guard let reference = cleanedImageReference(reference) else { return nil }

        if let parsedURL = URL(string: reference), parsedURL.scheme != nil {
            guard parsedURL.isFileURL,
                  FileManager.default.fileExists(atPath: parsedURL.path) else {
                return nil
            }

            return parsedURL
        }

        let resolvedURL = AppFileManager.shared.resolveStoredFileURL(for: reference)
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            return nil
        }

        return resolvedURL
    }

    private func resolvedRemoteImageURL(from reference: String?) -> URL? {
        guard let reference = cleanedImageReference(reference),
              let parsedURL = URL(string: reference),
              let scheme = parsedURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return parsedURL
    }
}

enum Tab: String, CaseIterable, Hashable {
    case home
    case library
    case search
    case settings

    static var allCases: [Tab] {
        [
            .home,
            .library,
            .search,
            .settings
        ]
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .library: return "folder.fill"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape.fill"
        }
    }

    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        case .search: return "Search"
        case .settings: return "Settings"
        }
    }
}

enum AppRoute: Hashable {
    case playlist(String)
    case onlineArtist(OnlineArtistRoute)
    case onlineRelease(OnlineReleaseRoute)
}

final class AppRouter: ObservableObject {
    @Published var selectedTab: Tab = .home
    @Published var path = NavigationPath()

    func navigate(to tab: Tab) {
        debugLog("Navigate to tab: \(tab.rawValue)")
        path = NavigationPath()
        selectedTab = tab
    }

    func openPlaylist(_ playlistId: String) {
        debugLog("Navigate to playlist: \(playlistId)")
        path.append(AppRoute.playlist(playlistId))
    }

    func openOnlineArtist(_ artist: OnlineArtistRoute) {
        debugLog("Navigate to online artist: \(artist.artistName) [\(artist.providerArtistID)]")
        path.append(AppRoute.onlineArtist(artist))
    }

    func openOnlineRelease(_ release: OnlineReleaseRoute) {
        debugLog("Navigate to online release: \(release.title) [\(release.providerReleaseID)]")
        path.append(AppRoute.onlineRelease(release))
    }

    func popToRoot() {
        debugLog("Pop to root")
        path = NavigationPath()
    }
}

func debugLog(_ message: String) {
    print("[UI DEBUG] \(message)")
}
