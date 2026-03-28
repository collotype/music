//
//  MyWaveViewModel.swift
//  FreeMusicPlayer
//
//  Main-actor bridge between My Wave recommendation services and the Home UI.
//

import Combine
import Foundation

@MainActor
final class MyWaveViewModel: ObservableObject {
    @Published private(set) var items: [MyWaveRecommendationItem] = []
    @Published private(set) var summaryLine: String = "Personalized from your listening activity."
    @Published private(set) var generatedAt: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isShowingCachedData = false
    @Published var errorMessage: String?

    private let dataManager: DataManager
    private let audioPlayer: AudioPlayer
    private let recommendationService: MyWaveRecommendationService

    private var hasLoaded = false
    private var signalObservationTask: Task<Void, Never>?
    private var refreshDebounceTask: Task<Void, Never>?

    init(
        dataManager: DataManager = .shared,
        audioPlayer: AudioPlayer = .shared,
        recommendationService: MyWaveRecommendationService = .shared
    ) {
        self.dataManager = dataManager
        self.audioPlayer = audioPlayer
        self.recommendationService = recommendationService
        observeMyWaveSignals()
    }

    deinit {
        signalObservationTask?.cancel()
        refreshDebounceTask?.cancel()
    }

    var hasRecommendations: Bool {
        !items.isEmpty
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        let currentSettings = dataManager.settings.myWaveSettings
        if let cachedSnapshot = await recommendationService.cachedRecommendations(matching: currentSettings) {
            apply(snapshot: cachedSnapshot, isCached: true)
        }

        await refresh(showLoadingState: items.isEmpty)
    }

    func refresh(showLoadingState: Bool = false) async {
        if showLoadingState {
            isLoading = items.isEmpty
        }
        isRefreshing = !items.isEmpty
        errorMessage = nil

        let context = MyWaveRecommendationContext(
            libraryTracks: dataManager.tracks,
            favoriteArtists: dataManager.favoriteArtists,
            currentTrack: audioPlayer.currentTrack,
            settings: dataManager.settings.myWaveSettings
        )
        let snapshot = await recommendationService.recommendations(for: context)
        apply(snapshot: snapshot, isCached: false)
    }

    func playPrimaryRecommendation() async {
        guard let firstItem = items.first else { return }
        await play(item: firstItem)
    }

    func play(item: MyWaveRecommendationItem) async {
        errorMessage = nil

        switch item.source {
        case .libraryTrack:
            guard let track = item.track else { return }
            let contextTracks = items.compactMap(\.track)

            if contextTracks.count > 1 {
                _ = audioPlayer.playTrack(track, in: contextTracks, contextName: "home:mywave")
            } else {
                _ = audioPlayer.playTrack(track)
            }
        case .onlineResult:
            guard let result = item.onlineResult else { return }

            do {
                try await OnlineTrackActionHelper.play(
                    result: result,
                    within: items.compactMap(\.onlineResult),
                    contextName: "home:mywave",
                    dataManager: dataManager,
                    audioPlayer: audioPlayer
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func apply(snapshot: MyWaveRecommendationSnapshot, isCached: Bool) {
        items = snapshot.items
        summaryLine = snapshot.summaryLine
        generatedAt = snapshot.generatedAt
        isLoading = false
        isRefreshing = false
        isShowingCachedData = isCached
    }

    private func observeMyWaveSignals() {
        signalObservationTask = Task { [weak self] in
            guard let self else { return }

            for await _ in NotificationCenter.default.notifications(named: .myWaveSignalsDidChange) {
                guard !Task.isCancelled else { return }
                self.enqueueRefresh()
            }
        }
    }

    private func enqueueRefresh() {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }

            await self.refresh(showLoadingState: false)
        }
    }
}
