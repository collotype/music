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
    
    private let legacyTracksKey = "fmp_tracks"
    private let legacyPlaylistsKey = "fmp_playlists"
    private let legacyFavoritesKey = "fmp_favorites"
    private let legacySettingsKey = "fmp_settings"
    
    private var tracksFileURL: URL { AppFileManager.shared.dataFileURL(named: "tracks.json") }
    private var playlistsFileURL: URL { AppFileManager.shared.dataFileURL(named: "playlists.json") }
    private var favoritesFileURL: URL { AppFileManager.shared.dataFileURL(named: "favorites.json") }
    private var settingsFileURL: URL { AppFileManager.shared.dataFileURL(named: "settings.json") }
    
    init() {
        loadData()
    }
    
    func loadData() {
        AppFileManager.shared.prepareDirectories()
        
        let didLoadFromFiles = loadDataFromFiles()
        if !didLoadFromFiles {
            migrateLegacyUserDefaults()
        }
        
        // Temp tracks should never survive app relaunch because temp storage is cleared on launch.
        tracks = tracks.filter { track in
            track.storageLocation != .temp
        }
        
        tracks = tracks.filter { track in
            guard let fileURL = track.fileURL else { return true }
            if URL(string: fileURL)?.scheme != nil {
                return true
            }
            return AppFileManager.shared.fileExists(at: fileURL)
        }
        
        saveData()
    }
    
    func saveData() {
        let persistedTracks = tracks.filter { $0.storageLocation != .temp }
        writeJSON(persistedTracks, to: tracksFileURL)
        writeJSON(playlists, to: playlistsFileURL)
        writeJSON(favorites, to: favoritesFileURL)
        writeJSON(settings, to: settingsFileURL)
    }
    
    @discardableResult
    func addTrack(_ track: Track) -> Track {
        debugLog("Add track: \(track.displayTitle)")
        
        if let existingIndex = existingTrackIndex(for: track) {
            var updatedTrack = track
            updatedTrack.id = tracks[existingIndex].id
            updatedTrack.isFavorite = favorites.contains(updatedTrack.id)
            tracks[existingIndex] = updatedTrack
            saveData()
            return updatedTrack
        }
        
        var insertedTrack = track
        insertedTrack.isFavorite = favorites.contains(insertedTrack.id)
        tracks.insert(insertedTrack, at: 0)
        saveData()
        return insertedTrack
    }
    
    func addTracks(_ newTracks: [Track]) {
        guard !newTracks.isEmpty else { return }
        debugLog("Add tracks count: \(newTracks.count)")
        
        for track in newTracks {
            _ = addTrack(track)
        }
    }
    
    func removeTrack(_ track: Track) {
        debugLog("Remove track: \(track.displayTitle)")
        
        if let fileURL = track.fileURL,
           track.storageLocation == .library {
            let resolvedURL = AppFileManager.shared.resolveStoredFileURL(for: fileURL)
            try? FileManager.default.removeItem(at: resolvedURL)
        }
        
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
        
        guard let trackIndex = tracks.firstIndex(where: { $0.id == track.id })
            ?? tracks.firstIndex(where: { $0.sourceID != nil && $0.sourceID == track.sourceID }) else {
            debugLog("Favorite toggle ignored because the track is not stored locally")
            return
        }
        
        let trackID = tracks[trackIndex].id
        
        if favorites.contains(trackID) {
            favorites.remove(trackID)
        } else {
            favorites.insert(trackID)
        }
        
        tracks[trackIndex].isFavorite = favorites.contains(trackID)
        
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
    
    func track(withSourceID sourceID: String) -> Track? {
        tracks.first { $0.sourceID == sourceID && $0.storageLocation == .library }
    }
    
    func makeTemporaryTrack(from result: OnlineTrackResult, tempFileURL: URL) -> Track {
        let storedPath = AppFileManager.shared.relativePath(for: tempFileURL) ?? tempFileURL.path
        
        return Track(
            title: result.title,
            artist: result.artist,
            album: nil,
            duration: result.duration,
            fileURL: storedPath,
            coverArtURL: result.coverArtURL,
            source: .youtube,
            isFavorite: false,
            playCount: 0,
            lastPlayed: nil,
            addedAt: Date(),
            sourceID: result.id,
            remotePageURL: result.webpageURL,
            storageLocation: .temp
        )
    }
    
    @discardableResult
    func saveDownloadedOnlineTrack(_ result: OnlineTrackResult, from tempFileURL: URL) throws -> Track {
        if let existingTrack = track(withSourceID: result.id) {
            return existingTrack
        }
        
        let destinationURL = try AppFileManager.shared.copyToLibrary(
            from: tempFileURL,
            preferredName: "\(result.artist)-\(result.title)"
        )
        let storedPath = AppFileManager.shared.relativePath(for: destinationURL) ?? destinationURL.path
        
        let track = Track(
            title: result.title,
            artist: result.artist,
            album: nil,
            duration: result.duration,
            fileURL: storedPath,
            coverArtURL: result.coverArtURL,
            source: .youtube,
            isFavorite: false,
            playCount: 0,
            lastPlayed: nil,
            addedAt: Date(),
            sourceID: result.id,
            remotePageURL: result.webpageURL,
            storageLocation: .library
        )
        
        return addTrack(track)
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
        
        UserDefaults.standard.removeObject(forKey: legacyTracksKey)
        UserDefaults.standard.removeObject(forKey: legacyPlaylistsKey)
        UserDefaults.standard.removeObject(forKey: legacyFavoritesKey)
        UserDefaults.standard.removeObject(forKey: legacySettingsKey)
        
        AppFileManager.shared.clearAllAppData()
        saveData()
    }
    
    private func loadDataFromFiles() -> Bool {
        let loadedTracks: [Track]? = readJSON(from: tracksFileURL)
        let loadedPlaylists: [Playlist]? = readJSON(from: playlistsFileURL)
        let loadedFavorites: Set<String>? = readJSON(from: favoritesFileURL)
        let loadedSettings: AppSettings? = readJSON(from: settingsFileURL)
        
        let didLoadAnything = loadedTracks != nil || loadedPlaylists != nil || loadedFavorites != nil || loadedSettings != nil
        
        if let loadedTracks {
            tracks = loadedTracks
        }
        
        if let loadedPlaylists {
            playlists = loadedPlaylists
        }
        
        if let loadedFavorites {
            favorites = loadedFavorites
        }
        
        if let loadedSettings {
            settings = loadedSettings
        }
        
        return didLoadAnything
    }
    
    private func migrateLegacyUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: legacyTracksKey),
           let decoded = try? JSONDecoder().decode([Track].self, from: data) {
            tracks = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: legacyPlaylistsKey),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: legacyFavoritesKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            favorites = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: legacySettingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        }
    }
    
    private func existingTrackIndex(for track: Track) -> Int? {
        if let sourceID = track.sourceID,
           let index = tracks.firstIndex(where: { $0.sourceID == sourceID && $0.storageLocation == .library }) {
            return index
        }
        
        if let fileURL = track.fileURL,
           let index = tracks.firstIndex(where: { $0.fileURL == fileURL && $0.storageLocation == track.storageLocation }) {
            return index
        }
        
        return tracks.firstIndex(where: { $0.id == track.id })
    }
    
    private func readJSON<T: Decodable>(from url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        
        return try? JSONDecoder().decode(T.self, from: data)
    }
    
    private func writeJSON<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
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
