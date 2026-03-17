//
//  SearchView.swift
//  FreeMusicPlayer
//
//  Combined local and online music search.
//

import SwiftUI

struct SearchView: View {
    private let onlineSearchTimeoutNanoseconds: UInt64 = 15_000_000_000

    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var router: AppRouter

    @State private var searchText: String = ""
    @State private var localResults: [Track] = []
    @State private var onlineResults: [OnlineTrackResult] = []
    @State private var isSearchingOnline: Bool = false
    @State private var onlineStatusMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var downloadingIDs: Set<String> = []
    @State private var savingIDs: Set<String> = []
    @State private var selectedCategory: SearchCategory = .tracks

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var artistResults: [LocalArtistSearchResult] {
        artistMatches(for: searchText)
    }

    private var albumResults: [LocalAlbumSearchResult] {
        albumMatches(for: searchText)
    }

    private var playlistResults: [LocalPlaylistSearchResult] {
        playlistMatches(for: searchText)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                searchHeader

                if searchText.isEmpty {
                    emptyState
                } else {
                    searchResultsContent
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: dataManager.tracks) { _ in
            guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            localResults = localMatches(for: searchText)
            debugLog("Local result count updated: \(localResults.count)")
            logResultCounts(for: searchText)
        }
        .onChange(of: selectedCategory) { newValue in
            debugLog("Search selected tab: \(newValue.title)")
            debugLog("Search query text: \(trimmedSearchText)")
            debugLog("\(newValue.title) result count: \(resultCount(for: newValue, query: searchText))")

            guard !trimmedSearchText.isEmpty else { return }

            if newValue == .tracks {
                performSearch(searchText, shouldSearchOnline: true)
            } else {
                searchTask?.cancel()
                isSearchingOnline = false
            }
        }
        .onChange(of: audioPlayer.playbackErrorMessage) { newValue in
            guard let newValue,
                  audioPlayer.currentTrack?.source != .local else { return }
            onlineStatusMessage = newValue
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    var searchHeader: some View {
        VStack(spacing: 10) {
            Spacer()
                .frame(height: 16)

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.5))

                TextField("Search music", text: $searchText)
                    .font(.system(size: 17))
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: searchText) { newValue in
                        performSearch(newValue, shouldSearchOnline: selectedCategory == .tracks)
                    }

                if !searchText.isEmpty {
                    Button {
                        debugLog("Search clear button pressed")
                        searchTask?.cancel()
                        searchText = ""
                        localResults = []
                        onlineResults = []
                        onlineStatusMessage = nil
                        isSearchingOnline = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )

            searchCategoryTabs
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    var searchCategoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(SearchCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Text(category.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(selectedCategory == category ? .black : .white.opacity(0.88))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(
                                Capsule()
                                    .fill(selectedCategory == category ? Color.white : Color.white.opacity(0.08))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        selectedCategory == category ? Color.white.opacity(0.0) : Color.white.opacity(0.08),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(
                                color: selectedCategory == category ? Color.black.opacity(0.18) : .clear,
                                radius: 10,
                                x: 0,
                                y: 4
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: selectedCategory)
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 80))
                .foregroundColor(.white.opacity(0.1))

            Text("Search")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white.opacity(0.3))

            Text("Find tracks, artists, albums, or playlists.")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.2))

