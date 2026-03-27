//
//  OnlineArtistDetailView.swift
//  FreeMusicPlayer
//
//  Native SoundCloud artist and release browsing inside the app.
//

import SwiftUI

struct OnlineArtistDetailView: View {
    let route: OnlineArtistRoute

    @EnvironmentObject private var dataManager: DataManager
    @EnvironmentObject private var audioPlayer: AudioPlayer
    @EnvironmentObject private var router: AppRouter

    @State private var profile: OnlineArtistProfile
    @State private var popularTracks: [OnlineTrackResult] = []
    @State private var releases: [OnlineAlbumResult] = []
    @State private var isLoadingPage = false
    @State private var isPlayingPrimaryAction = false
    @State private var profileErrorMessage: String?
    @State private var trackErrorMessage: String?
    @State private var releaseErrorMessage: String?
    @State private var actionStatusMessage: String?

    init(route: OnlineArtistRoute) {
        self.route = route
        _profile = State(
            initialValue: OnlineArtistProfile(
                name: route.artistName,
                imageURL: route.imageURL,
                heroImageURL: nil,
                followerCount: nil,
                trackCount: nil,
                isVerified: false,
                webpageURL: route.webpageURL
            )
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        artistHeroCard

                        VStack(alignment: .leading, spacing: 20) {
                            if let profileErrorMessage {
                                ArtistDetailSection(title: "Artist") {
                                    SearchStatusRow(
                                        icon: "info.circle",
                                        title: "Some artist details are unavailable",
                                        subtitle: profileErrorMessage
                                    )
                                }
                            }

                            popularTracksSection
                            releasesSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        .padding(.bottom, 64)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: geometry.size.width, alignment: .topLeading)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: route.id) {
            await loadArtistPage()
        }
    }

