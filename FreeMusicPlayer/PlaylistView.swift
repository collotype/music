//
//  PlaylistView.swift
//  FreeMusicPlayer
//
//  Playlist detail screen.
//

import SwiftUI

struct PlaylistView: View {
    let playlistId: String

    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var audioPlayer: AudioPlayer
    @State private var showingAddTracksSheet = false

    private var playlist: Playlist? {
        dataManager.playlist(withID: playlistId)
    }

    private var playlistTracks: [Track] {
        dataManager.tracks(for: playlistId)
    }

    private var availableLibraryTracks: [Track] {
        guard let playlist else { return [] }
        let existingTrackIDs = Set(playlist.trackIDs)
        return dataManager.tracks.filter { !existingTrackIDs.contains($0.id) }
    }

    private var addTracksEmptyTitle: String {
        if dataManager.tracks.isEmpty {
            return "Library is empty"
        }

        return "All tracks already added"
    }

    private var addTracksEmptySubtitle: String {
        if dataManager.tracks.isEmpty {
            return "Import tracks in Library first, then come back to this playlist."
        }

        return "Every track from your library is already in this playlist."
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let playlist {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                Text(playlist.displayName)
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.white)

                                Spacer()

                                Button {
                                    debugLog("Playlist favorite toggle pressed: \(playlist.displayName)")
                                    dataManager.togglePlaylistFavorite(playlist)
                                } label: {
                                    Image(systemName: playlist.isStarred ? "star.fill" : "star")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(playlist.isStarred ? .yellow : .white.opacity(0.6))
                                        .padding(10)
                                        .background(
                                            Circle()
                                                .fill(Color.white.opacity(0.08))
                                        )
                                }
                                .buttonStyle(.plain)
                            }

                            HStack(spacing: 8) {
                                Text("\(playlistTracks.count) tracks")
                                    .foregroundColor(.gray)

                                if playlist.isStarred {
                                    Text("Favorite")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.yellow)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule()
                                                .fill(Color.yellow.opacity(0.12))
                                        )
                                }
                            }

                            HStack(spacing: 12) {
                                if !playlistTracks.isEmpty {
                                    Button {
                                        debugLog("Playlist play button pressed: \(playlist.name)")
                                        if let firstTrack = playlistTracks.first {
                                            audioPlayer.playTrack(
                                                firstTrack,
                                                in: playlistTracks,
                                                contextName: "playlist:\(playlist.id)"
                                            )
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: "play.fill")
                                            Text("Play playlist")
                                        }
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 12)
                                        .background(
                                            Capsule()
                                                .fill(Color.white)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }

                                Button {
                                    debugLog("Playlist add tracks button pressed: \(playlist.name)")
                                    showingAddTracksSheet = true
                                } label: {
                                    HStack {
                                        Image(systemName: "plus")
                                        Text("Add tracks")
                                    }
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 12)
                                    .background(
                                        Capsule()
                                            .fill(Color(red: 0.12, green: 0.55, blue: 0.26))
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(dataManager.tracks.isEmpty || availableLibraryTracks.isEmpty)
                                .opacity(dataManager.tracks.isEmpty || availableLibraryTracks.isEmpty ? 0.45 : 1)
                            }

                            if !dataManager.tracks.isEmpty && availableLibraryTracks.isEmpty {
                                Text("All tracks from your library are already in this playlist.")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.45))
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(Color.clear)

                    if playlistTracks.isEmpty {
                        Section {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("This playlist is empty.")
                                    .foregroundColor(.gray)

                                Text("Open the add button here to pick tracks from your library.")
                                    .font(.system(size: 13))
                                    .foregroundColor(.gray.opacity(0.75))

                                Button {
                                    debugLog("Empty playlist add tracks button pressed: \(playlist.name)")
                                    showingAddTracksSheet = true
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Choose tracks from Library")
                                    }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        Capsule()
                                            .fill(Color.white.opacity(0.1))
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(dataManager.tracks.isEmpty || availableLibraryTracks.isEmpty)
                                .opacity(dataManager.tracks.isEmpty || availableLibraryTracks.isEmpty ? 0.45 : 1)
                            }
                            .padding(.vertical, 8)
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        Section("Tracks") {
                            ForEach(playlistTracks) { track in
                                PlaylistTrackRow(
                                    track: track,
                                    playlistName: playlist.name,
                                    playlistTracks: playlistTracks,
                                    playlistID: playlist.id
                                )
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets())
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.black)
                .navigationTitle(playlist.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showingAddTracksSheet) {
                    TrackSelectionSheet(
                        title: playlist.displayName,
                        subtitle: "Select tracks from your library to add to this playlist.",
                        tracks: availableLibraryTracks,
                        actionTitle: "Add to Playlist",
                        actionSystemImage: "plus.circle.fill",
                        actionTint: Color(red: 0.12, green: 0.55, blue: 0.26),
                        actionRole: nil,
                        emptyTitle: addTracksEmptyTitle,
                        emptySubtitle: addTracksEmptySubtitle
                    ) { selectedTracks in
                        debugLog("Playlist add tracks confirmed: \(selectedTracks.count) track(s) for \(playlist.name)")
                        dataManager.addTracks(selectedTracks, toPlaylistID: playlistId)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.2))
                    Text("Playlist not found")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .navigationTitle("Playlist")
            }
        }
    }
}

struct PlaylistTrackRow: View {
    let track: Track
    let playlistName: String
    let playlistTracks: [Track]
    let playlistID: String

    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var dataManager: DataManager
    @State private var showingTrackActions = false

