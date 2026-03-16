//
//  AudioPlayer.swift
//  FreeMusicPlayer
//
//  AVFoundation-backed audio playback.
//

import AVFoundation
import Foundation
import SwiftUI

final class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()

    @Published var currentTrack: Track?
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 0.7
    @Published var isShuffle: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var playbackSpeed: Float = 1.0
    @Published var playbackErrorMessage: String?

    private let fileManager = FileManager.default
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var durationObserver: NSKeyValueObservation?
    private var statusObserver: NSKeyValueObservation?
    private var manualQueue: [Track] = []

    enum RepeatMode {
        case off
        case all
        case one
    }

    private var tracks: [Track] {
        DataManager.shared.tracks
    }

    init() {
        configureAudioSession()
        setupNotifications()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            debugLog("Audio session configuration failed: \(error.localizedDescription)")
        }
    }

    private func setupTimeObserver() {
        guard let player else { return }

        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = max(time.seconds, 0)
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    @objc private func playerDidFinishPlaying(_ notification: Notification) {
        guard let finishedItem = notification.object as? AVPlayerItem,
              finishedItem == playerItem else {
            return
        }

        debugLog("Current item finished playing")

        switch repeatMode {
        case .one:
            seek(to: 0)
            play()
        case .all:
            playNext()
        case .off:
            if isShuffle {
                playNext()
            } else {
                isPlaying = false
            }
        }
    }

    @discardableResult
    func load(track: Track) -> Bool {
        guard let url = resolvedURL(for: track) else {
            failPlayback("Playback failed because the track URL could not be resolved.", track: track)
            return false
        }

        if url.isFileURL && !fileManager.fileExists(atPath: url.path) {
            failPlayback("Playback failed because the local audio file is missing.", track: track)
            return false
        }

        debugLog("Load track: \(track.displayTitle) from \(url.lastPathComponent)")
        playbackErrorMessage = nil

        currentTrack = track
        currentTime = 0
        duration = 0

        let newPlayerItem = AVPlayerItem(url: url)
        playerItem = newPlayerItem
        durationObserver = nil
        statusObserver = nil

        if let player {
            player.replaceCurrentItem(with: newPlayerItem)
        } else {
            player = AVPlayer(playerItem: newPlayerItem)
        }

        guard let player else {
            debugLog("AVPlayer was not created")
            isPlaying = false
            return false
        }

        player.volume = volume
        player.automaticallyWaitsToMinimizeStalling = true
        setupTimeObserver()

        statusObserver = newPlayerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                self?.handlePlayerItemStatus(item.status, error: item.error)
            }
        }

        durationObserver = newPlayerItem.observe(\.duration, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                let seconds = item.duration.seconds
                self?.duration = seconds.isFinite ? max(seconds, 0) : 0
            }
        }

        return true
    }

    @discardableResult
    func playTrack(_ track: Track) -> Bool {
        debugLog("playTrack called for: \(track.displayTitle)")
        manualQueue.removeAll { $0.id == track.id }

        guard load(track: track) else { return false }

        DataManager.shared.markTrackPlayed(track)
        return play()
    }

    private func getFileURL(for track: Track) -> URL? {
        guard let filename = track.fileURL else { return nil }
        return AppFileManager.shared.resolveStoredFileURL(for: filename)
    }

    private func resolvedURL(for track: Track) -> URL? {
        if let fileURL = track.fileURL,
           let remoteURL = URL(string: fileURL),
           remoteURL.scheme != nil {
            return remoteURL
        }

        return getFileURL(for: track)
    }

    @discardableResult
    func play() -> Bool {
        guard let player else {
            failPlayback("Playback failed because no player item is loaded.", track: currentTrack)
            return false
        }

        debugLog("Playback start: \(currentTrack?.displayTitle ?? "Unknown Track")")
        player.play()
        if playbackSpeed != 1.0 {
            player.rate = playbackSpeed
        }
        isPlaying = true
        playbackErrorMessage = nil
        return true
    }

    func pause() {
        debugLog("Pause pressed")
        player?.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        debugLog("Toggle play/pause")
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func playNext() {
        if let queuedTrack = nextQueuedTrack() {
            debugLog("Play queued track next: \(queuedTrack.displayTitle)")
            playTrack(queuedTrack)
            return
        }

        guard !tracks.isEmpty else { return }

        debugLog("Play next track")

        if let currentIndex = tracks.firstIndex(where: { $0.id == currentTrack?.id }) {
            let nextIndex: Int
            if isShuffle {
                nextIndex = Int.random(in: 0..<tracks.count)
            } else {
                nextIndex = (currentIndex + 1) % tracks.count
            }
            playTrack(tracks[nextIndex])
        } else {
            playTrack(tracks[0])
        }
    }

    func playPrevious() {
        guard !tracks.isEmpty else { return }

        debugLog("Play previous track")

        if currentTime > 3 {
            seek(to: 0)
        } else if let currentIndex = tracks.firstIndex(where: { $0.id == currentTrack?.id }) {
            let prevIndex = currentIndex <= 0 ? tracks.count - 1 : currentIndex - 1
            playTrack(tracks[prevIndex])
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clampedTime = max(0, min(time, duration))
        debugLog("Seek to time: \(clampedTime)")
        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: cmTime)
        currentTime = clampedTime
    }

    func setVolume(_ newVolume: Float) {
        volume = max(0, min(1, newVolume))
        debugLog("Set volume: \(volume)")
        player?.volume = volume
    }

    func queueTrackNext(_ track: Track) {
        debugLog("Queue track next: \(track.displayTitle)")
        manualQueue.removeAll { $0.id == track.id }
        manualQueue.insert(track, at: 0)
    }

    func addTrackToQueue(_ track: Track) {
        debugLog("Add track to queue: \(track.displayTitle)")
        manualQueue.removeAll { $0.id == track.id }
        manualQueue.append(track)
    }

    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = max(0.5, min(2.0, speed))
        debugLog("Set playback speed: \(playbackSpeed)")

        if isPlaying {
            player?.rate = playbackSpeed
        }
    }

    func cyclePlaybackSpeed() {
        let availableSpeeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]
        let currentIndex = availableSpeeds.firstIndex(of: playbackSpeed) ?? 1
        let nextIndex = (currentIndex + 1) % availableSpeeds.count
        setPlaybackSpeed(availableSpeeds[nextIndex])
    }

    func toggleShuffle() {
        isShuffle.toggle()
        debugLog("Shuffle set to: \(isShuffle)")
    }

    func toggleRepeat() {
        switch repeatMode {
        case .off:
            repeatMode = .all
        case .all:
            repeatMode = .one
        case .one:
            repeatMode = .off
        }

        debugLog("Repeat mode changed")
    }

    func stop() {
        debugLog("Stop playback")
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        manualQueue.removeAll()
        currentTrack = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        playerItem = nil
        playbackErrorMessage = nil
    }

    func clearPlaybackError() {
        playbackErrorMessage = nil
    }

    private func handlePlayerItemStatus(_ status: AVPlayerItem.Status, error: Error?) {
        switch status {
        case .failed:
            failPlayback(
                "Playback failed\(error.flatMap { ": \($0.localizedDescription)" } ?? ".")",
                track: currentTrack
            )
        case .readyToPlay:
            debugLog("Player item ready: \(currentTrack?.displayTitle ?? "Unknown Track")")
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func failPlayback(_ message: String, track: Track?) {
        debugLog("Playback failure for \(track?.displayTitle ?? "Unknown Track"): \(message)")
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playerItem = nil
        statusObserver = nil
        currentTime = 0
        duration = 0
        playbackErrorMessage = message
        currentTrack = track
        isPlaying = false
    }

    private func nextQueuedTrack() -> Track? {
        guard !manualQueue.isEmpty else { return nil }
        return manualQueue.removeFirst()
    }

    deinit {
        durationObserver = nil
        statusObserver = nil
        if let player, let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        NotificationCenter.default.removeObserver(self)
    }
}