    private var artistHeroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArtistBackdropBannerView(
                provider: route.provider,
                artworkReference: heroBackdropReference
            )
            .frame(height: artistBackdropHeight)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 16) {
                    ResolvedArtworkTileView(
                        provider: route.provider,
                        artworkReference: avatarArtworkReference,
                        fallbackSystemImage: "person.fill",
                        size: 92,
                        cornerRadius: 24,
                        showsProviderBadge: false
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(profile.name)
                                .font(.system(size: 30, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(2)

                            if profile.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(route.provider.accentColor)
                            }
                        }

                        Text(route.provider.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 16)

                if !artistMetadataChips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(artistMetadataChips, id: \.self) { chip in
                                HeroMetadataChip(text: chip)
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        playPrimarySelection()
                    } label: {
                        HeroActionButton(
                            title: "Play",
                            systemImage: isPlayingPrimaryAction ? nil : "play.fill",
                            tint: .white,
                            foregroundColor: .black,
                            isLoading: isPlayingPrimaryAction
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(primaryPlayableTrack == nil || isPlayingPrimaryAction)
                    .opacity(primaryPlayableTrack == nil ? 0.45 : 1)

                    Button {
                        dataManager.toggleFavoriteArtist(currentFavoriteArtist)
                    } label: {
                        HeroActionButton(
                            title: isFavoriteArtist ? "Unfavorite Artist" : "Favorite Artist",
                            systemImage: isFavoriteArtist ? "heart.fill" : "heart",
                            tint: Color.white.opacity(0.14),
                            foregroundColor: .white,
                            isLoading: false
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var popularTracksSection: some View {
        ArtistDetailSection(title: "Popular Tracks") {
            if let actionStatusMessage, !popularTracks.isEmpty {
                SearchStatusRow(
                    icon: "exclamationmark.circle",
                    title: "Track action unavailable",
                    subtitle: actionStatusMessage
                )

                Divider()
                    .background(Color.white.opacity(0.06))
            }

            if isLoadingPage && popularTracks.isEmpty && trackErrorMessage == nil {
                SearchStatusRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Loading tracks",
                    subtitle: "Fetching SoundCloud tracks for this artist."
                )
            } else if let trackErrorMessage, popularTracks.isEmpty {
                SearchStatusRow(
                    icon: "wifi.exclamationmark",
                    title: "Couldn't load tracks",
                    subtitle: trackErrorMessage,
                    actionTitle: "Retry",
                    action: retryLoadArtistPage
                )
            } else if popularTracks.isEmpty {
                SearchStatusRow(
                    icon: "music.note.list",
                    title: "No tracks found",
                    subtitle: "No playable SoundCloud tracks are available for this artist right now."
                )
            } else {
                OnlineTrackResultsList(
                    results: popularTracks,
                    statusMessage: $actionStatusMessage
                )
            }
        }
    }

    @ViewBuilder
    private var releasesSection: some View {
        ArtistDetailSection(title: "Releases") {
            if isLoadingPage && releases.isEmpty && releaseErrorMessage == nil {
                SearchStatusRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Loading releases",
                    subtitle: "Fetching SoundCloud releases for this artist."
                )
            } else if let releaseErrorMessage, releases.isEmpty {
                SearchStatusRow(
                    icon: "wifi.exclamationmark",
                    title: "Couldn't load releases",
                    subtitle: releaseErrorMessage,
                    actionTitle: "Retry",
                    action: retryLoadArtistPage
                )
            } else if releases.isEmpty {
                SearchStatusRow(
                    icon: "square.stack.3d.up.slash",
                    title: "No releases found",
                    subtitle: "SoundCloud did not return release collections for this artist."
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(releases) { release in
                            Button {
                                router.openOnlineRelease(release.releaseRoute)
                            } label: {
                                OnlineReleaseCard(release: release)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }

                if let releaseErrorMessage {
                    Divider()
                        .background(Color.white.opacity(0.06))

                    SearchStatusRow(
                        icon: "info.circle",
                        title: "Some releases may be missing",
                        subtitle: releaseErrorMessage
                    )
                }
            }
        }
    }

    private var primaryPlayableTrack: OnlineTrackResult? {
        popularTracks.first(where: \.supportsInAppPlayback)
    }

    private var isFavoriteArtist: Bool {
        dataManager.isFavoriteArtist(
            provider: route.provider,
            artistID: route.providerArtistID
        )
    }

    private var currentFavoriteArtist: FavoriteArtist {
        FavoriteArtist(
            provider: route.provider,
            providerArtistID: route.providerArtistID,
            artistName: profile.name,
            imageURL: profile.imageURL ?? route.imageURL,
            localImagePath: persistedFavoriteArtist?.localImagePath,
            webpageURL: profile.webpageURL ?? route.webpageURL
        )
    }

    private var persistedFavoriteArtist: FavoriteArtist? {
        dataManager.favoriteArtist(provider: route.provider, artistID: route.providerArtistID)
    }

    private var heroBackdropReference: String? {
        preferredArtworkReference(profile.heroImageURL)
    }

    private var avatarArtworkReference: String? {
        preferredArtworkReference(
            persistedFavoriteArtist?.localImagePath,
            profile.imageURL,
            route.imageURL,
            popularTracks.first?.artistImageURL,
            releases.first?.coverArtURL,
            popularTracks.first?.coverArtURL
        )
    }

    private var artistMetadataChips: [String] {
        var chips: [String] = []

        if let followerCount = profile.followerCount {
            chips.append("\(formattedCount(followerCount)) followers")
        }

        if let trackCount = profile.trackCount {
            chips.append("\(trackCount) track\(trackCount == 1 ? "" : "s")")
        } else if !popularTracks.isEmpty {
            chips.append("\(popularTracks.count) loaded track\(popularTracks.count == 1 ? "" : "s")")
        }

        return chips
    }

    private var artistBackdropHeight: CGFloat {
        resolvedArtworkURL(from: heroBackdropReference) == nil ? 110 : 156
    }

    private func retryLoadArtistPage() {
        Task {
            await loadArtistPage()
        }
    }

    @MainActor
    private func loadArtistPage() async {
        guard !isLoadingPage else { return }

        isLoadingPage = true
        profileErrorMessage = nil
        trackErrorMessage = nil
        releaseErrorMessage = nil
        actionStatusMessage = nil
        popularTracks = []
        releases = []

        defer {
            isLoadingPage = false
        }

        do {
            profile = try await OnlineMusicService.shared.fetchSoundCloudArtistProfile(for: route)
        } catch {
            profileErrorMessage = error.localizedDescription
            debugLog("Online artist profile load error for \(route.providerArtistID): \(error.localizedDescription)")
        }

        do {
            popularTracks = try await OnlineMusicService.shared.fetchSoundCloudTracks(for: route)
            prewarmPopularTrackPlayback()
        } catch {
            trackErrorMessage = error.localizedDescription
            debugLog("Online artist track load error for \(route.providerArtistID): \(error.localizedDescription)")
        }

        do {
            releases = try await OnlineMusicService.shared.fetchSoundCloudReleases(for: route)
        } catch {
            releaseErrorMessage = error.localizedDescription
            debugLog("Online artist release load error for \(route.providerArtistID): \(error.localizedDescription)")
        }
    }

    private func playPrimarySelection() {
        guard let primaryPlayableTrack else {
            actionStatusMessage = "No playable SoundCloud tracks are available for this artist yet."
            return
        }

        guard !isPlayingPrimaryAction else { return }

        debugLog("Artist hero play pressed: \(profile.name) [\(route.providerArtistID)]")
        isPlayingPrimaryAction = true
        actionStatusMessage = nil

        Task {
            defer {
                Task { @MainActor in
                    isPlayingPrimaryAction = false
                }
            }

            do {
                try await OnlineTrackActionHelper.play(
                    result: primaryPlayableTrack,
                    dataManager: dataManager,
                    audioPlayer: audioPlayer
                )
            } catch {
                await MainActor.run {
                    actionStatusMessage = error.localizedDescription
                }
            }
        }
    }

    private func prewarmPopularTrackPlayback() {
        let tracksToWarm = popularTracks
            .filter(\.supportsInAppPlayback)
            .prefix(3)

        guard !tracksToWarm.isEmpty else { return }

        Task(priority: .utility) {
            for track in tracksToWarm {
                _ = try? await OnlineMusicService.shared.resolvePlaybackStream(for: track)
            }
        }
    }
}

struct OnlineReleaseDetailView: View {
    let route: OnlineReleaseRoute

    @EnvironmentObject private var audioPlayer: AudioPlayer
    @EnvironmentObject private var dataManager: DataManager

    @State private var release: OnlineAlbumResult
    @State private var tracks: [OnlineTrackResult] = []
    @State private var isLoading = false
    @State private var isPlayingPrimaryAction = false
    @State private var loadingErrorMessage: String?
    @State private var actionStatusMessage: String?

    init(route: OnlineReleaseRoute) {
        self.route = route
        _release = State(
            initialValue: OnlineAlbumResult(
                provider: route.provider,
                providerAlbumID: route.providerReleaseID,
                title: route.title,
                artist: route.artistName,
                coverArtURL: route.imageURL,
                webpageURL: route.webpageURL ?? "",
                trackCount: nil,
                releaseDate: nil,
                releaseKind: "release"
            )
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        releaseHeroCard

                        VStack(alignment: .leading, spacing: 20) {
                            ArtistDetailSection(title: "Tracks") {
                                if let actionStatusMessage, !tracks.isEmpty {
                                    SearchStatusRow(
                                        icon: "exclamationmark.circle",
                                        title: "Track action unavailable",
                                        subtitle: actionStatusMessage
                                    )

                                    Divider()
                                        .background(Color.white.opacity(0.06))
                                }

                                if isLoading && tracks.isEmpty && loadingErrorMessage == nil {
                                    SearchStatusRow(
                                        icon: "arrow.triangle.2.circlepath",
                                        title: "Loading release",
                                        subtitle: "Fetching SoundCloud tracks for this release."
                                    )
                                } else if let loadingErrorMessage, tracks.isEmpty {
                                    SearchStatusRow(
                                        icon: "wifi.exclamationmark",
                                        title: "Couldn't load release",
                                        subtitle: loadingErrorMessage,
                                        actionTitle: "Retry",
                                        action: retryLoadRelease
                                    )
                                } else if tracks.isEmpty {
                                    SearchStatusRow(
                                        icon: "music.note.list",
                                        title: "No tracks found",
                                        subtitle: "This SoundCloud release does not include a playable track list."
                                    )
                                } else {
                                    OnlineTrackResultsList(
                                        results: tracks,
                                        statusMessage: $actionStatusMessage
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        .padding(.bottom, 64)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: geometry.size.width, alignment: .topLeading)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(release.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: route.providerReleaseID) {
            await loadRelease()
        }
    }

    private var releaseHeroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack {
                ArtistHeroArtworkView(
                    provider: route.provider,
                    artworkURLString: release.coverArtURL,
                    fallbackTitle: release.title,
                    fallbackSystemImage: "square.stack.fill",
                    cornerRadius: 0
                )
                .frame(maxWidth: .infinity)
                .frame(height: releaseHeroHeight)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.04),
                        Color.black.opacity(0.14),
                        Color.black.opacity(0.68)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 16) {
                    ResolvedArtworkTileView(
                        provider: route.provider,
                        artworkReference: release.coverArtURL,
                        fallbackSystemImage: "square.stack.fill",
                        size: 92,
                        cornerRadius: 22,
                        showsProviderBadge: false
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text(release.title)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)

                        Text(release.artist)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.72))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                if !releaseMetadataChips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(releaseMetadataChips, id: \.self) { chip in
                                HeroMetadataChip(text: chip)
                            }
                        }
                    }
                }

                Button {
                    playRelease()
                } label: {
                    HeroActionButton(
                        title: "Play",
                        systemImage: isPlayingPrimaryAction ? nil : "play.fill",
                        tint: .white,
                        foregroundColor: .black,
                        isLoading: isPlayingPrimaryAction
                    )
                }
                .buttonStyle(.plain)
                .disabled(primaryPlayableTrack == nil || isPlayingPrimaryAction)
                .opacity(primaryPlayableTrack == nil ? 0.45 : 1)
            }
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryPlayableTrack: OnlineTrackResult? {
        tracks.first(where: \.supportsInAppPlayback)
    }

    private var releaseMetadataChips: [String] {
        var chips: [String] = []

        if let kind = cleanedReleaseKind(release.releaseKind) {
            chips.append(kind)
        }

        if let releaseDate = release.releaseDate {
            chips.append(releaseDate.formatted(date: .abbreviated, time: .omitted))
        }

        if let trackCount = release.trackCount ?? (tracks.isEmpty ? nil : tracks.count) {
            chips.append("\(trackCount) track\(trackCount == 1 ? "" : "s")")
        }

        return chips
    }

    private var releaseHeroHeight: CGFloat {
        resolvedArtworkURL(from: release.coverArtURL) == nil ? 170 : 220
    }

    private func retryLoadRelease() {
        Task {
            await loadRelease()
        }
    }

    @MainActor
    private func loadRelease() async {
        guard !isLoading else { return }

        isLoading = true
        loadingErrorMessage = nil
        actionStatusMessage = nil
        tracks = []

        defer {
            isLoading = false
        }

        do {
            let pageData = try await OnlineMusicService.shared.fetchSoundCloudReleaseDetail(for: route)
            guard !Task.isCancelled else { return }

            release = pageData.release
            tracks = pageData.tracks
            debugLog("Loaded online release: \(route.title) = \(pageData.tracks.count)")
        } catch {
            guard !Task.isCancelled else { return }

            loadingErrorMessage = error.localizedDescription
            debugLog("Online release load error for \(route.providerReleaseID): \(error.localizedDescription)")
        }
    }

    private func playRelease() {
        guard let primaryPlayableTrack else {
            actionStatusMessage = "No playable SoundCloud tracks are available for this release yet."
            return
        }

        guard !isPlayingPrimaryAction else { return }

        debugLog("Release hero play pressed: \(release.title) [\(route.providerReleaseID)]")
        isPlayingPrimaryAction = true
        actionStatusMessage = nil

        Task {
            defer {
                Task { @MainActor in
                    isPlayingPrimaryAction = false
                }
            }

            do {
                try await OnlineTrackActionHelper.play(
                    result: primaryPlayableTrack,
                    dataManager: dataManager,
                    audioPlayer: audioPlayer
                )
            } catch {
                await MainActor.run {
                    actionStatusMessage = error.localizedDescription
                }
            }
        }
    }
}

struct OnlineTrackResultsList: View {
    let results: [OnlineTrackResult]
    @Binding var statusMessage: String?
    var onSaveCompletion: (() -> Void)? = nil

    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var dataManager: DataManager
    @EnvironmentObject private var audioPlayer: AudioPlayer

    @State private var performingPrimaryActionIDs: Set<String> = []
    @State private var savingIDs: Set<String> = []

    var body: some View {
        ForEach(results) { result in
            OnlineSearchTrackRow(
                result: result,
                isPerformingPrimaryAction: performingPrimaryActionIDs.contains(result.id),
                isSaving: savingIDs.contains(result.id),
                isSaved: dataManager.track(withSourceID: result.id) != nil,
                primaryAction: { handlePrimaryAction(for: result) },
                saveAction: result.supportsOfflineDownload ? { saveOnlineResult(result) } : nil
            )

            if result.id != results.last?.id {
                Divider()
                    .background(Color.white.opacity(0.06))
            }
        }
    }

    private func handlePrimaryAction(for result: OnlineTrackResult) {
        guard !performingPrimaryActionIDs.contains(result.id) else { return }

        if result.supportsInAppPlayback {
            debugLog("Online result play pressed: \(result.title) [\(result.providerTrackID)]")
            performingPrimaryActionIDs.insert(result.id)
            statusMessage = nil

            Task {
                defer {
                    Task { @MainActor in
                        performingPrimaryActionIDs.remove(result.id)
                    }
                }

                do {
                    try await OnlineTrackActionHelper.play(
                        result: result,
                        dataManager: dataManager,
                        audioPlayer: audioPlayer
                    )
                } catch {
                    debugLog("Playback error for \(result.providerTrackID): \(error.localizedDescription)")
                    await MainActor.run {
                        statusMessage = error.localizedDescription
                    }
                }
            }
        } else {
            debugLog("External result open pressed: \(result.title) [\(result.providerTrackID)]")
            openExternalResult(
                result.externalURL,
                failureMessage: "\(result.providerDisplayName) could not be opened from this result."
            )
        }
    }

    private func saveOnlineResult(_ result: OnlineTrackResult) {
        guard !savingIDs.contains(result.id) else { return }

        guard result.supportsOfflineDownload else {
            statusMessage = result.offlineDownloadUnavailableMessage
            return
        }

        if let savedTrack = dataManager.track(withSourceID: result.id) {
            debugLog("Saved online result tapped again: \(result.title) [\(result.providerTrackID)]")
            let didStartPlayback = audioPlayer.playTrack(savedTrack)
            if !didStartPlayback {
                statusMessage = audioPlayer.playbackErrorMessage ?? "Playback failed for the saved track."
            }
            return
        }

        debugLog("Online result save pressed: \(result.title) [\(result.providerTrackID)]")
        savingIDs.insert(result.id)
        statusMessage = nil

        Task {
            defer {
                Task { @MainActor in
                    savingIDs.remove(result.id)
                }
            }

            do {
                let savedTrack = try await OnlineTrackActionHelper.save(
                    result: result,
                    dataManager: dataManager
                )

                await MainActor.run {
                    audioPlayer.syncCurrentTrackReference(with: savedTrack)
                    onSaveCompletion?()
                }
            } catch {
                debugLog("Save error for \(result.providerTrackID): \(error.localizedDescription)")
                await MainActor.run {
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func openExternalResult(_ url: URL?, failureMessage: String) {
        guard let url else {
            statusMessage = failureMessage
            return
        }

        openURL(url) { didOpen in
            if !didOpen {
                statusMessage = failureMessage
            }
        }
    }
}

private enum OnlineTrackActionHelper {
    static func play(
        result: OnlineTrackResult,
        dataManager: DataManager,
        audioPlayer: AudioPlayer
    ) async throws {
        guard result.supportsInAppPlayback else {
            throw OnlineMusicServiceError.unsupportedSource(result.playbackUnavailableMessage)
        }

        await MainActor.run {
            audioPlayer.clearPlaybackError()
        }

        let resolvedStream = try await OnlineMusicService.shared.resolvePlaybackStream(for: result)
        let streamingTrack = await MainActor.run {
            dataManager.makeStreamingTrack(from: result, streamURL: resolvedStream.url)
        }

        let didStartPlayback = await MainActor.run {
            audioPlayer.playTrack(streamingTrack)
        }

        guard didStartPlayback else {
            let failureMessage = await MainActor.run {
                audioPlayer.playbackErrorMessage ?? "Playback failed for the selected SoundCloud track."
            }
            throw OnlineMusicServiceError.unsupportedSource(failureMessage)
        }

        debugLog("Playback success for \(result.providerTrackID) via \(resolvedStream.streamType)")
    }

    static func save(
        result: OnlineTrackResult,
        dataManager: DataManager
    ) async throws -> Track {
        guard result.supportsOfflineDownload else {
            throw OnlineMusicServiceError.unsupportedSource(result.offlineDownloadUnavailableMessage)
        }

        let tempURL = try await OnlineMusicService.shared.downloadAudio(for: result)
        return try await dataManager.saveDownloadedOnlineTrack(result, from: tempURL)
    }
}

private struct ResolvedArtworkTileView: View {
    let provider: OnlineTrackProvider
    let artworkReference: String?
    let fallbackSystemImage: String
    let size: CGFloat
    let cornerRadius: CGFloat
    let showsProviderBadge: Bool

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

            if showsProviderBadge {
                ProviderIconView(provider: provider, size: 13)
                    .padding(5)
                    .background(Circle().fill(Color.black.opacity(0.82)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(4)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    private var artworkContent: some View {
        if let artworkURL = resolvedArtworkURL(from: artworkReference) {
            if artworkURL.isFileURL {
                if let image = UIImage(contentsOfFile: artworkURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    fallbackArtwork
                }
            } else {
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
            }
        } else {
            fallbackArtwork
        }
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

private struct OnlineReleaseCard: View {
    let release: OnlineAlbumResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResolvedArtworkTileView(
                provider: release.provider,
                artworkReference: release.coverArtURL,
                fallbackSystemImage: "square.stack.fill",
                size: 168,
                cornerRadius: 18,
                showsProviderBadge: true
            )

            Text(release.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)

            Text(release.artist)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)

            Text(releaseMetadataLine)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.42))
                .lineLimit(2)
        }
        .frame(width: 168, alignment: .leading)
    }

    private var releaseMetadataLine: String {
        var pieces: [String] = []

        if let kind = cleanedReleaseKind(release.releaseKind) {
            pieces.append(kind)
        }

        if let releaseDate = release.releaseDate {
            pieces.append(releaseDate.formatted(date: .abbreviated, time: .omitted))
        }

        if let trackCount = release.trackCount {
            pieces.append("\(trackCount) track\(trackCount == 1 ? "" : "s")")
        }

        return pieces.isEmpty ? release.providerDisplayName : pieces.joined(separator: " | ")
    }
}

private struct ArtistBackdropBannerView: View {
    let provider: OnlineTrackProvider
    let artworkReference: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    provider.accentColor.opacity(0.92),
                    provider.secondaryAccentColor.opacity(0.92),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            backdropImage

            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.30),
                    Color.black.opacity(0.82)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
    }

    @ViewBuilder
    private var backdropImage: some View {
        if let artworkURL = resolvedArtworkURL(from: artworkReference) {
            if artworkURL.isFileURL, let image = UIImage(contentsOfFile: artworkURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.52)
            } else {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .opacity(0.52)
                    default:
                        Color.clear
                    }
                }
            }
        }
    }
}

private struct ArtistHeroArtworkView: View {
    let provider: OnlineTrackProvider
    let artworkURLString: String?
    let fallbackTitle: String
    let fallbackSystemImage: String
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    provider.accentColor.opacity(0.9),
                    provider.secondaryAccentColor.opacity(0.92),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let artworkURL = artworkURL {
                if artworkURL.isFileURL, let image = UIImage(contentsOfFile: artworkURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    AsyncImage(url: artworkURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            fallbackContent
                        }
                    }
                }
            } else {
                fallbackContent
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var artworkURL: URL? {
        resolvedArtworkURL(from: artworkURLString)
    }

    private var fallbackContent: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color.white.opacity(0.14),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 8,
                endRadius: 220
            )

            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 92, height: 92)

            VStack(spacing: 8) {
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.white.opacity(0.86))
            }
        }
    }
}

