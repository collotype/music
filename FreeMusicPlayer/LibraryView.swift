//
//  LibraryView.swift
//  FreeMusicPlayer
//
//  Library screen.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct LibraryView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var router: AppRouter
    @State private var showingFileImporter = false
    @State private var showingFolderImporter = false
    @State private var showingImportOptions = false
    @State private var showingLibraryUpdateAlert = false
    @State private var showingDeleteTrackPrompt = false
    @State private var showingBulkDeleteSheet = false
    @State private var showingCreatePlaylistPrompt = false
    @State private var isRefreshingImportFolders = false
    @State private var libraryUpdateMessage: String = ""
    @State private var newPlaylistName: String = ""
    @State private var pendingDeleteTrack: Track?
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
            isPresented: $showingFileImporter,
            allowedContentTypes: [.audio, .data],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .fileImporter(
            isPresented: $showingFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderImport(result)
        }
        .sheet(isPresented: $showingBulkDeleteSheet) {
            TrackSelectionSheet(
                title: "Delete Tracks",
                subtitle: "Choose tracks to remove from your library and playlists.",
                tracks: dataManager.tracks,
                actionTitle: "Delete Selected",
                actionSystemImage: "trash.fill",
                actionTint: .red,
                actionRole: .destructive,
                emptyTitle: "Library is empty",
                emptySubtitle: "Import tracks first, then you can manage or remove them here."
            ) { selectedTracks in
                deleteTracks(selectedTracks)
            }
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
        .confirmationDialog(
            "Remove track from library?",
            isPresented: $showingDeleteTrackPrompt,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deletePendingTrack()
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteTrack = nil
            }
        } message: {
            if let pendingDeleteTrack {
                Text("\"\(pendingDeleteTrack.displayTitle)\" will be removed from the library and from any playlists.")
            }
        }
        .confirmationDialog(
            "Library Actions",
            isPresented: $showingImportOptions,
            titleVisibility: .visible
        ) {
            Button("Import Files") {
                debugLog("Import files option pressed")
                showingFileImporter = true
            }
            Button("Link Music Folder") {
                debugLog("Link music folder option pressed")
                showingFolderImporter = true
            }
            if dataManager.hasImportFolders {
                Button("Refresh Linked Folder") {
                    debugLog("Refresh linked folders option pressed")
                    refreshLinkedFolders()
                }
            }
            if !dataManager.tracks.isEmpty {
                Button("Select Tracks to Delete", role: .destructive) {
                    debugLog("Bulk delete selector opened from library menu")
                    showingBulkDeleteSheet = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Import music, refresh linked folders, or manage tracks already saved in your library.")
        }
        .alert("Library Update", isPresented: $showingLibraryUpdateAlert) {
            Button("OK", role: .cancel) {
                libraryUpdateMessage = ""
            }
        } message: {
            Text(libraryUpdateMessage)
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
                        if dataManager.hasImportFolders {
                            debugLog("Library refresh folder button pressed")
                            refreshLinkedFolders()
                        } else {
                            debugLog("Library refresh button pressed without linked folders")
                            showingFolderImporter = true
                        }
                    } label: {
                        Image(systemName: dataManager.hasImportFolders ? "arrow.clockwise" : "folder.badge.plus")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshingImportFolders)
                    .padding(.trailing, 16)

                    Button {
                        debugLog("Library import menu button pressed")
                        showingImportOptions = true
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
                    if dataManager.hasImportFolders {
                        Text("\(dataManager.importFolders.count) linked folder(s)")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.45))
                    }
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
                    LibraryTrackRow(
                        track: track,
                        contextTracks: filteredTracks,
                        contextName: "library:\(selectedFilter.title):\(searchText)"
                    )
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                promptTrackDeletion(track)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
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
                showingImportOptions = true
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
            audioPlayer.playTrack(
                track,
                in: dataManager.tracks(for: playlist.id),
                contextName: "playlist:\(playlist.id)"
            )
            router.openPlaylist(playlist.id)
        default:
            guard let first = filteredTracks.first else { return }
            audioPlayer.playTrack(
                first,
                in: filteredTracks,
                contextName: "library:\(selectedFilter.title):\(searchText)"
            )
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            debugLog("Imported file count: \(urls.count)")
            let summary = dataManager.importFiles(from: urls)
            presentLibraryUpdate(summary, successTitle: "Imported tracks from selected files.")
        case .failure(let error):
            debugLog("File import failed: \(error.localizedDescription)")
            libraryUpdateMessage = "File import failed: \(error.localizedDescription)"
            showingLibraryUpdateAlert = true
        }
    }

    private func handleFolderImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let folderURL = urls.first else { return }
            let hasSecurityScope = folderURL.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    folderURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let linkedFolder = try dataManager.addImportFolder(folderURL)
                debugLog("Music folder linked from library: \(linkedFolder.displayName)")
                refreshLinkedFolders(successPrefix: "Linked folder \"\(linkedFolder.displayName)\".")
            } catch {
                debugLog("Link music folder failed: \(error.localizedDescription)")
                libraryUpdateMessage = "Music folder link failed: \(error.localizedDescription)"
                showingLibraryUpdateAlert = true
            }
        case .failure(let error):
            debugLog("Folder import failed: \(error.localizedDescription)")
            libraryUpdateMessage = "Folder selection failed: \(error.localizedDescription)"
            showingLibraryUpdateAlert = true
        }
    }

    private func refreshLinkedFolders(successPrefix: String? = nil) {
        isRefreshingImportFolders = true
        let summary = dataManager.refreshImportFolders()
        isRefreshingImportFolders = false
        presentLibraryUpdate(summary, successTitle: successPrefix ?? "Linked folders refreshed.")
    }

    private func presentLibraryUpdate(_ summary: LibraryImportSummary, successTitle: String) {
        var lines: [String] = []

        if !successTitle.isEmpty {
            lines.append(successTitle)
        }

        lines.append("Added \(summary.importedCount) track(s).")

        if summary.skippedCount > 0 {
            lines.append("Skipped \(summary.skippedCount) already imported track(s).")
        }

        if !summary.errors.isEmpty {
            lines.append(summary.errors.joined(separator: "\n"))
        }

        libraryUpdateMessage = lines.joined(separator: "\n")
        showingLibraryUpdateAlert = true
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

    private func promptTrackDeletion(_ track: Track) {
        debugLog("Track delete requested: \(track.displayTitle)")
        pendingDeleteTrack = track
        showingDeleteTrackPrompt = true
    }

    private func deletePendingTrack() {
        guard let pendingDeleteTrack else { return }

        debugLog("Track delete confirmed: \(pendingDeleteTrack.displayTitle)")
        if audioPlayer.currentTrack?.id == pendingDeleteTrack.id {
            audioPlayer.stop()
        }

        dataManager.removeTrack(pendingDeleteTrack)
        self.pendingDeleteTrack = nil
    }

    private func deleteTracks(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }

        let trackIDs = Set(tracks.map(\.id))
        debugLog("Bulk track delete confirmed: \(trackIDs.count) track(s)")

        if let currentTrack = audioPlayer.currentTrack,
           trackIDs.contains(currentTrack.id) {
            audioPlayer.stop()
        }

        dataManager.removeTracks(tracks)
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
    let contextTracks: [Track]
    let contextName: String
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var dataManager: DataManager
    @State private var showingTrackActions = false

    var isPlaying: Bool {
        audioPlayer.currentTrack?.id == track.id && audioPlayer.isPlaying
    }

    var isFavorite: Bool {
        dataManager.favorites.contains(track.id)
    }

    var body: some View {
        HStack(spacing: 12) {
            TrackArtworkView(track: track, size: 56, cornerRadius: 8, showsSourceBadge: true)

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
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundColor(isFavorite ? .red : .white.opacity(0.5))
            }
            .buttonStyle(.plain)

            AddToPlaylistMenu(track: track)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            debugLog("Library track row tapped: \(track.displayTitle)")
            audioPlayer.playTrack(track, in: contextTracks, contextName: contextName)
        }
        .onLongPressGesture(minimumDuration: 0.6) {
            debugLog("Long press menu opened: \(track.displayTitle)")
            showingTrackActions = true
        }
        .trackActionPopup(
            isPresented: $showingTrackActions,
            track: track,
            contextTracks: contextTracks,
            contextName: contextName,
            playlistContext: nil
        )
    }
}

