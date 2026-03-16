//
//  AudioPlayer.swift
//  FreeMusicPlayer
//
//  Аудиоплеер с AVFoundation
//

import Foundation
import AVFoundation
import SwiftUI

class AudioPlayer: ObservableObject {
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
    
    enum RepeatMode {
        case off
        case all
        case one
    }
    
    private var tracks: [Track] {
        DataManager.shared.tracks
    }
    
    init() {
        setupTimeObserver()
        setupNotifications()
    }
    
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }
    
    @objc private func playerDidFinishPlaying() {
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
    
    func load(track: Track) {
        guard let url = resolvedURL(for: track) else { return }
        
        currentTrack = track
        let playerItem = AVPlayerItem(url: url)
        self.playerItem = playerItem
        
        if player == nil {
            player = AVPlayer(playerItem: playerItem)
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }
        
        player?.volume = volume
        player?.rate = playbackSpeed
        
        duration = 0
        currentTime = 0
        
        // Получение длительности
        playerItem?.observe(\.duration, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                self?.duration = CMTimeGetSeconds(item.duration)
            }
        }
    }
    
    private func getFileURL(for track: Track) -> URL? {
        // Поиск файла в документах приложения
        if let filename = track.fileURL {
            let docsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            return docsPath?.appendingPathComponent(filename)
        }
        return nil
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
        player?.rate = playbackSpeed
        isPlaying = true
    }
    
    func pause() {
        player?.rate = 0
        isPlaying = false
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func playNext() {
        guard !tracks.isEmpty else { return }
        
        if let currentIndex = tracks.firstIndex(where: { $0.id == currentTrack?.id }) {
            let nextIndex: Int
            if isShuffle {
                nextIndex = Int.random(in: 0..<tracks.count)
            } else {
                nextIndex = (currentIndex + 1) % tracks.count
            }
            load(track: tracks[nextIndex])
            play()
        } else {
            load(track: tracks[0])
            play()
        }
    }
    
    func playPrevious() {
        guard !tracks.isEmpty else { return }
        
        if currentTime > 3 {
            seek(to: 0)
        } else if let currentIndex = tracks.firstIndex(where: { $0.id == currentTrack?.id }) {
            let prevIndex = currentIndex <= 0 ? tracks.count - 1 : currentIndex - 1
            load(track: tracks[prevIndex])
            play()
        }
    }
    
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime)
        currentTime = time
    }
    
    func setVolume(_ newVolume: Float) {
        volume = max(0, min(1, newVolume))
        player?.volume = volume
    }
    
    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = max(0.5, min(2.0, speed))
        player?.rate = isPlaying ? playbackSpeed : 0
    }
    
    func toggleShuffle() {
        isShuffle.toggle()
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
    }
    
    func stop() {
        pause()
        currentTrack = nil
        currentTime = 0
        duration = 0
    }
    
    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        NotificationCenter.default.removeObserver(self)
    }
}
