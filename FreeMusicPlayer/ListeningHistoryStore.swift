//
//  ListeningHistoryStore.swift
//  FreeMusicPlayer
//
//  Persistent user listening and recommendation impression history.
//

import Foundation

private struct ListeningHistoryPayload: Codable {
    var events: [ListeningEvent]
    var impressions: [MyWaveImpression]

    static let empty = ListeningHistoryPayload(events: [], impressions: [])
}

actor ListeningHistoryStore {
    static let shared = ListeningHistoryStore()

    private let historyFileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let maxEventCount: Int
    private let maxImpressionCount: Int

    private var payload: ListeningHistoryPayload?

    init(
        historyFileURL: URL = AppFileManager.shared.dataFileURL(named: "listening_history.json"),
        maxEventCount: Int = 2500,
        maxImpressionCount: Int = 800
    ) {
        self.historyFileURL = historyFileURL
        self.maxEventCount = maxEventCount
        self.maxImpressionCount = maxImpressionCount
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        AppFileManager.shared.prepareDirectories()
    }

    func snapshot() -> ListeningHistorySnapshot {
        let loadedPayload = loadPayloadIfNeeded()
        return ListeningHistorySnapshot(
            events: loadedPayload.events,
            impressions: loadedPayload.impressions
        )
    }

    func record(
        kind: ListeningEventKind,
        track: TrackTasteSnapshot,
        occurredAt: Date = Date(),
        sourceContext: String? = nil,
        playbackPosition: TimeInterval? = nil,
        playbackDuration: TimeInterval? = nil,
        completionRatio: Double? = nil,
        notify: Bool = true
    ) async {
        let event = ListeningEvent(
            kind: kind,
            occurredAt: occurredAt,
            track: track,
            sourceContext: sourceContext,
            playbackPosition: playbackPosition,
            playbackDuration: playbackDuration,
            completionRatio: completionRatio
        )

        await record(event, notify: notify)
    }

    func record(_ event: ListeningEvent, notify: Bool = true) async {
        var loadedPayload = loadPayloadIfNeeded()
        loadedPayload.events.insert(event, at: 0)
        if loadedPayload.events.count > maxEventCount {
            loadedPayload.events = Array(loadedPayload.events.prefix(maxEventCount))
        }

        payload = loadedPayload
        persist(payload: loadedPayload)

        if notify {
            await postSignalsDidChangeNotification()
        }
    }

    func recordImpressions(
        for items: [MyWaveRecommendationItem],
        shownAt: Date = Date()
    ) async {
        guard !items.isEmpty else { return }

        var loadedPayload = loadPayloadIfNeeded()
        let impressions = items.map { item in
            MyWaveImpression(shownAt: shownAt, track: item.tasteSnapshot)
        }

        loadedPayload.impressions.insert(contentsOf: impressions, at: 0)
        if loadedPayload.impressions.count > maxImpressionCount {
            loadedPayload.impressions = Array(loadedPayload.impressions.prefix(maxImpressionCount))
        }

        payload = loadedPayload
        persist(payload: loadedPayload)
    }

    func clear() async {
        payload = .empty
        persist(payload: .empty)
        await postSignalsDidChangeNotification()
    }

    private func loadPayloadIfNeeded() -> ListeningHistoryPayload {
        if let payload {
            return payload
        }

        guard let data = try? Data(contentsOf: historyFileURL),
              let decodedPayload = try? decoder.decode(ListeningHistoryPayload.self, from: data) else {
            payload = .empty
            return .empty
        }

        payload = decodedPayload
        return decodedPayload
    }

    private func persist(payload: ListeningHistoryPayload) {
        AppFileManager.shared.prepareDirectories()
        guard let encodedPayload = try? encoder.encode(payload) else {
            return
        }

        try? encodedPayload.write(to: historyFileURL, options: .atomic)
    }

    @MainActor
    private func postSignalsDidChangeNotification() {
        NotificationCenter.default.post(name: .myWaveSignalsDidChange, object: nil)
    }
}
