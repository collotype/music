//
//  DataManager.swift
//  FreeMusicPlayer
//
//  Управление данными (локальное хранилище)
//

import Foundation
import SwiftUI

class DataManager: ObservableObject {
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
        // Загрузка треков
        if let data = UserDefaults.standard.data(forKey: tracksKey),
           let decoded = try? JSONDecoder().decode([Track].self, from: data) {
            tracks = decoded
        }
        
        // Загрузка плейлистов
        if let data = UserDefaults.standard.data(forKey: playlistsKey),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded
        }
        
        // Загрузка избранного
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            favorites = decoded
        }
        
        // Загрузка настроек
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        }
    }
    
    func saveData() {
        // Сохранение треков
        if let encoded = try? JSONEncoder().encode(tracks) {
            UserDefaults.standard.set(encoded, forKey: tracksKey)
        }
        
        // Сохранение плейлистов
        if let encoded = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(encoded, forKey: playlistsKey)
        }
        
        // Сохранение избранного
        if let encoded = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(encoded, forKey: favoritesKey)
        }
        
        // Сохранение настроек
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: settingsKey)
        }
    }
    
    func addTrack(_ track: Track) {
        tracks.append(track)
        saveData()
    }
    
    func addTracks(_ newTracks: [Track]) {
        tracks.append(contentsOf: newTracks)
        saveData()
    }
    
    func removeTrack(_ track: Track) {
        tracks.removeAll { $0.id == track.id }
        favorites.remove(track.id)
        saveData()
    }
    
    func toggleFavorite(_ track: Track) {
        if favorites.contains(track.id) {
            favorites.remove(track.id)
            if let index = tracks.firstIndex(where: { $0.id == track.id }) {
                tracks[index].isFavorite = false
            }
        } else {
            favorites.insert(track.id)
            if let index = tracks.firstIndex(where: { $0.id == track.id }) {
                tracks[index].isFavorite = true
            }
        }
        saveData()
    }
    
    func createPlaylist(name: String) -> Playlist {
        let playlist = Playlist(name: name)
        playlists.append(playlist)
        saveData()
        return playlist
    }
    
    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        saveData()
    }
    
    func addToPlaylist(_ playlist: inout Playlist, track: Track) {
        if !playlist.trackIDs.contains(track.id) {
            playlist.trackIDs.append(track.id)
            playlist.updatedAt = Date()
            saveData()
        }
    }
    
    var favoriteTracks: [Track] {
        tracks.filter { favorites.contains($0.id) }
    }
    
    func clearAllData() {
        tracks.removeAll()
        playlists.removeAll()
        favorites.removeAll()
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
