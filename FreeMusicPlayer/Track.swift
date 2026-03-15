//
//  Track.swift
//  FreeMusicPlayer
//
//  Модель трека
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
        title.isEmpty ? "Неизвестный трек" : title
    }
    
    var displayArtist: String {
        artist.isEmpty ? "Неизвестный исполнитель" : artist
    }
}

struct Playlist: Identifiable, Codable {
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

enum Tab: String, CaseIterable {
    case home
    case library
    case search
    case profile
    
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .library: return "folder.fill"
        case .search: return "magnifyingglass"
        case .profile: return "gearshape.fill"
        }
    }
    
    var title: String {
        switch self {
        case .home: return "Главная"
        case .library: return "Медиатека"
        case .search: return "Поиск"
        case .profile: return "Настройки"
        }
    }
}
