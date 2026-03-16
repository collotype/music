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
    
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var durationObserver: NSKeyValueObservation?
    
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
            debugLog("Unable to resolve URL for track: \(track.displayTitle)")
            currentTrack = nil
            isPlaying = false
            return false
        }
        
        debugLog("Load track: \(track.displayTitle) from \(url.lastPathComponent)")
        
        currentTrack = track
        currentTime = 0
        duration = 0
        
        let newPlayerItem = AVPlayerItem(url: url)
        playerItem = newPlayerItem
        durationObserver = nil
        
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
        
        durationObserver = newPlayerItem.observe(\.duration, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                let seconds = item.duration.seconds
                self?.duration = seconds.isFinite ? max(seconds, 0) : 0
            }
        }
        
        return true
    }
    
    func playTrack(_ track: Track) {
        debugLog("playTrack called for: \(track.displayTitle)")
        
        guard load(track: track) else { return }
        
        DataManager.shared.markTrackPlayed(track)
        play()
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
    
    func play() {
        guard let player else {
            debugLog("Play requested without a loaded player")
            return
        }
        
        debugLog("Play pressed")
        player.play()
        if playbackSpeed != 1.0 {
            player.rate = playbackSpeed
        }
        isPlaying = true
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
        currentTrack = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        playerItem = nil
    }
    
    deinit {
        durationObserver = nil
        if let player, let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        NotificationCenter.default.removeObserver(self)
    }
}
