//
//  Track.swift
//  FreeMusicPlayer
//
//  Track and navigation models.
//

import Foundation
import SwiftUI

struct Track: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var artist: String
    var album: String?
    var duration: TimeInterval
    var fileURL: String?
    var coverArtURL: String?
    var source: TrackSource = .local
    var isFavorite: Bool = false
    var playCount: Int = 0
    var lastPlayed: Date?
    var addedAt: Date = Date()
    
    enum TrackSource: String, Codable {
        case local
        case youtube
        case soundcloud
        case spotify
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
        DataManager.shared.tracks.filter { trackIDs.contains($0.id) }
    }
    
    var trackCount: Int {
        tracks.count
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
    
    func popToRoot() {
        debugLog("Pop to root")
        path = NavigationPath()
    }
}

func debugLog(_ message: String) {
    print("[UI DEBUG] \(message)")
}
