//
//  DataManager.swift
//  FreeMusicPlayer
//
//  Local persistence and state updates.
//

import AVFoundation
import Foundation
import SwiftUI
import UIKit

enum PlaylistCoverPersistenceError: LocalizedError {
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "The selected image could not be used as a playlist cover."
        }
    }
}

final class DataManager: ObservableObject {
    static let shared = DataManager()

    @Published var tracks: [Track] = []
    @Published var playlists: [Playlist] = []
    @Published var likedTrackIDs: Set<String> = []
    @Published var favoriteArtists: [FavoriteArtist] = []
    @Published var savedAlbums: [SavedAlbum] = []
    @Published var settings: AppSettings = AppSettings()

    // Pre-computed derived collections to avoid expensive body computations
    @Published var popularTracks: [Track] = []
    @Published var recentTracks: [Track] = []
    @Published var likedTracksList: [Track] = []
    @Published var downloadedTracksList: [Track] = []

    private var isLoadingData = false
    private var hasLoadedData = false

    // Debounced save to avoid redundant disk writes
    private var saveDebounceTask: Task<Void, Never>?

    private let legacyTracksKey = "fmp_tracks"
    private let legacyPlaylistsKey = "fmp_playlists"
    private let legacyFavoritesKey = "fmp_favorites"
    private let legacySettingsKey = "fmp_settings"

    private var tracksFileURL: URL { AppFileManager.shared.dataFileURL(named: "tracks.json") }
    private var playlistsFileURL: URL { AppFileManager.shared.dataFileURL(named: "playlists.json") }
    private var likedTracksFileURL: URL { AppFileManager.shared.dataFileURL(named: "liked_tracks.json") }
    private var legacyFavoritesFileURL: URL { AppFileManager.shared.dataFileURL(named: "favorites.json") }
    private var favoriteArtistsFileURL: URL { AppFileManager.shared.dataFileURL(named: "favorite_artists.json") }
    private var savedAlbumsFileURL: URL { AppFileManager.shared.dataFileURL(named: "saved_albums.json") }
    private var settingsFileURL: URL { AppFileManager.shared.dataFileURL(named: "settings.json") }

    var importFolders: [ImportedMusicFolder] {
        settings.importFolders
    }

    var hasImportFolders: Bool {
        !settings.importFolders.isEmpty
    }

    var myWaveSettings: MyWaveSettings {
        settings.myWaveSettings
    }

    init() {
        // Data loading is deferred to loadData() which runs heavy I/O off the main thread.
        // See loadData() for the async background loading pipeline.
    }

    func setMyWaveActivity(_ activity: MyWaveSettings.Activity?) {
        updateAppSettings { settings in
            settings.myWaveSettings.activity = settings.myWaveSettings.activity == activity ? nil : activity
        }
    }

    func setMyWaveVibe(_ vibe: MyWaveSettings.Vibe?) {
        updateAppSettings { settings in
            settings.myWaveSettings.vibe = settings.myWaveSettings.vibe == vibe ? nil : vibe
        }
    }

    func setMyWaveMood(_ mood: MyWaveSettings.Mood?) {
        updateAppSettings { settings in
            settings.myWaveSettings.mood = settings.myWaveSettings.mood == mood ? nil : mood
        }
    }

    func setMyWaveLanguage(_ language: MyWaveSettings.Language?) {
        updateAppSettings { settings in
            settings.myWaveSettings.language = settings.myWaveSettings.language == language ? nil : language
        }
    }

    func resetMyWaveSettings() {
        updateAppSettings { settings in
            settings.myWaveSettings = .default
        }
    }

    func setShufflePreference(_ isEnabled: Bool) {
        updateAppSettings { settings in
            settings.shuffle = isEnabled
        }
    }

    func setRepeatModePreference(_ repeatMode: AppSettings.RepeatMode) {
        updateAppSettings { settings in
            settings.repeatMode = repeatMode
        }
    }

    func setShowLyricsPreference(_ isEnabled: Bool) {
        updateAppSettings { settings in
            settings.showLyrics = isEnabled
        }
    }

    func setCacheEnabledPreference(_ isEnabled: Bool) {
        updateAppSettings { settings in
            settings.cacheEnabled = isEnabled
        }
    }

    func setAudioQualityPreference(_ quality: AppSettings.AudioQuality) {
        updateAppSettings { settings in
            settings.quality = quality
        }
    }

    func loadData() {
        guard !hasLoadedData, !isLoadingData else { return }
        isLoadingData = true

        Task.detached(priority: .high) { [weak self] in
            guard let self else { return }

            AppFileManager.shared.prepareDirectories(resetTemporaryStorage: true)

            let didLoadFromFiles = self.loadDataFromFiles()
            if !didLoadFromFiles {
                self.migrateLegacyUserDefaults()
            }

            // Filter out temp tracks and verify file existence in background
            var filteredTracks = self.tracks.filter { track in
                track.storageLocation != .temp
            }

            filteredTracks = filteredTracks.filter { track in
                guard let fileURL = track.fileURL else { return true }
                if URL(string: fileURL)?.scheme != nil { return true }
                return AppFileManager.shared.fileExists(at: fileURL)
            }

            // Publish results back on main thread
            await MainActor.run {
                self.tracks = filteredTracks
                self.refreshStoredLocalMetadataIfNeeded()
                self.synchronizeUnifiedTrackLibraryState()
                self.refreshDerivedCollections()
                self.isLoadingData = false
                self.hasLoadedData = true
            }

            // Save in background — only write files that actually changed
            self.saveDataInBackground()
        }
    }

    func saveData() {
        synchronizeUnifiedTrackLibraryState()
        refreshDerivedCollections()

        let persistedTracks = tracks.filter { $0.storageLocation != .temp }
        writeJSONIfChanged(persistedTracks, to: tracksFileURL)
        writeJSONIfChanged(playlists, to: playlistsFileURL)
        writeJSONIfChanged(likedTrackIDs, to: likedTracksFileURL)
        writeJSONIfChanged(favoriteArtists, to: favoriteArtistsFileURL)
        writeJSONIfChanged(savedAlbums, to: savedAlbumsFileURL)
        writeJSONIfChanged(settings, to: settingsFileURL)
        NotificationCenter.default.post(name: .myWaveSignalsDidChange, object: nil)
    }