    var body: some View {
        HStack(spacing: 12) {
            TrackArtworkView(track: track, size: 50, cornerRadius: 8, showsSourceBadge: true)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)

                Text(track.displayArtist)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            Button {
                debugLog("Playlist favorite button pressed: \(track.displayTitle)")
                dataManager.toggleFavorite(track)
            } label: {
                Image(systemName: dataManager.favorites.contains(track.id) ? "heart.fill" : "heart")
                    .foregroundColor(dataManager.favorites.contains(track.id) ? .red : .white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            debugLog("Playlist track tapped: \(track.displayTitle) from \(playlistName)")
            audioPlayer.playTrack(
                track,
                in: playlistTracks,
                contextName: "playlist:\(playlistID)"
            )
        }
        .onLongPressGesture(minimumDuration: 0.6) {
            debugLog("Long press menu opened: \(track.displayTitle)")
            showingTrackActions = true
        }
        .trackActionPopup(
            isPresented: $showingTrackActions,
            track: track,
            contextTracks: playlistTracks,
            contextName: "playlist:\(playlistID)",
            playlistContext: TrackActionPlaylistContext(id: playlistID, name: playlistName)
        )
    }
}

struct TrackSelectionSheet: View {
    let title: String
    let subtitle: String
    let tracks: [Track]
    let actionTitle: String
    let actionSystemImage: String
    let actionTint: Color
    let actionRole: ButtonRole?
    let emptyTitle: String
    let emptySubtitle: String
    let onSubmit: ([Track]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var selectedTrackIDs: Set<String>

    init(
        title: String,
        subtitle: String,
        tracks: [Track],
        actionTitle: String,
        actionSystemImage: String,
        actionTint: Color,
        actionRole: ButtonRole?,
        emptyTitle: String,
        emptySubtitle: String,
        initiallySelectedTrackIDs: Set<String> = [],
        onSubmit: @escaping ([Track]) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.tracks = tracks
        self.actionTitle = actionTitle
        self.actionSystemImage = actionSystemImage
        self.actionTint = actionTint
        self.actionRole = actionRole
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.onSubmit = onSubmit
        _selectedTrackIDs = State(initialValue: initiallySelectedTrackIDs)
    }

    private var filteredTracks: [Track] {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSearch.isEmpty else { return tracks }

        return tracks.filter { track in
            track.displayTitle.localizedCaseInsensitiveContains(normalizedSearch) ||
            track.displayArtist.localizedCaseInsensitiveContains(normalizedSearch) ||
            (track.album?.localizedCaseInsensitiveContains(normalizedSearch) ?? false)
        }
    }

    private var selectedTracks: [Track] {
        tracks.filter { selectedTrackIDs.contains($0.id) }
    }

    private var visibleTrackIDs: Set<String> {
        Set(filteredTracks.map(\.id))
    }

    private var allVisibleTracksSelected: Bool {
        !visibleTrackIDs.isEmpty && visibleTrackIDs.isSubset(of: selectedTrackIDs)
    }

    private var selectionSummary: String {
        selectedTrackIDs.isEmpty ? subtitle : "\(selectedTrackIDs.count) track(s) selected"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if tracks.isEmpty {
                    TrackSelectionEmptyState(title: emptyTitle, subtitle: emptySubtitle)
                } else if filteredTracks.isEmpty {
                    TrackSelectionEmptyState(
                        title: "No matches",
                        subtitle: "Try a different title, artist, or album."
                    )
                } else {
                    List {
                        Section {
                            HStack {
                                Button(allVisibleTracksSelected ? "Clear visible" : "Select visible") {
                                    toggleVisibleSelection()
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .buttonStyle(.plain)

                                Spacer()

                                Text(selectionSummary)
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.clear)

                        Section {
                            ForEach(filteredTracks) { track in
                                SelectableTrackRow(track: track, isSelected: selectedTrackIDs.contains(track.id)) {
                                    toggleSelection(for: track)
                                }
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets())
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.black)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search library")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !tracks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(selectionSummary)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.65))

                        Button(role: actionRole) {
                            guard !selectedTracks.isEmpty else { return }
                            onSubmit(selectedTracks)
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Label("\(actionTitle) (\(selectedTrackIDs.count))", systemImage: actionSystemImage)
                                    .font(.system(size: 15, weight: .semibold))
                                Spacer()
                            }
                            .padding(.vertical, 14)
                            .foregroundColor(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(selectedTrackIDs.isEmpty ? Color.white.opacity(0.08) : actionTint)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedTrackIDs.isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                    .background(Color.black.opacity(0.96))
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 0.5)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func toggleSelection(for track: Track) {
        if selectedTrackIDs.contains(track.id) {
            selectedTrackIDs.remove(track.id)
        } else {
            selectedTrackIDs.insert(track.id)
        }
    }

    private func toggleVisibleSelection() {
        if allVisibleTracksSelected {
            selectedTrackIDs.subtract(visibleTrackIDs)
        } else {
            selectedTrackIDs.formUnion(visibleTrackIDs)
        }
    }
}

struct SelectableTrackRow: View {
    let track: Track
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                TrackArtworkView(track: track, size: 52, cornerRadius: 8, showsSourceBadge: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.displayTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(track.displayArtist)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer()

                Text(track.formattedDuration)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(isSelected ? .red : .white.opacity(0.35))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct TrackSelectionEmptyState: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 54))
                .foregroundColor(.white.opacity(0.18))

            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white.opacity(0.72))

            Text(subtitle)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        PlaylistView(playlistId: UUID().uuidString)
            .environmentObject(DataManager.shared)
            .environmentObject(AudioPlayer.shared)
    }
}
