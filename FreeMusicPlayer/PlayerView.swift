//
//  PlayerView.swift
//  FreeMusicPlayer
//
//  Full screen player.
//

import SwiftUI

struct PlayerView: View {
    @EnvironmentObject var audioPlayer: AudioPlayer
    @Binding var isPresented: Bool
    @State private var showLyrics: Bool = false
    @State private var showEQ: Bool = false
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.7, green: 0.15, blue: 0.15),
                    Color(red: 0.2, green: 0.05, blue: 0.05),
                    Color.black
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                playerHeader
                Spacer()
                albumArt
                Spacer()
                playerControls
            }
        }
        .sheet(isPresented: $showEQ) {
            PlayerPlaceholderSheet(
                title: "Equalizer",
                description: "The button is wired up and ready for a real EQ screen."
            )
        }
        .sheet(isPresented: $showLyrics) {
            PlayerPlaceholderSheet(
                title: "Lyrics",
                description: "Lyrics mode is toggled and ready for future integration."
            )
        }
    }
    
    var playerHeader: some View {
        HStack {
            Button {
                debugLog("Player dismiss button pressed")
                withAnimation(.spring(response: 0.3)) {
                    isPresented = false
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text("NOW PLAYING")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            
            Spacer()
            
            Button {
                debugLog("Player EQ button pressed")
                showEQ = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
    
    var albumArt: some View {
        VStack(spacing: 20) {
            ZStack {
                if let currentTrack = audioPlayer.currentTrack {
                    TrackArtworkView(track: currentTrack, size: 320, cornerRadius: 24, showsSourceBadge: false)
                        .aspectRatio(1, contentMode: .fit)
                        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.8, green: 0.2, blue: 0.2),
                                        Color(red: 0.3, green: 0.1, blue: 0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .aspectRatio(1, contentMode: .fit)
                            .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)

                        Image(systemName: "music.note")
                            .font(.system(size: 80))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            
            VStack(spacing: 8) {
                Text(audioPlayer.currentTrack?.displayTitle ?? "Unknown Track")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(audioPlayer.currentTrack?.displayArtist ?? "Unknown Artist")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            HStack(spacing: 24) {
                Button {
                    debugLog("Player previous button pressed")
                    audioPlayer.playPrevious()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                Button {
                    debugLog("Player play/pause button pressed")
                    audioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                Button {
                    debugLog("Player next button pressed")
                    audioPlayer.playNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
    }
    
    var playerControls: some View {
        VStack(spacing: 20) {
            progressSection
            extraControls
            Spacer(minLength: 20)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }
    
    var progressSection: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .frame(width: progressWidth(geometry.size.width), height: 4)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let percent = max(0, min(1, value.location.x / geometry.size.width))
                            audioPlayer.seek(to: percent * audioPlayer.duration)
                        }
                )
            }
            .frame(height: 20)
            
            HStack {
                Text(formatTime(audioPlayer.currentTime))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                
                Spacer()
                
                Text(formatTime(audioPlayer.duration))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
    
    func progressWidth(_ totalWidth: CGFloat) -> CGFloat {
        guard audioPlayer.duration > 0 else { return 0 }
        let percent = audioPlayer.currentTime / audioPlayer.duration
        return CGFloat(percent) * totalWidth
    }
    
    var extraControls: some View {
        HStack(spacing: 0) {
            Button {
                debugLog("Player shuffle button pressed")
                audioPlayer.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 22))
                    .foregroundColor(audioPlayer.isShuffle ? .red : .white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .frame(width: 60)
            
            Button {
                debugLog("Player speed button pressed")
                audioPlayer.cyclePlaybackSpeed()
            } label: {
                Text(String(format: "%.2gx", audioPlayer.playbackSpeed))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .frame(width: 50)
            
            Spacer()
            
            Button {
                debugLog("Player lyrics button pressed")
                showLyrics = true
            } label: {
                Image(systemName: "text.bubble")
                    .font(.system(size: 20))
                    .foregroundColor(showLyrics ? .red : .white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .frame(width: 50)
            
            Spacer()
            
            Button {
                debugLog("Player repeat button pressed")
                audioPlayer.toggleRepeat()
            } label: {
                Image(systemName: repeatIcon)
                    .font(.system(size: 22))
                    .foregroundColor(audioPlayer.repeatMode != .off ? .red : .white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .frame(width: 60)
        }
    }
    
    var repeatIcon: String {
        switch audioPlayer.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let mins = Int(time) / 60
        let secs = Int(time.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", mins, secs)
    }
}

struct PlayerPlaceholderSheet: View {
    let title: String
    let description: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(description)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    PlayerView(isPresented: .constant(true))
        .environmentObject(AudioPlayer.shared)
}
