//
//  LibraryView.swift
//  FreeMusicPlayer
//
//  Library screen.
//

import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var router: AppRouter
    @State private var showingImporter = false
    @State private var showingCreatePlaylistPrompt = false
    @State private var newPlaylistName: String = ""
    @State private var selectedFilter: LibraryFilter = .all
    @State private var searchText: String = ""

    var filteredTracks: [Track] {
        var tracks = dataManager.tracks

        switch selectedFilter {
        case .all:
            break
        case .favorites:
            tracks = dataManager.favoriteTracks
        case .offline:
            tracks = tracks.filter { $0.fileURL != nil }
        case .playlists:
            return []
        }

        if !searchText.isEmpty {
            tracks = tracks.filter {
                $0.displayTitle.localizedCaseInsensitiveContains(searchText) ||
                $0.displayArtist.localizedCaseInsensitiveContains(searchText)
            }
        }

        return tracks
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection
                filterSection
                contentSection
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .alert("Create Playlist", isPresented: $showingCreatePlaylistPrompt) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) {
                newPlaylistName = ""
            }
            Button("Create") {
                createPlaylistAndOpen()
            }
        } message: {
            Text("Choose a name for the playlist.")
        }
    }

    var headerSection: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.8, green: 0.15, blue: 0.15),
                    Color(red: 0.4, green: 0.1, blue: 0.1),
                    Color.black
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Button {
                        debugLog("Library back button pressed")
                        router.navigate(to: .home)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        debugLog("Library cycle filter button pressed")
                        selectedFilter = selectedFilter.next
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)

                    Button {
                        debugLog("Library search button pressed")
                        router.navigate(to: .search)
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)

                    Button {
                        debugLog("Library import button pressed")
                        showingImporter = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedFilter.screenTitle)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                    Text(selectedFilter.subtitle(for: dataManager, filteredTracks: filteredTracks))
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

                HStack(spacing: 12) {
                    Button {
                        debugLog("Library play button pressed")
                        playPrimarySelection()
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Play")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(Color.white)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        debugLog("Library shuffle button pressed")
                        dataManager.shuffleTracks()
                    } label: {
                        HStack {
                            Image(systemName: "shuffle")
                            Text("Shuffle")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.15))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .frame(height: 280)
    }

    var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        title: filter.title,
                        isSelected: selectedFilter == filter,
                        count: filterCount(for: filter)
                    ) {
                        debugLog("Library filter pressed: \(filter.title)")
                        selectedFilter = filter
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    var contentSection: some View {
        if selectedFilter == .playlists {
            playlistSection
        } else if filteredTracks.isEmpty {
            emptyStateView
        } else {
            List {
                ForEach(filteredTracks) { track in
                    LibraryTrackRow(track: track)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black)
        }
    }

    var playlistSection: some View {
        Group {
            if dataManager.playlists.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.2))

                    Text("No playlists yet")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))

                    Button {
                        debugLog("Library create playlist button pressed")
                        presentCreatePlaylistPrompt()
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                            Text("Create playlist")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.15))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 100)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            debugLog("Library playlist create prompt button pressed")
                            presentCreatePlaylistPrompt()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                Text("Create playlist")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if !dataManager.favoritePlaylists.isEmpty {
                            Text("\(dataManager.favoritePlaylists.count) favorites")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.45))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    List {
                        ForEach(dataManager.sortedPlaylists) { playlist in
                            HStack(spacing: 12) {
                                Button {
                                    debugLog("Library playlist row pressed: \(playlist.displayName)")
                                    router.openPlaylist(playlist.id)
                                } label: {
                                    HStack(spacing: 12) {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.white.opacity(0.08))
                                            .frame(width: 52, height: 52)
                                            .overlay(
                                                Image(systemName: playlist.isStarred ? "star.circle.fill" : "music.note.list")
                                                    .foregroundColor(playlist.isStarred ? .yellow : .white.opacity(0.5))
                                            )

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(playlist.displayName)
                                                .foregroundColor(.white)
                                            Text("\(playlist.trackCount) tracks")
                                                .font(.system(size: 13))
                                                .foregroundColor(.gray)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.gray)
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    debugLog("Library playlist favorite button pressed: \(playlist.displayName)")
                                    dataManager.togglePlaylistFavorite(playlist)
                                } label: {
                                    Image(systemName: playlist.isStarred ? "star.fill" : "star")
                                        .foregroundColor(playlist.isStarred ? .yellow : .white.opacity(0.5))
                                        .frame(width: 28, height: 28)
                                }
                                .buttonStyle(.plain)
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.black)
                }
            }
        }
    }

    var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.2))

            Text("Library is empty")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))

            Text("Import tracks to start listening.")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.3))

            Button {
                debugLog("Empty state import button pressed")
                showingImporter = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("Import tracks")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.15))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 100)
    }

    func filterCount(for filter: LibraryFilter) -> Int {
        switch filter {
        case .all:
            return dataManager.tracks.count
        case .favorites:
            return dataManager.favoriteTracks.count
        case .offline:
            return dataManager.tracks.filter { $0.fileURL != nil }.count
        case .playlists:
            return dataManager.playlists.count
        }
    }

    private func playPrimarySelection() {
        switch selectedFilter {
        case .playlists:
            guard let playlist = dataManager.sortedPlaylists.first,
                  let track = dataManager.tracks(for: playlist.id).first else {
                return
            }
            audioPlayer.playTrack(track)
            router.openPlaylist(playlist.id)
        default:
            guard let first = filteredTracks.first else { return }
            audioPlayer.playTrack(first)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            debugLog("Imported file count: \(urls.count)")
            let importedTracks = urls.compactMap(importTrack)
            guard !importedTracks.isEmpty else { return }
            dataManager.addTracks(importedTracks)
        case .failure(let error):
            debugLog("File import failed: \(error.localizedDescription)")
        }
    }

    private func importTrack(from url: URL) -> Track? {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let preferredBaseName = url.deletingPathExtension().lastPathComponent
        let destinationURL = AppFileManager.shared.uniqueLibraryURL(
            baseName: preferredBaseName,
            fileExtension: url.pathExtension
        )

        do {
            try FileManager.default.copyItem(at: url, to: destinationURL)
        } catch {
            debugLog("Copy imported file failed: \(error.localizedDescription)")
            return nil
        }

        let asset = AVURLAsset(url: destinationURL)
        let title = metadataValue(for: asset, identifier: .commonIdentifierTitle)
            ?? destinationURL.deletingPathExtension().lastPathComponent
        let artist = metadataValue(for: asset, identifier: .commonIdentifierArtist)
            ?? "Unknown Artist"
        let album = metadataValue(for: asset, identifier: .commonIdentifierAlbumName)
        let duration = max(CMTimeGetSeconds(asset.duration), 0)

        return Track(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            fileURL: AppFileManager.shared.relativePath(for: destinationURL),
            coverArtURL: nil,
            source: .local,
            storageLocation: .library
        )
    }

    private func metadataValue(for asset: AVURLAsset, identifier: AVMetadataIdentifier) -> String? {
        asset.commonMetadata
            .first(where: { $0.identifier == identifier })?
            .stringValue
    }

    private func presentCreatePlaylistPrompt(suggestedName: String? = nil) {
        newPlaylistName = suggestedName ?? "New Playlist"
        showingCreatePlaylistPrompt = true
    }

    private func createPlaylistAndOpen() {
        let playlist = dataManager.createPlaylist(name: newPlaylistName)
        newPlaylistName = ""
        router.openPlaylist(playlist.id)
    }
}