            VStack(alignment: .leading, spacing: 12) {
                Text("Popular")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))

                FlowLayout {
                    ForEach(["Rock", "Pop", "Hip-Hop", "Electronic", "Jazz"], id: \.self) { query in
                        Button {
                            debugLog("Popular search pressed: \(query)")
                            searchText = query
                        } label: {
                            Text(query)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 20)

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    var searchResultsContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                switch selectedCategory {
                case .tracks:
                    trackSearchResults
                case .artists:
                    artistSearchResults
                case .albums:
                    albumSearchResults
                case .playlists:
                    playlistSearchResults
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 120)
        }
    }

    @ViewBuilder
    var trackSearchResults: some View {
        if !localResults.isEmpty {
            SearchSectionCard(title: "Library") {
                ForEach(localResults) { track in
                    SearchTrackRow(
                        track: track,
                        contextTracks: localResults,
                        contextName: "search:local:\(searchText)"
                    )
                    if track.id != localResults.last?.id {
                        Divider()
                            .background(Color.white.opacity(0.06))
                    }
                }
            }
        }

        SearchSectionCard(title: "Online") {
            if isSearchingOnline && onlineResults.isEmpty {
                SearchStatusRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Searching online...",
                    subtitle: "Looking up matching tracks on SoundCloud."
                )
            } else if !onlineResults.isEmpty {
                ForEach(onlineResults) { result in
                    OnlineSearchTrackRow(
                        result: result,
                        isDownloading: downloadingIDs.contains(result.id),
                        isSaving: savingIDs.contains(result.id),
                        isSaved: dataManager.track(withSourceID: result.id) != nil,
                        playAction: { playOnlineResult(result) },
                        saveAction: { saveOnlineResult(result) }
                    )
                    if result.id != onlineResults.last?.id {
                        Divider()
                            .background(Color.white.opacity(0.06))
                    }
                }
            } else if let onlineStatusMessage {
                SearchStatusRow(
                    icon: "wifi.exclamationmark",
                    title: "Online search unavailable",
                    subtitle: onlineStatusMessage
                )
            } else {
                SearchStatusRow(
                    icon: "note.slash",
                    title: "No online matches",
                    subtitle: "Try another query or save a track to your library."
                )
            }
        }
    }

    var artistSearchResults: some View {
        SearchSectionCard(title: "Artists") {
            if artistResults.isEmpty {
                SearchStatusRow(
                    icon: "person.crop.circle.badge.questionmark",
                    title: "No artists found",
                    subtitle: "Try a different artist name from your library."
                )
            } else {
                ForEach(artistResults) { result in
                    NavigationLink {
                        TrackCollectionView(
                            title: result.name,
                            subtitle: "Artist",
                            tracks: result.tracks,
                            contextName: "search:artist:\(result.name)"
                        )
                    } label: {
                        SearchArtistRow(result: result)
                    }
                    .buttonStyle(.plain)

                    if result.id != artistResults.last?.id {
                        Divider()
                            .background(Color.white.opacity(0.06))
                    }
                }
            }
        }
    }

    var albumSearchResults: some View {
        SearchSectionCard(title: "Albums") {
            if albumResults.isEmpty {
                SearchStatusRow(
                    icon: "square.stack.badge.minus",
                    title: "No albums found",
                    subtitle: "Try a different album title from your library."
                )
            } else {
                ForEach(albumResults) { result in
                    NavigationLink {
                        TrackCollectionView(
                            title: result.title,
                            subtitle: result.artist,
                            tracks: result.tracks,
                            contextName: "search:album:\(result.id)"
                        )
                    } label: {
                        SearchAlbumRow(result: result)
                    }
                    .buttonStyle(.plain)

                    if result.id != albumResults.last?.id {
                        Divider()
                            .background(Color.white.opacity(0.06))
                    }
                }
            }
        }
    }

    var playlistSearchResults: some View {
        SearchSectionCard(title: "Playlists") {
            if playlistResults.isEmpty {
                SearchStatusRow(
                    icon: "music.note.list",
                    title: "No playlists found",
                    subtitle: "Try a different playlist name from your library."
                )
            } else {
                ForEach(playlistResults) { result in
                    Button {
                        debugLog("Search playlist row tapped: \(result.playlist.displayName)")
                        router.openPlaylist(result.playlist.id)
                    } label: {
                        SearchPlaylistRow(result: result)
                    }
                    .buttonStyle(.plain)

                    if result.id != playlistResults.last?.id {
                        Divider()
                            .background(Color.white.opacity(0.06))
                    }
                }
            }
        }
    }

    private func performSearch(_ query: String, shouldSearchOnline: Bool) {
        searchTask?.cancel()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            localResults = []
            onlineResults = []
            onlineStatusMessage = nil
            isSearchingOnline = false
            return
        }

        debugLog("Query entered: \(trimmedQuery)")
        localResults = localMatches(for: trimmedQuery)
        debugLog("Local result count: \(localResults.count)")
        logResultCounts(for: trimmedQuery)
        onlineResults = []
        onlineStatusMessage = nil

        guard shouldSearchOnline else {
            isSearchingOnline = false
            return
        }

        isSearchingOnline = true
        debugLog("Online search start: \(trimmedQuery)")

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }

            do {
                let fetchedResults = try await searchOnlineResultsWithTimeout(for: trimmedQuery)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard searchText.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedQuery else { return }
                    onlineResults = fetchedResults
                    isSearchingOnline = false
                    onlineStatusMessage = nil
                    debugLog("Online result count: \(fetchedResults.count)")
                }
            } catch let onlineError as OnlineMusicServiceError {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard searchText.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedQuery else { return }
                    onlineResults = []
                    isSearchingOnline = false

                    switch onlineError {
                    case .noResults(_):
                        onlineStatusMessage = nil
                        debugLog("Online result count: 0")
                    case .timedOut(let message):
                        onlineStatusMessage = message
                    default:
                        onlineStatusMessage = onlineError.localizedDescription
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard searchText.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedQuery else { return }
                    onlineResults = []
                    isSearchingOnline = false
                    onlineStatusMessage = error.localizedDescription
                }
            }
        }
    }

    private func searchOnlineResultsWithTimeout(for query: String) async throws -> [OnlineTrackResult] {
        let timeoutNanoseconds = onlineSearchTimeoutNanoseconds

        return try await withThrowingTaskGroup(of: [OnlineTrackResult].self) { group in
            group.addTask {
                try await OnlineMusicService.shared.search(query)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                debugLog("Online search timeout: \(query)")
                throw OnlineMusicServiceError.timedOut(
                    "Online search timed out. Try another query or try again."
                )
            }

            do {
                guard let result = try await group.next() else {
                    throw OnlineMusicServiceError.networkFailure("Online search ended unexpectedly.")
                }
                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private func playOnlineResult(_ result: OnlineTrackResult) {
        guard !downloadingIDs.contains(result.id) else { return }

        debugLog("Online result play pressed: \(result.title) [\(result.providerTrackID)]")
        downloadingIDs.insert(result.id)
        onlineStatusMessage = nil
        audioPlayer.clearPlaybackError()

        Task {
            defer {
                Task { @MainActor in
                    downloadingIDs.remove(result.id)
                }
            }

            do {
                let resolvedStream = try await OnlineMusicService.shared.resolvePlaybackStream(for: result)
                let streamingTrack = await MainActor.run {
                    dataManager.makeStreamingTrack(from: result, streamURL: resolvedStream.url)
                }

                await MainActor.run {
                    let didStartPlayback = audioPlayer.playTrack(streamingTrack)
                    if didStartPlayback {
                        debugLog(
                            "Playback success for \(result.providerTrackID) via \(resolvedStream.streamType)"
                        )
                    } else {
                        onlineStatusMessage = audioPlayer.playbackErrorMessage ?? "Playback failed for the selected SoundCloud track."
                    }
                }
            } catch {
                debugLog("Playback error for \(result.providerTrackID): \(error.localizedDescription)")
                await MainActor.run {
                    onlineStatusMessage = error.localizedDescription
                }
            }
        }
    }

    private func saveOnlineResult(_ result: OnlineTrackResult) {
        guard !savingIDs.contains(result.id) else { return }

        if let savedTrack = dataManager.track(withSourceID: result.id) {
            debugLog("Saved online result tapped again: \(result.title) [\(result.providerTrackID)]")
            let didStartPlayback = audioPlayer.playTrack(savedTrack)
            if !didStartPlayback {
                onlineStatusMessage = audioPlayer.playbackErrorMessage ?? "Playback failed for the saved track."
            }
            return
        }

        debugLog("Online result save pressed: \(result.title) [\(result.providerTrackID)]")
        savingIDs.insert(result.id)
        onlineStatusMessage = nil

        Task {
            defer {
                Task { @MainActor in
                    savingIDs.remove(result.id)
                }
            }

            do {
                let tempURL = try await OnlineMusicService.shared.downloadAudio(for: result)
                let savedTrack = try await MainActor.run {
                    try dataManager.saveDownloadedOnlineTrack(result, from: tempURL)
                }

                await MainActor.run {
                    audioPlayer.syncCurrentTrackReference(with: savedTrack)
                    localResults = localMatches(for: searchText)
                    debugLog("Local result count after save: \(localResults.count)")
                }
            } catch {
                debugLog("Save error for \(result.providerTrackID): \(error.localizedDescription)")
                await MainActor.run {
                    onlineStatusMessage = error.localizedDescription
                }
            }
        }
    }

    private func localMatches(for query: String) -> [Track] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        return dataManager.tracks.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(normalized) ||
            $0.displayArtist.localizedCaseInsensitiveContains(normalized) ||
            ($0.album?.localizedCaseInsensitiveContains(normalized) ?? false)
        }
    }

    private func artistMatches(for query: String) -> [LocalArtistSearchResult] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        return allArtistResults().filter { result in
            matchesSearchQuery(
                normalized,
                fields: [result.name] + result.tracks.flatMap { track in
                    [
                        track.displayTitle,
                        track.displayArtist,
                        track.album ?? ""
                    ]
                }
            )
        }
    }

    private func albumMatches(for query: String) -> [LocalAlbumSearchResult] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        return allAlbumResults().filter { result in
            matchesSearchQuery(
                normalized,
                fields: [result.title, result.artist] + result.tracks.flatMap { track in
                    [
                        track.displayTitle,
                        track.displayArtist,
                        track.album ?? ""
                    ]
                }
            )
        }
    }

    private func playlistMatches(for query: String) -> [LocalPlaylistSearchResult] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        return dataManager.sortedPlaylists.compactMap { playlist in
            let tracks = dataManager.tracks(for: playlist.id)
            let result = LocalPlaylistSearchResult(
                playlist: playlist,
                representativeTrack: representativeTrackOrNil(from: tracks),
                trackCount: tracks.count,
                coverArtURL: playlist.coverArtURL,
                tracks: tracks
            )

            let searchableFields = [playlist.displayName] + tracks.flatMap { track in
                [
                    track.displayTitle,
                    track.displayArtist,
                    track.album ?? ""
                ]
            }

            guard matchesSearchQuery(normalized, fields: searchableFields) else { return nil }
            return result
        }
    }

    private func resultCount(for category: SearchCategory, query: String) -> Int {
        switch category {
        case .tracks:
            return localMatches(for: query).count
        case .artists:
            return artistMatches(for: query).count
        case .albums:
            return albumMatches(for: query).count
        case .playlists:
            return playlistMatches(for: query).count
        }
    }

    private func logResultCounts(for query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        let artistCatalogCount = allArtistResults().count
        let albumCatalogCount = allAlbumResults().count
        let playlistResultCount = playlistMatches(for: trimmedQuery).count
        debugLog("Artist aggregation count: \(artistCatalogCount)")
        debugLog("Album aggregation count: \(albumCatalogCount)")
        debugLog("Playlist search result count: \(playlistResultCount)")
        debugLog(
            "Search result counts for \(trimmedQuery): tracks=\(localMatches(for: trimmedQuery).count), artists=\(artistMatches(for: trimmedQuery).count), albums=\(albumMatches(for: trimmedQuery).count), playlists=\(playlistMatches(for: trimmedQuery).count)"
        )
    }

    private func allArtistResults() -> [LocalArtistSearchResult] {
        let groupedTracks = Dictionary(grouping: dataManager.tracks) { track in
            normalizedArtistName(for: track)
        }

        return groupedTracks.compactMap { _, tracks in
            let sortedTracks = tracks.sorted(by: trackSortOrder)
            guard let firstTrack = sortedTracks.first else { return nil }

            return LocalArtistSearchResult(
                name: displayArtistName(for: firstTrack),
                representativeTrack: representativeTrack(from: sortedTracks),
                tracks: sortedTracks
            )
        }
        .sorted { left, right in
            if left.name == "Unknown Artist" {
                return false
            }
            if right.name == "Unknown Artist" {
                return true
            }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    private func allAlbumResults() -> [LocalAlbumSearchResult] {
        let albumTracks = dataManager.tracks.filter { track in
            let albumTitle = track.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !albumTitle.isEmpty
        }

        let groupedTracks = Dictionary(grouping: albumTracks) { track in
            let albumTitle = track.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return "\(albumTitle.lowercased())::\(normalizedArtistName(for: track))"
        }

        return groupedTracks.compactMap { _, tracks in
            let sortedTracks = tracks.sorted(by: trackSortOrder)
            guard let firstTrack = sortedTracks.first,
                  let albumTitle = firstTrack.album?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !albumTitle.isEmpty else {
                return nil
            }

            return LocalAlbumSearchResult(
                title: albumTitle,
                artist: displayArtistName(for: firstTrack),
                representativeTrack: representativeTrack(from: sortedTracks),
                tracks: sortedTracks
            )
        }
        .sorted { left, right in
            if left.title.caseInsensitiveCompare(right.title) == .orderedSame {
                return left.artist.localizedCaseInsensitiveCompare(right.artist) == .orderedAscending
            }
            return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        }
    }

    private func normalizedArtistName(for track: Track) -> String {
        let artistName = track.displayArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        return artistName.isEmpty ? "unknown artist" : artistName.lowercased()
    }

    private func displayArtistName(for track: Track) -> String {
        let artistName = track.displayArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        return artistName.isEmpty ? "Unknown Artist" : artistName
    }

    private func representativeTrack(from tracks: [Track]) -> Track {
        tracks.first(where: hasArtwork) ?? tracks.first!
    }

    private func representativeTrackOrNil(from tracks: [Track]) -> Track? {
        tracks.first(where: hasArtwork) ?? tracks.first
    }

    private func hasArtwork(for track: Track) -> Bool {
        !(track.coverArtURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private func trackSortOrder(_ left: Track, _ right: Track) -> Bool {
        if left.displayTitle.caseInsensitiveCompare(right.displayTitle) == .orderedSame {
            return left.addedAt > right.addedAt
        }
        return left.displayTitle.localizedCaseInsensitiveCompare(right.displayTitle) == .orderedAscending
    }

    private func matchesSearchQuery(_ query: String, fields: [String]) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return false }

        let searchableFields = fields
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !searchableFields.isEmpty else { return false }

        let loweredQuery = normalizedQuery.lowercased()
        let combinedFields = searchableFields.joined(separator: " ").lowercased()
        if combinedFields.contains(loweredQuery) {
            return true
        }

        let queryTokens = loweredQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !queryTokens.isEmpty else { return false }

        return queryTokens.allSatisfy { token in
            searchableFields.contains(where: { $0.lowercased().contains(token) })
        }
    }
}

enum SearchCategory: String, CaseIterable, Identifiable {
    case tracks
    case artists
    case albums
    case playlists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tracks:
            return "Tracks"
        case .artists:
            return "Artists"
        case .albums:
            return "Albums"
        case .playlists:
            return "Playlists"
        }
    }
}

