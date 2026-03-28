//
//  OnlineTrackActionHelper.swift
//  FreeMusicPlayer
//
//  Shared online track playback and save actions.
//

import Foundation

enum OnlineTrackActionHelper {
    static func play(
        result: OnlineTrackResult,
        within contextResults: [OnlineTrackResult] = [],
        contextName: String? = nil,
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
        let orderedPlayableResults = orderedPlayableResults(
            from: contextResults.isEmpty ? [result] : contextResults,
            selectedResultID: result.id
        )
        let initialContextTracks = await resolveInitialContextTracks(
            for: orderedPlayableResults,
            selectedResult: result,
            selectedTrack: streamingTrack,
            dataManager: dataManager
        )

        let didStartPlayback = await MainActor.run {
            if let contextName, !initialContextTracks.isEmpty {
                return audioPlayer.playTrack(
                    streamingTrack,
                    in: initialContextTracks,
                    contextName: contextName
                )
            }

            return audioPlayer.playTrack(streamingTrack)
        }

        guard didStartPlayback else {
            let failureMessage = await MainActor.run {
                audioPlayer.playbackErrorMessage ?? "Playback failed for the selected SoundCloud track."
            }
            throw OnlineMusicServiceError.unsupportedSource(failureMessage)
        }

        if let contextName, orderedPlayableResults.count > initialContextTracks.count {
            Task(priority: .utility) {
                await progressivelyHydratePlaybackContext(
                    named: contextName,
                    orderedResults: orderedPlayableResults,
                    seedTracks: initialContextTracks,
                    selectedResult: result,
                    selectedTrack: streamingTrack,
                    dataManager: dataManager,
                    audioPlayer: audioPlayer
                )
            }
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

    private static func orderedPlayableResults(
        from results: [OnlineTrackResult],
        selectedResultID: String
    ) -> [OnlineTrackResult] {
        var seenIDs: Set<String> = []
        var playableResults: [OnlineTrackResult] = []

        for result in results {
            guard result.supportsInAppPlayback else { continue }
            guard seenIDs.insert(result.id).inserted else { continue }
            playableResults.append(result)
        }

        if playableResults.contains(where: { $0.id == selectedResultID }) {
            return playableResults
        }

        return playableResults
    }

    private static func resolveInitialContextTracks(
        for orderedResults: [OnlineTrackResult],
        selectedResult: OnlineTrackResult,
        selectedTrack: Track,
        dataManager: DataManager
    ) async -> [Track] {
        guard orderedResults.count > 1,
              let selectedIndex = orderedResults.firstIndex(where: { $0.id == selectedResult.id }) else {
            return [selectedTrack]
        }

        let lowerBound = max(0, selectedIndex - 2)
        let upperBound = min(orderedResults.count - 1, selectedIndex + 2)
        let initialResults = Array(orderedResults[lowerBound...upperBound])
        var resolvedTracksByID: [String: Track] = [selectedResult.id: selectedTrack]

        for result in initialResults where result.id != selectedResult.id {
            if let track = await resolvePlaybackTrack(for: result, dataManager: dataManager) {
                resolvedTracksByID[result.id] = track
            }
        }

        return initialResults.compactMap { resolvedTracksByID[$0.id] }
    }

    private static func progressivelyHydratePlaybackContext(
        named contextName: String,
        orderedResults: [OnlineTrackResult],
        seedTracks: [Track],
        selectedResult: OnlineTrackResult,
        selectedTrack: Track,
        dataManager: DataManager,
        audioPlayer: AudioPlayer
    ) async {
        var resolvedTracksByID: [String: Track] = [selectedResult.id: selectedTrack]
        let selectedIndex = orderedResults.firstIndex(where: { $0.id == selectedResult.id }) ?? 0
        let lowerBound = max(0, selectedIndex - 2)
        let upperBound = min(orderedResults.count - 1, selectedIndex + 2)
        let prioritizedResults =
            Array(orderedResults.dropFirst(upperBound + 1)) +
            Array(orderedResults.prefix(lowerBound))

        for track in seedTracks {
            resolvedTracksByID[track.sourceID ?? track.id] = track
        }

        for result in prioritizedResults {
            if resolvedTracksByID[result.id] == nil {
                if let resolvedTrack = await resolvePlaybackTrack(for: result, dataManager: dataManager) {
                    resolvedTracksByID[result.id] = resolvedTrack
                }
            }

            let resolvedOrderedTracks = orderedResults.compactMap { resolvedTracksByID[$0.id] }
            guard resolvedOrderedTracks.count >= 2 else { continue }

            await MainActor.run {
                audioPlayer.refreshPlaybackContextIfNeeded(
                    name: contextName,
                    tracks: resolvedOrderedTracks
                )
            }
        }
    }

    private static func resolvePlaybackTrack(
        for result: OnlineTrackResult,
        dataManager: DataManager
    ) async -> Track? {
        if let savedTrack = await MainActor.run(body: {
            dataManager.track(withSourceID: result.id)
        }) {
            return savedTrack
        }

        guard let resolvedStream = try? await OnlineMusicService.shared.resolvePlaybackStream(for: result) else {
            return nil
        }

        return await MainActor.run {
            dataManager.makeStreamingTrack(from: result, streamURL: resolvedStream.url)
        }
    }
}