enum LibraryFilter: CaseIterable {
    case all
    case favorites
    case offline
    case playlists

    var title: String {
        switch self {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .offline: return "Offline"
        case .playlists: return "Playlists"
        }
    }

    var screenTitle: String {
        switch self {
        case .all: return "Library"
        case .favorites: return "Favorites"
        case .offline: return "Offline"
        case .playlists: return "Playlists"
        }
    }

    var next: LibraryFilter {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return .all }
        return all[(index + 1) % all.count]
    }

    func subtitle(for dataManager: DataManager, filteredTracks: [Track]) -> String {
        switch self {
        case .playlists:
            return "\(dataManager.playlists.count) playlists"
        default:
            return "\(filteredTracks.count) tracks"
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("(\(count))")
                        .font(.system(size: 13))
                }
            }
            .foregroundColor(isSelected ? .black : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white : Color.white.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}

struct LibraryTrackRow: View {
    let track: Track
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var dataManager: DataManager

    var isPlaying: Bool {
        audioPlayer.currentTrack?.id == track.id && audioPlayer.isPlaying
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 56, height: 56)

                Image(systemName: "music.note")
                    .foregroundColor(.white.opacity(0.3))

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: track.source == .youtube ? "play.circle.fill" : "cloud.fill")
                            .font(.system(size: 14))
                            .foregroundColor(track.source == .youtube ? .red : .orange)
                            .background(Circle().fill(Color.black))
                    }
                    .padding(4)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isPlaying ? .red : .white)

                Text(track.displayArtist)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            Text(track.formattedDuration)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                )

            Button {
                debugLog("Library favorite button pressed: \(track.displayTitle)")
                dataManager.toggleFavorite(track)
            } label: {
                Image(systemName: dataManager.favorites.contains(track.id) ? "heart.fill" : "heart")
                    .foregroundColor(dataManager.favorites.contains(track.id) ? .red : .white.opacity(0.5))
            }
            .buttonStyle(.plain)

            AddToPlaylistMenu(track: track)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            debugLog("Library track row tapped: \(track.displayTitle)")
            audioPlayer.playTrack(track)
        }
    }
}