struct TrackArtworkView: View {
    let track: Track
    let size: CGFloat
    let cornerRadius: CGFloat
    var showsSourceBadge: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.white.opacity(0.08))

            artworkContent

            if showsSourceBadge {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        sourceBadgeView
                            .padding(5)
                            .background(Circle().fill(Color.black.opacity(0.85)))
                    }
                }
                .padding(4)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    private var artworkContent: some View {
        if let image = localArtworkImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let remoteArtworkURL {
            AsyncImage(url: remoteArtworkURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    fallbackArtwork
                }
            }
        } else {
            fallbackArtwork
        }
    }

    private var fallbackArtwork: some View {
        ZStack {
            Image("PlayerAvatar")
                .resizable()
                .scaledToFill()

            LinearGradient(
                colors: [Color.black.opacity(0.04), Color.black.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var localArtworkImage: UIImage? {
        guard let localArtworkURL else { return nil }
        guard let data = try? Data(contentsOf: localArtworkURL),
              let image = UIImage(data: data) else {
            return nil
        }

        return image
    }

    private var localArtworkURL: URL? {
        track.localArtworkURL
    }

    private var remoteArtworkURL: URL? {
        track.resolvedRemoteArtworkURL
    }

    @ViewBuilder
    private var sourceBadgeView: some View {
        if let provider = track.source.onlineProvider {
            ProviderIconView(provider: provider, size: 13)
        } else {
            Image(systemName: sourceBadgeSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(sourceBadgeColor)
        }
    }

    private var sourceBadgeSymbol: String {
        switch track.source {
        case .appleMusicPreview:
            return "apple.logo"
        case .youtube:
            return "play.circle.fill"
        case .soundcloud, .spotify:
            return "music.note"
        case .local:
            return "music.note"
        }
    }

    private var sourceBadgeColor: Color {
        switch track.source {
        case .appleMusicPreview:
            return .white.opacity(0.9)
        case .youtube:
            return .red
        case .soundcloud, .spotify:
            return .white
        case .local:
            return .white.opacity(0.85)
        }
    }
}

struct TrackArtworkPalette: Equatable, Sendable {
    let primaryRed: Double
    let primaryGreen: Double
    let primaryBlue: Double
    let secondaryRed: Double
    let secondaryGreen: Double
    let secondaryBlue: Double

    static let playerFallback = TrackArtworkPalette(
        primaryRed: 0.40,
        primaryGreen: 0.12,
        primaryBlue: 0.12,
        secondaryRed: 0.12,
        secondaryGreen: 0.05,
        secondaryBlue: 0.05
    )

    static let cardFallback = TrackArtworkPalette(
        primaryRed: 0.16,
        primaryGreen: 0.16,
        primaryBlue: 0.18,
        secondaryRed: 0.08,
        secondaryGreen: 0.08,
        secondaryBlue: 0.10
    )

    var primaryColor: Color {
        Color(red: primaryRed, green: primaryGreen, blue: primaryBlue)
    }

    var secondaryColor: Color {
        Color(red: secondaryRed, green: secondaryGreen, blue: secondaryBlue)
    }

    var debugSummary: String {
        String(
            format: "primary=(%.2f, %.2f, %.2f) secondary=(%.2f, %.2f, %.2f)",
            primaryRed,
            primaryGreen,
            primaryBlue,
            secondaryRed,
            secondaryGreen,
            secondaryBlue
        )
    }
}

struct TrackArtworkBackdrop: View {
    let track: Track?
    let fallbackPalette: TrackArtworkPalette
    var cornerRadius: CGFloat = 0

    @State private var palette: TrackArtworkPalette

    init(
        track: Track?,
        fallbackPalette: TrackArtworkPalette = .cardFallback,
        cornerRadius: CGFloat = 0
    ) {
        self.track = track
        self.fallbackPalette = fallbackPalette
        self.cornerRadius = cornerRadius
        _palette = State(initialValue: fallbackPalette)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    palette.primaryColor.opacity(0.96),
                    palette.secondaryColor.opacity(0.88),
                    Color.black.opacity(0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(palette.primaryColor.opacity(0.34))
                .frame(width: 260, height: 260)
                .blur(radius: 78)
                .offset(x: -90, y: -80)

            Circle()
                .fill(palette.secondaryColor.opacity(0.30))
                .frame(width: 220, height: 220)
                .blur(radius: 70)
                .offset(x: 110, y: 100)

            LinearGradient(
                colors: [Color.white.opacity(0.04), Color.black.opacity(0.18), Color.black.opacity(0.42)],
                startPoint: .topLeading,
                endPoint: .bottom
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: backdropIdentity) {
            let resolvedPalette = await TrackArtworkPaletteStore.shared.palette(for: track) ?? fallbackPalette
            await MainActor.run {
                palette = resolvedPalette
            }
        }
    }

    private var backdropIdentity: String {
        track?.artworkCacheIdentity ?? track?.sourceID ?? track?.id ?? "no-artwork"
    }
}

private actor TrackArtworkPaletteStore {
    static let shared = TrackArtworkPaletteStore()

    private var palettesByKey: [String: TrackArtworkPalette] = [:]
    private var fallbackLoggedKeys: Set<String> = []

    func palette(for track: Track?) async -> TrackArtworkPalette? {
        guard let track else {
            logFallbackIfNeeded(for: "no-track", reason: "Artwork missing fallback for no active track")
            return nil
        }

        guard let key = paletteCacheKey(for: track),
              let artworkURL = resolvedArtworkURL(for: track) else {
            logFallbackIfNeeded(
                for: "missing:\(track.id)",
                reason: "Artwork missing fallback for \(track.displayTitle)"
            )
            return nil
        }

        if let cachedPalette = palettesByKey[key] {
            return cachedPalette
        }

        guard let data = await loadArtworkData(from: artworkURL),
              let image = UIImage(data: data),
              let palette = Self.extractPalette(from: image) else {
            logFallbackIfNeeded(
                for: "invalid:\(key)",
                reason: "Artwork missing fallback for \(track.displayTitle)"
            )
            return nil
        }

        palettesByKey[key] = palette
        debugLog("Dominant color extraction result for \(track.displayTitle): \(palette.debugSummary)")
        return palette
    }

    private func paletteCacheKey(for track: Track) -> String? {
        track.preferredArtworkReference ?? track.sourceID ?? track.id
    }

    private func resolvedArtworkURL(for track: Track) -> URL? {
        track.localArtworkURL ?? track.resolvedRemoteArtworkURL
    }

    private func loadArtworkData(from url: URL) async -> Data? {
        if url.isFileURL {
            return try? Data(contentsOf: url)
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private func logFallbackIfNeeded(for key: String, reason: String) {
        guard fallbackLoggedKeys.insert(key).inserted else { return }
        debugLog(reason)
    }

    private static func extractPalette(from image: UIImage) -> TrackArtworkPalette? {
        guard let cgImage = image.cgImage else { return nil }

        let width = 24
        let height = 24
        let bitsPerComponent = 8
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rawData = [UInt8](repeating: 0, count: Int(height * bytesPerRow))

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var redAccumulator: Double = 0
        var greenAccumulator: Double = 0
        var blueAccumulator: Double = 0
        var alphaAccumulator: Double = 0

        for index in stride(from: 0, to: rawData.count, by: bytesPerPixel) {
            let alpha = Double(rawData[index + 3]) / 255.0
            guard alpha > 0.08 else { continue }

            redAccumulator += Double(rawData[index]) * alpha
            greenAccumulator += Double(rawData[index + 1]) * alpha
            blueAccumulator += Double(rawData[index + 2]) * alpha
            alphaAccumulator += alpha
        }

        guard alphaAccumulator > 0 else { return nil }

        let baseColor = UIColor(
            red: CGFloat((redAccumulator / alphaAccumulator) / 255.0),
            green: CGFloat((greenAccumulator / alphaAccumulator) / 255.0),
            blue: CGFloat((blueAccumulator / alphaAccumulator) / 255.0),
            alpha: 1
        )

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        guard baseColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return nil
        }

        let primaryColor = UIColor(
            hue: hue,
            saturation: min(max(saturation * 0.72 + 0.10, 0.18), 0.70),
            brightness: min(max(brightness * 0.76 + 0.08, 0.28), 0.74),
            alpha: 1
        )

        let secondaryColor = UIColor(
            hue: hue,
            saturation: min(max(saturation * 0.48 + 0.08, 0.12), 0.58),
            brightness: min(max(brightness * 0.42 + 0.04, 0.16), 0.44),
            alpha: 1
        )

        return TrackArtworkPalette(
            primaryRed: primaryColor.rgb.red,
            primaryGreen: primaryColor.rgb.green,
            primaryBlue: primaryColor.rgb.blue,
            secondaryRed: secondaryColor.rgb.red,
            secondaryGreen: secondaryColor.rgb.green,
            secondaryBlue: secondaryColor.rgb.blue
        )
    }
}

private extension UIColor {
    var rgb: (red: Double, green: Double, blue: Double) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Double(red), Double(green), Double(blue))
    }
}

struct TrackContextPreview: View {
    let track: Track

    var body: some View {
        VStack(spacing: 14) {
            TrackArtworkView(track: track, size: 120, cornerRadius: 18, showsSourceBadge: false)

            VStack(spacing: 4) {
                Text(track.displayTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text(track.displayArtist)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            TrackArtworkBackdrop(track: track, fallbackPalette: .cardFallback)
                .ignoresSafeArea()
        )
    }
}

struct TrackSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct TrackActionPlaylistContext: Equatable {
    let id: String
    let name: String
}

extension View {
    @ViewBuilder
    func trackActionPopup(
        isPresented: Binding<Bool>,
        track: Track,
        contextTracks: [Track],
        contextName: String,
        playlistContext: TrackActionPlaylistContext?
    ) -> some View {
        Group {
            if #available(iOS 16.4, *) {
                self.popover(isPresented: isPresented, attachmentAnchor: .point(.bottomTrailing), arrowEdge: .trailing) {
                    TrackActionSheet(
                        track: track,
                        contextTracks: contextTracks,
                        contextName: contextName,
                        playlistContext: playlistContext
                    )
                    .presentationCompactAdaptation(.popover)
                }
            } else {
                self.sheet(isPresented: isPresented) {
                    TrackActionSheet(
                        track: track,
                        contextTracks: contextTracks,
                        contextName: contextName,
                        playlistContext: playlistContext
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
        .onChange(of: isPresented.wrappedValue) { presented in
            guard presented else { return }
            debugLog("Popup anchor position requested: bottomTrailing for \(track.displayTitle)")
            debugLog("Popup final placement request: trailing for \(track.displayTitle)")
        }
    }
}

struct TrackActionSheet: View {
    let track: Track
    let contextTracks: [Track]
    let contextName: String
    let playlistContext: TrackActionPlaylistContext?

    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    @State private var sharePayload: TrackSharePayload?

    private let popupWidth: CGFloat = 300
    private let popupMaxHeight: CGFloat = 448
    private let popupCornerRadius: CGFloat = 20

    private var effectiveFavoriteTrack: Track? {
        if dataManager.tracks.contains(where: { $0.id == track.id }) {
            return track
        }

        guard let sourceID = track.sourceID else { return nil }
        return dataManager.track(withSourceID: sourceID)
    }

    private var isFavorite: Bool {
        guard let effectiveFavoriteTrack else { return false }
        return dataManager.favorites.contains(effectiveFavoriteTrack.id)
    }

    private var trimmedAlbum: String? {
        let album = track.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return album.isEmpty ? nil : album
    }

    private var artistTracks: [Track] {
        let artistName = track.displayArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !artistName.isEmpty,
              artistName != "Unknown Artist" else {
            return [track]
        }

        let matches = dataManager.tracks.filter {
            $0.displayArtist.caseInsensitiveCompare(artistName) == .orderedSame
        }

        return matches.isEmpty ? [track] : matches
    }

    private var albumTracks: [Track] {
        guard let trimmedAlbum else { return [track] }

        let matches = dataManager.tracks.filter {
            ($0.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                .caseInsensitiveCompare(trimmedAlbum) == .orderedSame
        }

        return matches.isEmpty ? [track] : matches
    }

    private var canShowArtist: Bool {
        let artistName = track.displayArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        return !artistName.isEmpty && artistName != "Unknown Artist"
    }

    private var canShowAlbum: Bool {
        trimmedAlbum != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    CompactTrackActionHeader(track: track)

                    CompactTrackActionSection {
                        Button {
                            debugLog("Track context action selected: play next for \(track.displayTitle)")
                            audioPlayer.queueTrackNext(track)
                            dismiss()
                        } label: {
                            CompactTrackActionRow {
                                TrackActionRowLabel(title: "Play Next", systemImage: "text.insert")
                            }
                        }
                        .buttonStyle(.plain)

                        if let effectiveFavoriteTrack {
                            CompactTrackActionDivider()

                            Button {
                                debugLog("Track context action selected: favorite toggle for \(track.displayTitle)")
                                dataManager.toggleFavorite(effectiveFavoriteTrack)
                                dismiss()
                            } label: {
                                CompactTrackActionRow {
                                    TrackActionRowLabel(
                                        title: isFavorite ? "Unlike" : "Like",
                                        systemImage: isFavorite ? "heart.slash" : "heart"
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        CompactTrackActionDivider()

                        Button {
                            debugLog("Track context action selected: add to queue for \(track.displayTitle)")
                            audioPlayer.addTrackToQueue(track)
                            dismiss()
                        } label: {
                            CompactTrackActionRow {
                                TrackActionRowLabel(title: "Add to Queue", systemImage: "list.bullet")
                            }
                        }
                        .buttonStyle(.plain)

                        CompactTrackActionDivider()

                        NavigationLink {
                            TrackLyricsView(track: track)
                                .navigationTitle("Lyrics")
                                .navigationBarTitleDisplayMode(.inline)
                                .onAppear {
                                    debugLog("Track context action selected: show lyrics for \(track.displayTitle)")
                                }
                        } label: {
                            CompactTrackActionRow {
                                TrackActionRowLabel(title: "Show Lyrics", systemImage: "text.quote")
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    CompactTrackActionSection {
                        NavigationLink {
                            TrackPlaylistPickerView(track: track)
                                .onAppear {
                                    debugLog("Track context action selected: add to playlist for \(track.displayTitle)")
                                }
                        } label: {
                            CompactTrackActionRow {
                                TrackActionRowLabel(title: "Add to Playlist", systemImage: "text.badge.plus")
                            }
                        }
                        .buttonStyle(.plain)

                        if let playlistContext {
                            CompactTrackActionDivider()

                            Button(role: .destructive) {
                                debugLog("Track context action selected: remove from playlist \(playlistContext.name) for \(track.displayTitle)")
                                dataManager.removeTrack(track, fromPlaylistID: playlistContext.id)
                                dismiss()
                            } label: {
                                CompactTrackActionRow {
                                    TrackActionRowLabel(
                                        title: "Remove from Playlist",
                                        systemImage: "minus.circle",
                                        tint: .red
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if canShowArtist || canShowAlbum || track.shareTargetURL != nil {
                        CompactTrackActionSection {
                            if canShowArtist {
                                NavigationLink {
                                    TrackCollectionView(
                                        title: track.displayArtist,
                                        subtitle: "Artist",
                                        tracks: artistTracks,
                                        contextName: "artist:\(track.displayArtist)"
                                    )
                                    .onAppear {
                                        debugLog("Track context action selected: go to artist for \(track.displayTitle)")
                                    }
                                } label: {
                                    CompactTrackActionRow {
                                        TrackActionRowLabel(title: "Go to Artist", systemImage: "person.fill")
                                    }
                                }
                                .buttonStyle(.plain)
                            }

                            if canShowArtist && (canShowAlbum || track.shareTargetURL != nil) {
                                CompactTrackActionDivider()
                            }

                            if canShowAlbum, let trimmedAlbum {
                                NavigationLink {
                                    TrackCollectionView(
                                        title: trimmedAlbum,
                                        subtitle: track.displayArtist,
                                        tracks: albumTracks,
                                        contextName: "album:\(trimmedAlbum)"
                                    )
                                    .onAppear {
                                        debugLog("Track context action selected: go to album for \(track.displayTitle)")
                                    }
                                } label: {
                                    CompactTrackActionRow {
                                        TrackActionRowLabel(title: "Go to Album", systemImage: "square.stack.fill")
                                    }
                                }
                                .buttonStyle(.plain)

                                if track.shareTargetURL != nil {
                                    CompactTrackActionDivider()
                                }
                            }

                            if let shareTarget = track.shareTargetURL {
                                Button {
                                    debugLog("Track context action selected: share \(track.displayTitle)")
                                    sharePayload = TrackSharePayload(items: [shareTarget])
                                } label: {
                                    CompactTrackActionRow {
                                        TrackActionRowLabel(title: "Share", systemImage: "square.and.arrow.up")
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    CompactTrackActionSection {
                        NavigationLink {
                            TrackDetailsView(track: track)
                                .onAppear {
                                    debugLog("Track context action selected: about track for \(track.displayTitle)")
                                }
                        } label: {
                            CompactTrackActionRow {
                                TrackActionRowLabel(title: "About Track", systemImage: "info.circle")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background {
                    ZStack {
                        TrackArtworkBackdrop(
                            track: track,
                            fallbackPalette: .cardFallback,
                            cornerRadius: popupCornerRadius
                        )
                        .opacity(0.52)

                        RoundedRectangle(cornerRadius: popupCornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .opacity(0.88)

                        RoundedRectangle(cornerRadius: popupCornerRadius, style: .continuous)
                            .fill(Color.black.opacity(0.08))

                        RoundedRectangle(cornerRadius: popupCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }
                }
            }
            .background(Color.clear)
            .scrollIndicators(.hidden)
            .frame(width: popupWidth)
            .frame(maxHeight: popupMaxHeight)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            debugLog("Track action popup presented: \(track.displayTitle)")
            debugLog("Popup size: width=\(Int(popupWidth)) maxHeight=\(Int(popupMaxHeight))")
            debugLog("Popup final placement request: trailing from bottomTrailing anchor")
        }
        .sheet(item: $sharePayload) { payload in
            ActivityView(activityItems: payload.items)
        }
    }
}

struct CompactTrackActionSection<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

struct CompactTrackActionRow<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            content
            Spacer(minLength: 10)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

struct CompactTrackActionDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.white.opacity(0.05))
            .padding(.leading, 42)
    }
}

struct CompactTrackActionHeader: View {
    let track: Track

    var body: some View {
        HStack(spacing: 10) {
            TrackArtworkView(track: track, size: 52, cornerRadius: 12, showsSourceBadge: true)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text(track.displayArtist)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.68))
                    .lineLimit(1)

                if let album = track.album?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !album.isEmpty {
                    Text(album)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.40))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            TrackArtworkBackdrop(track: track, fallbackPalette: .cardFallback, cornerRadius: 18)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

struct TrackActionHeader: View {
    let track: Track

    var body: some View {
        HStack(spacing: 16) {
            TrackArtworkView(track: track, size: 86, cornerRadius: 18, showsSourceBadge: true)

            VStack(alignment: .leading, spacing: 6) {
                Text(track.displayTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text(track.displayArtist)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(1)

                if let album = track.album?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !album.isEmpty {
                    Text(album)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(
            TrackArtworkBackdrop(track: track, fallbackPalette: .cardFallback, cornerRadius: 24)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct TrackActionRowLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = .white

    var body: some View {
        Label {
            Text(title)
                .foregroundColor(tint)
        } icon: {
            Image(systemName: systemImage)
                .foregroundColor(tint.opacity(0.9))
                .frame(width: 22)
        }
    }
}

struct TrackPlaylistPickerView: View {
    let track: Track

    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    @State private var showingCreatePlaylistPrompt = false
    @State private var newPlaylistName = ""

    var body: some View {
        List {
            if dataManager.sortedPlaylists.isEmpty {
                Section {
                    Text("No playlists yet")
                        .foregroundColor(.secondary)
                }
            } else {
                Section("Playlists") {
                    ForEach(dataManager.sortedPlaylists) { playlist in
                        Button {
                            debugLog("Track context action selected: add \(track.displayTitle) to playlist \(playlist.displayName)")
                            dataManager.addTrack(track, toPlaylistID: playlist.id)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(playlist.displayName)
                                        .foregroundColor(.white)
                                    Text("\(playlist.trackCount) tracks")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.45))
                                }

                                Spacer()

                                if playlist.trackIDs.contains(track.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    newPlaylistName = track.displayTitle
                    showingCreatePlaylistPrompt = true
                } label: {
                    TrackActionRowLabel(title: "New Playlist", systemImage: "plus.circle")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle("Add to Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .alert("New Playlist", isPresented: $showingCreatePlaylistPrompt) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) {
                newPlaylistName = ""
            }
            Button("Create") {
                let playlist = dataManager.createPlaylist(name: newPlaylistName)
                dataManager.addTrack(track, toPlaylistID: playlist.id)
                newPlaylistName = ""
                dismiss()
            }
        } message: {
            Text("Create a playlist and add this track to it.")
        }
    }
}

struct TrackCollectionView: View {
    let title: String
    let subtitle: String
    let tracks: [Track]
    let contextName: String

    @EnvironmentObject var audioPlayer: AudioPlayer

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.55))
                    Text("\(tracks.count) track(s)")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.45))
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("Tracks") {
                ForEach(tracks) { track in
                    Button {
                        debugLog("Track collection row tapped: \(track.displayTitle)")
                        audioPlayer.playTrack(track, in: tracks, contextName: contextName)
                    } label: {
                        HStack(spacing: 12) {
                            TrackArtworkView(track: track, size: 50, cornerRadius: 10, showsSourceBadge: true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.displayTitle)
                                    .foregroundColor(.white)
                                Text(track.displayArtist)
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.5))
                            }

                            Spacer()

                            Text(track.formattedDuration)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.45))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TrackDetailsView: View {
    let track: Track

    var body: some View {
        List {
            Section {
                TrackActionHeader(track: track)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section("Details") {
                TrackMetadataRow(label: "Title", value: track.displayTitle)
                TrackMetadataRow(label: "Artist", value: track.displayArtist)
                if let album = track.album?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !album.isEmpty {
                    TrackMetadataRow(label: "Album", value: album)
                }
                TrackMetadataRow(label: "Duration", value: track.formattedDuration)
                TrackMetadataRow(label: "Source", value: track.source.rawValue)
                TrackMetadataRow(label: "Storage", value: track.storageLocation.rawValue)
                TrackMetadataRow(label: "Play Count", value: "\(track.playCount)")
                TrackMetadataRow(label: "Added", value: track.addedAt.formatted(date: .abbreviated, time: .omitted))
            }

            if let remotePageURL = track.remotePageURL,
               !remotePageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Source Link") {
                    Text(remotePageURL)
                        .foregroundColor(.white.opacity(0.85))
                        .textSelection(.enabled)
                }
            } else if let fileURL = track.fileURL,
                      !fileURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("File") {
                    Text(fileURL)
                        .foregroundColor(.white.opacity(0.85))
                        .textSelection(.enabled)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle("About Track")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TrackMetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .foregroundColor(.white.opacity(0.55))
            Spacer()
            Text(value)
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
        }
    }
}

private extension Track {
    var shareTargetURL: URL? {
        if let remotePageURL,
           let url = URL(string: remotePageURL) {
            return url
        }

        guard let fileURL else { return nil }

        if let parsedURL = URL(string: fileURL),
           parsedURL.scheme != nil {
            return parsedURL
        }

        return AppFileManager.shared.resolveStoredFileURL(for: fileURL)
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
