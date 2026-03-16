//
//  DataManager.swift
//  FreeMusicPlayer
//
//  Local persistence and state updates.
//

import Foundation
import SwiftUI

final class DataManager: ObservableObject {
    static let shared = DataManager()
    
    @Published var tracks: [Track] = []
    @Published var playlists: [Playlist] = []
    @Published var favorites: Set<String> = []
    @Published var settings: AppSettings = AppSettings()
    
    private let tracksKey = "fmp_tracks"
    private let playlistsKey = "fmp_playlists"
    private let favoritesKey = "fmp_favorites"
    private let settingsKey = "fmp_settings"
    
    init() {
        loadData()
    }
    
    func loadData() {
        if let data = UserDefaults.standard.data(forKey: tracksKey),
           let decoded = try? JSONDecoder().decode([Track].self, from: data) {
            tracks = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: playlistsKey),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            favorites = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        }
    }
    
    func saveData() {
        if let encoded = try? JSONEncoder().encode(tracks) {
            UserDefaults.standard.set(encoded, forKey: tracksKey)
        }
        
        if let encoded = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(encoded, forKey: playlistsKey)
        }
        
        if let encoded = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(encoded, forKey: favoritesKey)
        }
        
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: settingsKey)
        }
    }
    
    func addTrack(_ track: Track) {
        debugLog("Add track: \(track.displayTitle)")
        tracks.append(track)
        saveData()
    }
    
    func addTracks(_ newTracks: [Track]) {
        guard !newTracks.isEmpty else { return }
        debugLog("Add tracks count: \(newTracks.count)")
        tracks.append(contentsOf: newTracks)
        saveData()
    }
    
    func removeTrack(_ track: Track) {
        debugLog("Remove track: \(track.displayTitle)")
        tracks.removeAll { $0.id == track.id }
        favorites.remove(track.id)
        
        for index in playlists.indices {
            playlists[index].trackIDs.removeAll { $0 == track.id }
            playlists[index].updatedAt = Date()
        }
        
        saveData()
    }
    
    func toggleFavorite(_ track: Track) {
        debugLog("Toggle favorite: \(track.displayTitle)")
        
        if favorites.contains(track.id) {
            favorites.remove(track.id)
        } else {
            favorites.insert(track.id)
        }
        
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[index].isFavorite = favorites.contains(track.id)
        }
        
        saveData()
    }
    
    @discardableResult
    func createPlaylist(name: String) -> Playlist {
        let playlist = Playlist(name: name)
        debugLog("Create playlist: \(playlist.name)")
        playlists.append(playlist)
        saveData()
        return playlist
    }
    
    func deletePlaylist(_ playlist: Playlist) {
        debugLog("Delete playlist: \(playlist.name)")
        playlists.removeAll { $0.id == playlist.id }
        saveData()
    }
    
    func playlist(withID playlistId: String) -> Playlist? {
        playlists.first { $0.id == playlistId }
    }
    
    func tracks(for playlistId: String) -> [Track] {
        guard let playlist = playlist(withID: playlistId) else { return [] }
        return tracks.filter { playlist.trackIDs.contains($0.id) }
    }
    
    func addTrack(_ track: Track, toPlaylistID playlistId: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        guard !playlists[index].trackIDs.contains(track.id) else { return }
        
        debugLog("Add track \(track.displayTitle) to playlist \(playlists[index].name)")
        
        var playlist = playlists[index]
        playlist.trackIDs.append(track.id)
        playlist.updatedAt = Date()
        playlists[index] = playlist
        saveData()
    }
    
    func removeTrack(_ track: Track, fromPlaylistID playlistId: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        
        debugLog("Remove track \(track.displayTitle) from playlist \(playlists[index].name)")
        
        var playlist = playlists[index]
        playlist.trackIDs.removeAll { $0 == track.id }
        playlist.updatedAt = Date()
        playlists[index] = playlist
        saveData()
    }
    
    func markTrackPlayed(_ track: Track) {
        guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        
        tracks[index].playCount += 1
        tracks[index].lastPlayed = Date()
        saveData()
    }
    
    func shuffleTracks() {
        guard tracks.count > 1 else { return }
        debugLog("Shuffle library tracks")
        tracks.shuffle()
        saveData()
    }
    
    var favoriteTracks: [Track] {
        tracks.filter { favorites.contains($0.id) }
    }
    
    func clearAllData() {
        debugLog("Clear all stored data")
        tracks.removeAll()
        playlists.removeAll()
        favorites.removeAll()
        settings = AppSettings()
        
        UserDefaults.standard.removeObject(forKey: tracksKey)
        UserDefaults.standard.removeObject(forKey: playlistsKey)
        UserDefaults.standard.removeObject(forKey: favoritesKey)
        UserDefaults.standard.removeObject(forKey: settingsKey)
    }
}

struct AppSettings: Codable {
    var theme: AppTheme = .dark
    var accentColor: String = "FF0000"
    var autoplay: Bool = true
    var shuffle: Bool = false
    var repeatMode: RepeatMode = .off
    var quality: AudioQuality = .high
    var showLyrics: Bool = true
    var cacheEnabled: Bool = true
    
    enum AppTheme: String, Codable {
        case light
        case dark
        case system
    }
    
    enum RepeatMode: String, Codable {
        case off
        case all
        case one
    }
    
    enum AudioQuality: String, Codable {
        case low
        case medium
        case high
        case lossless
    }
}
