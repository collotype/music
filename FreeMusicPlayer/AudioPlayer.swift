//
//  AudioPlayer.swift
//  FreeMusicPlayer
//
//  AVFoundation-backed audio playback.
//

import AVFoundation
import Foundation
import MediaPlayer
import SwiftUI
import UIKit

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
    private var artworkDataTask: URLSessionDataTask?
    private var nowPlayingArtworkIdentifier: String?
    private var playbackContext: PlaybackContext?
    private var playbackSequence: PlaybackSequence = .standalone
    private var queueResumeContext: QueueResumeContext?
    private var shouldPrioritizeQueueOnNextAdvance = false

    enum RepeatMode {
        case off
        case all
        case one
    }

    private struct PlaybackContext {
        enum Kind: String {
            case playlist
            case collection
        }

        let name: String
        let kind: Kind
        let tracks: [Track]
    }

    private enum PlaybackSequence: String {
        case standalone
        case context
        case queue
    }

    private struct QueueResumeContext {
        let context: PlaybackContext
        let anchorTrack: Track
    }

    private var tracks: [Track] {
        DataManager.shared.tracks
    }

    init() {
        configureAudioSession()
        setupNotifications()
        setupRemoteTransportControls()
        updateRemoteCommandAvailability()
        clearNowPlayingInfo()
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

    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self, self.currentTrack != nil else { return .noActionableNowPlayingItem }
            return self.play() ? .success : .commandFailed
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.currentTrack != nil else { return .noActionableNowPlayingItem }
            self.pause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, self.currentTrack != nil else { return .noActionableNowPlayingItem }
            self.togglePlayPause()
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, self.currentTrack != nil else { return .noActionableNowPlayingItem }
            self.playNext()
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, self.currentTrack != nil else { return .noActionableNowPlayingItem }
            self.playPrevious()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  self.currentTrack != nil,
                  let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .noActionableNowPlayingItem
            }

            self.seek(to: event.positionTime)
            return .success
        }

        DispatchQueue.main.async {
            UIApplication.shared.beginReceivingRemoteControlEvents()
        }
    }

    private func updateRemoteCommandAvailability() {
        let commandCenter = MPRemoteCommandCenter.shared()
        let hasActiveTrack = currentTrack != nil
        let hasSeekableTrack = hasActiveTrack && max(duration, currentTrack?.duration ?? 0) > 0

        commandCenter.playCommand.isEnabled = hasActiveTrack
        commandCenter.pauseCommand.isEnabled = hasActiveTrack
        commandCenter.togglePlayPauseCommand.isEnabled = hasActiveTrack
        commandCenter.nextTrackCommand.isEnabled = hasActiveTrack
        commandCenter.previousTrackCommand.isEnabled = hasActiveTrack
        commandCenter.changePlaybackPositionCommand.isEnabled = hasSeekableTrack
    }

    private func updateNowPlayingInfo(refreshArtwork: Bool = false) {
        guard let track = currentTrack else {
            clearNowPlayingInfo()
            return
        }

        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = track.displayTitle
        info[MPMediaItemPropertyArtist] = track.displayArtist

        let normalizedAlbum = track.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if normalizedAlbum.isEmpty {
            info.removeValue(forKey: MPMediaItemPropertyAlbumTitle)
        } else {
            info[MPMediaItemPropertyAlbumTitle] = normalizedAlbum
        }

        let resolvedDuration = duration > 0 ? duration : max(track.duration, 0)
        if resolvedDuration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = resolvedDuration
        } else {
            info.removeValue(forKey: MPMediaItemPropertyPlaybackDuration)
        }

        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(currentTime, 0)
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackSpeed : 0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = playbackSpeed
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        updateRemoteCommandAvailability()

        if refreshArtwork {
            refreshNowPlayingArtwork(for: track)
        }
    }

    private func refreshNowPlayingArtwork(for track: Track) {
        let identifier = "\(track.id)::\(track.artworkCacheIdentity)"
        guard identifier != nowPlayingArtworkIdentifier else { return }

        nowPlayingArtworkIdentifier = identifier
        artworkDataTask?.cancel()
        artworkDataTask = nil

        guard let artworkURL = resolvedArtworkURL(for: track) else {
            applyNowPlayingArtwork(nil)
            return
        }

        if artworkURL.isFileURL {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let image = (try? Data(contentsOf: artworkURL)).flatMap(UIImage.init(data:))

                DispatchQueue.main.async {
                    guard let self,
                          self.nowPlayingArtworkIdentifier == identifier,
                          self.currentTrack?.id == track.id else {
                        return
                    }

                    self.applyNowPlayingArtwork(image)
                }
            }
            return
        }

        let task = URLSession.shared.dataTask(with: artworkURL) { [weak self] data, _, _ in
            let image = data.flatMap(UIImage.init(data:))

            DispatchQueue.main.async {
                guard let self,
                      self.nowPlayingArtworkIdentifier == identifier,
                      self.currentTrack?.id == track.id else {
                    return
                }

                self.artworkDataTask = nil
                self.applyNowPlayingArtwork(image)
            }
        }

        artworkDataTask = task
        task.resume()
    }

    private func applyNowPlayingArtwork(_ image: UIImage?) {
        guard currentTrack != nil else { return }

        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]

        if let finalImage = image ?? UIImage(named: "PlayerAvatar") {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: finalImage.size) { _ in
                finalImage
            }
        } else {
            info.removeValue(forKey: MPMediaItemPropertyArtwork)
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlayingInfo() {
        artworkDataTask?.cancel()
        artworkDataTask = nil
        nowPlayingArtworkIdentifier = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        updateRemoteCommandAvailability()
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
            self?.updateNowPlayingInfo()
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let interruptionType = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch interruptionType {
        case .began:
            debugLog("Audio session interruption began")
            pause()
        case .ended:
            debugLog("Audio session interruption ended")

            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume), currentTrack != nil {
                    _ = play()
                }
            }
        @unknown default:
            break
        }
    }

    @objc private func playerDidFinishPlaying(_ notification: Notification) {
        guard let finishedItem = notification.object as? AVPlayerItem,
              finishedItem == playerItem else {
            return
        }

        debugLog("Current track ended: \(currentTrack?.displayTitle ?? "Unknown Track")")
        debugLog("Autoplay source context: \(playbackSequenceDescription)")

        switch repeatMode {
        case .one:
            seek(to: 0)
            play()
        case .all, .off:
            let didAdvance = playNext(reason: "track-ended")
            if !didAdvance {
                isPlaying = false
                updateNowPlayingInfo()
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

        let logSource = url.isFileURL ? url.lastPathComponent : url.absoluteString
        debugLog("Load track: \(track.displayTitle) from \(logSource)")
        playbackErrorMessage = nil

        currentTrack = track
        currentTime = 0
        duration = 0
        updateNowPlayingInfo(refreshArtwork: true)

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
                self?.updateNowPlayingInfo()
            }
        }

        return true
    }

    @discardableResult
    func playTrack(_ track: Track) -> Bool {
        return playTrack(track, contextTracks: nil, contextName: nil, updateContext: true)
    }

    @discardableResult
    func playTrack(_ track: Track, in contextTracks: [Track], contextName: String) -> Bool {
        return playTrack(track, contextTracks: contextTracks, contextName: contextName, updateContext: true)
    }

    @discardableResult
    private func playTrack(
        _ track: Track,
        contextTracks: [Track]?,
        contextName: String?,
        updateContext: Bool
    ) -> Bool {
        debugLog("playTrack called for: \(track.displayTitle)")

        if updateContext {
            if let contextTracks,
               let contextName {
                updatePlaybackContext(with: contextTracks, name: contextName)
                queueResumeContext = nil
                playbackSequence = .context
                shouldPrioritizeQueueOnNextAdvance = false
            } else {
                clearPlaybackContext()
                queueResumeContext = nil
                playbackSequence = .standalone
                shouldPrioritizeQueueOnNextAdvance = false
            }
        }

        manualQueue.removeAll { $0.id == track.id }

        guard load(track: track) else { return false }

        DataManager.shared.markTrackPlayed(track)
        let didStartPlayback = play()
        debugLog("Playback \(didStartPlayback ? "success" : "failure") for track: \(track.displayTitle)")
        return didStartPlayback
    }

    func syncCurrentTrackReference(with track: Track) {
        guard currentTrack?.sourceID != nil,
              currentTrack?.sourceID == track.sourceID else {
            return
        }

        currentTrack = track
        debugLog("Current track reference synced to saved library track: \(track.displayTitle)")
        updateNowPlayingInfo(refreshArtwork: true)
    }

    func refreshPlaybackContextIfNeeded(name: String, tracks: [Track]) {
        let deduplicatedContextTracks = deduplicatedTracks(from: tracks)

        if playbackContext?.name == name {
            guard !deduplicatedContextTracks.isEmpty else {
                clearPlaybackContext()
                return
            }

            playbackContext = PlaybackContext(
                name: name,
                kind: playbackContextKind(for: name),
                tracks: deduplicatedContextTracks
            )
            debugLog("Playback context refreshed: \(name) with \(deduplicatedContextTracks.count) tracks")
        }

        if let queueResumeContext, queueResumeContext.context.name == name {
            guard !deduplicatedContextTracks.isEmpty else {
                self.queueResumeContext = nil
                return
            }

            self.queueResumeContext = QueueResumeContext(
                context: PlaybackContext(
                    name: name,
                    kind: playbackContextKind(for: name),
                    tracks: deduplicatedContextTracks
                ),
                anchorTrack: resolvedTrackForPlayback(queueResumeContext.anchorTrack)
            )
            debugLog("Queue resume context refreshed: \(name) with \(deduplicatedContextTracks.count) tracks")
        }
    }

    private func getFileURL(for track: Track) -> URL? {
        guard let filename = track.fileURL else { return nil }
        return AppFileManager.shared.resolveStoredFileURL(for: filename)
    }

    private func resolvedURL(for track: Track) -> URL? {
        if let fileURL = track.fileURL,
           let parsedURL = URL(string: fileURL),
           parsedURL.scheme != nil {
            let scheme = parsedURL.scheme?.lowercased()
            if parsedURL.isFileURL || scheme == "http" || scheme == "https" {
                return parsedURL
            }

            debugLog("Rejected unsupported playback URL for \(track.displayTitle): \(parsedURL.absoluteString)")
            return nil
        }

        return getFileURL(for: track)
    }

    @discardableResult
    func play() -> Bool {
        guard let player else {
            failPlayback("Playback failed because no player item is loaded.", track: currentTrack)
            return false
        }

        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            debugLog("Audio session activation failed: \(error.localizedDescription)")
        }

        debugLog("Playback start: \(currentTrack?.displayTitle ?? "Unknown Track")")
        player.play()
        if playbackSpeed != 1.0 {
            player.rate = playbackSpeed
        }
        isPlaying = true
        playbackErrorMessage = nil
        updateNowPlayingInfo()
        return true
    }

    func pause() {
        debugLog("Pause pressed")
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func togglePlayPause() {
        debugLog("Toggle play/pause")
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    @discardableResult
    func playNext(reason: String = "manual-next") -> Bool {
        debugLog("Play next track requested: \(reason)")
        debugLog("Autoplay decision path: source=\(playbackSequenceDescription), queued=\(manualQueue.count)")

        if playbackSequence == .queue {
            if let queuedTrack = nextQueuedTrack() {
                debugLog("Next track selected from queue: \(queuedTrack.displayTitle)")
                let didStartPlayback = startQueuedPlayback(for: queuedTrack)
                debugLog("Playback of next track \(didStartPlayback ? "succeeded" : "failed"): \(queuedTrack.displayTitle)")
                return didStartPlayback
            }

            if let resumedTrack = resumedTrackAfterQueue() {
                let resumeContextName = queueResumeContext?.context.name ?? "unknown"
                debugLog("Queue exhausted; resuming context \(resumeContextName) with \(resumedTrack.displayTitle)")
                let didStartPlayback = startResumedContextPlayback(for: resumedTrack)
                debugLog("Playback of next track \(didStartPlayback ? "succeeded" : "failed"): \(resumedTrack.displayTitle)")
                return didStartPlayback
            }
        }

        if shouldPrioritizeQueueOnNextAdvance,
           let queuedTrack = nextQueuedTrack() {
            debugLog("Next track selected from explicit queue override: \(queuedTrack.displayTitle)")
            let didStartPlayback = startQueuedPlayback(for: queuedTrack)
            debugLog("Playback of next track \(didStartPlayback ? "succeeded" : "failed"): \(queuedTrack.displayTitle)")
            return didStartPlayback
        }

        if let contextTrack = nextTrackInPlaybackContext() {
            debugLog("Next track selected from context \(playbackContext?.name ?? "unknown"): \(contextTrack.displayTitle)")
            let didStartPlayback = playTrack(
                contextTrack,
                contextTracks: playbackContext?.tracks,
                contextName: playbackContext?.name,
                updateContext: false
            )
            playbackSequence = .context
            queueResumeContext = nil
            debugLog("Playback of next track \(didStartPlayback ? "succeeded" : "failed"): \(contextTrack.displayTitle)")
            return didStartPlayback
        }

        if let queuedTrack = nextQueuedTrack() {
            debugLog("Next track selected from queue: \(queuedTrack.displayTitle)")
            let didStartPlayback = startQueuedPlayback(for: queuedTrack)
            debugLog("Playback of next track \(didStartPlayback ? "succeeded" : "failed"): \(queuedTrack.displayTitle)")
            return didStartPlayback
        }

        if let libraryTrack = fallbackNextLibraryTrack() {
            debugLog("Next track selected from library fallback: \(libraryTrack.displayTitle)")
            playbackSequence = .standalone
            queueResumeContext = nil
            let didStartPlayback = playTrack(libraryTrack, contextTracks: nil, contextName: nil, updateContext: false)
            debugLog("Playback of next track \(didStartPlayback ? "succeeded" : "failed"): \(libraryTrack.displayTitle)")
            return didStartPlayback
        }

        debugLog("No next track available after \(reason)")
        return false
    }

    @discardableResult
    func playPrevious() -> Bool {
        debugLog("Play previous track")

        if currentTime > 3 {
            seek(to: 0)
            return true
        }

        if playbackSequence == .queue,
           let anchorTrack = queueResumeContext?.anchorTrack {
            debugLog("Returning to queue anchor track: \(anchorTrack.displayTitle)")
            playbackSequence = .context
            let didStartPlayback = startResumedContextPlayback(for: anchorTrack, stepBackwards: false)
            debugLog("Playback of previous track \(didStartPlayback ? "succeeded" : "failed"): \(anchorTrack.displayTitle)")
            return didStartPlayback
        }

        if let contextTrack = previousTrackInPlaybackContext() {
            debugLog("Previous track selected from context \(playbackContext?.name ?? "unknown"): \(contextTrack.displayTitle)")
            let didStartPlayback = playTrack(
                contextTrack,
                contextTracks: playbackContext?.tracks,
                contextName: playbackContext?.name,
                updateContext: false
            )
            playbackSequence = .context
            debugLog("Playback of previous track \(didStartPlayback ? "succeeded" : "failed"): \(contextTrack.displayTitle)")
            return didStartPlayback
        }

        guard let libraryTrack = fallbackPreviousLibraryTrack() else {
            debugLog("No previous track available")
            return false
        }

        debugLog("Previous track selected from library fallback: \(libraryTrack.displayTitle)")
        playbackSequence = .standalone
        let didStartPlayback = playTrack(libraryTrack, contextTracks: nil, contextName: nil, updateContext: false)
        debugLog("Playback of previous track \(didStartPlayback ? "succeeded" : "failed"): \(libraryTrack.displayTitle)")
        return didStartPlayback
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clampedTime = max(0, min(time, duration))
        debugLog("Seek to time: \(clampedTime)")
        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: cmTime)
        currentTime = clampedTime
        updateNowPlayingInfo()
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
        shouldPrioritizeQueueOnNextAdvance = true
    }

    func addTrackToQueue(_ track: Track) {
        debugLog("Add track to queue: \(track.displayTitle)")
        manualQueue.removeAll { $0.id == track.id }
        manualQueue.append(track)
        shouldPrioritizeQueueOnNextAdvance = true
    }

    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = max(0.5, min(2.0, speed))
        debugLog("Set playback speed: \(playbackSpeed)")

        if isPlaying {
            player?.rate = playbackSpeed
        }

        updateNowPlayingInfo()
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
        clearPlaybackContext()
        queueResumeContext = nil
        playbackSequence = .standalone
        shouldPrioritizeQueueOnNextAdvance = false
        currentTrack = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        playerItem = nil
        playbackErrorMessage = nil
        clearNowPlayingInfo()
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
            updateNowPlayingInfo()
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
        clearNowPlayingInfo()
    }

    private func nextQueuedTrack() -> Track? {
        guard !manualQueue.isEmpty else { return nil }
        return resolvedTrackForPlayback(manualQueue.removeFirst())
    }

    private func updatePlaybackContext(with tracks: [Track], name: String) {
        let contextTracks = deduplicatedTracks(from: tracks)
        guard !contextTracks.isEmpty else {
            clearPlaybackContext()
            return
        }

        playbackContext = PlaybackContext(
            name: name,
            kind: playbackContextKind(for: name),
            tracks: contextTracks
        )
        debugLog("Playback context updated: \(name) with \(contextTracks.count) tracks")
    }

    private func clearPlaybackContext() {
        guard playbackContext != nil else { return }
        debugLog("Playback context cleared")
        playbackContext = nil
    }

    private func nextTrackInPlaybackContext() -> Track? {
        guard let playbackContext,
              playbackSequence == .context else { return nil }
        return adjacentTrack(in: playbackContext.tracks, step: 1, anchorTrack: currentTrack, requiresAnchorMatch: true)
    }

    private func previousTrackInPlaybackContext() -> Track? {
        guard let playbackContext,
              playbackSequence == .context else { return nil }
        return adjacentTrack(in: playbackContext.tracks, step: -1, anchorTrack: currentTrack, requiresAnchorMatch: true)
    }

    private func fallbackNextLibraryTrack() -> Track? {
        adjacentTrack(in: tracks, step: 1, anchorTrack: currentTrack)
    }

    private func fallbackPreviousLibraryTrack() -> Track? {
        adjacentTrack(in: tracks, step: -1, anchorTrack: currentTrack)
    }

    private func adjacentTrack(
        in trackList: [Track],
        step: Int,
        anchorTrack: Track?,
        requiresAnchorMatch: Bool = false
    ) -> Track? {
        let resolvedTracks = deduplicatedTracks(from: trackList)
        guard !resolvedTracks.isEmpty else { return nil }

        if isShuffle {
            let candidates = resolvedTracks.filter { candidate in
                guard let anchorTrack else { return true }
                return !matchesPlaybackIdentity(candidate, anchorTrack)
            }

            if let shuffledTrack = candidates.randomElement() {
                return resolvedTrackForPlayback(shuffledTrack)
            }

            return requiresAnchorMatch ? nil : (repeatMode == .all ? resolvedTrackForPlayback(resolvedTracks.first!) : nil)
        }

        guard let anchorTrack else {
            guard !requiresAnchorMatch else { return nil }
            return resolvedTrackForPlayback(step >= 0 ? resolvedTracks.first! : resolvedTracks.last!)
        }

        guard let currentIndex = resolvedTracks.firstIndex(where: { matchesPlaybackIdentity($0, anchorTrack) }) else {
            guard !requiresAnchorMatch else { return nil }
            return resolvedTrackForPlayback(step >= 0 ? resolvedTracks.first! : resolvedTracks.last!)
        }

        let nextIndex = currentIndex + step
        if resolvedTracks.indices.contains(nextIndex) {
            return resolvedTrackForPlayback(resolvedTracks[nextIndex])
        }

        guard repeatMode == .all else { return nil }
        return resolvedTrackForPlayback(step >= 0 ? resolvedTracks.first! : resolvedTracks.last!)
    }

    private func startQueuedPlayback(for track: Track) -> Bool {
        if playbackSequence != .queue,
           let playbackContext,
           let currentTrack {
            queueResumeContext = QueueResumeContext(context: playbackContext, anchorTrack: currentTrack)
            debugLog("Queue override armed from \(playbackContext.name) after \(currentTrack.displayTitle)")
        }

        playbackSequence = .queue
        shouldPrioritizeQueueOnNextAdvance = false
        return playTrack(track, contextTracks: nil, contextName: nil, updateContext: false)
    }

    private func startResumedContextPlayback(for track: Track, stepBackwards: Bool = true) -> Bool {
        guard let queueResumeContext else {
            playbackSequence = .standalone
            return playTrack(track, contextTracks: nil, contextName: nil, updateContext: false)
        }

        playbackSequence = .context
        let didStartPlayback = playTrack(
            stepBackwards ? track : queueResumeContext.anchorTrack,
            contextTracks: queueResumeContext.context.tracks,
            contextName: queueResumeContext.context.name,
            updateContext: false
        )

        if didStartPlayback {
            self.queueResumeContext = nil
        }

        return didStartPlayback
    }

    private func resumedTrackAfterQueue() -> Track? {
        guard let queueResumeContext else { return nil }
        return adjacentTrack(
            in: queueResumeContext.context.tracks,
            step: 1,
            anchorTrack: queueResumeContext.anchorTrack,
            requiresAnchorMatch: true
        )
    }

    private func playbackContextKind(for name: String) -> PlaybackContext.Kind {
        name.hasPrefix("playlist:") ? .playlist : .collection
    }

    private var playbackSequenceDescription: String {
        switch playbackSequence {
        case .standalone:
            return "standalone"
        case .context:
            if let playbackContext {
                return "\(playbackContext.kind.rawValue):\(playbackContext.name)"
            }
            return "context:missing"
        case .queue:
            if let queueResumeContext {
                return "queue(resume:\(queueResumeContext.context.name))"
            }
            return "queue"
        }
    }

    private func resolvedTrackForPlayback(_ track: Track) -> Track {
        if let resolvedTrack = tracks.first(where: { matchesPlaybackIdentity($0, track) }) {
            return resolvedTrack
        }

        return track
    }

    private func deduplicatedTracks(from tracks: [Track]) -> [Track] {
        var seenTrackIDs: Set<String> = []
        var uniqueTracks: [Track] = []

        for track in tracks {
            let identity = track.sourceID ?? track.id
            guard seenTrackIDs.insert(identity).inserted else { continue }
            uniqueTracks.append(track)
        }

        return uniqueTracks
    }

    private func matchesPlaybackIdentity(_ left: Track, _ right: Track) -> Bool {
        if left.id == right.id {
            return true
        }

        if let leftSourceID = left.sourceID,
           let rightSourceID = right.sourceID,
           leftSourceID == rightSourceID {
            return true
        }

        return false
    }

    private func resolvedArtworkURL(for track: Track) -> URL? {
        track.localArtworkURL ?? track.resolvedRemoteArtworkURL
    }

    deinit {
        durationObserver = nil
        statusObserver = nil
        artworkDataTask?.cancel()
        if let player, let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        NotificationCenter.default.removeObserver(self)
    }
}
