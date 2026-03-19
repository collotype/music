//
//  SearchView.swift
//  FreeMusicPlayer
//
//  Combined local and online music search.
//

import SwiftUI

struct SearchView: View {
    private let onlineSearchTimeoutNanoseconds: UInt64 = 15_000_000_000

    @Environment(\.openURL) private var openURL
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var router: AppRouter
    @AppStorage("search.selectedProvider") private var selectedProviderRawValue: String = OnlineTrackProvider.soundcloud.rawValue

    @State private var searchText: String = ""
    @State private var localResults: [Track] = []
    @State private var onlineResults: OnlineSearchResults = .empty
    @State private var isSearchingOnline: Bool = false
    @State private var onlineStatusMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var downloadingIDs: Set<String> = []
    @State private var savingIDs: Set<String> = []
    @State private var selectedCategory: SearchCategory = .tracks
    @State private var onlinePrompt: OnlineSearchPrompt?
    @State private var isAuthorizingSpotify: Bool = false

    private var selectedProvider: OnlineTrackProvider {
        OnlineTrackProvider(rawValue: selectedProviderRawValue) ?? .soundcloud
    }

    private var isSpotifyProviderAvailable: Bool {
        OnlineMusicService.shared.isSpotifyConfigured
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var onlineTrackResults: [OnlineTrackResult] {
        onlineResults.tracks
    }

    private var onlineArtistResults: [OnlineArtistResult] {
        onlineResults.artists
    }

    private var onlineAlbumResults: [OnlineAlbumResult] {
        onlineResults.albums
    }

    private var onlinePlaylistResults: [OnlinePlaylistResult] {
        onlineResults.playlists
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
            guard !trimmedSearchText.isEmpty else { return }
            localResults = localMatches(for: searchText)
            debugLog("Local result count updated: \(localResults.count)")
            logResultCounts(for: searchText)
        }
        .onChange(of: dataManager.playlists) { _ in
            guard !trimmedSearchText.isEmpty else { return }
            logResultCounts(for: searchText)
        }
        .onChange(of: selectedCategory) { newValue in
            debugLog("Search selected tab: \(newValue.title)")
            debugLog("Search query text: \(trimmedSearchText)")
            debugLog("Library \(newValue.title) result count: \(resultCount(for: newValue, query: searchText))")
            debugLog("\(selectedProvider.displayName) \(newValue.title) result count: \(onlineResultCount(for: newValue))")
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
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.5))

