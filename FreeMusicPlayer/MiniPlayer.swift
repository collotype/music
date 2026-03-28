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

    private let backgroundCornerRadius: CGFloat = 22
    private let rowHeight: CGFloat = 64
    
    var body: some View {
        miniPlayerRow
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        debugLog(
                            "Mini player row height: \(Int(proxy.size.height.rounded())) background container height: \(Int(proxy.size.height.rounded())) safe area inset: \(Int(proxy.safeAreaInsets.bottom.rounded())) final rendered frame: \(Int(proxy.frame(in: .global).height.rounded()))"
                        )
                    }
                    .onChange(of: audioPlayer.currentTrack?.id) { _ in
                        debugLog(
                            "Mini player row height updated: \(Int(proxy.size.height.rounded())) safe area inset: \(Int(proxy.safeAreaInsets.bottom.rounded()))"
                        )
                    }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            debugLog("Mini player layout state: \(audioPlayer.currentTrack?.displayTitle ?? "none")")
            debugLog("Mini player background metrics: cornerRadius=\(Int(backgroundCornerRadius)), rowHeight=\(Int(rowHeight))")
        }
        .onChange(of: audioPlayer.currentTrack?.id) { _ in
            debugLog("Mini player layout state updated: \(audioPlayer.currentTrack?.displayTitle ?? "none")")
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

            Image(systemName: getHeartIcon())
                .foregroundColor(getHeartColor())
                .font(.system(size: 20))
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
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .center)
        .background {
            ZStack {
                TrackArtworkBackdrop(
                    track: audioPlayer.currentTrack,
                    fallbackPalette: .cardFallback,
                    cornerRadius: backgroundCornerRadius
                )
                .opacity(0.5)

                RoundedRectangle(cornerRadius: backgroundCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.78)

                RoundedRectangle(cornerRadius: backgroundCornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.18))

                RoundedRectangle(cornerRadius: backgroundCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: backgroundCornerRadius, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: backgroundCornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.24), radius: 20, x: 0, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: backgroundCornerRadius, style: .continuous))
        .onTapGesture {
            debugLog("Mini player tapped")
            withAnimation(.spring(response: 0.3)) {
                showPlayer = true
            }
        }
    }
    
    func getHeartIcon() -> String {
        guard let track = audioPlayer.currentTrack else { return "heart" }

        return dataManager.isTrackSaved(track) ? "heart.fill" : "heart"
    }
    
    func getHeartColor() -> Color {
        guard let track = audioPlayer.currentTrack else { return .white.opacity(0.5) }

        return dataManager.isTrackSaved(track) ? .red : .white.opacity(0.5)
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