struct AddToPlaylistMenu: View {
    let track: Track

    @EnvironmentObject var dataManager: DataManager
    @State private var showingCreatePlaylistPrompt = false
    @State private var newPlaylistName: String = ""

    var body: some View {
        Menu {
            if dataManager.sortedPlaylists.isEmpty {
                Button {
                    debugLog("Add to playlist requested without existing playlists: \(track.displayTitle)")
                    newPlaylistName = track.displayTitle
                    showingCreatePlaylistPrompt = true
                } label: {
                    Label("Create playlist", systemImage: "plus.circle")
                }
            } else {
                ForEach(dataManager.sortedPlaylists) { playlist in
                    Button {
                        debugLog("Add \(track.displayTitle) to playlist \(playlist.displayName)")
                        dataManager.addTrack(track, toPlaylistID: playlist.id)
                    } label: {
                        Label(
                            playlist.displayName,
                            systemImage: playlist.trackIDs.contains(track.id) ? "checkmark.circle.fill" : "music.note.list"
                        )
                    }
                }

                Button {
                    debugLog("Create playlist from add menu for track: \(track.displayTitle)")
                    newPlaylistName = track.displayTitle
                    showingCreatePlaylistPrompt = true
                } label: {
                    Label("New playlist", systemImage: "plus.circle")
                }
            }
        } label: {
            Image(systemName: "text.badge.plus")
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .alert("New Playlist", isPresented: $showingCreatePlaylistPrompt) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) {
                newPlaylistName = ""
            }
            Button("Create") {
                let playlist = dataManager.createPlaylist(name: newPlaylistName)
                dataManager.addTrack(track, toPlaylistID: playlist.id)
                newPlaylistName = ""
            }
        } message: {
            Text("Create a playlist and add this track to it.")
        }
    }
}

#Preview {
    LibraryView()
        .environmentObject(AudioPlayer.shared)
        .environmentObject(DataManager.shared)
        .environmentObject(AppRouter())
}