                    TextField("Search music", text: $searchText)
                        .font(.system(size: 17))
                        .foregroundColor(.white)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: searchText) { newValue in
                            performSearch(newValue, shouldSearchOnline: true)
                        }

                    if !searchText.isEmpty {
                        Button {
                            debugLog("Search clear button pressed")
                            searchTask?.cancel()
                            searchText = ""
                            localResults = []
                            onlineResults = .empty
                            onlineStatusMessage = nil
                            onlinePrompt = nil
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

                Menu {
                    ForEach(OnlineTrackProvider.allCases) { provider in
                        Button {
                            selectProvider(provider)
                        } label: {
                            SearchProviderMenuRow(
                                provider: provider,
                                isSelected: provider == selectedProvider,
                                isAvailable: isProviderAvailable(provider)
                            )
                        }
                    }
                } label: {
                    SearchProviderButton(
                        provider: selectedProvider,
                        isAvailable: isProviderAvailable(selectedProvider)
                    )
                }
                .buttonStyle(.plain)
            }

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

        SearchSectionCard(title: selectedProvider.displayName) {
            if isSearchingOnline && onlineTrackResults.isEmpty {
                SearchStatusRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Searching \(selectedProvider.displayName)...",
                    subtitle: onlineSearchSubtitle(for: .tracks)
                )
            } else if !onlineTrackResults.isEmpty {
                ForEach(onlineTrackResults) { result in
                    OnlineSearchTrackRow(
                        result: result,
                        isPerformingPrimaryAction: downloadingIDs.contains(result.id),
                        isSaving: savingIDs.contains(result.id),
                        isSaved: dataManager.track(withSourceID: result.id) != nil,
                        primaryAction: { handlePrimaryAction(for: result) },
                        saveAction: result.supportsOfflineDownload ? { saveOnlineResult(result) } : nil
                    )
                    if result.id != onlineTrackResults.last?.id {
                        Divider()
                            .background(Color.white.opacity(0.06))
                    }
                }
            } else {
                onlineStatusRow(for: .tracks)
            }
        }
    }

    @ViewBuilder
    var artistSearchResults: some View {
        SearchSectionCard(title: "Library") {
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

        SearchSectionCard(title: selectedProvider.displayName) {
            if isSearchingOnline && onlineArtistResults.isEmpty {
                SearchStatusRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Searching \(selectedProvider.displayName)...",
                    subtitle: onlineSearchSubtitle(for: .artists)
                )
            } else if !onlineArtistResults.isEmpty {
                ForEach(onlineArtistResults) { result in
                    OnlineSearchArtistRow(result: result) {
                        openExternalResult(result.externalURL, failureMessage: "Couldn't open that artist result.")
                    }

                    if result.id != onlineArtistResults.last?.id {
                        Divider()
                            .background(Color.white.opacity(0.06))
                    }
                }
            } else {
                onlineStatusRow(for: .artists)
            }
        }
    }

    @ViewBuilder
    var albumSearchResults: some View {
        SearchSectionCard(title: "Library") {
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

        SearchSectionCard(title: selectedProvider.displayName) {
            if isSearchingOnline && onlineAlbumResults.isEmpty {
                SearchStatusRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Searching \(selectedProvider.displayName)...",
                    subtitle: onlineSearchSubtitle(for: .albums)
                )
            } else if !onlineAlbumResults.isEmpty {
                ForEach(onlineAlbumResults) { result in
                    OnlineSearchAlbumRow(result: result) {
                        openExternalResult(result.externalURL, failureMessage: "Couldn't open that album result.")
                    }

                    if result.id != onlineAlbumResults.last?.id {
                        Divider()
                            .background(Color.white.opacity(0.06))
                    }
                }
            } else {
                onlineStatusRow(for: .albums)
            }
        }
    }

    @ViewBuilder
    var playlistSearchResults: some View {
        SearchSectionCard(title: "Library") {
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

        SearchSectionCard(title: selectedProvider.displayName) {
            if isSearchingOnline && onlinePlaylistResults.isEmpty {
                SearchStatusRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Searching \(selectedProvider.displayName)...",
                    subtitle: onlineSearchSubtitle(for: .playlists)
                )
            } else if !onlinePlaylistResults.isEmpty {
                ForEach(onlinePlaylistResults) { result in
                    OnlineSearchPlaylistRow(result: result) {
                        openExternalResult(result.externalURL, failureMessage: "Couldn't open that playlist result.")
                    }

                    if result.id != onlinePlaylistResults.last?.id {
                        Divider()
                            .background(Color.white.opacity(0.06))
                    }
                }
            } else {
                onlineStatusRow(for: .playlists)
            }
        }
    }

    private func performSearch(_ query: String, shouldSearchOnline: Bool) {
        searchTask?.cancel()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            localResults = []
            onlineResults = .empty
            onlineStatusMessage = nil
            onlinePrompt = nil
            isSearchingOnline = false
            return
        }

        debugLog("Query entered: \(trimmedQuery)")
        debugLog("Selected provider: \(selectedProvider.displayName)")
        localResults = localMatches(for: trimmedQuery)
        debugLog("Local result count: \(localResults.count)")
        logResultCounts(for: trimmedQuery)
        onlineResults = .empty
        onlineStatusMessage = nil
        onlinePrompt = nil

        guard shouldSearchOnline else {
            isSearchingOnline = false
            return
        }

        let provider = selectedProvider
        isSearchingOnline = true
        debugLog("Provider search start: \(provider.displayName) for \(trimmedQuery)")

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }

            do {
                let fetchedResults = try await searchOnlineResultsWithTimeout(for: trimmedQuery, provider: provider)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard searchText.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedQuery,
                          selectedProvider == provider else { return }
                    onlineResults = fetchedResults
                    isSearchingOnline = false
                    onlineStatusMessage = nil
                    onlinePrompt = nil
                    debugLog(
                        "Provider search end: \(provider.displayName) tracks=\(fetchedResults.tracks.count), artists=\(fetchedResults.artists.count), albums=\(fetchedResults.albums.count), playlists=\(fetchedResults.playlists.count)"
                    )
                }
            } catch let onlineError as OnlineMusicServiceError {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard searchText.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedQuery,
                          selectedProvider == provider else { return }
                    onlineResults = .empty
                    isSearchingOnline = false
                    onlinePrompt = nil

                    switch onlineError {
                    case .noResults(_):
                        onlineStatusMessage = nil
                        debugLog("Provider search end: \(provider.displayName) with 0 results")
                    case .timedOut(let message):
                        onlineStatusMessage = message
                    case .authenticationRequired(let message):
                        onlineStatusMessage = message
                        if provider == .spotify && OnlineMusicService.shared.isSpotifyConfigured {
                            onlinePrompt = .connectSpotify
                        }
                    case .configurationMissing(let message):
                        onlineStatusMessage = message
                    default:
                        onlineStatusMessage = onlineError.localizedDescription
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard searchText.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedQuery,
                          selectedProvider == provider else { return }
                    onlineResults = .empty
                    isSearchingOnline = false
                    onlinePrompt = nil
                    onlineStatusMessage = error.localizedDescription
                }
            }
        }
    }

    private func searchOnlineResultsWithTimeout(
        for query: String,
        provider: OnlineTrackProvider
    ) async throws -> OnlineSearchResults {
        let timeoutNanoseconds = onlineSearchTimeoutNanoseconds

        return try await withThrowingTaskGroup(of: OnlineSearchResults.self) { group in
            group.addTask {
                try await OnlineMusicService.shared.search(query, provider: provider)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                debugLog("Provider search timeout: \(provider.displayName) for \(query)")
                throw OnlineMusicServiceError.timedOut(
                    "\(provider.displayName) search timed out. Try another query or try again."
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

    private func handlePrimaryAction(for result: OnlineTrackResult) {
        if result.supportsInAppPlayback {
            playOnlineResult(result)
        } else {
            debugLog("External result open pressed: \(result.title) [\(result.providerTrackID)]")
            openExternalResult(
                result.externalURL,
                failureMessage: "\(result.providerDisplayName) could not be opened from this result."
            )
        }
    }

    private func playOnlineResult(_ result: OnlineTrackResult) {
        guard !downloadingIDs.contains(result.id) else { return }
        guard result.supportsInAppPlayback else {
            onlineStatusMessage = result.playbackUnavailableMessage
            return
        }

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
        guard result.supportsOfflineDownload else {
            onlineStatusMessage = result.offlineDownloadUnavailableMessage
            return
        }

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

    private func selectProvider(_ provider: OnlineTrackProvider) {
        guard provider != selectedProvider else { return }

        debugLog("Selected provider switched to: \(provider.displayName)")
        debugLog("Provider \(provider.displayName) enabled: \(isProviderAvailable(provider) ? "yes" : "no")")
        selectedProviderRawValue = provider.rawValue
        onlineStatusMessage = nil
        onlinePrompt = nil

        guard !trimmedSearchText.isEmpty else { return }
        performSearch(searchText, shouldSearchOnline: true)
    }

    private func connectSpotify() {
        guard !isAuthorizingSpotify else { return }

        debugLog("Spotify connect button pressed")
        isAuthorizingSpotify = true
        onlineStatusMessage = nil

        Task {
            defer {
                Task { @MainActor in
                    isAuthorizingSpotify = false
                }
            }

            do {
                try await OnlineMusicService.shared.authorizeSpotify()
                await MainActor.run {
                    onlinePrompt = nil
                    if !trimmedSearchText.isEmpty {
                        performSearch(searchText, shouldSearchOnline: true)
                    }
                }
            } catch {
                debugLog("Spotify connect error: \(error.localizedDescription)")
                await MainActor.run {
                    onlineStatusMessage = error.localizedDescription
                    if OnlineMusicService.shared.isSpotifyConfigured {
                        onlinePrompt = .connectSpotify
                    }
                }
            }
        }
    }

    private func openExternalResult(_ url: URL?, failureMessage: String) {
        guard let url else {
            onlineStatusMessage = failureMessage
            return
        }

        openURL(url) { didOpen in
            if !didOpen {
                onlineStatusMessage = failureMessage
            }
        }
    }

    @ViewBuilder
    private func onlineStatusRow(for category: SearchCategory) -> some View {
        if let onlineStatusMessage {
            SearchStatusRow(
                icon: "wifi.exclamationmark",
                title: unavailableOnlineTitle,
                subtitle: onlineStatusMessage,
                actionTitle: onlinePrompt == .connectSpotify ? "Connect" : nil,
                isActionLoading: isAuthorizingSpotify,
                action: onlinePrompt == .connectSpotify ? connectSpotify : nil
            )
        } else {
            SearchStatusRow(
                icon: "note.slash",
                title: noOnlineMatchesTitle(for: category),
                subtitle: noOnlineMatchesSubtitle(for: category)
            )
        }
    }

    private func onlineSearchSubtitle(for category: SearchCategory) -> String {
        switch category {
        case .tracks:
            return "Looking up matching tracks on \(selectedProvider.displayName)."
        case .artists:
            return "Looking up matching artists on \(selectedProvider.displayName)."
        case .albums:
            return "Looking up matching albums on \(selectedProvider.displayName)."
        case .playlists:
            return "Looking up matching playlists on \(selectedProvider.displayName)."
        }
    }

    private func noOnlineMatchesTitle(for category: SearchCategory) -> String {
        switch category {
        case .tracks:
            return "No \(selectedProvider.displayName) tracks"
        case .artists:
            return "No \(selectedProvider.displayName) artists"
        case .albums:
            return "No \(selectedProvider.displayName) albums"
        case .playlists:
            return "No \(selectedProvider.displayName) playlists"
        }
    }

    private func noOnlineMatchesSubtitle(for category: SearchCategory) -> String {
        if selectedProvider == .soundcloud && category == .playlists {
            return "SoundCloud playlist search is not available in this app yet."
        }

        return "Try another query or switch providers."
    }

    private var unavailableOnlineTitle: String {
        if selectedProvider == .spotify && !isSpotifyProviderAvailable {
            return "Spotify setup required"
        }

        return "\(selectedProvider.displayName) search unavailable"
    }

    private func isProviderAvailable(_ provider: OnlineTrackProvider) -> Bool {
        switch provider {
        case .soundcloud:
            return true
        case .spotify:
            return isSpotifyProviderAvailable
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

        var resultsByID: [String: LocalArtistSearchResult] = [:]

        for result in artistResults(from: localMatches(for: normalized)) {
            resultsByID[result.id] = result
        }

        for result in allArtistResults() where matchesSearchQuery(normalized, fields: [result.name]) {
            resultsByID[result.id] = result
        }

        return resultsByID.values.sorted { left, right in
            if left.name == "Unknown Artist" {
                return false
            }
            if right.name == "Unknown Artist" {
                return true
            }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    private func albumMatches(for query: String) -> [LocalAlbumSearchResult] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        var resultsByID: [String: LocalAlbumSearchResult] = [:]

        for result in albumResults(from: localMatches(for: normalized)) {
            resultsByID[result.id] = result
        }

        for result in allAlbumResults() where matchesSearchQuery(normalized, fields: [result.title, result.artist]) {
            resultsByID[result.id] = result
        }

        return resultsByID.values.sorted { left, right in
            if left.title.caseInsensitiveCompare(right.title) == .orderedSame {
                return left.artist.localizedCaseInsensitiveCompare(right.artist) == .orderedAscending
            }
            return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        }
    }

    private func playlistMatches(for query: String) -> [LocalPlaylistSearchResult] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        let matchingTrackIDs = Set(localMatches(for: normalized).map(\.id))
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

            let containsMatchingTrack = tracks.contains { matchingTrackIDs.contains($0.id) }
            guard containsMatchingTrack || matchesSearchQuery(normalized, fields: searchableFields) else { return nil }
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

    private func onlineResultCount(for category: SearchCategory) -> Int {
        switch category {
        case .tracks:
            return onlineTrackResults.count
        case .artists:
            return onlineArtistResults.count
        case .albums:
            return onlineAlbumResults.count
        case .playlists:
            return onlinePlaylistResults.count
        }
    }

    private func logResultCounts(for query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        let artistCatalogCount = allArtistResults().count
        let albumCatalogCount = allAlbumResults().count
        let playlistCatalogCount = dataManager.sortedPlaylists.count
        let playlistResultCount = playlistMatches(for: trimmedQuery).count
        debugLog("Artist aggregation count: \(artistCatalogCount)")
        debugLog("Album aggregation count: \(albumCatalogCount)")
        debugLog("Playlist aggregation count: \(playlistCatalogCount)")
        debugLog("Playlist search result count: \(playlistResultCount)")
        debugLog(
            "Search result counts for \(trimmedQuery): tracks=\(localMatches(for: trimmedQuery).count), artists=\(artistMatches(for: trimmedQuery).count), albums=\(albumMatches(for: trimmedQuery).count), playlists=\(playlistMatches(for: trimmedQuery).count)"
        )
        debugLog(
            "Provider result counts for \(selectedProvider.displayName): tracks=\(onlineTrackResults.count), artists=\(onlineArtistResults.count), albums=\(onlineAlbumResults.count), playlists=\(onlinePlaylistResults.count)"
        )
    }

    private func allArtistResults() -> [LocalArtistSearchResult] {
        artistResults(from: dataManager.tracks)
    }

    private func allAlbumResults() -> [LocalAlbumSearchResult] {
        albumResults(from: dataManager.tracks)
    }

    private func artistResults(from tracks: [Track]) -> [LocalArtistSearchResult] {
        let groupedTracks = Dictionary(grouping: tracks) { track in
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
    }

    private func albumResults(from tracks: [Track]) -> [LocalAlbumSearchResult] {
        let albumTracks = tracks.filter { track in
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

private enum OnlineSearchPrompt {
    case connectSpotify
}

struct SearchProviderButton: View {
    let provider: OnlineTrackProvider
    let isAvailable: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))

            Circle()
                .stroke(provider.accentColor.opacity(0.4), lineWidth: 1)

            ProviderIconView(provider: provider, size: 20)

            if !isAvailable {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.yellow)
                    .background(Circle().fill(Color.black))
                    .offset(x: 12, y: -12)
            }
        }
        .frame(width: 42, height: 42)
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
        .accessibilityLabel(Text(isAvailable ? provider.displayName : "\(provider.displayName), setup required"))
    }
}

struct SearchProviderMenuRow: View {
    let provider: OnlineTrackProvider
    let isSelected: Bool
    let isAvailable: Bool

    var body: some View {
        HStack(spacing: 10) {
            ProviderIconView(provider: provider, size: 16)
            Text(isAvailable ? provider.displayName : "\(provider.displayName) (Setup Required)")
                .foregroundColor(isAvailable ? .primary : .secondary)
            if isSelected {
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
            }
        }
        .opacity(isAvailable ? 1.0 : 0.82)
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
    var actionTitle: String? = nil
    var isActionLoading: Bool = false
    var action: (() -> Void)? = nil

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

            if let actionTitle, let action {
                Button(action: action) {
                    Group {
                        if isActionLoading {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 18, height: 18)
                        } else {
                            Text(actionTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
            }
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
    let isPerformingPrimaryAction: Bool
    let isSaving: Bool
    let isSaved: Bool
    let primaryAction: () -> Void
    let saveAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            OnlineResultArtworkView(
                provider: result.provider,
                artworkURLString: result.coverArtURL,
                fallbackSystemImage: "music.note",
                size: 50,
                cornerRadius: 8
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(result.detailLine)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer()

            Text(result.formattedDuration)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))

            if let saveAction {
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
            } else {
                Color.clear
                    .frame(width: 28, height: 28)
            }

            Button(action: primaryAction) {
                if isPerformingPrimaryAction {
                    ProgressView()
                        .tint(result.supportsInAppPlayback ? .red : result.provider.accentColor)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: result.supportsInAppPlayback ? "play.circle.fill" : "arrow.up.right.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(result.supportsInAppPlayback ? .red : result.provider.accentColor)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: primaryAction)
    }
}

struct OnlineSearchArtistRow: View {
    let result: OnlineArtistResult
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            OnlineResultArtworkView(
                provider: result.provider,
                artworkURLString: result.imageURL,
                fallbackSystemImage: "person.fill",
                size: 54,
                cornerRadius: 27
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(result.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(result.providerDisplayName)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.52))
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.28))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

struct OnlineSearchAlbumRow: View {
    let result: OnlineAlbumResult
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            OnlineResultArtworkView(
                provider: result.provider,
                artworkURLString: result.coverArtURL,
                fallbackSystemImage: "square.stack.fill",
                size: 54,
                cornerRadius: 12
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

                Text(result.providerDisplayName)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.42))
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.28))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

struct OnlineSearchPlaylistRow: View {
    let result: OnlinePlaylistResult
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            OnlineResultArtworkView(
                provider: result.provider,
                artworkURLString: result.coverArtURL,
                fallbackSystemImage: "music.note.list",
                size: 54,
                cornerRadius: 12
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(result.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(metadataLine)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.52))
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.28))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    private var metadataLine: String {
        let pieces = [
            result.ownerName,
            result.trackCount.map { "\($0) track\($0 == 1 ? "" : "s")" },
            result.providerDisplayName
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? $0 : nil }

        return pieces.isEmpty ? result.providerDisplayName : pieces.joined(separator: " | ")
    }
}

struct OnlineResultArtworkView: View {
    let provider: OnlineTrackProvider
    let artworkURLString: String?
    let fallbackSystemImage: String
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            provider.accentColor,
                            provider.secondaryAccentColor
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            artworkContent

            ProviderIconView(provider: provider, size: 13)
                .padding(5)
                .background(Circle().fill(Color.black.opacity(0.82)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(4)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
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
        guard let artworkURLString,
              let parsedURL = URL(string: artworkURLString),
              let scheme = parsedURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return parsedURL
    }

    private var fallbackArtwork: some View {
        ZStack {
            LinearGradient(
                colors: [provider.accentColor, provider.secondaryAccentColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: fallbackSystemImage)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
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
