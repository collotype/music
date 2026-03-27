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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                artistHeroCard

                if let profileErrorMessage {
                    SearchSectionCard(title: "Artist") {
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
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: route.id) {
            await loadArtistPage()
        }
    }

    private var artistHeroCard: some View {
        ZStack(alignment: .bottomLeading) {
            ArtistHeroArtworkView(
                provider: route.provider,
                artworkURLString: heroArtworkURLString,
                fallbackTitle: profile.name,
                fallbackSystemImage: "person.fill",
                cornerRadius: 28
            )
            .frame(height: 320)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.05),
                    Color.black.opacity(0.35),
                    Color.black.opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom, spacing: 14) {
                    OnlineResultArtworkView(
                        provider: route.provider,
                        artworkURLString: avatarArtworkURLString,
                        fallbackSystemImage: "person.fill",
                        size: 88,
                        cornerRadius: 24
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
            }
            .padding(22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var popularTracksSection: some View {
        SearchSectionCard(title: "Popular Tracks") {
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
        SearchSectionCard(title: "Releases") {
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
            imageURL: avatarArtworkURLString,
            webpageURL: profile.webpageURL ?? route.webpageURL
        )
    }

    private var heroArtworkURLString: String? {
        profile.heroImageURL ??
            profile.imageURL ??
            route.imageURL ??
            releases.first?.coverArtURL ??
            popularTracks.first?.coverArtURL
    }

    private var avatarArtworkURLString: String? {
        profile.imageURL ??
            route.imageURL ??
            popularTracks.first?.artistImageURL ??
            releases.first?.coverArtURL ??
            popularTracks.first?.coverArtURL
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                releaseHeroCard

                SearchSectionCard(title: "Tracks") {
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
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(release.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: route.providerReleaseID) {
            await loadRelease()
        }
    }

    private var releaseHeroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            ArtistHeroArtworkView(
                provider: route.provider,
                artworkURLString: release.coverArtURL,
                fallbackTitle: release.title,
                fallbackSystemImage: "square.stack.fill",
                cornerRadius: 24
            )
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text(release.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text(release.artist)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(1)

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
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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

        return try await MainActor.run {
            try dataManager.saveDownloadedOnlineTrack(result, from: tempURL)
        }
    }
}

private struct OnlineReleaseCard: View {
    let release: OnlineAlbumResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OnlineResultArtworkView(
                provider: release.provider,
                artworkURLString: release.coverArtURL,
                fallbackSystemImage: "square.stack.fill",
                size: 168,
                cornerRadius: 18
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
            } else {
                fallbackContent
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var artworkURL: URL? {
        guard let artworkURLString,
              let artworkURL = URL(string: artworkURLString),
              let scheme = artworkURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return artworkURL
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

            VStack(spacing: 10) {
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundColor(.white.opacity(0.86))

                Text(String(fallbackTitle.prefix(1)).uppercased())
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white.opacity(0.52))
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