struct LocalArtistSearchResult: Identifiable {
    let name: String
    let representativeTrack: Track
    let tracks: [Track]

    var id: String {
        name.lowercased()
    }
}

struct LocalAlbumSearchResult: Identifiable {
    let title: String
    let artist: String
    let representativeTrack: Track
    let tracks: [Track]

    var id: String {
        "\(title.lowercased())::\(artist.lowercased())"
    }
}

struct LocalPlaylistSearchResult: Identifiable {
    let playlist: Playlist
    let representativeTrack: Track?
    let trackCount: Int
    let coverArtURL: String?
    let tracks: [Track]

    var id: String {
        playlist.id
    }
}

struct SearchSectionCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }
}

struct SearchStatusRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 12)
    }
}

struct SearchArtistRow: View {
    let result: LocalArtistSearchResult

    var body: some View {
        HStack(spacing: 12) {
            TrackArtworkView(
                track: result.representativeTrack,
                size: 54,
                cornerRadius: 27,
                showsSourceBadge: false
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(result.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("\(result.tracks.count) track\(result.tracks.count == 1 ? "" : "s")")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.52))
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.28))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct SearchAlbumRow: View {
    let result: LocalAlbumSearchResult

    var body: some View {
        HStack(spacing: 12) {
            TrackArtworkView(
                track: result.representativeTrack,
                size: 54,
                cornerRadius: 12,
                showsSourceBadge: false
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(result.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(result.artist)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.58))
                    .lineLimit(1)

                Text("\(result.tracks.count) track\(result.tracks.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.42))
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.28))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct SearchPlaylistRow: View {
    let result: LocalPlaylistSearchResult

    var body: some View {
        HStack(spacing: 12) {
            SearchPlaylistArtworkView(
                coverArtURL: result.coverArtURL,
                representativeTrack: result.representativeTrack,
                fallbackTitle: result.playlist.displayName,
                size: 54
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(result.playlist.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("\(result.trackCount) track\(result.trackCount == 1 ? "" : "s")")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.52))
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.28))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct SearchTrackRow: View {
    let track: Track
    let contextTracks: [Track]
    let contextName: String
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
                    .lineLimit(1)

                Text(track.displayArtist)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer()

            Text(track.formattedDuration)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))

            Button {
                debugLog("Search play button pressed: \(track.displayTitle)")
                audioPlayer.playTrack(track, in: contextTracks, contextName: contextName)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            debugLog("Search result row tapped: \(track.displayTitle)")
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

struct SearchPlaylistArtworkView: View {
    let coverArtURL: String?
    let representativeTrack: Track?
    let fallbackTitle: String
    let size: CGFloat

    var body: some View {
        Group {
            if let artworkURL = artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackArtwork
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if let representativeTrack {
                TrackArtworkView(
                    track: representativeTrack,
                    size: size,
                    cornerRadius: 12,
                    showsSourceBadge: false
                )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white.opacity(0.72))
                            Text(String(fallbackTitle.prefix(1)).uppercased())
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white.opacity(0.42))
                        }
                    }
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
    }

    private var artworkURL: URL? {
        guard let coverArtURL,
              !coverArtURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if let parsedURL = URL(string: coverArtURL), parsedURL.scheme != nil {
            guard parsedURL.isFileURL || parsedURL.scheme?.lowercased() == "http" || parsedURL.scheme?.lowercased() == "https" else {
                return nil
            }
            return parsedURL
        }

        return AppFileManager.shared.resolveStoredFileURL(for: coverArtURL)
    }

    private var fallbackArtwork: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white.opacity(0.72))
                    Text(String(fallbackTitle.prefix(1)).uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.42))
                }
            }
    }
}