private struct HeroActionButton: View {
    let title: String
    let systemImage: String?
    let tint: Color
    let foregroundColor: Color
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .tint(foregroundColor)
            } else if let systemImage {
                Image(systemName: systemImage)
            }

            Text(title)
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(foregroundColor)
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(
            Capsule()
                .fill(tint)
        )
    }
}

private struct HeroMetadataChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct ArtistDetailSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension OnlineAlbumResult {
    var releaseRoute: OnlineReleaseRoute {
        OnlineReleaseRoute(
            provider: provider,
            providerReleaseID: providerAlbumID,
            title: title,
            artistName: artist,
            imageURL: coverArtURL,
            webpageURL: webpageURL
        )
    }
}

private func resolvedArtworkURL(from reference: String?) -> URL? {
    guard let reference = reference?.trimmingCharacters(in: .whitespacesAndNewlines),
          !reference.isEmpty else {
        return nil
    }

    if let parsedURL = URL(string: reference), parsedURL.scheme != nil {
        let scheme = parsedURL.scheme?.lowercased()
        guard parsedURL.isFileURL || scheme == "http" || scheme == "https" else {
            return nil
        }

        if parsedURL.isFileURL,
           !FileManager.default.fileExists(atPath: parsedURL.path) {
            return nil
        }

        return parsedURL
    }

    let resolvedURL = AppFileManager.shared.resolveStoredFileURL(for: reference)
    guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
        return nil
    }

    return resolvedURL
}

private func preferredArtworkReference(_ candidates: String?...) -> String? {
    candidates.compactMap { $0 }.first { resolvedArtworkURL(from: $0) != nil }
}

private func formattedCount(_ value: Int) -> String {
    if value >= 1_000_000 {
        return String(format: "%.1fM", Double(value) / 1_000_000)
    }

    if value >= 1_000 {
        return String(format: "%.1fK", Double(value) / 1_000)
    }

    return "\(value)"
}

private func cleanedReleaseKind(_ rawValue: String?) -> String? {
    guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
          !rawValue.isEmpty else {
        return nil
    }

    switch rawValue.lowercased() {
    case "album":
        return "Album"
    case "playlist":
        return "Release"
    default:
        return rawValue.capitalized
    }
}
