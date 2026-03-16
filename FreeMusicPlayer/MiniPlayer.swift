//
//  MiniPlayer.swift
//  FreeMusicPlayer
//
//  Compact player shown above the tab bar.
//

import SwiftUI

struct MiniPlayer: View {
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var dataManager: DataManager
    @Binding var showPlayer: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.1))
            
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [Color.red, Color(red: 0.3, green: 0.1, blue: 0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "music.note")
                        .foregroundColor(.white.opacity(0.5))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(audioPlayer.currentTrack?.displayTitle ?? "Nothing selected")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(audioPlayer.currentTrack?.displayArtist ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button {
                    debugLog("Mini player favorite button pressed")
                    if let track = audioPlayer.currentTrack {
                        dataManager.toggleFavorite(track)
                    }
                } label: {
                    Image(systemName: getHeartIcon())
                        .foregroundColor(getHeartColor())
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                
                Button {
                    debugLog("Mini player play/pause button pressed")
                    audioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Color(red: 0.12, green: 0.12, blue: 0.12)
                    .opacity(0.95)
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            debugLog("Mini player tapped")
            withAnimation(.spring(response: 0.3)) {
                showPlayer = true
            }
        }
    }
    
    func getHeartIcon() -> String {
        guard let track = audioPlayer.currentTrack else { return "heart" }
        
        if dataManager.favorites.contains(track.id) {
            return "heart.fill"
        }
        
        if let sourceID = track.sourceID,
           let storedTrack = dataManager.track(withSourceID: sourceID),
           dataManager.favorites.contains(storedTrack.id) {
            return "heart.fill"
        }
        
        return "heart"
    }
    
    func getHeartColor() -> Color {
        guard let track = audioPlayer.currentTrack else { return .white.opacity(0.5) }
        
        if dataManager.favorites.contains(track.id) {
            return .red
        }
        
        if let sourceID = track.sourceID,
           let storedTrack = dataManager.track(withSourceID: sourceID),
           dataManager.favorites.contains(storedTrack.id) {
            return .red
        }
        
        return .white.opacity(0.5)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        MiniPlayer(showPlayer: .constant(false))
            .environmentObject(AudioPlayer.shared)
            .environmentObject(DataManager.shared)
    }
}