struct OnlineSearchTrackRow: View {
    let result: OnlineTrackResult
    let isDownloading: Bool
    let isSaving: Bool
    let isSaved: Bool
    let playAction: () -> Void
    let saveAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            OnlineTrackArtworkView(result: result, size: 50)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("\(result.artist) - \(result.providerDisplayName)")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer()

            Text(result.formattedDuration)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))

            Button(action: saveAction) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: isSaved ? "checkmark.circle.fill" : "square.and.arrow.down")
                        .font(.system(size: 20))
                        .foregroundColor(isSaved ? .green : .white.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
            .frame(width: 28)

            Button(action: playAction) {
                if isDownloading {
                    ProgressView()
                        .tint(.red)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.red)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: playAction)
    }
}

struct OnlineTrackArtworkView: View {
    let result: OnlineTrackResult
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.75, green: 0.2, blue: 0.2),
                            Color(red: 0.25, green: 0.08, blue: 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            artworkContent

            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.orange.opacity(0.95))
                .padding(5)
                .background(Circle().fill(Color.black.opacity(0.82)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(4)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var artworkContent: some View {
        if let artworkURL = artworkURL {
            AsyncImage(url: artworkURL) { phase in
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

    private var artworkURL: URL? {
        guard let coverArtURL = result.coverArtURL,
              let parsedURL = URL(string: coverArtURL),
              let scheme = parsedURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return parsedURL
    }

    private var fallbackArtwork: some View {
        ZStack {
            Image("PlayerAvatar")
                .resizable()
                .scaledToFill()

            LinearGradient(
                colors: [Color.black.opacity(0.08), Color.black.opacity(0.28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct FlowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(
                    x: bounds.minX + result.positions[index].x,
                    y: bounds.minY + result.positions[index].y
                ),
                proposal: .unspecified
            )
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + 8
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + 8
            }

            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

#Preview {
    SearchView()
        .environmentObject(AudioPlayer.shared)
        .environmentObject(DataManager.shared)
        .environmentObject(AppRouter())
}
