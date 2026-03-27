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
    @Published var favorites: Set<String> = []
    @Published var favoriteArtists: [FavoriteArtist] = []
    @Published var settings: AppSettings = AppSettings()

    private let legacyTracksKey = "fmp_tracks"
    private let legacyPlaylistsKey = "fmp_playlists"
    private let legacyFavoritesKey = "fmp_favorites"
    private let legacySettingsKey = "fmp_settings"

    private var tracksFileURL: URL { AppFileManager.shared.dataFileURL(named: "tracks.json") }
    private var playlistsFileURL: URL { AppFileManager.shared.dataFileURL(named: "playlists.json") }
    private var favoritesFileURL: URL { AppFileManager.shared.dataFileURL(named: "favorites.json") }
    private var favoriteArtistsFileURL: URL { AppFileManager.shared.dataFileURL(named: "favorite_artists.json") }
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
        AppFileManager.shared.prepareDirectories(resetTemporaryStorage: true)

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
        writeJSON(favoriteArtists, to: favoriteArtistsFileURL)
        writeJSON(settings, to: settingsFileURL)
    }

    @discardableResult
    func addTrack(_ track: Track) -> Track {
        debugLog("Add track: \(track.displayTitle)")

        if let existingIndex = existingTrackIndex(for: track) {
            var updatedTrack = track
            updatedTrack.id = tracks[existingIndex].id
            updatedTrack.coverArtURL = resolvedPreferredStoredImageReference(
                newValue: track.coverArtURL,
                existingValue: tracks[existingIndex].coverArtURL
            )
            updatedTrack.remoteCoverArtURL = resolvedPreferredRemoteImageReference(
                newValue: track.remoteCoverArtURL,
                existingValue: tracks[existingIndex].remoteCoverArtURL
            )
            updatedTrack.artistImageURL = resolvedPreferredStoredImageReference(
                newValue: track.artistImageURL,
                existingValue: tracks[existingIndex].artistImageURL
            )
            updatedTrack.remoteArtistImageURL = resolvedPreferredRemoteImageReference(
                newValue: track.remoteArtistImageURL,
                existingValue: tracks[existingIndex].remoteArtistImageURL
            )
            updatedTrack.providerArtistID = resolvedPreferredTextValue(
                newValue: track.providerArtistID,
                existingValue: tracks[existingIndex].providerArtistID
            )
            updatedTrack.artistWebpageURL = resolvedPreferredTextValue(
                newValue: track.artistWebpageURL,
                existingValue: tracks[existingIndex].artistWebpageURL
            )
            updatedTrack.lyricsText = resolvedPreferredTextValue(
                newValue: track.lyricsText,
                existingValue: tracks[existingIndex].lyricsText
            )
            updatedTrack.lyricsSource = resolvedPreferredTextValue(
                newValue: track.lyricsSource,
                existingValue: tracks[existingIndex].lyricsSource
            )
            updatedTrack.lyricsURL = resolvedPreferredTextValue(
                newValue: track.lyricsURL,
                existingValue: tracks[existingIndex].lyricsURL
            )
            updatedTrack.lyricsLastUpdated = track.lyricsLastUpdated ?? tracks[existingIndex].lyricsLastUpdated
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

        if favorites.contains(trackID) {
            let storedTrack = tracks[trackIndex]
            scheduleOfflineVisualPersistenceIfNeeded(
                forTrackID: storedTrack.id,
                preferredCoverReference: storedTrack.remoteCoverArtURL ?? storedTrack.coverArtURL,
                preferredArtistReference: storedTrack.remoteArtistImageURL ?? storedTrack.artistImageURL
            )
            scheduleLyricsPersistenceIfNeeded(for: storedTrack)
        }
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
        let metadata = resolvedDownloadedTrackMetadata(from: result, localFileURL: tempFileURL)
        debugLog("Create temporary track entry for \(result.title) at \(storedPath)")

        return Track(
            title: metadata.title,
            artist: metadata.artist,
            album: metadata.album,
            duration: metadata.duration,
            fileURL: storedPath,
            coverArtURL: result.coverArtURL,
            source: result.trackSource,
            isFavorite: false,
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
            duration: result.duration,
            fileURL: streamURL.absoluteString,
            coverArtURL: result.coverArtURL,
            source: result.trackSource,
            isFavorite: false,
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
    func saveDownloadedOnlineTrack(_ result: OnlineTrackResult, from tempFileURL: URL) async throws -> Track {
        if let existingTrack = track(withSourceID: result.id) {
            debugLog("Reuse existing saved online track: \(existingTrack.displayTitle)")
            let existingIndex = tracks.firstIndex(where: { $0.id == existingTrack.id })

            if let existingIndex {
                var updatedTrack = tracks[existingIndex]
                var didUpdateMetadata = false

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
            duration: metadata.duration,
            fileURL: storedPath,
            coverArtURL: resolvedArtworkPath ?? result.coverArtURL,
            source: result.trackSource,
            isFavorite: false,
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
        scheduleLyricsPersistenceIfNeeded(for: savedTrack)
        return savedTrack
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
        let fallbackPlayer = try? AVAudioPlayer(contentsOf: localFileURL)
        let assetDuration = max(CMTimeGetSeconds(asset.duration), 0)
        let fallbackDuration = max(fallbackPlayer?.duration ?? 0, 0)
        let resolvedDuration = [assetDuration, fallbackDuration, max(result.duration, 0)]
            .first(where: { $0 > 0 }) ?? 0

        let title = metadataValue(for: asset, identifier: .commonIdentifierTitle) ?? result.title
        let artist = metadataValue(for: asset, identifier: .commonIdentifierArtist) ?? result.artist
        let album = metadataValue(for: asset, identifier: .commonIdentifierAlbumName) ?? result.album

        debugLog("Downloaded metadata resolved for \(result.title): title=\(title), artist=\(artist), duration=\(resolvedDuration)")

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
        favoriteArtists.removeAll()
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
        let loadedFavoriteArtists: [FavoriteArtist]? = readJSON(from: favoriteArtistsFileURL)
        let loadedSettings: AppSettings? = readJSON(from: settingsFileURL)

        let didLoadAnything = loadedTracks != nil ||
            loadedPlaylists != nil ||
            loadedFavorites != nil ||
            loadedFavoriteArtists != nil ||
            loadedSettings != nil

        if let loadedTracks {
            tracks = loadedTracks
        }

        if let loadedPlaylists {
            playlists = loadedPlaylists
        }

        if let loadedFavorites {
            favorites = loadedFavorites
        }

        if let loadedFavoriteArtists {
            favoriteArtists = deduplicatedFavoriteArtists(loadedFavoriteArtists)
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

        if let artworkURL = track.localArtworkURL {
            try? FileManager.default.removeItem(at: artworkURL)
        }
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
        guard track.storageLocation == .library || favorites.contains(track.id) else { return }

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

private struct ImportedMetadataSummary {
    let title: String?
    let artistTag: String?
    let albumArtistTag: String?
    let commonArtist: String?
    let album: String?
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
