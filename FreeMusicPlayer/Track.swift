//
//  Track.swift
//  FreeMusicPlayer
//
//  Track and navigation models.
//

import Foundation
import SwiftUI

struct Track: Identifiable, Codable, Equatable {
    enum TrackSource: String, Codable {
        case local
        case youtube
        case appleMusicPreview
        case soundcloud
        case spotify
    }

    enum StorageLocation: String, Codable {
        case library
        case temp
        case remote
    }

    var id: String
    var title: String
    var artist: String
    var album: String?
    var duration: TimeInterval
    var fileURL: String?
    var coverArtURL: String?
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
        importOriginID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.fileURL = fileURL
        self.coverArtURL = coverArtURL
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
        case duration
        case fileURL
        case coverArtURL
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
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        fileURL = try container.decodeIfPresent(String.self, forKey: .fileURL)
        coverArtURL = try container.decodeIfPresent(String.self, forKey: .coverArtURL)
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
        try container.encode(duration, forKey: .duration)
        try container.encodeIfPresent(fileURL, forKey: .fileURL)
        try container.encodeIfPresent(coverArtURL, forKey: .coverArtURL)
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

struct Playlist: Identifiable, Codable, Equatable {
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

struct ImportedMusicFolder: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var bookmarkData: Data
    var addedAt: Date = Date()
    var lastRefreshedAt: Date?

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Music Folder" : name
    }
}

enum Tab: String, CaseIterable, Hashable {
    case home
    case library
    case search
    case settings

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
    case onlineArtist(OnlineArtistResult)
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

    func openOnlineArtist(_ artist: OnlineArtistResult) {
        debugLog("Navigate to online artist: \(artist.name) [\(artist.providerArtistID)]")
        path.append(AppRoute.onlineArtist(artist))
    }

    func popToRoot() {
        debugLog("Pop to root")
        path = NavigationPath()
    }
}

func debugLog(_ message: String) {
    print("[UI DEBUG] \(message)")
}
