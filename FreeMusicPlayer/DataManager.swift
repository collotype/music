//
//  DataManager.swift
//  FreeMusicPlayer
//
//  Local persistence and state updates.
//

import AVFoundation
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

    var importFolders: [ImportedMusicFolder] {
        settings.importFolders
    }

    var hasImportFolders: Bool {
        !settings.importFolders.isEmpty
    }

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

        refreshStoredLocalMetadataIfNeeded()
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

    @discardableResult
    func importFiles(from urls: [URL]) -> LibraryImportSummary {
        importTracks(from: urls, requiresSecurityScope: true)
    }

    @discardableResult
    func addImportFolder(_ folderURL: URL) throws -> ImportedMusicFolder {
        let standardizedPath = folderURL.standardizedFileURL.path

        if let existingFolder = settings.importFolders.first(where: { storedFolder in
            guard let resolvedURL = try? AppFileManager.shared.resolveBookmarkedURL(from: storedFolder.bookmarkData) else {
                return false
            }

            return resolvedURL.standardizedFileURL.path == standardizedPath
        }) {
            debugLog("Reuse linked music folder: \(existingFolder.displayName)")
            return existingFolder
        }

        let bookmarkData = try AppFileManager.shared.bookmarkData(for: folderURL)
        let folder = ImportedMusicFolder(name: folderURL.lastPathComponent, bookmarkData: bookmarkData)
        debugLog("Linked music folder: \(folder.displayName)")
        settings.importFolders.append(folder)
        saveData()
        return folder
    }

    @discardableResult
    func refreshImportFolders() -> LibraryImportSummary {
        guard !settings.importFolders.isEmpty else {
            debugLog("Refresh import folders ignored because there are no linked folders")
            return LibraryImportSummary(errors: ["No linked music folders yet."])
        }

        debugLog("Refresh linked music folders: \(settings.importFolders.count)")

        var summary = LibraryImportSummary()
        var updatedFolders = settings.importFolders

        for index in updatedFolders.indices {
            let folder = updatedFolders[index]

            do {
                let folderSummary = try AppFileManager.shared.withBookmarkedDirectoryAccess(bookmarkData: folder.bookmarkData) { folderURL in
                    let audioFiles = try AppFileManager.shared.audioFiles(in: folderURL)
                    debugLog("Scanned linked folder \(folder.displayName): \(audioFiles.count) audio files")
                    return importTracks(from: audioFiles, requiresSecurityScope: false)
                }

                updatedFolders[index].lastRefreshedAt = Date()
                summary.formUnion(with: folderSummary)
            } catch {
                let message = "\(folder.displayName): \(error.localizedDescription)"
                debugLog("Linked folder refresh failed: \(message)")
                summary.errors.append(message)
            }
        }

        settings.importFolders = updatedFolders
        saveData()
        return summary
    }

    func removeTrack(_ track: Track) {
        debugLog("Remove track: \(track.displayTitle)")
        removeTracks([track])
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
        let resolvedName = uniquePlaylistName(from: name)
        let playlist = Playlist(name: resolvedName)
        debugLog("Create playlist: \(playlist.name)")
        playlists.append(playlist)
        saveData()
        return playlist
    }

    func togglePlaylistFavorite(_ playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }

        playlists[index].isStarred.toggle()
        playlists[index].updatedAt = Date()
        debugLog("Toggle playlist favorite: \(playlists[index].name) -> \(playlists[index].isStarred)")
        saveData()
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

        return playlist.trackIDs.compactMap { trackID in
            tracks.first(where: { $0.id == trackID })
        }
    }

    func addTrack(_ track: Track, toPlaylistID playlistId: String) {
        addTracks([track], toPlaylistID: playlistId)
    }

    func addTracks(_ tracksToAdd: [Track], toPlaylistID playlistId: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }

        var playlist = playlists[index]
        var seenTrackIDs = Set(playlist.trackIDs)
        var didAddTrack = false

        for track in tracksToAdd {
            guard seenTrackIDs.insert(track.id).inserted else { continue }
            debugLog("Add track \(track.displayTitle) to playlist \(playlist.name)")
            playlist.trackIDs.append(track.id)
            didAddTrack = true
        }

        guard didAddTrack else { return }

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

    func removeTracks(_ tracksToRemove: [Track]) {
        var seenTrackIDs: Set<String> = []
        var uniqueTracks: [Track] = []

        for track in tracksToRemove where seenTrackIDs.insert(track.id).inserted {
            uniqueTracks.append(track)
        }

        guard !uniqueTracks.isEmpty else { return }

        let trackIDs = Set(uniqueTracks.map(\.id))
        debugLog("Bulk remove tracks count: \(trackIDs.count)")

        for track in uniqueTracks {
            deleteStoredResources(for: track)
        }

        tracks.removeAll { trackIDs.contains($0.id) }
        favorites.subtract(trackIDs)

        let updateDate = Date()
        for index in playlists.indices {
            let originalCount = playlists[index].trackIDs.count
            playlists[index].trackIDs.removeAll { trackIDs.contains($0) }

            if playlists[index].trackIDs.count != originalCount {
                playlists[index].updatedAt = updateDate
            }
        }

        saveData()
    }

    func track(withSourceID sourceID: String) -> Track? {
        tracks.first { $0.sourceID == sourceID && $0.storageLocation == .library }
    }

    func makeTemporaryTrack(from result: OnlineTrackResult, tempFileURL: URL) -> Track {
        let storedPath = AppFileManager.shared.relativePath(for: tempFileURL) ?? tempFileURL.path
        debugLog("Create temporary track entry for \(result.title) at \(storedPath)")

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
            debugLog("Reuse existing saved online track: \(existingTrack.displayTitle)")
            return existingTrack
        }

        let destinationURL = try AppFileManager.shared.copyToLibrary(
            from: tempFileURL,
            preferredName: "\(result.artist)-\(result.title)"
        )
        let storedPath = AppFileManager.shared.relativePath(for: destinationURL) ?? destinationURL.path
        debugLog("Register saved online track in library: \(result.title) at \(storedPath)")

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

    var favoritePlaylists: [Playlist] {
        sortedPlaylists.filter(\.isStarred)
    }

    var sortedPlaylists: [Playlist] {
        playlists.sorted { left, right in
            if left.isStarred != right.isStarred {
                return left.isStarred && !right.isStarred
            }

            if left.updatedAt != right.updatedAt {
                return left.updatedAt > right.updatedAt
            }

            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
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

        if let importOriginID = track.importOriginID,
           let index = tracks.firstIndex(where: { $0.importOriginID == importOriginID && $0.storageLocation == .library }) {
            return index
        }

        if let fileURL = track.fileURL,
           let index = tracks.firstIndex(where: { $0.fileURL == fileURL && $0.storageLocation == track.storageLocation }) {
            return index
        }

        return tracks.firstIndex(where: { $0.id == track.id })
    }

    private func uniquePlaylistName(from rawName: String) -> String {
        let baseName = sanitizedPlaylistName(rawName)
        let existingNames = Set(playlists.map { $0.name.lowercased() })

        guard !existingNames.contains(baseName.lowercased()) else {
            for index in 2...999 {
                let candidate = "\(baseName) \(index)"
                if !existingNames.contains(candidate.lowercased()) {
                    return candidate
                }
            }

            return "\(baseName) \(Int.random(in: 1000...9999))"
        }

        return baseName
    }

    private func sanitizedPlaylistName(_ rawName: String) -> String {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "New Playlist" : trimmedName
    }

    private func deleteStoredResources(for track: Track) {
        if let fileURL = track.fileURL,
           track.storageLocation == .library {
            let resolvedURL = AppFileManager.shared.resolveStoredFileURL(for: fileURL)
            try? FileManager.default.removeItem(at: resolvedURL)
        }

        if let coverArtURL = track.coverArtURL,
           URL(string: coverArtURL)?.scheme == nil {
            let artworkURL = AppFileManager.shared.resolveStoredFileURL(for: coverArtURL)
            try? FileManager.default.removeItem(at: artworkURL)
        }
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

    private func importTracks(from urls: [URL], requiresSecurityScope: Bool) -> LibraryImportSummary {
        var summary = LibraryImportSummary()

        for url in urls {
            summary.scannedCount += 1
            debugLog("Import pipeline inspecting file: \(url.lastPathComponent)")

            do {
                switch try importTrack(from: url, requiresSecurityScope: requiresSecurityScope) {
                case .imported:
                    summary.importedCount += 1
                case .skipped:
                    summary.skippedCount += 1
                }
            } catch {
                let message = "\(url.lastPathComponent): \(error.localizedDescription)"
                debugLog("Track import failed: \(message)")
                summary.errors.append(message)
            }
        }

        return summary
    }

    private func importTrack(from url: URL, requiresSecurityScope: Bool) throws -> ImportedTrackStatus {
        let accessBlock = {
            let importOriginID = self.importOriginIdentifier(for: url)

            if self.tracks.contains(where: { $0.importOriginID == importOriginID && $0.storageLocation == .library }) {
                debugLog("Skip already imported file: \(url.lastPathComponent)")
                return ImportedTrackStatus.skipped
            }

            let probe = try self.probeImportedTrack(at: url)

            let preferredBaseName = url.deletingPathExtension().lastPathComponent
            let destinationURL = AppFileManager.shared.uniqueLibraryURL(
                baseName: preferredBaseName,
                fileExtension: url.pathExtension
            )

            do {
                try FileManager.default.copyItem(at: url, to: destinationURL)
            } catch {
                throw LibraryImportError.copyFailed(url.lastPathComponent, error.localizedDescription)
            }

            let artworkPath = try self.storeArtworkIfAvailable(
                data: probe.artworkData,
                preferredName: importOriginID
            )

            let track = Track(
                title: probe.title,
                artist: probe.artist,
                album: probe.album,
                duration: probe.duration,
                fileURL: AppFileManager.shared.relativePath(for: destinationURL),
                coverArtURL: artworkPath,
                source: .local,
                storageLocation: .library,
                importOriginID: importOriginID
            )

            _ = self.addTrack(track)
            return ImportedTrackStatus.imported
        }

        if requiresSecurityScope {
            return try AppFileManager.shared.withSecurityScopedAccess(to: url) { _ in
                try accessBlock()
            }
        }

        return try accessBlock()
    }

    private func importOriginIdentifier(for url: URL) -> String {
        url.standardizedFileURL.path.lowercased()
    }

    private func metadataValue(for asset: AVURLAsset, identifier: AVMetadataIdentifier) -> String? {
        asset.commonMetadata
            .first(where: { $0.identifier == identifier })?
            .stringValue
    }

    private func probeImportedTrack(at url: URL) throws -> ImportedTrackProbe {
        let asset = AVURLAsset(url: url)
        let audioTracks = asset.tracks(withMediaType: .audio)
        let fallbackPlayer = try? AVAudioPlayer(contentsOf: url)
        let durationSeconds = max(CMTimeGetSeconds(asset.duration), 0)
        let resolvedDuration = durationSeconds > 0 ? durationSeconds : max(fallbackPlayer?.duration ?? 0, 0)

        guard !audioTracks.isEmpty || asset.isPlayable || fallbackPlayer != nil else {
            debugLog("Track probe skipped \(url.lastPathComponent): no readable audio stream found")
            throw LibraryImportError.unplayableFile(url.lastPathComponent)
        }

        let title = metadataValue(for: asset, identifier: .commonIdentifierTitle)
            ?? url.deletingPathExtension().lastPathComponent
        let artist = metadataValue(for: asset, identifier: .commonIdentifierArtist)
            ?? "Unknown Artist"
        let album = metadataValue(for: asset, identifier: .commonIdentifierAlbumName)
        let artworkData = artworkData(for: asset)

        debugLog("Metadata extracted for \(url.lastPathComponent): title=\(title), artist=\(artist), duration=\(resolvedDuration)")
        debugLog("Artwork extraction for \(url.lastPathComponent): \(artworkData == nil ? "missing" : "embedded artwork found")")

        return ImportedTrackProbe(
            title: title,
            artist: artist,
            album: album,
            duration: resolvedDuration,
            artworkData: artworkData
        )
    }

    private func artworkData(for asset: AVURLAsset) -> Data? {
        let artworkItems = asset.commonMetadata.filter {
            $0.identifier == .commonIdentifierArtwork ||
            $0.commonKey?.rawValue == AVMetadataKey.commonKeyArtwork.rawValue
        }

        for item in artworkItems {
            if let dataValue = item.dataValue {
                return dataValue
            }

            if let value = item.value as? Data {
                return value
            }
        }

        for format in asset.availableMetadataFormats {
            for item in asset.metadata(forFormat: format) {
                if item.identifier == .commonIdentifierArtwork ||
                   item.commonKey?.rawValue == AVMetadataKey.commonKeyArtwork.rawValue {
                    if let dataValue = item.dataValue {
                        return dataValue
                    }

                    if let value = item.value as? Data {
                        return value
                    }
                }
            }
        }

        return nil
    }

    private func storeArtworkIfAvailable(data: Data?, preferredName: String) throws -> String? {
        guard let data else { return nil }

        let artworkURL = try AppFileManager.shared.saveArtworkData(data, preferredName: preferredName)
        let storedPath = AppFileManager.shared.relativePath(for: artworkURL) ?? artworkURL.path
        debugLog("Artwork stored for imported track at \(storedPath)")
        return storedPath
    }

    private func refreshStoredLocalMetadataIfNeeded() {
        guard !tracks.isEmpty else { return }

        var didUpdateAnyTrack = false

        for index in tracks.indices {
            guard shouldRefreshStoredMetadata(for: tracks[index]),
                  let fileURL = tracks[index].fileURL else {
                continue
            }

            let resolvedURL = AppFileManager.shared.resolveStoredFileURL(for: fileURL)
            guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
                continue
            }

            do {
                let probe = try probeImportedTrack(at: resolvedURL)
                let artworkPath = try storeArtworkIfAvailable(
                    data: probe.artworkData,
                    preferredName: tracks[index].importOriginID ?? tracks[index].id
                )

                tracks[index].title = probe.title
                tracks[index].artist = probe.artist
                tracks[index].album = probe.album
                tracks[index].duration = probe.duration

                if let artworkPath {
                    tracks[index].coverArtURL = artworkPath
                }

                didUpdateAnyTrack = true
                debugLog("Refreshed stored metadata for \(tracks[index].displayTitle)")
            } catch {
                debugLog("Stored metadata refresh skipped for \(tracks[index].displayTitle): \(error.localizedDescription)")
            }
        }

        if didUpdateAnyTrack {
            saveData()
        }
    }

    private func shouldRefreshStoredMetadata(for track: Track) -> Bool {
        guard track.source == .local,
              track.storageLocation == .library,
              track.fileURL != nil else {
            return false
        }

        if track.coverArtURL == nil {
            return true
        }

        if let coverArtURL = track.coverArtURL,
           URL(string: coverArtURL)?.scheme == nil,
           !AppFileManager.shared.fileExists(at: coverArtURL) {
            return true
        }

        return track.duration <= 0 ||
            track.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            track.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
    var importFolders: [ImportedMusicFolder] = []

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

struct LibraryImportSummary {
    var importedCount: Int = 0
    var skippedCount: Int = 0
    var scannedCount: Int = 0
    var errors: [String] = []

    mutating func formUnion(with other: LibraryImportSummary) {
        importedCount += other.importedCount
        skippedCount += other.skippedCount
        scannedCount += other.scannedCount
        errors.append(contentsOf: other.errors)
    }
}

private enum ImportedTrackStatus {
    case imported
    case skipped
}

private enum LibraryImportError: LocalizedError {
    case copyFailed(String, String)
    case unplayableFile(String)

    var errorDescription: String? {
        switch self {
        case .copyFailed(let fileName, let details):
            return "Failed to copy \"\(fileName)\" into the app library. \(details)"
        case .unplayableFile(let fileName):
            return "\"\(fileName)\" is not recognized as playable audio."
        }
    }
}

private struct ImportedTrackProbe {
    let title: String
    let artist: String
    let album: String?
    let duration: TimeInterval
    let artworkData: Data?
}
