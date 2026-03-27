//
//  OnlineArtistDetailView.swift
//  FreeMusicPlayer
//
//  Native SoundCloud artist browsing inside the app.
//

import SwiftUI

struct OnlineArtistDetailView: View {
    let artist: OnlineArtistResult

    @State private var tracks: [OnlineTrackResult] = []
    @State private var isLoading: Bool = false
    @State private var loadingErrorMessage: String?
    @State private var actionStatusMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                artistHeader

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

                    if isLoading && tracks.isEmpty {
                        SearchStatusRow(
                            icon: "arrow.triangle.2.circlepath",
                            title: "Loading \(artist.name)...",
                            subtitle: "Fetching tracks from \(artist.providerDisplayName)."
                        )
                    } else if let loadingErrorMessage, tracks.isEmpty {
                        SearchStatusRow(
                            icon: "wifi.exclamationmark",
                            title: "Couldn't load tracks",
                            subtitle: loadingErrorMessage,
                            actionTitle: "Retry",
                            action: retryLoadTracks
                        )
                    } else if tracks.isEmpty {
                        SearchStatusRow(
                            icon: "music.note.list",
                            title: "No tracks found",
                            subtitle: "No playable \(artist.providerDisplayName) tracks were returned for this artist."
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
            .padding(.bottom, 120)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: artist.id) {
            await loadTracks()
        }
    }

    private var artistHeader: some View {
        HStack(spacing: 16) {
            OnlineResultArtworkView(
                provider: artist.provider,
                artworkURLString: artist.imageURL,
                fallbackSystemImage: "person.fill",
                size: 92,
                cornerRadius: 46
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(artist.name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text(artist.providerDisplayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))

                Text(trackSummaryText)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.42))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var trackSummaryText: String {
        if isLoading && tracks.isEmpty {
            return "Loading artist tracks."
        }

        if loadingErrorMessage != nil && tracks.isEmpty {
            return "Artist tracks are unavailable right now."
        }

        if tracks.isEmpty {
            return "No tracks loaded yet."
        }

        return "\(tracks.count) track\(tracks.count == 1 ? "" : "s")"
    }

    private func retryLoadTracks() {
        Task {
            await loadTracks()
        }
    }

    @MainActor
    private func loadTracks() async {
        guard !isLoading else { return }

        isLoading = true
        loadingErrorMessage = nil
        actionStatusMessage = nil
        tracks = []

        defer {
            isLoading = false
        }

        do {
            let fetchedTracks = try await OnlineMusicService.shared.fetchSoundCloudTracks(for: artist)
            guard !Task.isCancelled else { return }

            tracks = fetchedTracks
            debugLog("Loaded online artist tracks: \(artist.name) = \(fetchedTracks.count)")
        } catch {
            guard !Task.isCancelled else { return }

            loadingErrorMessage = error.localizedDescription
            debugLog("Online artist load error for \(artist.providerArtistID): \(error.localizedDescription)")
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

    @State private var downloadingIDs: Set<String> = []
    @State private var savingIDs: Set<String> = []

    var body: some View {
        ForEach(results) { result in
            OnlineSearchTrackRow(
                result: result,
                isPerformingPrimaryAction: downloadingIDs.contains(result.id),
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
            statusMessage = result.playbackUnavailableMessage
            return
        }

        debugLog("Online result play pressed: \(result.title) [\(result.providerTrackID)]")
        downloadingIDs.insert(result.id)
        statusMessage = nil
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
                        debugLog("Playback success for \(result.providerTrackID) via \(resolvedStream.streamType)")
                    } else {
                        statusMessage = audioPlayer.playbackErrorMessage ?? "Playback failed for the selected SoundCloud track."
                    }
                }
            } catch {
                debugLog("Playback error for \(result.providerTrackID): \(error.localizedDescription)")
                await MainActor.run {
                    statusMessage = error.localizedDescription
                }
            }
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
                let tempURL = try await OnlineMusicService.shared.downloadAudio(for: result)
                let savedTrack = try await MainActor.run {
                    try dataManager.saveDownloadedOnlineTrack(result, from: tempURL)
                }

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
