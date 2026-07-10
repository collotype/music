//
//  MiniPlayer.swift
//  FreeMusicPlayer
//
//  Compact player shown above the tab bar.
//

import SwiftUI

enum MiniPlayerVisualStyle: String, CaseIterable, Hashable {
    case compact
    case record

    var title: String {
        switch self {
        case .compact: return "Compact"
        case .record: return "Record"
        }
    }

    var systemImage: String {
        switch self {
        case .compact: return "rectangle.compress.vertical"
        case .record: return "record.circle"
        }
    }
}

struct MiniPlayer: View {
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var dataManager: DataManager
    @Binding var showPlayer: Bool
    @AppStorage("miniPlayer.visualStyle") private var visualStyleRawValue: String = MiniPlayerVisualStyle.compact.rawValue

    private let backgroundCornerRadius: CGFloat = 22
    private let rowHeight: CGFloat = 64

    private var currentTrackIsLiked: Bool {
        guard let track = audioPlayer.currentTrack else { return false }
        return dataManager.isTrackLiked(track)
    }

    private var visualStyle: MiniPlayerVisualStyle {
        get { MiniPlayerVisualStyle(rawValue: visualStyleRawValue) ?? .compact }
        nonmutating set { visualStyleRawValue = newValue.rawValue }
    }

