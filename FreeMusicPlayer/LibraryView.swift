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
    @State private var sharePayload: TrackSharePayload?

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
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 1).onEnded { _ in
                debugLog("Library long press menu presented: \(track.displayTitle)")
            }
        )
        .contextMenu {
            Button {
                debugLog("Track context action selected: play next for \(track.displayTitle)")
                audioPlayer.queueTrackNext(track)
            } label: {
                Label("Play Next", systemImage: "forward.fill")
            }

            Button {
                debugLog("Track context action selected: add to queue for \(track.displayTitle)")
                audioPlayer.addTrackToQueue(track)
            } label: {
                Label("Add to Queue", systemImage: "list.bullet")
            }

            Button {
                debugLog("Track context action selected: favorite toggle for \(track.displayTitle)")
                dataManager.toggleFavorite(track)
            } label: {
                Label(
                    isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: isFavorite ? "heart.slash" : "heart"
                )
            }

            Menu {
                if dataManager.sortedPlaylists.isEmpty {
                    Button("No playlists yet") {}
                        .disabled(true)
                } else {
                    ForEach(dataManager.sortedPlaylists) { playlist in
                        Button {
                            debugLog("Track context action selected: add \(track.displayTitle) to playlist \(playlist.displayName)")
                            dataManager.addTrack(track, toPlaylistID: playlist.id)
                        } label: {
                            Label(
                                playlist.displayName,
                                systemImage: playlist.trackIDs.contains(track.id) ? "checkmark.circle.fill" : "music.note.list"
                            )
                        }
                    }
                }
            } label: {
                Label("Add to Playlist", systemImage: "text.badge.plus")
            }

            if let shareTarget = track.shareTargetURL {
                Button {
                    debugLog("Track context action selected: share \(track.displayTitle)")
                    sharePayload = TrackSharePayload(items: [shareTarget])
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        } preview: {
            TrackContextPreview(track: track)
        }
        .sheet(item: $sharePayload) { payload in
            ActivityView(activityItems: payload.items)
        }
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
                        Image(systemName: sourceBadgeSymbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(sourceBadgeColor)
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
        guard let coverArtURL = track.coverArtURL else { return nil }
        guard let parsedURL = URL(string: coverArtURL), parsedURL.scheme != nil else {
            return AppFileManager.shared.resolveStoredFileURL(for: coverArtURL)
        }

        return parsedURL.isFileURL ? parsedURL : nil
    }

    private var remoteArtworkURL: URL? {
        guard let coverArtURL = track.coverArtURL,
              let parsedURL = URL(string: coverArtURL),
              let scheme = parsedURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return parsedURL
    }

    private var sourceBadgeSymbol: String {
        switch track.source {
        case .appleMusicPreview:
            return "apple.logo"
        case .youtube:
            return "play.circle.fill"
        case .soundcloud:
            return "waveform"
        case .spotify:
            return "dot.radiowaves.left.and.right"
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
        case .soundcloud:
            return .orange
        case .spotify:
            return .green
        case .local:
            return .white.opacity(0.85)
        }
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
        .background(Color.black.opacity(0.96))
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
