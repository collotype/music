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

    private let backgroundCornerRadius: CGFloat = 18
    private let outerHorizontalPadding: CGFloat = 8
    private let rowVerticalPadding: CGFloat = 6
    
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
                .padding(.horizontal, outerHorizontalPadding)

            miniPlayerRow
                .padding(.horizontal, outerHorizontalPadding)
                .padding(.top, 1)
                .padding(.bottom, 2)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                debugLog(
                                    "Mini player row height: \(Int(proxy.size.height.rounded())) background container height: \(Int(proxy.size.height.rounded())) safe area inset: \(Int(proxy.safeAreaInsets.bottom.rounded()))"
                                )
                            }
                            .onChange(of: audioPlayer.currentTrack?.id) { _ in
                                debugLog(
                                    "Mini player row height updated: \(Int(proxy.size.height.rounded())) safe area inset: \(Int(proxy.safeAreaInsets.bottom.rounded()))"
                                )
                            }
                    }
                }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        debugLog(
                            "Mini player parent container height: \(Int(proxy.size.height.rounded()))"
                        )
                    }
            }
        }
        .onAppear {
            debugLog("Mini player layout state: \(audioPlayer.currentTrack?.displayTitle ?? "none")")
            debugLog("Mini player background metrics: cornerRadius=\(Int(backgroundCornerRadius)), horizontalPadding=\(Int(outerHorizontalPadding)), verticalPadding=\(Int(rowVerticalPadding))")
        }
        .onChange(of: audioPlayer.currentTrack?.id) { _ in
            debugLog("Mini player layout state updated: \(audioPlayer.currentTrack?.displayTitle ?? "none")")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            debugLog("Mini player tapped")
            withAnimation(.spring(response: 0.3)) {
                showPlayer = true
            }
        }
    }

    private var miniPlayerRow: some View {
        HStack(spacing: 12) {
            Group {
                if let currentTrack = audioPlayer.currentTrack {
                    TrackArtworkView(track: currentTrack, size: 48, cornerRadius: 8, showsSourceBadge: true)
                } else {
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
                }
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

            Spacer(minLength: 12)

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
        .padding(.vertical, rowVerticalPadding)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            ZStack {
                TrackArtworkBackdrop(
                    track: audioPlayer.currentTrack,
                    fallbackPalette: .cardFallback,
                    cornerRadius: backgroundCornerRadius
                )
                .opacity(0.86)

                RoundedRectangle(cornerRadius: backgroundCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.82)

                RoundedRectangle(cornerRadius: backgroundCornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.12))

                RoundedRectangle(cornerRadius: backgroundCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: backgroundCornerRadius, style: .continuous))
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