    var body: some View {
        Group {
            switch visualStyle {
            case .compact:
                compactMiniPlayer
            case .record:
                recordMiniPlayer
            }
        }
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

    private var compactMiniPlayer: some View {
        HStack(spacing: 12) {
            compactArtwork

            VStack(alignment: .leading, spacing: 2) {
                Text(audioPlayer.currentTrack?.displayTitle ?? "Nothing selected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.ink)
                    .lineLimit(1)

                Text(audioPlayer.currentTrack?.displayArtist ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.mutedInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            styleMenu

            Button {
                debugLog("Mini player play/pause button pressed")
                audioPlayer.togglePlayPause()
            } label: {
                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24))
                    .foregroundColor(AppTheme.paper)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(AppTheme.accent)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .center)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: backgroundCornerRadius, style: .continuous)
                    .fill(AppTheme.elevatedPanel)

                RoundedRectangle(cornerRadius: backgroundCornerRadius, style: .continuous)
                    .stroke(AppTheme.line, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: backgroundCornerRadius, style: .continuous))
        }
        .overlay(alignment: .bottom) {
            PlaybackProgressBar(
                progress: playbackProgress,
                barHeight: 3,
                activeColor: AppTheme.accent,
                inactiveColor: Color.white.opacity(0.08),
                thumbColor: .clear,
                maxWidth: nil,
                showsThumb: false,
                animationDuration: 0.45,
                onSeek: nil
            )
            .frame(height: 10)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: backgroundCornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: backgroundCornerRadius, style: .continuous))
        .onTapGesture {
            debugLog("Mini player tapped")
            withAnimation(.spring(response: 0.3)) {
                showPlayer = true
            }
        }
    }

    private var recordMiniPlayer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(audioPlayer.currentTrack?.displayArtist ?? "FreeMusic")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.mutedInk)
                    .lineLimit(1)

                Spacer()

                styleMenu
            }

            HStack(spacing: 14) {
                MiniVinylArtwork(track: audioPlayer.currentTrack, size: 70)

                VStack(alignment: .leading, spacing: 5) {
                    Text(audioPlayer.currentTrack?.displayTitle ?? "Nothing selected")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.ink)
                        .lineLimit(1)

                    Text(timeLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.mutedInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    debugLog("Mini player play/pause button pressed")
                    audioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(AppTheme.paper)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(AppTheme.accent))
                }
                .buttonStyle(.plain)
            }

            PlaybackProgressBar(
                progress: playbackProgress,
                barHeight: 3,
                activeColor: AppTheme.accent,
                inactiveColor: Color.white.opacity(0.08),
                thumbColor: .clear,
                maxWidth: nil,
                showsThumb: false,
                animationDuration: 0.45,
                onSeek: nil
            )
            .frame(height: 8)
            .allowsHitTesting(false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppTheme.elevatedPanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppTheme.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture {
            debugLog("Mini player tapped")
            withAnimation(.spring(response: 0.3)) {
                showPlayer = true
            }
        }
    }

    private var compactArtwork: some View {
        Group {
            if let currentTrack = audioPlayer.currentTrack {
                TrackArtworkView(track: currentTrack, size: 48, cornerRadius: 10, showsSourceBadge: true)
                    .overlay(alignment: .topTrailing) {
                        if dataManager.isTrackLiked(currentTrack) {
                            Circle()
                                .fill(AppTheme.accent)
                                .frame(width: 10, height: 10)
                                .offset(x: 3, y: -3)
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.panel)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(AppTheme.mutedInk)
                    )
            }
        }
    }

    private var styleMenu: some View {
        Menu {
            ForEach(MiniPlayerVisualStyle.allCases, id: \.self) { style in
                Button {
                    visualStyle = style
                } label: {
                    Label(style.title, systemImage: style.systemImage)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppTheme.mutedInk)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }

    private var timeLine: String {
        "\(formatMiniTime(audioPlayer.currentTime)) / \(formatMiniTime(audioPlayer.duration))"
    }

    private var playbackProgress: Double {
        resolvedPlaybackProgress(
            currentTime: audioPlayer.currentTime,
            duration: audioPlayer.duration
        )
    }

    private func formatMiniTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let mins = Int(time) / 60
        let secs = Int(time.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", mins, secs)
    }
}

struct PlaybackProgressBar: View {
    let progress: Double
    let barHeight: CGFloat
    let activeColor: Color
    let inactiveColor: Color
    let thumbColor: Color
    let maxWidth: CGFloat?
    let showsThumb: Bool
    let animationDuration: Double
    let onSeek: ((Double) -> Void)?

    private let thumbSize: CGFloat = 14

    private var clampedProgress: CGFloat {
        CGFloat(min(max(progress, 0), 1))
    }

    private var hitAreaHeight: CGFloat {
        max(barHeight + (showsThumb ? 16 : 10), 22)
    }

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let totalWidth = min(maxWidth ?? availableWidth, availableWidth)
            let fillWidth = totalWidth * clampedProgress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(inactiveColor)
                    .frame(width: totalWidth, height: barHeight)

                Capsule()
                    .fill(activeColor)
                    .frame(width: max(fillWidth, fillWidth > 0 ? barHeight : 0), height: barHeight)
                    .shadow(color: activeColor.opacity(showsThumb ? 0.18 : 0.08), radius: showsThumb ? 8 : 4)

                if showsThumb {
                    Circle()
                        .fill(thumbColor)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: .black.opacity(0.28), radius: 8, y: 2)
                        .offset(x: thumbOffset(fillWidth: fillWidth, totalWidth: totalWidth))
                }
            }
            .frame(width: totalWidth, height: hitAreaHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let onSeek, totalWidth > 0 else { return }
                        let percent = min(max(value.location.x / totalWidth, 0), 1)
                        onSeek(percent)
                    }
            )
        }
        .frame(height: hitAreaHeight)
        .animation(.linear(duration: animationDuration), value: clampedProgress)
    }

    private func thumbOffset(fillWidth: CGFloat, totalWidth: CGFloat) -> CGFloat {
        let clampedOffset = min(max(fillWidth - (thumbSize / 2), 0), max(totalWidth - thumbSize, 0))
        return clampedOffset
    }
}

func resolvedPlaybackProgress(currentTime: TimeInterval, duration: TimeInterval) -> Double {
    guard duration > 0, currentTime.isFinite, duration.isFinite else {
        return 0
    }

    return min(max(currentTime / duration, 0), 1)
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        MiniPlayer(showPlayer: .constant(false))
            .environmentObject(AudioPlayer.shared)
            .environmentObject(DataManager.shared)
    }
}