    /// Debounced save — coalesces rapid successive calls into a single disk write.
    func scheduleSave() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.saveData()
            }
        }
    }

    /// Runs saveData() entirely on a background thread — all file writes happen off main.
    private func saveDataInBackground() {
        synchronizeUnifiedTrackLibraryState()
        refreshDerivedCollections()

        let persistedTracks = tracks.filter { $0.storageLocation != .temp }
        let currentPlaylists = playlists
        let currentLikedIDs = likedTrackIDs
        let currentArtists = favoriteArtists
        let currentAlbums = savedAlbums
        let currentSettings = settings

        Task.detached(priority: .utility) {
            self.writeJSONIfChanged(persistedTracks, to: self.tracksFileURL)
            self.writeJSONIfChanged(currentPlaylists, to: self.playlistsFileURL)
            self.writeJSONIfChanged(currentLikedIDs, to: self.likedTracksFileURL)
            self.writeJSONIfChanged(currentArtists, to: self.favoriteArtistsFileURL)
            self.writeJSONIfChanged(currentAlbums, to: self.savedAlbumsFileURL)
            self.writeJSONIfChanged(currentSettings, to: self.settingsFileURL)

            await MainActor.run {
                NotificationCenter.default.post(name: .myWaveSignalsDidChange, object: nil)
            }
        }
    }

    /// Refreshes pre-computed derived collections so Views don't compute them in body.
    private func refreshDerivedCollections() {
        popularTracks = Array(
            tracks
                .filter { $0.playCount > 0 }
                .sorted(by: popularTrackSort)
                .prefix(5)
        )

        recentTracks = Array(
            tracks
                .filter { $0.lastPlayed != nil }
                .sorted(by: recentTrackSort)
                .prefix(10)
        )

        likedTracksList = tracks.filter { $0.isLiked && $0.isDownloaded }
        downloadedTracksList = tracks.filter { $0.isDownloaded }
    }

    private func popularTrackSort(_ left: Track, _ right: Track) -> Bool {
        if left.playCount != right.playCount {
            return left.playCount > right.playCount
        }
        let leftLastPlayed = left.lastPlayed ?? .distantPast
        let rightLastPlayed = right.lastPlayed ?? .distantPast
        if leftLastPlayed != rightLastPlayed {
            return leftLastPlayed > rightLastPlayed
        }
        return left.addedAt > right.addedAt
    }

    private func recentTrackSort(_ left: Track, _ right: Track) -> Bool {
        let leftLastPlayed = left.lastPlayed ?? .distantPast
        let rightLastPlayed = right.lastPlayed ?? .distantPast
        if leftLastPlayed != rightLastPlayed {
            return leftLastPlayed > rightLastPlayed
        }
        if left.playCount != right.playCount {
            return left.playCount > right.playCount
        }
        return left.addedAt > right.addedAt
    }

    @discardableResult
    func addTrack(_ track: Track) -> Track {
        debugLog("Add track: \(track.displayTitle)")

        if let existingIndex = existingTrackIndex(for: track) {
            var updatedTrack = track
            let existingTrack = tracks[existingIndex]
            updatedTrack.id = existingTrack.id
            updatedTrack.coverArtURL = resolvedPreferredStoredImageReference(
                newValue: track.coverArtURL,
                existingValue: existingTrack.coverArtURL
            )
            updatedTrack.remoteCoverArtURL = resolvedPreferredRemoteImageReference(
                newValue: track.remoteCoverArtURL,
                existingValue: existingTrack.remoteCoverArtURL
            )
            updatedTrack.artistImageURL = resolvedPreferredStoredImageReference(
                newValue: track.artistImageURL,
                existingValue: existingTrack.artistImageURL
            )
            updatedTrack.remoteArtistImageURL = resolvedPreferredRemoteImageReference(
                newValue: track.remoteArtistImageURL,
                existingValue: existingTrack.remoteArtistImageURL
            )
            updatedTrack.providerArtistID = resolvedPreferredTextValue(
                newValue: track.providerArtistID,
                existingValue: existingTrack.providerArtistID
            )
            updatedTrack.artistWebpageURL = resolvedPreferredTextValue(
                newValue: track.artistWebpageURL,
                existingValue: existingTrack.artistWebpageURL
            )
            updatedTrack.lyricsText = resolvedPreferredTextValue(
                newValue: track.lyricsText,
                existingValue: existingTrack.lyricsText
            )
            updatedTrack.lyricsSyncedText = resolvedPreferredTextValue(
                newValue: track.lyricsSyncedText,
                existingValue: existingTrack.lyricsSyncedText
            )
            updatedTrack.lyricsSource = resolvedPreferredTextValue(
                newValue: track.lyricsSource,
                existingValue: existingTrack.lyricsSource
            )
            updatedTrack.lyricsURL = resolvedPreferredTextValue(
                newValue: track.lyricsURL,
                existingValue: existingTrack.lyricsURL
            )
            if updatedTrack.genres.isEmpty {
                updatedTrack.genres = existingTrack.genres
            }
            if updatedTrack.tags.isEmpty {
                updatedTrack.tags = existingTrack.tags
            }
            if updatedTrack.moods.isEmpty {
                updatedTrack.moods = existingTrack.moods
            }
            updatedTrack.lyricsLastUpdated = track.lyricsLastUpdated ?? existingTrack.lyricsLastUpdated
            updatedTrack.isLiked = updatedTrack.isDownloaded &&
                (track.isLiked || existingTrack.isLiked || likedTrackIDs.contains(existingTrack.id))
            tracks[existingIndex] = updatedTrack
            saveData()
            return updatedTrack
        }

        var insertedTrack = track
        insertedTrack.isLiked = insertedTrack.isDownloaded && insertedTrack.isLiked
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

    @MainActor
    func toggleFavorite(_ track: Track) {
        debugLog("Toggle liked state for stored track: \(track.displayTitle)")

        guard let storedTrack = storedDownloadedTrack(for: track) else {
            debugLog("Like toggle ignored because the track is not downloaded locally")
            return
        }

        _ = setTrackLikedState(forStoredTrackID: storedTrack.id, isLiked: !storedTrack.isLiked)
    }

    @MainActor
    @discardableResult
    func toggleTrackSavedState(for track: Track) async throws -> Track? {
        debugLog("Toggle downloaded state from current track context: \(track.displayTitle)")

        if let storedTrack = storedDownloadedTrack(for: track) {
            removeTrack(storedTrack)
            return nil
        }

        let resolvedResult = try await OnlineMusicService.shared.resolveTrackResult(for: track)
        let savedTrack = try await downloadOnlineTrack(result: resolvedResult, isLiked: false)
        AudioPlayer.shared.syncCurrentTrackReference(with: savedTrack)
        return savedTrack
    }

    @MainActor
    @discardableResult
    func toggleTrackSavedState(for result: OnlineTrackResult) async throws -> Track? {
        debugLog("Toggle downloaded state for online result: \(result.title)")

        if let storedTrack = track(withSourceID: result.id) {
            removeTrack(storedTrack)
            return nil
        }

        return try await downloadOnlineTrack(result: result, isLiked: false)
    }

    @MainActor
    @discardableResult
    func toggleTrackLikedState(for track: Track) async throws -> Track? {
        debugLog("Toggle liked state from current track context: \(track.displayTitle)")

        if let storedTrack = storedDownloadedTrack(for: track) {
            return setTrackLikedState(forStoredTrackID: storedTrack.id, isLiked: !storedTrack.isLiked)
        }

        let resolvedResult = try await OnlineMusicService.shared.resolveTrackResult(for: track)
        let savedTrack = try await downloadOnlineTrack(result: resolvedResult, isLiked: true)
        AudioPlayer.shared.syncCurrentTrackReference(with: savedTrack)
        return savedTrack
    }

    @MainActor
    @discardableResult
    func toggleTrackLikedState(for result: OnlineTrackResult) async throws -> Track? {
        debugLog("Toggle liked state for online result: \(result.title)")

        if let storedTrack = track(withSourceID: result.id) {
            return setTrackLikedState(forStoredTrackID: storedTrack.id, isLiked: !storedTrack.isLiked)
        }

        return try await downloadOnlineTrack(result: result, isLiked: true)
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

    func isFavoriteArtist(provider: OnlineTrackProvider, artistID: String) -> Bool {
        favoriteArtists.contains { $0.provider == provider && $0.providerArtistID == artistID }
    }

    func favoriteArtist(provider: OnlineTrackProvider, artistID: String) -> FavoriteArtist? {
        favoriteArtists.first { $0.provider == provider && $0.providerArtistID == artistID }
    }

    func toggleFavoriteArtist(_ artist: FavoriteArtist) {
        debugLog("Toggle favorite artist: \(artist.artistName)")

        if let index = favoriteArtists.firstIndex(where: {
            $0.provider == artist.provider && $0.providerArtistID == artist.providerArtistID
        }) {
            favoriteArtists.remove(at: index)
        } else {
            favoriteArtists.insert(artist, at: 0)
        }

        saveData()

        guard favoriteArtists.contains(where: {
            $0.provider == artist.provider && $0.providerArtistID == artist.providerArtistID
        }) else {
            return
        }

        persistFavoriteArtistImageIfNeeded(artist: artist)
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

        // Build a dictionary for O(1) lookups instead of O(n*m) linear scan
        let trackDictionary = Dictionary(uniqueKeysWithValues:
            tracks.map { ($0.id, $0) }
        )
        return playlist.trackIDs.compactMap { trackDictionary[$0] }
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

    func moveTracks(inPlaylistID playlistId: String, fromOffsets: IndexSet, toOffset: Int) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }

        var playlist = playlists[index]
        playlist.trackIDs.move(fromOffsets: fromOffsets, toOffset: toOffset)
        playlist.updatedAt = Date()
        playlists[index] = playlist
        saveData()
    }

    func setPlaylistCoverImage(_ imageData: Data, forPlaylistID playlistId: String) throws {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        guard let image = UIImage(data: imageData) else {
            throw PlaylistCoverPersistenceError.invalidImageData
        }

        let normalizedImageData: Data
        let fileExtension: String

        if let jpegData = image.jpegData(compressionQuality: 0.92) {
            normalizedImageData = jpegData
            fileExtension = "jpg"
        } else if let pngData = image.pngData() {
            normalizedImageData = pngData
            fileExtension = "png"
        } else {
            throw PlaylistCoverPersistenceError.invalidImageData
        }

        let previousCoverReference = playlists[index].coverArtURL
        let storedURL = try AppFileManager.shared.savePersistentImageData(
            normalizedImageData,
            preferredName: "playlist-\(playlistId)-cover",
            fileExtension: fileExtension
        )

        playlists[index].coverArtURL = AppFileManager.shared.relativePath(for: storedURL)
        playlists[index].updatedAt = Date()
        saveData()

        if previousCoverReference != playlists[index].coverArtURL {
            deleteStoredImageIfNeeded(reference: previousCoverReference)
        }
    }

    func removePlaylistCover(forPlaylistID playlistId: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }

        let previousCoverReference = playlists[index].coverArtURL
        guard previousCoverReference != nil else { return }

        playlists[index].coverArtURL = nil
        playlists[index].updatedAt = Date()
        saveData()
        deleteStoredImageIfNeeded(reference: previousCoverReference)
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
        likedTrackIDs.subtract(trackIDs)

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
        tracks.first { $0.sourceID == sourceID && $0.isDownloaded }
    }

    func storedDownloadedTrack(for track: Track) -> Track? {
        if let storedTrack = tracks.first(where: { $0.id == track.id && $0.isDownloaded }) {
            return storedTrack
        }

        if let sourceID = track.sourceID,
           let storedTrack = self.track(withSourceID: sourceID) {
            return storedTrack
        }

        if let importOriginID = track.importOriginID,
           let storedTrack = tracks.first(where: {
               $0.importOriginID == importOriginID && $0.isDownloaded
            }) {
            return storedTrack
        }

        return nil
    }

    func storedLibraryTrack(for track: Track) -> Track? {
        storedDownloadedTrack(for: track)
    }

    func isTrackDownloaded(_ track: Track) -> Bool {
        storedDownloadedTrack(for: track) != nil
    }

    func isTrackDownloaded(sourceID: String) -> Bool {
        track(withSourceID: sourceID) != nil
    }

    func isTrackSaved(_ track: Track) -> Bool {
        isTrackDownloaded(track)
    }

    func isTrackSaved(sourceID: String) -> Bool {
        isTrackDownloaded(sourceID: sourceID)
    }

    func isTrackLiked(_ track: Track) -> Bool {
        storedDownloadedTrack(for: track)?.isLiked == true
    }

    func isTrackLiked(sourceID: String) -> Bool {
        track(withSourceID: sourceID)?.isLiked == true
    }

    @MainActor
    @discardableResult
    func setTrackLikedState(for track: Track, isLiked: Bool) -> Track? {
        guard let storedTrack = storedDownloadedTrack(for: track) else {
            return nil
        }

        return setTrackLikedState(forStoredTrackID: storedTrack.id, isLiked: isLiked)
    }

    func makeTemporaryTrack(from result: OnlineTrackResult, tempFileURL: URL) -> Track {
        let storedPath = AppFileManager.shared.relativePath(for: tempFileURL) ?? tempFileURL.path
        let metadata = resolvedDownloadedTrackMetadata(from: result, localFileURL: tempFileURL)
        debugLog("Create temporary track entry for \(result.title) at \(storedPath)")

        return Track(
            title: metadata.title,
            artist: metadata.artist,
            album: metadata.album,
            genres: result.genres,
            tags: result.tags,
            moods: result.moods,
            duration: metadata.duration,
            fileURL: storedPath,
            coverArtURL: result.coverArtURL,
            source: result.trackSource,
            isLiked: false,
            playCount: 0,
            lastPlayed: nil,
            addedAt: Date(),
            sourceID: result.id,
            remotePageURL: result.webpageURL,
            storageLocation: .temp,
            remoteCoverArtURL: result.coverArtURL,
            artistImageURL: result.artistImageURL,
            remoteArtistImageURL: result.artistImageURL,
            providerArtistID: result.providerArtistID,
            artistWebpageURL: result.artistWebpageURL
        )
    }

    func makeStreamingTrack(from result: OnlineTrackResult, streamURL: URL) -> Track {
        debugLog("Create streaming track entry for \(result.title) at \(streamURL.absoluteString)")

        return Track(
            title: result.title,
            artist: result.artist,
            album: result.album,
            genres: result.genres,
            tags: result.tags,
            moods: result.moods,
            duration: result.duration,
            fileURL: streamURL.absoluteString,
            coverArtURL: result.coverArtURL,
            source: result.trackSource,
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

    @MainActor
    @discardableResult
    func saveDownloadedOnlineTrack(
        _ result: OnlineTrackResult,
        from tempFileURL: URL,
        isLiked: Bool = false
    ) async throws -> Track {
        if let existingTrack = track(withSourceID: result.id) {
            debugLog("Reuse existing saved online track: \(existingTrack.displayTitle)")
            let existingIndex = tracks.firstIndex(where: { $0.id == existingTrack.id })

            if let existingIndex {
                var updatedTrack = tracks[existingIndex]
                var didUpdateMetadata = false

                if isLiked && !updatedTrack.isLiked {
                    updatedTrack.isLiked = true
                    didUpdateMetadata = true
                }

                let resolvedProviderArtistID = resolvedPreferredTextValue(
                    newValue: result.providerArtistID,
                    existingValue: updatedTrack.providerArtistID
                )
                if updatedTrack.providerArtistID != resolvedProviderArtistID {
                    updatedTrack.providerArtistID = resolvedProviderArtistID
                    didUpdateMetadata = true
                }

                let resolvedArtistWebpageURL = resolvedPreferredTextValue(
                    newValue: result.artistWebpageURL,
                    existingValue: updatedTrack.artistWebpageURL
                )
                if updatedTrack.artistWebpageURL != resolvedArtistWebpageURL {
                    updatedTrack.artistWebpageURL = resolvedArtistWebpageURL
                    didUpdateMetadata = true
                }

                if !result.genres.isEmpty && updatedTrack.genres != result.genres {
                    updatedTrack.genres = result.genres
                    didUpdateMetadata = true
                }

                if !result.tags.isEmpty && updatedTrack.tags != result.tags {
                    updatedTrack.tags = result.tags
                    didUpdateMetadata = true
                }

                if !result.moods.isEmpty && updatedTrack.moods != result.moods {
                    updatedTrack.moods = result.moods
                    didUpdateMetadata = true
                }

                if didUpdateMetadata {
                    tracks[existingIndex] = updatedTrack
                    saveData()
                }
            }

            if let refreshedTrack = await persistOfflineVisualsIfNeeded(
                forTrackID: existingTrack.id,
                preferredCoverReference: result.coverArtURL ?? existingTrack.remoteCoverArtURL,
                preferredArtistReference: result.artistImageURL ?? existingTrack.remoteArtistImageURL
            ) {
                let resolvedTrack = existingIndex.map { tracks[$0] } ?? refreshedTrack
                scheduleLyricsPersistenceIfNeeded(for: resolvedTrack)
                return resolvedTrack
            }

            let resolvedTrack = existingIndex.map { tracks[$0] } ?? existingTrack
            scheduleLyricsPersistenceIfNeeded(for: resolvedTrack)
            return resolvedTrack
        }

        async let localArtworkPath = persistImageReferenceIfNeeded(
            result.coverArtURL,
            preferredName: "track-\(result.id)-cover"
        )
        async let localArtistImagePath = persistImageReferenceIfNeeded(
            result.artistImageURL,
            preferredName: "artist-\(result.providerArtistID ?? result.id)-avatar"
        )

        let destinationURL = try AppFileManager.shared.copyToLibrary(
            from: tempFileURL,
            preferredName: "\(result.artist)-\(result.title)"
        )
        let storedPath = AppFileManager.shared.relativePath(for: destinationURL) ?? destinationURL.path
        let metadata = resolvedDownloadedTrackMetadata(from: result, localFileURL: destinationURL)
        let resolvedArtworkPath = await localArtworkPath
        let resolvedArtistImagePath = await localArtistImagePath
        debugLog("Register saved online track in library: \(result.title) at \(storedPath)")

        let track = Track(
            title: metadata.title,
            artist: metadata.artist,
            album: metadata.album,
            genres: result.genres,
            tags: result.tags,
            moods: result.moods,
            duration: metadata.duration,
            fileURL: storedPath,
            coverArtURL: resolvedArtworkPath ?? result.coverArtURL,
            source: result.trackSource,
            isLiked: isLiked,
            playCount: 0,
            lastPlayed: nil,
            addedAt: Date(),
            sourceID: result.id,
            remotePageURL: result.webpageURL,
            storageLocation: .library,
            remoteCoverArtURL: result.coverArtURL,
            artistImageURL: resolvedArtistImagePath ?? result.artistImageURL,
            remoteArtistImageURL: result.artistImageURL,
            providerArtistID: result.providerArtistID,
            artistWebpageURL: result.artistWebpageURL
        )

        let savedTrack = addTrack(track)
        Task(priority: .utility) {
            await ListeningHistoryStore.shared.record(
                kind: .libraryAdd,
                track: TrackTasteSnapshot(track: savedTrack),
                sourceContext: "library:add",
                notify: false
            )
        }
        scheduleLyricsPersistenceIfNeeded(for: savedTrack)
        return savedTrack
    }

    @MainActor
    @discardableResult
    func toggleAlbumSavedState(
        release: OnlineAlbumResult,
        trackResults: [OnlineTrackResult]
    ) async throws -> SavedAlbum? {
        debugLog("Toggle saved album state: \(release.title) [\(release.providerAlbumID)]")

        if savedAlbum(provider: release.provider, providerAlbumID: release.providerAlbumID) != nil {
            removeSavedAlbum(provider: release.provider, providerAlbumID: release.providerAlbumID)
            return nil
        }

        return try await saveAlbum(release: release, trackResults: trackResults)
    }

    @MainActor
    @discardableResult
    func saveAlbum(
        release: OnlineAlbumResult,
        trackResults: [OnlineTrackResult]
    ) async throws -> SavedAlbum {
        var savedTracks: [Track] = []
        savedTracks.reserveCapacity(trackResults.count)

        for result in trackResults {
            if let existingTrack = track(withSourceID: result.id) {
                savedTracks.append(existingTrack)
            } else {
                let savedTrack = try await downloadOnlineTrack(result: result, isLiked: false)
                savedTracks.append(savedTrack)
            }
        }

        let trackSourceIDs = savedTracks.compactMap(\.sourceID)
        let savedAlbum = upsertSavedAlbum(
            release.savedAlbum,
            trackSourceIDs: trackSourceIDs
        )
        return savedAlbum
    }

    func isAlbumSaved(provider: OnlineTrackProvider, providerAlbumID: String) -> Bool {
        savedAlbum(provider: provider, providerAlbumID: providerAlbumID) != nil
    }

    func savedAlbum(provider: OnlineTrackProvider, providerAlbumID: String) -> SavedAlbum? {
        savedAlbums.first {
            $0.provider == provider && $0.providerAlbumID == providerAlbumID
        }
    }

    func tracks(for savedAlbum: SavedAlbum) -> [Track] {
        savedAlbum.trackSourceIDs.compactMap { sourceID in
            track(withSourceID: sourceID)
        }
    }

    func representativeTrack(for savedAlbum: SavedAlbum) -> Track? {
        tracks(for: savedAlbum).first(where: { $0.preferredArtworkReference != nil }) ?? tracks(for: savedAlbum).first
    }

    @discardableResult
    func removeSavedAlbum(provider: OnlineTrackProvider, providerAlbumID: String) -> SavedAlbum? {
        guard let index = savedAlbums.firstIndex(where: {
            $0.provider == provider && $0.providerAlbumID == providerAlbumID
        }) else {
            return nil
        }

        let removedAlbum = savedAlbums.remove(at: index)
        saveData()
        return removedAlbum
    }

    @MainActor
    @discardableResult
    func persistLyrics(_ lyrics: ResolvedTrackLyrics, for track: Track) -> Track? {
        guard let index = tracks.firstIndex(where: { $0.id == track.id })
            ?? tracks.firstIndex(where: { $0.sourceID != nil && $0.sourceID == track.sourceID }) else {
            return nil
        }

        var updatedTrack = tracks[index]
        var didUpdateTrack = false

        if updatedTrack.lyricsText != lyrics.text {
            updatedTrack.lyricsText = lyrics.text
            didUpdateTrack = true
        }

        if updatedTrack.lyricsSyncedText != lyrics.syncedText {
            updatedTrack.lyricsSyncedText = lyrics.syncedText
            didUpdateTrack = true
        }

        if updatedTrack.lyricsSource != lyrics.source {
            updatedTrack.lyricsSource = lyrics.source
            didUpdateTrack = true
        }

        if updatedTrack.lyricsURL != lyrics.url {
            updatedTrack.lyricsURL = lyrics.url
            didUpdateTrack = true
        }

        if updatedTrack.lyricsLastUpdated != lyrics.lastUpdated {
            updatedTrack.lyricsLastUpdated = lyrics.lastUpdated
            didUpdateTrack = true
        }

        guard didUpdateTrack else {
            return updatedTrack
        }

        tracks[index] = updatedTrack
        saveData()
        AudioPlayer.shared.syncCurrentTrackReference(with: updatedTrack)
        return updatedTrack
    }

    private func resolvedDownloadedTrackMetadata(from result: OnlineTrackResult, localFileURL: URL) -> DownloadedTrackMetadata {
        let asset = AVURLAsset(url: localFileURL)
        let validation = downloadedAudioValidationResult(
            from: localFileURL,
            expectedDuration: result.duration
        )
        let resolvedDuration = resolvedPreferredSavedDuration(
            actualDuration: validation.actualDuration,
            fallbackDuration: result.duration,
            expectedDuration: result.duration
        )

        let title = metadataValue(for: asset, identifier: .commonIdentifierTitle) ?? result.title
        let artist = metadataValue(for: asset, identifier: .commonIdentifierArtist) ?? result.artist
        let album = metadataValue(for: asset, identifier: .commonIdentifierAlbumName) ?? result.album

        debugLog(
            "Downloaded metadata resolved for \(result.title): title=\(title), artist=\(artist), expected=\(validation.expectedDuration), asset=\(validation.assetDuration), player=\(validation.audioPlayerDuration), actual=\(validation.actualDuration), fileSize=\(validation.fileSize), passed=\(validation.passedValidation), truncated=\(validation.isLikelyTruncated), finalDuration=\(resolvedDuration)"
        )

        return DownloadedTrackMetadata(
            title: title,
            artist: artist,
            album: album,
            duration: resolvedDuration
        )
    }

    func markTrackPlayed(_ track: Track) {
        guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }

        tracks[index].playCount += 1
        tracks[index].lastPlayed = Date()
        scheduleSave()
    }

    func shuffleTracks() {
        guard tracks.count > 1 else { return }
        debugLog("Shuffle library tracks")
        tracks.shuffle()
        saveData()
    }

    var likedTracks: [Track] {
        likedTracksList
    }

    var downloadedTracks: [Track] {
        downloadedTracksList
    }

    var favoriteTracks: [Track] {
        likedTracks
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
        likedTrackIDs.removeAll()
        favoriteArtists.removeAll()
        savedAlbums.removeAll()
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
        let loadedLikedTrackIDs: Set<String>? = readJSON(from: likedTracksFileURL) ??
            readJSON(from: legacyFavoritesFileURL)
        let loadedFavoriteArtists: [FavoriteArtist]? = readJSON(from: favoriteArtistsFileURL)
        let loadedSavedAlbums: [SavedAlbum]? = readJSON(from: savedAlbumsFileURL)
        let loadedSettings: AppSettings? = readJSON(from: settingsFileURL)

        let didLoadAnything = loadedTracks != nil ||
            loadedPlaylists != nil ||
            loadedLikedTrackIDs != nil ||
            loadedFavoriteArtists != nil ||
            loadedSavedAlbums != nil ||
            loadedSettings != nil

        if let loadedTracks {
            tracks = loadedTracks
        }

        if let loadedPlaylists {
            playlists = loadedPlaylists
        }

        if let loadedLikedTrackIDs {
            likedTrackIDs = loadedLikedTrackIDs
        }

        if let loadedFavoriteArtists {
            favoriteArtists = deduplicatedFavoriteArtists(loadedFavoriteArtists)
        }

        if let loadedSavedAlbums {
            savedAlbums = deduplicatedSavedAlbums(loadedSavedAlbums)
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
            likedTrackIDs = decoded
        }

        if let data = UserDefaults.standard.data(forKey: legacySettingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        }
    }

    private func existingTrackIndex(for track: Track) -> Int? {
        if let sourceID = track.sourceID,
           let index = tracks.firstIndex(where: { $0.sourceID == sourceID && $0.isDownloaded }) {
            return index
        }

        if let importOriginID = track.importOriginID,
           let index = tracks.firstIndex(where: { $0.importOriginID == importOriginID && $0.isDownloaded }) {
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
        if isCurrentPlaybackTrack(track) {
            debugLog("Preserve stored resources for active playback track during library removal: \(track.displayTitle)")
            return
        }

        if let fileURL = track.fileURL,
           track.isDownloaded {
            let resolvedURL = AppFileManager.shared.resolveStoredFileURL(for: fileURL)
            try? FileManager.default.removeItem(at: resolvedURL)
        }

        if let artworkURL = track.localArtworkURL {
            try? FileManager.default.removeItem(at: artworkURL)
        }
    }

    private func isCurrentPlaybackTrack(_ track: Track) -> Bool {
        guard let currentTrack = AudioPlayer.shared.currentTrack else {
            return false
        }

        if currentTrack.id == track.id {
            return true
        }

        if let sourceID = currentTrack.sourceID,
           sourceID == track.sourceID {
            return true
        }

        return false
    }

    private func resolvedPreferredStoredImageReference(newValue: String?, existingValue: String?) -> String? {
        let cleanedNewValue = cleanedImageReference(newValue)
        let cleanedExistingValue = cleanedImageReference(existingValue)

        if let cleanedExistingValue,
           !isRemoteImageReference(cleanedExistingValue),
           hasAccessibleLocalImageReference(cleanedExistingValue) {
            return cleanedExistingValue
        }

        if let cleanedNewValue,
           !isRemoteImageReference(cleanedNewValue),
           hasAccessibleLocalImageReference(cleanedNewValue) {
            return cleanedNewValue
        }

        if let cleanedExistingValue, isRemoteImageReference(cleanedExistingValue) {
            return cleanedExistingValue
        }

        if let cleanedNewValue, isRemoteImageReference(cleanedNewValue) {
            return cleanedNewValue
        }

        return cleanedNewValue ?? cleanedExistingValue
    }

    private func resolvedPreferredRemoteImageReference(newValue: String?, existingValue: String?) -> String? {
        if let cleanedNewValue = cleanedImageReference(newValue),
           isRemoteImageReference(cleanedNewValue) {
            return cleanedNewValue
        }

        if let cleanedExistingValue = cleanedImageReference(existingValue),
           isRemoteImageReference(cleanedExistingValue) {
            return cleanedExistingValue
        }

        return nil
    }

    private func resolvedPreferredTextValue(newValue: String?, existingValue: String?) -> String? {
        cleanedImageReference(newValue) ?? cleanedImageReference(existingValue)
    }

    private func persistFavoriteArtistImageIfNeeded(artist: FavoriteArtist) {
        guard !hasAccessibleLocalImageReference(artist.localImagePath),
              let preferredImageReference = cleanedImageReference(artist.imageURL) else {
            return
        }

        let preferredName = "favorite-artist-\(artist.id)-avatar"

        Task { [weak self] in
            guard let self else { return }

            let localImagePath = await self.persistImageReferenceIfNeeded(
                preferredImageReference,
                preferredName: preferredName
            )

            guard let localImagePath else { return }

            await MainActor.run {
                guard let index = self.favoriteArtists.firstIndex(where: {
                    $0.provider == artist.provider && $0.providerArtistID == artist.providerArtistID
                }) else {
                    return
                }

                self.favoriteArtists[index] = FavoriteArtist(
                    provider: artist.provider,
                    providerArtistID: artist.providerArtistID,
                    artistName: self.favoriteArtists[index].artistName,
                    imageURL: self.favoriteArtists[index].imageURL,
                    localImagePath: localImagePath,
                    webpageURL: self.favoriteArtists[index].webpageURL
                )
                self.saveData()
            }
        }
    }

    private func scheduleLyricsPersistenceIfNeeded(for track: Track) {
        guard cleanedImageReference(track.lyricsText) == nil else { return }
        guard track.isDownloaded || isTrackDownloaded(track) else { return }

        Task { [weak self] in
            guard let self else { return }
            guard let resolvedLyrics = await LyricsMetadataResolver.shared.resolvedLyrics(for: track) else {
                return
            }

            await MainActor.run {
                _ = self.persistLyrics(resolvedLyrics, for: track)
            }
        }
    }

    private func scheduleOfflineVisualPersistenceIfNeeded(
        forTrackID trackID: String,
        preferredCoverReference: String?,
        preferredArtistReference: String?
    ) {
        Task { [weak self] in
            guard let self else { return }
            _ = await self.persistOfflineVisualsIfNeeded(
                forTrackID: trackID,
                preferredCoverReference: preferredCoverReference,
                preferredArtistReference: preferredArtistReference
            )
        }
    }

    @MainActor
    @discardableResult
    private func persistOfflineVisualsIfNeeded(
        forTrackID trackID: String,
        preferredCoverReference: String?,
        preferredArtistReference: String?
    ) async -> Track? {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else {
            return nil
        }

        let existingTrack = tracks[index]
        let resolvedCoverReference = cleanedImageReference(preferredCoverReference) ??
            cleanedImageReference(existingTrack.remoteCoverArtURL) ??
            cleanedImageReference(existingTrack.coverArtURL)
        let resolvedArtistReference = cleanedImageReference(preferredArtistReference) ??
            cleanedImageReference(existingTrack.remoteArtistImageURL) ??
            cleanedImageReference(existingTrack.artistImageURL)

        async let localArtworkPath = persistImageReferenceIfNeeded(
            resolvedCoverReference,
            preferredName: "track-\(existingTrack.sourceID ?? existingTrack.id)-cover"
        )
        async let localArtistPath = persistImageReferenceIfNeeded(
            resolvedArtistReference,
            preferredName: "artist-\(existingTrack.sourceID ?? existingTrack.id)-avatar"
        )

        let resolvedArtworkPath = await localArtworkPath
        let resolvedArtistPath = await localArtistPath

        var updatedTrack = existingTrack
        var didUpdateTrack = false

        if let resolvedCoverReference,
           updatedTrack.remoteCoverArtURL == nil,
           isRemoteImageReference(resolvedCoverReference) {
            updatedTrack.remoteCoverArtURL = resolvedCoverReference
            didUpdateTrack = true
        }

        if let resolvedArtistReference,
           updatedTrack.remoteArtistImageURL == nil,
           isRemoteImageReference(resolvedArtistReference) {
            updatedTrack.remoteArtistImageURL = resolvedArtistReference
            didUpdateTrack = true
        }

        if let resolvedArtworkPath,
           updatedTrack.coverArtURL != resolvedArtworkPath {
            updatedTrack.coverArtURL = resolvedArtworkPath
            didUpdateTrack = true
        }

        if let resolvedArtistPath,
           updatedTrack.artistImageURL != resolvedArtistPath {
            updatedTrack.artistImageURL = resolvedArtistPath
            didUpdateTrack = true
        }

        guard didUpdateTrack else {
            return existingTrack
        }

        tracks[index] = updatedTrack
        saveData()
        return updatedTrack
    }

    private func persistImageReferenceIfNeeded(
        _ reference: String?,
        preferredName: String
    ) async -> String? {
        guard let reference = cleanedImageReference(reference) else {
            return nil
        }

        if let parsedURL = URL(string: reference), parsedURL.scheme != nil {
            if parsedURL.isFileURL {
                guard FileManager.default.fileExists(atPath: parsedURL.path) else { return nil }
                return AppFileManager.shared.relativePath(for: parsedURL) ?? parsedURL.path
            }

            guard let scheme = parsedURL.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return nil
            }

            do {
                var request = URLRequest(url: parsedURL)
                request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
                request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    return nil
                }

                guard !data.isEmpty else { return nil }

                let fileExtension = preferredImageFileExtension(
                    mimeType: response.mimeType,
                    fallbackURL: parsedURL
                )
                let storedURL = try AppFileManager.shared.savePersistentImageData(
                    data,
                    preferredName: preferredName,
                    fileExtension: fileExtension
                )
                return AppFileManager.shared.relativePath(for: storedURL) ?? storedURL.path
            } catch {
                debugLog("Image persistence skipped for \(preferredName): \(error.localizedDescription)")
                return nil
            }
        }

        guard AppFileManager.shared.fileExists(at: reference) else {
            return nil
        }

        return reference
    }

    private func preferredImageFileExtension(mimeType: String?, fallbackURL: URL) -> String {
        if let mimeType = mimeType?.lowercased() {
            if mimeType.contains("png") { return "png" }
            if mimeType.contains("webp") { return "webp" }
            if mimeType.contains("gif") { return "gif" }
            if mimeType.contains("heic") || mimeType.contains("heif") { return "heic" }
            if mimeType.contains("jpeg") || mimeType.contains("jpg") { return "jpg" }
        }

        let fallbackExtension = fallbackURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallbackExtension.isEmpty ? "jpg" : fallbackExtension
    }

    private func cleanedImageReference(_ value: String?) -> String? {
        guard let value else { return nil }

        let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedValue.isEmpty ? nil : cleanedValue
    }

    private func isRemoteImageReference(_ value: String) -> Bool {
        guard let parsedURL = URL(string: value),
              let scheme = parsedURL.scheme?.lowercased() else {
            return false
        }

        return scheme == "http" || scheme == "https"
    }

    private func hasAccessibleLocalImageReference(_ value: String?) -> Bool {
        guard let value = cleanedImageReference(value) else {
            return false
        }

        if let parsedURL = URL(string: value), parsedURL.scheme != nil {
            guard parsedURL.isFileURL else { return false }
            return FileManager.default.fileExists(atPath: parsedURL.path)
        }

        return AppFileManager.shared.fileExists(at: value)
    }

    @MainActor
    private func downloadOnlineTrack(result: OnlineTrackResult, isLiked: Bool) async throws -> Track {
        let tempURL = try await OnlineMusicService.shared.downloadAudio(for: result)
        let savedTrack = try await saveDownloadedOnlineTrack(
            result,
            from: tempURL,
            isLiked: isLiked
        )
        return savedTrack
    }

    @MainActor
    @discardableResult
    private func setTrackLikedState(forStoredTrackID trackID: String, isLiked: Bool) -> Track? {
        guard let index = tracks.firstIndex(where: { $0.id == trackID && $0.isDownloaded }) else {
            return nil
        }

        tracks[index].isLiked = isLiked
        if isLiked {
            likedTrackIDs.insert(trackID)
        } else {
            likedTrackIDs.remove(trackID)
        }
        saveData()
        return tracks[index]
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

    /// Only writes to disk if the value has actually changed from the persisted version.
    /// Avoids redundant atomic file writes when nothing has been modified.
    private func writeJSONIfChanged<T: Codable & Equatable>(_ value: T, to url: URL) {
        if let existing: T = readJSON(from: url), existing == value {
            return
        }
        writeJSON(value, to: url)
    }

    private func deleteStoredImageIfNeeded(reference: String?) {
        guard let reference = cleanedImageReference(reference) else { return }

        if let parsedURL = URL(string: reference), parsedURL.scheme != nil {
            guard parsedURL.isFileURL else { return }
            try? FileManager.default.removeItem(at: parsedURL)
            return
        }

        let resolvedURL = AppFileManager.shared.resolveStoredFileURL(for: reference)
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else { return }
        try? FileManager.default.removeItem(at: resolvedURL)
    }

    private func deduplicatedFavoriteArtists(_ artists: [FavoriteArtist]) -> [FavoriteArtist] {
        var seenIDs: Set<String> = []
        var orderedArtists: [FavoriteArtist] = []

        for artist in artists where seenIDs.insert(artist.id).inserted {
            orderedArtists.append(artist)
        }

        return orderedArtists
    }

    @discardableResult
    private func upsertSavedAlbum(_ album: SavedAlbum, trackSourceIDs: [String]) -> SavedAlbum {
        let orderedTrackSourceIDs = orderedUniqueValues(trackSourceIDs)
        var updatedAlbum = album
        updatedAlbum.trackSourceIDs = orderedTrackSourceIDs

        if let index = savedAlbums.firstIndex(where: { $0.id == album.id }) {
            updatedAlbum.addedAt = savedAlbums[index].addedAt
            savedAlbums[index] = updatedAlbum
        } else {
            savedAlbums.insert(updatedAlbum, at: 0)
        }

        saveData()
        return updatedAlbum
    }

    private func deduplicatedSavedAlbums(_ albums: [SavedAlbum]) -> [SavedAlbum] {
        var seenIDs: Set<String> = []
        var orderedAlbums: [SavedAlbum] = []

        for album in albums where seenIDs.insert(album.id).inserted {
            var deduplicatedAlbum = album
            deduplicatedAlbum.trackSourceIDs = orderedUniqueValues(album.trackSourceIDs)
            orderedAlbums.append(deduplicatedAlbum)
        }

        return orderedAlbums
    }

    private func synchronizeUnifiedTrackLibraryState() {
        let downloadedTrackIDs = Set(
            tracks
                .filter(\.isDownloaded)
                .map(\.id)
        )
        likedTrackIDs = likedTrackIDs.intersection(downloadedTrackIDs)
        likedTrackIDs.formUnion(
            tracks
                .filter { $0.isDownloaded && $0.isLiked }
                .map(\.id)
        )

        for index in tracks.indices {
            let shouldBeLiked = tracks[index].isDownloaded && likedTrackIDs.contains(tracks[index].id)
            if tracks[index].isLiked != shouldBeLiked {
                tracks[index].isLiked = shouldBeLiked
            }
        }
    }

    private func orderedUniqueValues(_ values: [String]) -> [String] {
        var seenValues: Set<String> = []
        return values.filter { seenValues.insert($0).inserted }
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

            if self.tracks.contains(where: { $0.importOriginID == importOriginID && $0.isDownloaded }) {
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
                genres: probe.genre.map { [$0] } ?? [],
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
        let metadataItems = allMetadataItems(for: asset)
        let audioTracks = asset.tracks(withMediaType: .audio)
        let fallbackPlayer = try? AVAudioPlayer(contentsOf: url)
        let durationSeconds = max(CMTimeGetSeconds(asset.duration), 0)
        let resolvedDuration = durationSeconds > 0 ? durationSeconds : max(fallbackPlayer?.duration ?? 0, 0)

        guard !audioTracks.isEmpty || asset.isPlayable || fallbackPlayer != nil else {
            debugLog("Track probe skipped \(url.lastPathComponent): no readable audio stream found")
            throw LibraryImportError.unplayableFile(url.lastPathComponent)
        }

        let filenameFallback = parsedFilenameMetadata(from: url)
        let metadataSummary = resolvedImportedMetadata(from: metadataItems)
        let title = metadataSummary.title ?? filenameFallback.title
        let artist = metadataSummary.preferredArtist ?? filenameFallback.artist ?? "Unknown Artist"
        let album = metadataSummary.album
        let genre = metadataSummary.genre
        let artworkData = artworkData(for: asset)

        debugLog("Imported file path: \(url.path)")
        debugLog("Metadata artist found: \(metadataSummary.artistTag ?? "none")")
        debugLog("Album artist found: \(metadataSummary.albumArtistTag ?? "none")")
        if metadataSummary.preferredArtist == nil {
            debugLog("Filename fallback used: \(filenameFallback.didParseArtist ? "artist+title" : "title-only") for \(url.lastPathComponent)")
        }
        debugLog("Metadata parsing source: \(metadataSummary.preferredArtistSource ?? (filenameFallback.didParseArtist ? "filename" : "default"))")
        debugLog("Final parsed title/artist: \(title) / \(artist)")
        debugLog("Metadata extracted for \(url.lastPathComponent): title=\(title), artist=\(artist), duration=\(resolvedDuration)")
        debugLog("Artwork extraction for \(url.lastPathComponent): \(artworkData == nil ? "missing" : "embedded artwork found")")

        return ImportedTrackProbe(
            title: title,
            artist: artist,
            album: album,
            genre: genre,
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

    private func allMetadataItems(for asset: AVURLAsset) -> [AVMetadataItem] {
        asset.commonMetadata + asset.availableMetadataFormats.flatMap { asset.metadata(forFormat: $0) }
    }

    private func resolvedImportedMetadata(from items: [AVMetadataItem]) -> ImportedMetadataSummary {
        let title = firstMetadataString(in: items) { descriptor in
            descriptor.commonKey == "title" ||
            descriptor.identifier.contains("title") ||
            descriptor.identifier.contains("/tit2") ||
            descriptor.key == "tit2" ||
            descriptor.key == "title" ||
            descriptor.key == "\u{00A9}nam"
        }

        let artistTag = firstMetadataString(in: items) { descriptor in
            isExplicitArtistDescriptor(descriptor) && !isAlbumArtistDescriptor(descriptor)
        }

        let albumArtistTag = firstMetadataString(in: items) { descriptor in
            isAlbumArtistDescriptor(descriptor)
        }

        let commonArtist = firstMetadataString(in: items) { descriptor in
            descriptor.commonKey == "artist" ||
            descriptor.identifier.contains("commonidentifierartist") ||
            descriptor.identifier.contains("common/artist")
        }

        let album = firstMetadataString(in: items) { descriptor in
            descriptor.commonKey == "albumname" ||
            descriptor.identifier.contains("albumname") ||
            descriptor.identifier.contains("/talb") ||
            descriptor.key == "talb" ||
            descriptor.key == "\u{00A9}alb" ||
            descriptor.key == "album"
        }

        let genre = firstMetadataString(in: items) { descriptor in
            descriptor.commonKey == "genre" ||
            descriptor.identifier.contains("genre") ||
            descriptor.identifier.contains("/tcon") ||
            descriptor.key == "tcon" ||
            descriptor.key == "\u{00A9}gen" ||
            descriptor.key == "genre"
        }

        let preferredArtist = artistTag ?? albumArtistTag ?? commonArtist
        let preferredArtistSource: String?

        if artistTag != nil {
            preferredArtistSource = "artist-tag"
        } else if albumArtistTag != nil {
            preferredArtistSource = "album-artist-tag"
        } else if commonArtist != nil {
            preferredArtistSource = "common-artist"
        } else {
            preferredArtistSource = nil
        }

        return ImportedMetadataSummary(
            title: title,
            artistTag: artistTag,
            albumArtistTag: albumArtistTag,
            commonArtist: commonArtist,
            album: album,
            genre: genre,
            preferredArtist: preferredArtist,
            preferredArtistSource: preferredArtistSource
        )
    }

    private func firstMetadataString(
        in items: [AVMetadataItem],
        matching predicate: (MetadataDescriptor) -> Bool
    ) -> String? {
        for item in items {
            let descriptor = metadataDescriptor(for: item)
            guard predicate(descriptor),
                  let value = metadataString(from: item) else {
                continue
            }

            return value
        }

        return nil
    }

    private func metadataDescriptor(for item: AVMetadataItem) -> MetadataDescriptor {
        let keyValue: String
        if let stringKey = item.key as? String {
            keyValue = stringKey
        } else if let stringKey = item.key as? NSString {
            keyValue = stringKey as String
        } else {
            keyValue = item.key.map { String(describing: $0) } ?? ""
        }

        return MetadataDescriptor(
            identifier: item.identifier?.rawValue.lowercased() ?? "",
            commonKey: item.commonKey?.rawValue.lowercased() ?? "",
            key: keyValue.lowercased(),
            keySpace: item.keySpace?.rawValue.lowercased() ?? ""
        )
    }

    private func metadataString(from item: AVMetadataItem) -> String? {
        if let stringValue = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !stringValue.isEmpty {
            return stringValue
        }

        if let value = item.value as? String {
            let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanedValue.isEmpty {
                return cleanedValue
            }
        }

        if let dataValue = item.dataValue {
            for encoding in [String.Encoding.utf8, .utf16, .unicode, .isoLatin1] {
                if let decodedValue = String(data: dataValue, encoding: encoding) {
                    let cleanedValue = decodedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleanedValue.isEmpty {
                        return cleanedValue
                    }
                }
            }
        }

        return nil
    }

    private func isExplicitArtistDescriptor(_ descriptor: MetadataDescriptor) -> Bool {
        descriptor.identifier.contains("/tpe1") ||
        descriptor.identifier.contains("itunesmetadataartist") ||
        descriptor.identifier.contains("quicktime/artist") ||
        descriptor.identifier.hasSuffix("/artist") ||
        descriptor.key == "tpe1" ||
        descriptor.key == "\u{00A9}art" ||
        descriptor.key == "artist"
    }

    private func isAlbumArtistDescriptor(_ descriptor: MetadataDescriptor) -> Bool {
        descriptor.identifier.contains("albumartist") ||
        descriptor.identifier.contains("album artist") ||
        descriptor.identifier.contains("/tpe2") ||
        descriptor.key == "tpe2" ||
        descriptor.key == "aart" ||
        descriptor.key == "albumartist" ||
        descriptor.key == "album artist"
    }

    private func parsedFilenameMetadata(from url: URL) -> FilenameMetadataFallback {
        let rawFilename = url.deletingPathExtension().lastPathComponent
        let cleanedFilename = rawFilename
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let leadingTrackNumberPattern = #"^\s*\d{1,3}\s*[-._]\s*"#
        let strippedFilename = cleanedFilename.replacingOccurrences(
            of: leadingTrackNumberPattern,
            with: "",
            options: .regularExpression
        )

        let separators = [" - ", " \u{2013} ", " \u{2014} "]
        for separator in separators {
            let components = strippedFilename.components(separatedBy: separator)
            guard components.count >= 2 else { continue }

            let artist = components.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = components.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)

            if !artist.isEmpty && !title.isEmpty {
                return FilenameMetadataFallback(title: title, artist: artist, didParseArtist: true)
            }
        }

        return FilenameMetadataFallback(
            title: strippedFilename.isEmpty ? rawFilename : strippedFilename,
            artist: nil,
            didParseArtist: false
        )
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
                if let genre = probe.genre {
                    tracks[index].genres = [genre]
                }
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
              track.isDownloaded,
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

        if track.genres.isEmpty {
            return true
        }

        return track.duration <= 0 ||
            track.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            track.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func updateAppSettings(_ mutation: (inout AppSettings) -> Void) {
        var updatedSettings = settings
        mutation(&updatedSettings)
        settings = updatedSettings
        saveData()
    }
}

struct AppSettings: Codable, Equatable {
    var theme: AppTheme = .dark
    var accentColor: String = "FF0000"
    var autoplay: Bool = true
    var shuffle: Bool = false
    var repeatMode: RepeatMode = .off
    var quality: AudioQuality = .high
    var showLyrics: Bool = true
    var cacheEnabled: Bool = true
    var importFolders: [ImportedMusicFolder] = []
    var myWaveSettings: MyWaveSettings = .default

    enum AppTheme: String, Codable, CaseIterable {
        case light
        case dark
        case system
    }

    enum RepeatMode: String, Codable, CaseIterable {
        case off
        case all
        case one
    }

    enum AudioQuality: String, Codable, CaseIterable {
        case low
        case medium
        case high
        case lossless
    }

    enum CodingKeys: String, CodingKey {
        case theme
        case accentColor
        case autoplay
        case shuffle
        case repeatMode
        case quality
        case showLyrics
        case cacheEnabled
        case importFolders
        case myWaveSettings
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .dark
        accentColor = try container.decodeIfPresent(String.self, forKey: .accentColor) ?? "FF0000"
        autoplay = try container.decodeIfPresent(Bool.self, forKey: .autoplay) ?? true
        shuffle = try container.decodeIfPresent(Bool.self, forKey: .shuffle) ?? false
        repeatMode = try container.decodeIfPresent(RepeatMode.self, forKey: .repeatMode) ?? .off
        quality = try container.decodeIfPresent(AudioQuality.self, forKey: .quality) ?? .high
        showLyrics = try container.decodeIfPresent(Bool.self, forKey: .showLyrics) ?? true
        cacheEnabled = try container.decodeIfPresent(Bool.self, forKey: .cacheEnabled) ?? true
        importFolders = try container.decodeIfPresent([ImportedMusicFolder].self, forKey: .importFolders) ?? []
        myWaveSettings = try container.decodeIfPresent(MyWaveSettings.self, forKey: .myWaveSettings) ?? .default
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(theme, forKey: .theme)
        try container.encode(accentColor, forKey: .accentColor)
        try container.encode(autoplay, forKey: .autoplay)
        try container.encode(shuffle, forKey: .shuffle)
        try container.encode(repeatMode, forKey: .repeatMode)
        try container.encode(quality, forKey: .quality)
        try container.encode(showLyrics, forKey: .showLyrics)
        try container.encode(cacheEnabled, forKey: .cacheEnabled)
        try container.encode(importFolders, forKey: .importFolders)
        try container.encode(myWaveSettings, forKey: .myWaveSettings)
    }

    static func == (lhs: AppSettings, rhs: AppSettings) -> Bool {
        lhs.theme == rhs.theme
            && lhs.accentColor == rhs.accentColor
            && lhs.autoplay == rhs.autoplay
            && lhs.shuffle == rhs.shuffle
            && lhs.repeatMode == rhs.repeatMode
            && lhs.quality == rhs.quality
            && lhs.showLyrics == rhs.showLyrics
            && lhs.cacheEnabled == rhs.cacheEnabled
            && lhs.importFolders == rhs.importFolders
            && lhs.myWaveSettings == rhs.myWaveSettings
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
    let genre: String?
    let duration: TimeInterval
    let artworkData: Data?
}

private struct ImportedMetadataSummary {
    let title: String?
    let artistTag: String?
    let albumArtistTag: String?
    let commonArtist: String?
    let album: String?
    let genre: String?
    let preferredArtist: String?
    let preferredArtistSource: String?
}

private struct MetadataDescriptor {
    let identifier: String
    let commonKey: String
    let key: String
    let keySpace: String
}

private struct FilenameMetadataFallback {
    let title: String
    let artist: String?
    let didParseArtist: Bool
}

private struct DownloadedTrackMetadata {
    let title: String
    let artist: String
    let album: String?
    let duration: TimeInterval
}
