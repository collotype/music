//
//  PlayerView.swift
//  FreeMusicPlayer
//
//  Full screen player.
//

import AVFoundation
import SwiftUI

struct PlayerView: View {
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var router: AppRouter
    @Binding var isPresented: Bool
    @State private var showLyricsSheet: Bool = false
    @State private var showQueueSheet: Bool = false
    @State private var showEQ: Bool = false
    @State private var isTogglingFavorite = false
    @State private var favoriteActionErrorMessage: String?
    
    var body: some View {
        ZStack {
            playerBackground
            
            VStack(spacing: 0) {
                playerHeader
                albumArt
                    .padding(.top, 12)
                Spacer(minLength: 56)
                playerControls
            }
        }
        .onAppear {
            debugLog("Player background stack composed: artwork backdrop -> blur -> dark tint -> foreground UI")
        }
        .onChange(of: audioPlayer.currentTrack?.id) { _ in
            debugLog("Player background updated for track: \(audioPlayer.currentTrack?.displayTitle ?? "none")")
        }
        .sheet(isPresented: $showEQ) {
            PlayerPlaceholderSheet(
                title: "Equalizer",
                description: "The button is wired up and ready for a real EQ screen."
            )
        }
        .sheet(isPresented: $showLyricsSheet) {
            lyricsSheet
        }
        .sheet(isPresented: $showQueueSheet) {
            UpNextQueueSheet()
        }
        .alert("Library Unavailable", isPresented: favoriteActionErrorIsPresented) {
            Button("OK", role: .cancel) {
                favoriteActionErrorMessage = nil
            }
        } message: {
            Text(favoriteActionErrorMessage ?? "This track could not be updated in your library.")
        }
    }

    @ViewBuilder
    private var lyricsSheet: some View {
        if #available(iOS 16.4, *) {
            PlayerLyricsSheet()
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        } else {
            PlayerLyricsSheet()
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var playerBackground: some View {
        ZStack {
            TrackArtworkBackdrop(
                track: audioPlayer.currentTrack,
                fallbackPalette: .playerFallback
            )
            .scaleEffect(1.08)
            .blur(radius: 34)
            .opacity(0.96)

            TrackArtworkBackdrop(
                track: audioPlayer.currentTrack,
                fallbackPalette: .playerFallback
            )
            .opacity(0.34)

            Rectangle()
                .fill(Color.black.opacity(0.18))

            LinearGradient(
                colors: [
                    Color.black.opacity(0.22),
                    Color.black.opacity(0.34),
                    Color.black.opacity(0.58),
                    Color.black.opacity(0.74)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
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

            HStack(spacing: 14) {
                Button {
                    debugLog("Player queue button pressed")
                    showQueueSheet = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.84))

                        if !audioPlayer.queuedTracks.isEmpty {
                            Text("\(audioPlayer.queuedTracks.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white))
                                .offset(x: 10, y: -8)
                        }
                    }
                }
                .buttonStyle(.plain)

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
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
    
    var albumArt: some View {
        VStack(spacing: 20) {
            ZStack {
                if let currentTrack = audioPlayer.currentTrack {
                    TrackArtworkBackdrop(
                        track: currentTrack,
                        fallbackPalette: .playerFallback,
                        cornerRadius: 34
                    )
                    .frame(width: 340, height: 340)
                    .blur(radius: 42)
                    .opacity(0.68)

                    ZStack {
                        TrackArtworkView(track: currentTrack, size: 320, cornerRadius: 24, showsSourceBadge: false)
                            .aspectRatio(1, contentMode: .fit)

                        artworkHint
                    }
                    .frame(width: 320, height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                    .contentShape(RoundedRectangle(cornerRadius: 24))
                    .onTapGesture {
                        guard dataManager.settings.showLyrics else { return }
                        showLyricsSheet = true
                    }
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
                    .frame(width: 320, height: 320)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            
            VStack(spacing: 8) {
                Text(audioPlayer.currentTrack?.displayTitle ?? "Unknown Track")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                if let currentArtistRoute {
                    Button {
                        openArtistPage(currentArtistRoute)
                    } label: {
                        HStack(spacing: 6) {
                            Text(currentArtistRoute.artistName)
                                .lineLimit(1)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(audioPlayer.currentTrack?.displayArtist ?? "Unknown Artist")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
    }
    
    var playerControls: some View {
        VStack(spacing: 24) {
            progressSection
            primaryControls
            secondaryControls
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 46)
    }
    
    var progressSection: some View {
        VStack(spacing: 10) {
            PlaybackProgressBar(
                progress: playbackProgress,
                barHeight: 6,
                activeColor: .white.opacity(0.98),
                inactiveColor: .white.opacity(0.18),
                thumbColor: .white,
                maxWidth: 312,
                showsThumb: true,
                animationDuration: 0.12
            ) { percent in
                audioPlayer.seek(to: percent * audioPlayer.duration)
            }
            .frame(height: 26)

            HStack {
                Text(formatTime(audioPlayer.currentTime))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                
                Spacer()
                
                Text(formatTime(audioPlayer.duration))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: 312)
        }
        .frame(maxWidth: .infinity)
    }

    var primaryControls: some View {
        HStack(spacing: 0) {
            playbackModeButton
            Spacer(minLength: 6)
            previousButton
            Spacer(minLength: 6)
            playPauseButton
            Spacer(minLength: 6)
            nextButton
            Spacer(minLength: 6)
            favoriteButton
        }
    }

    var secondaryControls: some View {
        HStack(spacing: 14) {
            secondaryControlChip(
                title: "Up Next",
                value: audioPlayer.queuedTracks.isEmpty ? "Empty" : "\(audioPlayer.queuedTracks.count)",
                systemImage: "list.bullet"
            ) {
                debugLog("Player secondary queue button pressed")
                showQueueSheet = true
            }

            secondaryControlChip(
                title: "Speed",
                value: playbackSpeedLabel,
                systemImage: "speedometer"
            ) {
                debugLog("Player speed cycle button pressed")
                audioPlayer.cyclePlaybackSpeed()
            }
        }
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let mins = Int(time) / 60
        let secs = Int(time.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", mins, secs)
    }

    private var playbackProgress: Double {
        resolvedPlaybackProgress(
            currentTime: audioPlayer.currentTime,
            duration: audioPlayer.duration
        )
    }

    private var currentArtistRoute: OnlineArtistRoute? {
        audioPlayer.currentTrack?.onlineArtistRoute
    }

    private var currentTrackIsSaved: Bool {
        guard let currentTrack = audioPlayer.currentTrack else { return false }
        return dataManager.isTrackSaved(currentTrack)
    }

    private var canToggleFavoriteForCurrentTrack: Bool {
        guard let currentTrack = audioPlayer.currentTrack else { return false }

        if dataManager.isTrackSaved(currentTrack) {
            return true
        }

        return currentTrack.source == .soundcloud && currentTrack.sourceID != nil
    }

    private var favoriteButtonSystemImage: String {
        guard canToggleFavoriteForCurrentTrack else { return "heart.slash" }
        return currentTrackIsSaved ? "heart.fill" : "heart"
    }

    private var favoriteButtonTintColor: Color {
        guard canToggleFavoriteForCurrentTrack else { return .white.opacity(0.24) }
        return currentTrackIsSaved ? .red : .white.opacity(0.7)
    }

    private var favoriteButtonBackgroundColor: Color {
        guard canToggleFavoriteForCurrentTrack else { return Color.white.opacity(0.05) }
        return currentTrackIsSaved ? Color.red.opacity(0.14) : Color.white.opacity(0.08)
    }

    private var playbackModeIcon: String {
        if audioPlayer.repeatMode == .all {
            return "repeat"
        }

        switch audioPlayer.playbackMode {
        case .ordered:
            return "list.number"
        case .shuffled:
            return "shuffle"
        case .repeatOne:
            return "repeat.1"
        }
    }

    private var playbackModeTintColor: Color {
        if audioPlayer.repeatMode == .all {
            return .red
        }

        switch audioPlayer.playbackMode {
        case .ordered:
            return .white.opacity(0.78)
        case .shuffled, .repeatOne:
            return .red
        }
    }

    private var playbackModeBackgroundColor: Color {
        if audioPlayer.repeatMode == .all {
            return Color.red.opacity(0.14)
        }

        switch audioPlayer.playbackMode {
        case .ordered:
            return Color.white.opacity(0.08)
        case .shuffled, .repeatOne:
            return Color.red.opacity(0.14)
        }
    }

    private var playbackSpeedLabel: String {
        String(format: "%.2gx", Double(audioPlayer.playbackSpeed))
    }

    private var favoriteActionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { favoriteActionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    favoriteActionErrorMessage = nil
                }
            }
        )
    }

    private var playbackModeButton: some View {
        Menu {
            Button {
                audioPlayer.setPlaybackMode(.ordered)
                dataManager.setShufflePreference(false)
                dataManager.setRepeatModePreference(.off)
            } label: {
                Label("Play in order", systemImage: "list.number")
            }

            Button {
                audioPlayer.setPlaybackMode(.shuffled)
                dataManager.setShufflePreference(true)
                dataManager.setRepeatModePreference(.off)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }

            Button {
                audioPlayer.setRepeatMode(.all)
                dataManager.setShufflePreference(audioPlayer.isShuffle)
                dataManager.setRepeatModePreference(.all)
            } label: {
                Label("Repeat all", systemImage: "repeat")
            }

            Button {
                audioPlayer.setPlaybackMode(.repeatOne)
                dataManager.setShufflePreference(false)
                dataManager.setRepeatModePreference(.one)
            } label: {
                Label("Repeat one", systemImage: "repeat.1")
            }

            Divider()

            Button {
                audioPlayer.setPlaybackSpeed(0.75)
            } label: {
                Label("0.75x", systemImage: "speedometer")
            }

            Button {
                audioPlayer.setPlaybackSpeed(1.0)
            } label: {
                Label("1.0x", systemImage: "speedometer")
            }

            Button {
                audioPlayer.setPlaybackSpeed(1.25)
            } label: {
                Label("1.25x", systemImage: "speedometer")
            }

            Button {
                audioPlayer.setPlaybackSpeed(1.5)
            } label: {
                Label("1.5x", systemImage: "speedometer")
            }

            Button {
                audioPlayer.setPlaybackSpeed(2.0)
            } label: {
                Label("2.0x", systemImage: "speedometer")
            }
        } label: {
            ZStack {
                Circle()
                    .fill(playbackModeBackgroundColor)
                    .frame(width: 40, height: 40)

                Image(systemName: playbackModeIcon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(playbackModeTintColor)
            }
        }
        .buttonStyle(.plain)
    }

    private var previousButton: some View {
        Button {
            debugLog("Player previous button pressed")
            audioPlayer.playPrevious()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 46, height: 46)

                Image(systemName: "backward.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
            }
        }
        .buttonStyle(.plain)
    }

    private var playPauseButton: some View {
        Button {
            debugLog("Player play/pause button pressed")
            audioPlayer.togglePlayPause()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 74, height: 74)

                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.black)
                    .offset(x: audioPlayer.isPlaying ? 0 : 2)
            }
            .shadow(color: .black.opacity(0.24), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var nextButton: some View {
        Button {
            debugLog("Player next button pressed")
            audioPlayer.playNext()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 46, height: 46)

                Image(systemName: "forward.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
            }
        }
        .buttonStyle(.plain)
    }

    private var favoriteButton: some View {
        Button {
            toggleFavoriteForCurrentTrack()
        } label: {
            ZStack {
                Circle()
                    .fill(favoriteButtonBackgroundColor)
                    .frame(width: 40, height: 40)

                Group {
                    if isTogglingFavorite {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: favoriteButtonSystemImage)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(favoriteButtonTintColor)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canToggleFavoriteForCurrentTrack || isTogglingFavorite)
    }

    private var artworkHint: some View {
        VStack {
            Spacer()

            if dataManager.settings.showLyrics {
                HStack(spacing: 8) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 12, weight: .semibold))

                    Text("Tap artwork to open lyrics")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.82))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.42))
                )
                .padding(.bottom, 14)
            }
        }
    }

    private func secondaryControlChip(
        title: String,
        value: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                    Text(value)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.64))
                }
                Spacer(minLength: 0)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    private func openArtistPage(_ route: OnlineArtistRoute) {
        debugLog("Player artist pressed: \(route.artistName) [\(route.providerArtistID)]")

        withAnimation(.spring(response: 0.3)) {
            isPresented = false
        }

        Task { @MainActor in
            await Task.yield()
            router.openOnlineArtist(route)
        }
    }

    private func toggleFavoriteForCurrentTrack() {
        guard let currentTrack = audioPlayer.currentTrack,
              canToggleFavoriteForCurrentTrack,
              !isTogglingFavorite else {
            return
        }

        isTogglingFavorite = true
        favoriteActionErrorMessage = nil

        Task {
            defer {
                Task { @MainActor in
                    isTogglingFavorite = false
                }
            }

            do {
                let savedTrack = try await dataManager.toggleTrackSavedState(for: currentTrack)

                await MainActor.run {
                    if let savedTrack {
                        audioPlayer.syncCurrentTrackReference(with: savedTrack)
                    }
                }
            } catch {
                debugLog("Player favorite toggle failed: \(error.localizedDescription)")
                await MainActor.run {
                    favoriteActionErrorMessage = error.localizedDescription
                }
            }
        }
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

struct UpNextQueueSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var audioPlayer: AudioPlayer

    var body: some View {
        NavigationStack {
            Group {
                if audioPlayer.currentTrack == nil && audioPlayer.queuedTracks.isEmpty {
                    emptyQueueState
                } else {
                    List {
                        if let currentTrack = audioPlayer.currentTrack {
                            Section("Now Playing") {
                                QueueNowPlayingRow(track: currentTrack)
                                    .listRowBackground(Color.clear)
                            }
                        }

                        Section {
                            if audioPlayer.queuedTracks.isEmpty {
                                Text("Use Play Next or Add to Queue from track actions to build Up Next.")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 10)
                            } else {
                                ForEach(audioPlayer.queuedTracks) { track in
                                    UpNextQueueRow(track: track) {
                                        _ = audioPlayer.playQueuedTrackNow(track)
                                        dismiss()
                                    }
                                    .listRowBackground(Color.clear)
                                }
                                .onDelete(perform: deleteQueuedTracks)
                                .onMove(perform: moveQueuedTracks)
                            }
                        } header: {
                            Text("Up Next")
                        } footer: {
                            if !audioPlayer.queuedTracks.isEmpty {
                                Text("Tap a queued track to play it immediately.")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color.black)
                }
            }
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                if !audioPlayer.queuedTracks.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") {
                            audioPlayer.clearQueue()
                        }
                    }
                }
            }
        }
    }

    private var emptyQueueState: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 52))
                .foregroundColor(.white.opacity(0.2))

            Text("Queue is empty")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)

            Text("Use Play Next or Add to Queue from any track menu.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.55))
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }

    private func deleteQueuedTracks(at offsets: IndexSet) {
        let tracks = offsets.compactMap { index in
            audioPlayer.queuedTracks.indices.contains(index) ? audioPlayer.queuedTracks[index] : nil
        }

        for track in tracks {
            audioPlayer.removeQueuedTrack(track)
        }
    }

    private func moveQueuedTracks(from source: IndexSet, to destination: Int) {
        audioPlayer.moveQueuedTracks(fromOffsets: source, toOffset: destination)
    }
}

private struct QueueNowPlayingRow: View {
    let track: Track

    var body: some View {
        HStack(spacing: 12) {
            TrackArtworkView(track: track, size: 52, cornerRadius: 12, showsSourceBadge: true)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(track.displayArtist)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.58))
                    .lineLimit(1)

                Text("Playing now")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green.opacity(0.9))
            }

            Spacer()

            Text(track.formattedDuration)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.42))
        }
        .padding(.vertical, 6)
    }
}

private struct UpNextQueueRow: View {
    let track: Track
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                TrackArtworkView(track: track, size: 52, cornerRadius: 12, showsSourceBadge: true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.displayTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(track.displayArtist)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.58))
                        .lineLimit(1)
                }

                Spacer()

                Text(track.formattedDuration)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.42))
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

struct PlayerLyricsSheet: View {
    @EnvironmentObject private var audioPlayer: AudioPlayer

    var body: some View {
        NavigationStack {
            TrackLyricsView(
                track: audioPlayer.currentTrack,
                playbackTime: audioPlayer.currentTime
            )
                .navigationTitle("Lyrics")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        DismissButton()
                    }
                }
        }
    }
}

struct TrackLyricsView: View {
    let track: Track?
    let playbackTime: TimeInterval?

    init(track: Track?, playbackTime: TimeInterval? = nil) {
        self.track = track
        self.playbackTime = playbackTime
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TrackLyricsContentView(
                track: track,
                playbackTime: playbackTime,
                style: .fullscreen,
                onClose: nil
            )
        }
    }
}

private enum TrackLyricsPresentationStyle: Equatable {
    case fullscreen
    case inlineOverlay

    var horizontalPadding: CGFloat {
        switch self {
        case .fullscreen:
            return 20
        case .inlineOverlay:
            return 18
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .fullscreen:
            return 20
        case .inlineOverlay:
            return 16
        }
    }
}

private struct PlayerLyricsOverlay: View {
    let track: Track
    let playbackTime: TimeInterval
    let onClose: () -> Void

    var body: some View {
        TrackLyricsContentView(
            track: track,
            playbackTime: playbackTime,
            style: .inlineOverlay,
            onClose: onClose
        )
    }
}

private func cleanedPersistedLyricsText(_ value: String?) -> String? {
    guard let value else { return nil }
    let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return cleanedValue.isEmpty ? nil : cleanedValue
}

private func strippedSyncedLyricsText(_ rawText: String) -> String? {
    let parsedLines = SyncedLyricsParser.parse(rawText)
    guard !parsedLines.isEmpty else { return nil }

    var plainLines: [String] = []
    var previousLineText: String?

    for line in parsedLines {
        guard line.text != previousLineText else { continue }
        plainLines.append(line.text)
        previousLineText = line.text
    }

    return cleanedPersistedLyricsText(plainLines.joined(separator: "\n"))
}

private func persistedResolvedLyrics(for track: Track) -> ResolvedTrackLyrics? {
    let storedSyncedText = cleanedPersistedLyricsText(track.lyricsSyncedText)
    guard let persistedText = cleanedPersistedLyricsText(track.lyricsText)
        ?? storedSyncedText.flatMap(strippedSyncedLyricsText) else {
        return nil
    }

    let inferredSyncedText = storedSyncedText ??
        (SyncedLyricsParser.parse(persistedText).isEmpty ? nil : persistedText)
    let plainText = strippedSyncedLyricsText(inferredSyncedText ?? "") ?? persistedText

    return ResolvedTrackLyrics(
        text: plainText,
        syncedText: inferredSyncedText,
        source: cleanedPersistedLyricsText(track.lyricsSource) ?? "saved",
        url: cleanedPersistedLyricsText(track.lyricsURL),
        lastUpdated: track.lyricsLastUpdated ?? Date()
    )
}

@MainActor
private final class TrackLyricsViewModel: ObservableObject {
    @Published private(set) var resolvedLyrics: ResolvedTrackLyrics?
    @Published private(set) var isLoading = false

    private let dataManager: DataManager
    private var activeTrackIdentity: String?

    init(dataManager: DataManager = .shared) {
        self.dataManager = dataManager
    }

    var timedLines: [TimedLyricLine] {
        resolvedLyrics?.timedLines ?? []
    }

    var lyricsSourceLabel: String? {
        guard let source = resolvedLyrics?.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !source.isEmpty else {
            return nil
        }

        switch source {
        case "embedded":
            return "Embedded lyrics"
        case "genius":
            return "Lyrics from Genius"
        case "lrclib":
            return timedLines.isEmpty ? "Lyrics via LRCLIB" : "Synced lyrics via LRCLIB"
        case "lyricsovh":
            return "Lyrics via Lyrics.ovh"
        default:
            return source.capitalized
        }
    }

    func load(track: Track?) async {
        let trackIdentity = track?.sourceID ?? track?.id ?? "no-track"
        activeTrackIdentity = trackIdentity

        guard let track else {
            resolvedLyrics = nil
            isLoading = false
            debugLog("Lyrics unavailable because there is no current track")
            return
        }

        if let persistedLyrics = persistedLyrics(for: track) {
            resolvedLyrics = persistedLyrics
        } else {
            resolvedLyrics = nil
        }

        isLoading = true
        let resolvedLyrics = await LyricsMetadataResolver.shared.resolvedLyrics(for: track)
        guard activeTrackIdentity == trackIdentity else { return }

        if let resolvedLyrics {
            self.resolvedLyrics = resolvedLyrics
            _ = dataManager.persistLyrics(resolvedLyrics, for: track)
        }

        isLoading = false
        debugLog("Lyrics \(resolvedLyrics == nil ? "unavailable" : "loaded") for \(track.displayTitle)")
    }

    private func persistedLyrics(for track: Track) -> ResolvedTrackLyrics? {
        persistedResolvedLyrics(for: track)
    }
}

private struct TrackLyricsContentView: View {
    let track: Track?
    let playbackTime: TimeInterval?
    let style: TrackLyricsPresentationStyle
    let onClose: (() -> Void)?

    @StateObject private var viewModel = TrackLyricsViewModel()

    private var trackIdentity: String {
        track?.sourceID ?? track?.id ?? "no-track"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if style == .fullscreen {
                header
            } else {
                inlineOverlayHeader
            }

            if viewModel.isLoading && viewModel.resolvedLyrics == nil {
                lyricsLoadingState
            } else if !viewModel.timedLines.isEmpty, let playbackTime {
                SyncedLyricsView(
                    lines: viewModel.timedLines,
                    currentTime: playbackTime,
                    compact: style == .inlineOverlay
                )
            } else if let lyricsText = viewModel.resolvedLyrics?.text {
                PlainLyricsView(text: lyricsText, compact: style == .inlineOverlay)
            } else {
                lyricsUnavailableState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .background(backgroundView)
        .task(id: trackIdentity) {
            await viewModel.load(track: track)
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .fullscreen:
            Color.clear
        case .inlineOverlay:
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.black.opacity(0.76))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track?.displayTitle ?? "Nothing playing")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)

            Text(track?.displayArtist ?? "")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))

            if let lyricsSourceLabel = viewModel.lyricsSourceLabel {
                TrackLyricsSourcePill(title: lyricsSourceLabel)
                    .padding(.top, 6)
            }
        }
    }

    private var inlineOverlayHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Lyrics")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)

                if let lyricsSourceLabel = viewModel.lyricsSourceLabel {
                    Text(lyricsSourceLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.48))
                        .lineLimit(1)
                }
            }

            Spacer()

            if let onClose {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.84))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var lyricsLoadingState: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.white)

            Text("Loading lyrics...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var lyricsUnavailableState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lyrics unavailable")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            Text("No saved, embedded, or online lyrics were found for this track.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct TrackLyricsSourcePill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white.opacity(0.78))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
            )
    }
}

private struct PlainLyricsView: View {
    let text: String
    let compact: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            Text(text)
                .font(.system(size: compact ? 15 : 16, weight: .regular))
                .foregroundColor(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, compact ? 6 : 4)
                .padding(.bottom, compact ? 22 : 28)
        }
    }
}

private struct SyncedLyricsView: View {
    let lines: [TimedLyricLine]
    let currentTime: TimeInterval
    let compact: Bool

    private var activeLineIndex: Int {
        guard !lines.isEmpty else { return 0 }

        return lines.lastIndex(where: { $0.time <= currentTime + 0.05 }) ?? 0
    }

    private var activeLineID: String? {
        guard lines.indices.contains(activeLineIndex) else { return nil }
        return lines[activeLineIndex].id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: compact ? 14 : 18) {
                    Color.clear
                        .frame(height: compact ? 56 : 72)

                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        Text(line.text)
                            .font(font(forDistance: abs(index - activeLineIndex)))
                            .foregroundColor(color(forDistance: abs(index - activeLineIndex)))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .id(line.id)
                    }

                    Color.clear
                        .frame(height: compact ? 96 : 128)
                }
                .animation(.easeInOut(duration: 0.22), value: activeLineIndex)
            }
            .onAppear {
                scrollToActiveLine(with: proxy, animated: false)
            }
            .onChange(of: activeLineID) { _ in
                scrollToActiveLine(with: proxy, animated: true)
            }
        }
    }

    private func scrollToActiveLine(with proxy: ScrollViewProxy, animated: Bool) {
        guard let activeLineID else { return }

        let scrollAction = {
            proxy.scrollTo(activeLineID, anchor: .center)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.28)) {
                scrollAction()
            }
        } else {
            scrollAction()
        }
    }

    private func font(forDistance distance: Int) -> Font {
        switch distance {
        case 0:
            return .system(size: compact ? 20 : 24, weight: .semibold)
        case 1:
            return .system(size: compact ? 17 : 19, weight: .medium)
        default:
            return .system(size: compact ? 14 : 16, weight: .regular)
        }
    }

    private func color(forDistance distance: Int) -> Color {
        switch distance {
        case 0:
            return .white
        case 1:
            return .white.opacity(0.72)
        default:
            return .white.opacity(0.38)
        }
    }
}

private struct DismissButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Close") {
            dismiss()
        }
    }
}

struct TimedLyricLine: Identifiable, Equatable {
    let time: TimeInterval
    let text: String

    var id: String {
        "\(time)::\(text)"
    }
}

struct ResolvedTrackLyrics: Equatable {
    let text: String
    let syncedText: String?
    let source: String
    let url: String?
    let lastUpdated: Date

    var timedLines: [TimedLyricLine] {
        SyncedLyricsParser.parse(syncedText)
    }
}

enum SyncedLyricsParser {
    static func parse(_ rawText: String?) -> [TimedLyricLine] {
        guard let rawText = cleanedLyricsText(rawText) else { return [] }
        let lines = rawText.components(separatedBy: .newlines)

        guard let regex = try? NSRegularExpression(
            pattern: #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#,
            options: []
        ) else {
            return []
        }

        var parsedLines: [TimedLyricLine] = []

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            let fullRange = NSRange(trimmedLine.startIndex..., in: trimmedLine)
            let matches = regex.matches(in: trimmedLine, options: [], range: fullRange)
            guard !matches.isEmpty else { continue }

            let lyricText = regex.stringByReplacingMatches(
                in: trimmedLine,
                options: [],
                range: fullRange,
                withTemplate: ""
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !lyricText.isEmpty else { continue }

            for match in matches {
                guard let minutesRange = Range(match.range(at: 1), in: trimmedLine),
                      let secondsRange = Range(match.range(at: 2), in: trimmedLine) else {
                    continue
                }

                let minutes = Double(trimmedLine[minutesRange]) ?? 0
                let seconds = Double(trimmedLine[secondsRange]) ?? 0
                var fraction = 0.0

                if let fractionRange = Range(match.range(at: 3), in: trimmedLine) {
                    let fractionText = String(trimmedLine[fractionRange])
                    let divisor = pow(10.0, Double(fractionText.count))
                    fraction = (Double(fractionText) ?? 0) / divisor
                }

                parsedLines.append(
                    TimedLyricLine(
                        time: max((minutes * 60) + seconds + fraction, 0),
                        text: lyricText
                    )
                )
            }
        }

        return parsedLines.sorted { left, right in
            if left.time != right.time {
                return left.time < right.time
            }

            return left.text < right.text
        }
    }

    private static func cleanedLyricsText(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedValue.isEmpty ? nil : cleanedValue
    }
}

actor LyricsMetadataResolver {
    static let shared = LyricsMetadataResolver()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()
    private let browserUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    private var resolvedLyricsCache: [String: ResolvedTrackLyrics] = [:]

    func resolvedLyrics(for track: Track) async -> ResolvedTrackLyrics? {
        let persistedLyrics = persistedLyrics(for: track)
        let shouldRefreshPersistedLyrics = shouldRefreshPersistedLyrics(persistedLyrics)

        if let persistedLyrics, !shouldRefreshPersistedLyrics {
            return persistedLyrics
        }

        let cacheKey = lyricsCacheKey(for: track)
        if let cachedLyrics = resolvedLyricsCache[cacheKey],
           !shouldRefreshPersistedLyrics || !cachedLyrics.timedLines.isEmpty {
            return cachedLyrics
        }

        guard let fileURL = localFileURL(for: track),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            if let resolvedNetworkLyrics = await resolvedNetworkLyrics(for: track) {
                resolvedLyricsCache[cacheKey] = resolvedNetworkLyrics
                return resolvedNetworkLyrics
            }
            return persistedLyrics
        }

        let asset = AVURLAsset(url: fileURL)
        if let metadataLyrics = metadataLyrics(from: asset) {
            let resolvedLyrics = ResolvedTrackLyrics(
                text: metadataLyrics,
                syncedText: cleanedLyricsText(metadataLyrics).flatMap { lyricsText in
                    SyncedLyricsParser.parse(lyricsText).isEmpty ? nil : lyricsText
                },
                source: "embedded",
                url: nil,
                lastUpdated: Date()
            )
            resolvedLyricsCache[cacheKey] = resolvedLyrics
            return resolvedLyrics
        }

        if let resolvedNetworkLyrics = await resolvedNetworkLyrics(for: track) {
            resolvedLyricsCache[cacheKey] = resolvedNetworkLyrics
            return resolvedNetworkLyrics
        }

        return persistedLyrics
    }

    private func localFileURL(for track: Track) -> URL? {
        guard let fileURL = track.fileURL else { return nil }

        if let parsedURL = URL(string: fileURL),
           parsedURL.isFileURL {
            return parsedURL
        }

        if URL(string: fileURL)?.scheme != nil {
            return nil
        }

        return AppFileManager.shared.resolveStoredFileURL(for: fileURL)
    }

    private func persistedLyrics(for track: Track) -> ResolvedTrackLyrics? {
        persistedResolvedLyrics(for: track)
    }

    private func shouldRefreshPersistedLyrics(_ lyrics: ResolvedTrackLyrics?) -> Bool {
        guard let lyrics else { return false }
        let normalizedSource = lyrics.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lyrics.syncedText == nil && (normalizedSource == "lrclib" || normalizedSource == "embedded")
    }

    private func lyricsCacheKey(for track: Track) -> String {
        let identity = track.sourceID ?? track.id
        return "\(identity)::\(normalizedComparisonText(track.displayArtist))::\(normalizedComparisonText(track.displayTitle))"
    }

    private func metadataLyrics(from asset: AVURLAsset) -> String? {
        let metadataCollections = [asset.commonMetadata] + asset.availableMetadataFormats.map { asset.metadata(forFormat: $0) }

        for items in metadataCollections {
            for item in items {
                let identifier = item.identifier?.rawValue.lowercased() ?? ""
                let commonKey = item.commonKey?.rawValue.lowercased() ?? ""

                guard identifier.contains("lyric") || commonKey.contains("lyric") else {
                    continue
                }

                if let cleanedString = cleanedLyricsText(item.stringValue) {
                    return cleanedString
                }

                if let value = item.value as? String,
                   let cleanedValue = cleanedLyricsText(value) {
                    return cleanedValue
                }

                if let dataValue = item.dataValue {
                    for encoding in [String.Encoding.utf8, .utf16, .unicode, .isoLatin1] {
                        if let decodedValue = String(data: dataValue, encoding: encoding),
                           let cleanedValue = cleanedLyricsText(decodedValue) {
                            return cleanedValue
                        }
                    }
                }
            }
        }

        return nil
    }

    private func resolvedNetworkLyrics(for track: Track) async -> ResolvedTrackLyrics? {
        guard let lookupMetadata = lookupMetadata(for: track) else {
            debugLog("Lyrics lookup skipped for \(track.displayTitle): insufficient artist/title metadata")
            return nil
        }

        if let geniusLyrics = await geniusLyrics(using: lookupMetadata) {
            return geniusLyrics
        }

        if let lrcLibLyrics = await lrcLibLyrics(using: lookupMetadata) {
            return lrcLibLyrics
        }

        if let lyricsOVH = await lyricsOVHLyrics(using: lookupMetadata) {
            return lyricsOVH
        }

        return nil
    }

    private func geniusLyrics(using lookupMetadata: LyricsLookupMetadata) async -> ResolvedTrackLyrics? {
        var candidateResultsByID: [Int: GeniusSongHitResult] = [:]

        for searchQuery in lookupMetadata.geniusSearchQueries {
            guard let encodedQuery = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let searchURL = URL(string: "https://genius.com/api/search/multi?per_page=5&q=\(encodedQuery)") else {
                continue
            }

            do {
                let searchData = try await fetchData(from: searchURL)
                guard let response = try? JSONDecoder().decode(GeniusSearchEnvelope.self, from: searchData) else {
                    continue
                }

                for result in response.response.sections.flatMap({ $0.hits ?? [] }).map(\.result) {
                    candidateResultsByID[result.id] = result
                }
            } catch {
                debugLog("Genius lyrics lookup failed for query \(searchQuery): \(error.localizedDescription)")
                continue
            }
        }

        let rankedCandidates = rankedGeniusResults(
            using: lookupMetadata,
            in: Array(candidateResultsByID.values)
        )

        for candidate in rankedCandidates.prefix(5) {
            let lyricsPageURLString = cleanedLyricsText(candidate.url) ??
                cleanedLyricsText(candidate.path).map { "https://genius.com\($0)" }

            guard let lyricsPageURLString,
                  let lyricsPageURL = URL(string: lyricsPageURLString) else {
                continue
            }

            do {
                let pageHTML = try await fetchHTML(from: lyricsPageURL)
                guard let lyricsHTML = extractLyricsHTML(from: pageHTML),
                      let lyricsText = plainTextLyrics(fromHTML: lyricsHTML) else {
                    continue
                }

                debugLog("Lyrics resolved through Genius for \(lookupMetadata.artistVariants.first ?? "unknown artist") - \(lookupMetadata.titleVariants.first ?? "unknown title")")
                return ResolvedTrackLyrics(
                    text: lyricsText,
                    syncedText: nil,
                    source: "genius",
                    url: lyricsPageURLString,
                    lastUpdated: Date()
                )
            } catch {
                debugLog("Genius lyrics page fetch failed for \(lyricsPageURLString): \(error.localizedDescription)")
            }
        }

        return nil
    }

    private func lrcLibLyrics(using lookupMetadata: LyricsLookupMetadata) async -> ResolvedTrackLyrics? {
        for query in lookupMetadata.providerQueries {
            guard var components = URLComponents(string: "https://lrclib.net/api/get") else {
                continue
            }

            components.queryItems = [
                URLQueryItem(name: "artist_name", value: query.artist),
                URLQueryItem(name: "track_name", value: query.title)
            ]

            guard let requestURL = components.url else { continue }

            do {
                let data = try await fetchData(from: requestURL)
                let result = try JSONDecoder().decode(LRCLibLyricsResult.self, from: data)
                let syncedLyricsText = cleanedLyricsText(result.syncedLyrics)
                guard let lyricsText = cleanedLyricsText(result.plainLyrics) ??
                        syncedLyricsText.flatMap(strippedSyncedLyrics(from:)) else {
                    continue
                }

                debugLog("Lyrics resolved through LRCLIB for \(query.artist) - \(query.title)")
                return ResolvedTrackLyrics(
                    text: lyricsText,
                    syncedText: syncedLyricsText,
                    source: "lrclib",
                    url: result.url,
                    lastUpdated: Date()
                )
            } catch {
                continue
            }
        }

        return nil
    }

    private func lyricsOVHLyrics(using lookupMetadata: LyricsLookupMetadata) async -> ResolvedTrackLyrics? {
        let pathAllowedCharacterSet = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))

        for query in lookupMetadata.providerQueries {
            guard let encodedArtist = query.artist.addingPercentEncoding(withAllowedCharacters: pathAllowedCharacterSet),
                  let encodedTitle = query.title.addingPercentEncoding(withAllowedCharacters: pathAllowedCharacterSet),
                  let requestURL = URL(string: "https://api.lyrics.ovh/v1/\(encodedArtist)/\(encodedTitle)") else {
                continue
            }

            do {
                let data = try await fetchData(from: requestURL)
                let result = try JSONDecoder().decode(LyricsOVHResponse.self, from: data)
                guard let lyricsText = cleanedLyricsText(result.lyrics) else {
                    continue
                }

                debugLog("Lyrics resolved through Lyrics.ovh for \(query.artist) - \(query.title)")
                return ResolvedTrackLyrics(
                    text: lyricsText,
                    syncedText: nil,
                    source: "lyricsovh",
                    url: nil,
                    lastUpdated: Date()
                )
            } catch {
                continue
            }
        }

        return nil
    }

    private func fetchData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return data
    }

    private func fetchHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else {
            throw URLError(.cannotDecodeContentData)
        }

        return html
    }

    private func rankedGeniusResults(
        using lookupMetadata: LyricsLookupMetadata,
        in results: [GeniusSongHitResult]
    ) -> [GeniusSongHitResult] {
        results.compactMap { result -> (result: GeniusSongHitResult, score: Int, titleScore: Int, artistScore: Int)? in
            guard let title = cleanedLyricsText(result.title),
                  looksLikeGeniusSongResult(result) else {
                return nil
            }

            let candidateTitleScore = comparisonScore(
                expectedCandidates: lookupMetadata.normalizedTitleCandidates,
                actualCandidates: normalizedTitleCandidates(
                    for: [title, result.titleWithFeatured, result.fullTitle].compactMap { $0 }
                )
            )
            let candidateArtistScore = comparisonScore(
                expectedCandidates: lookupMetadata.normalizedArtistCandidates,
                actualCandidates: normalizedArtistCandidates(
                    for: [result.artistNames, result.primaryArtist?.name].compactMap { $0 }
                )
            )
            var score = (candidateTitleScore * 2) + candidateArtistScore

            if result.lyricsState?.lowercased() == "complete" {
                score += 10
            }

            if candidateArtistScore >= 96 {
                score += 8
            }

            if candidateTitleScore >= 96 {
                score += 6
            }

            if hasVersionMismatch(expectedCandidates: lookupMetadata.normalizedTitleCandidates, candidateTitle: title) {
                score -= 22
            }

            if looksLikeDerivedLyricsResult(result), candidateArtistScore < 50 {
                score -= 80
            }

            guard candidateTitleScore >= 52 else {
                return nil
            }

            guard candidateArtistScore >= 28 || candidateTitleScore >= 100 else {
                return nil
            }

            guard score >= 128 else {
                return nil
            }

            return (result, score, candidateTitleScore, candidateArtistScore)
        }
        .sorted { left, right in
            if left.score != right.score {
                return left.score > right.score
            }

            if left.titleScore != right.titleScore {
                return left.titleScore > right.titleScore
            }

            return left.artistScore > right.artistScore
        }
        .map(\.result)
    }

    private func comparisonScore(expectedCandidates: Set<String>, actualCandidates: Set<String>) -> Int {
        guard !expectedCandidates.isEmpty, !actualCandidates.isEmpty else { return 0 }

        var bestScore = 0

        for expected in expectedCandidates {
            for actual in actualCandidates {
                bestScore = max(bestScore, comparisonScore(expected: expected, actual: actual))
                if bestScore == 100 {
                    return bestScore
                }
            }
        }

        return bestScore
    }

    private func comparisonScore(expected: String, actual: String) -> Int {
        guard !expected.isEmpty, !actual.isEmpty else { return 0 }

        if expected == actual {
            return 100
        }

        let condensedExpected = expected.replacingOccurrences(of: " ", with: "")
        let condensedActual = actual.replacingOccurrences(of: " ", with: "")
        if condensedExpected == condensedActual {
            return 98
        }

        if expected.count > 4,
           actual.count > 4,
           (expected.contains(actual) || actual.contains(expected)) {
            return 92
        }

        let expectedTokens = tokenSet(for: expected)
        let actualTokens = tokenSet(for: actual)
        let sharedTokens = expectedTokens.intersection(actualTokens)
        let expectedCoverage = percentageScore(sharedTokens.count, over: expectedTokens.count)
        let actualCoverage = percentageScore(sharedTokens.count, over: actualTokens.count)

        if expectedCoverage == 100 && actualCoverage >= 70 {
            return 94
        }

        if expectedCoverage >= 85 && actualCoverage >= 50 {
            return 92
        }

        if expectedCoverage >= 72 && actualCoverage >= 40 {
            return 78
        }

        if expectedCoverage >= 55 && actualCoverage >= 30 {
            return 64
        }

        if sharedTokens.count >= 2 {
            return 56
        }

        return 0
    }

    private func tokenSet(for value: String) -> Set<String> {
        Set(value.split(separator: " ").map(String.init))
    }

    private func percentageScore(_ numerator: Int, over denominator: Int) -> Int {
        guard denominator > 0 else { return 0 }
        return Int((Double(numerator) / Double(denominator)) * 100)
    }

    private func normalizedTitleCandidates(for values: [String]) -> Set<String> {
        Set(values.flatMap(titleSearchVariants).map(normalizedComparisonText).filter { !$0.isEmpty })
    }

    private func normalizedTitleCandidates(for title: String) -> Set<String> {
        normalizedTitleCandidates(for: [title])
    }

    private func normalizedArtistCandidates(for values: [String]) -> Set<String> {
        Set(values.flatMap(artistSearchVariants).map(normalizedComparisonText).filter { !$0.isEmpty })
    }

    private func normalizedArtistCandidates(for artist: String) -> Set<String> {
        normalizedArtistCandidates(for: [artist])
    }

    private func normalizedComparisonText(_ value: String) -> String {
        let strippedValue = normalizedSearchSource(value)
            .replacingOccurrences(of: "\u{0451}", with: "\u{0435}")
            .replacingOccurrences(of: #"[()\[\]{}]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[|/:]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*-\s*"#, with: " ", options: .regularExpression)
            .applyingSearchNoiseCleanup()
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        return strippedValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizedSearchSource(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: "\u{00D7}", with: " x ")
            .replacingOccurrences(of: "\u{FF0F}", with: "/")
            .replacingOccurrences(of: "\u{FF06}", with: "&")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "â€“", with: "-")
            .replacingOccurrences(of: "â€”", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "×", with: " x ")
            .replacingOccurrences(of: "／", with: "/")
            .replacingOccurrences(of: "＆", with: "&")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func hasVersionMismatch(expectedCandidates: Set<String>, candidateTitle: String) -> Bool {
        let normalizedCandidateTitle = normalizedComparisonText(candidateTitle)
        let versionMarkers = [
            "live", "remix", "edit", "sped up", "slowed", "remaster",
            "radio edit", "extended mix", "instrumental", "acoustic"
        ]

        return versionMarkers.contains { marker in
            normalizedCandidateTitle.contains(marker) &&
                !expectedCandidates.contains(where: { $0.contains(marker) })
        }
    }

    private func looksLikeGeniusSongResult(_ result: GeniusSongHitResult) -> Bool {
        if result.resultType?.lowercased() == "song" {
            return true
        }

        let candidatePath = cleanedLyricsText(result.path) ??
            cleanedLyricsText(result.url).flatMap { URL(string: $0)?.path }
        let normalizedPath = normalizedSearchSource(candidatePath ?? "").lowercased()
        return normalizedPath.contains("-lyrics")
    }

    private func looksLikeDerivedLyricsResult(_ result: GeniusSongHitResult) -> Bool {
        let combinedValue = normalizedSearchSource(
            [
                result.title,
                result.artistNames,
                result.fullTitle,
                result.path,
                result.url
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        )
        .lowercased()

        let markers = [
            "translation", "traduccion", "traducción", "traducao", "traduction", "traduzione",
            "ceviri", "çeviri", "ubersetzung", "übersetzung", "перевод", "deutsche",
            "espanol", "español", "francaise", "française", "russian translations",
            "annotated", "playlist", "tracklist", "ranking page", "essentials", "top hits",
            "spanish version", "turkce", "türkçe"
        ]

        return markers.contains { combinedValue.contains($0) }
    }

    private func extractLyricsHTML(from pageHTML: String) -> String? {
        let lowercasedHTML = pageHTML.lowercased()
        if lowercasedHTML.contains("cloudflare_error.challenge") ||
            lowercasedHTML.contains("make sure you're a human") {
            return nil
        }

        if let preloadedStateLyricsHTML = extractLyricsHTMLFromPreloadedState(from: pageHTML) {
            return preloadedStateLyricsHTML
        }

        return extractLyricsHTMLFromContainers(from: pageHTML)
    }

    private func extractLyricsHTMLFromPreloadedState(from pageHTML: String) -> String? {
        let marker = "window.__PRELOADED_STATE__ = JSON.parse('"
        guard let markerRange = pageHTML.range(of: marker) else {
            return nil
        }

        let stateStartIndex = markerRange.upperBound
        var stateEndIndex = stateStartIndex
        var isEscaped = false

        while stateEndIndex < pageHTML.endIndex {
            let currentCharacter = pageHTML[stateEndIndex]

            if currentCharacter == "'" && !isEscaped {
                break
            }

            isEscaped = currentCharacter == "\\" && !isEscaped
            if currentCharacter != "\\" {
                isEscaped = false
            }
            stateEndIndex = pageHTML.index(after: stateEndIndex)
        }

        guard stateEndIndex < pageHTML.endIndex else {
            return nil
        }

        let escapedJSON = String(pageHTML[stateStartIndex..<stateEndIndex])
        let wrappedJSONString = "\"\(escapedJSON)\""

        guard let decodedJSONString = try? JSONDecoder().decode(String.self, from: Data(wrappedJSONString.utf8)),
              let pageStateData = decodedJSONString.data(using: .utf8),
              let pageState = try? JSONDecoder().decode(GeniusSongPageState.self, from: pageStateData) else {
            return nil
        }

        return cleanedLyricsText(pageState.songPage?.lyricsData?.body?.html)
    }

    private func extractLyricsHTMLFromContainers(from pageHTML: String) -> String? {
        let pattern = #"<div[^>]*data-lyrics-container=\"true\"[^>]*>(.*?)</div>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(pageHTML.startIndex..., in: pageHTML)
        let snippets = regex.matches(in: pageHTML, options: [], range: range).compactMap { match -> String? in
            guard let captureRange = Range(match.range(at: 1), in: pageHTML) else {
                return nil
            }

            return String(pageHTML[captureRange])
        }

        guard !snippets.isEmpty else {
            return nil
        }

        return cleanedLyricsText(snippets.joined(separator: "<br><br>"))
    }

    private func plainTextLyrics(fromHTML html: String) -> String? {
        guard let data = html.data(using: .utf8),
              let attributedString = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return cleanedLyricsText(html
                .replacingOccurrences(of: "<br>", with: "\n")
                .replacingOccurrences(of: "<br/>", with: "\n")
                .replacingOccurrences(of: "<br />", with: "\n"))
        }

        return cleanedLyricsText(
            attributedString.string.replacingOccurrences(
                of: #"\n{3,}"#,
                with: "\n\n",
                options: .regularExpression
            )
        )
    }

    private func cleanedLyricsText(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedValue.isEmpty ? nil : cleanedValue
    }

    private func lookupMetadata(for track: Track) -> LyricsLookupMetadata? {
        let cleanedTitle = normalizedSearchSource(track.displayTitle)
        let cleanedArtist = normalizedSearchSource(track.displayArtist)
        let inferredMetadata = inferredMetadata(fromTitle: cleanedTitle, artist: cleanedArtist)
        let titleVariants = deduplicatedNonEmptyValues(
            (inferredMetadata.titleValues + [cleanedTitle]).flatMap(titleSearchVariants)
        )
        let artistVariants = deduplicatedNonEmptyValues(
            (inferredMetadata.artistValues + [cleanedArtist]).flatMap(artistSearchVariants)
        )
        let normalizedTitleCandidates = Set(titleVariants.map(normalizedComparisonText).filter { !$0.isEmpty })
        let normalizedArtistCandidates = Set(artistVariants.map(normalizedComparisonText).filter { !$0.isEmpty })

        guard !titleVariants.isEmpty,
              !artistVariants.isEmpty,
              !normalizedTitleCandidates.isEmpty,
              !normalizedArtistCandidates.isEmpty else {
            return nil
        }

        return LyricsLookupMetadata(
            titleVariants: titleVariants,
            artistVariants: artistVariants,
            normalizedTitleCandidates: normalizedTitleCandidates,
            normalizedArtistCandidates: normalizedArtistCandidates
        )
    }

    private func inferredMetadata(fromTitle title: String, artist: String) -> (titleValues: [String], artistValues: [String]) {
        guard let (left, right) = splitCombinedTitle(title) else {
            return ([], [])
        }

        let knownArtistCandidates = normalizedArtistCandidates(for: artist)
        let normalizedLeft = normalizedComparisonText(left)
        let normalizedRight = normalizedComparisonText(right)

        if knownArtistCandidates.isEmpty {
            return ([right], [left])
        }

        let leftArtistScore = comparisonScore(
            expectedCandidates: knownArtistCandidates,
            actualCandidates: Set([normalizedLeft])
        )
        let rightArtistScore = comparisonScore(
            expectedCandidates: knownArtistCandidates,
            actualCandidates: Set([normalizedRight])
        )

        if leftArtistScore >= 82 && leftArtistScore > rightArtistScore {
            return ([right], [left])
        }

        if rightArtistScore >= 82 && rightArtistScore > leftArtistScore {
            return ([left], [right])
        }

        return ([], [])
    }

    private func splitCombinedTitle(_ value: String) -> (String, String)? {
        let cleanedValue = normalizedSearchSource(value)
        let separators = [" - ", " | ", " / "]

        for separator in separators {
            guard let range = cleanedValue.range(of: separator) else { continue }
            let left = String(cleanedValue[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(cleanedValue[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !left.isEmpty, !right.isEmpty else { continue }
            return (left, right)
        }

        return nil
    }

    private func titleSearchVariants(for title: String) -> [String] {
        let trimmedTitle = normalizedSearchSource(title)
        guard !trimmedTitle.isEmpty else { return [] }

        let flattenedBracketTitle = trimmedTitle
            .replacingOccurrences(of: #"[()\[\]{}]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let strippedBracketedTitle = trimmedTitle.replacingOccurrences(
            of: #"\[[^\]]*\]|\([^)]*\)|\{[^}]*\}"#,
            with: " ",
            options: .regularExpression
        )
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        let strippedFeatureTitle = removingFeatureClauses(from: flattenedBracketTitle)
        let strippedNoiseTitle = removingVersionNoise(from: strippedFeatureTitle)

        var variants: [String] = [
            trimmedTitle,
            flattenedBracketTitle,
            strippedBracketedTitle,
            strippedFeatureTitle,
            strippedNoiseTitle
        ]

        let titleSeparators = [" - ", " | ", " / ", ": "]
        for separator in titleSeparators {
            guard let range = trimmedTitle.range(of: separator) else { continue }
            let prefix = String(trimmedTitle[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = String(trimmedTitle[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedPrefix = removingVersionNoise(from: removingFeatureClauses(from: prefix))
            let cleanedSuffix = removingVersionNoise(from: removingFeatureClauses(from: suffix))

            if containsLyricsNoise(in: suffix) {
                if !cleanedPrefix.isEmpty {
                    variants.append(cleanedPrefix)
                }
                if !cleanedSuffix.isEmpty {
                    variants.append(cleanedSuffix)
                }
            }

            if containsLyricsNoise(in: prefix) {
                if !cleanedSuffix.isEmpty {
                    variants.append(cleanedSuffix)
                }
            }
        }

        return deduplicatedNonEmptyValues(variants)
    }

    private func artistSearchVariants(for artist: String) -> [String] {
        let trimmedArtist = normalizedSearchSource(artist)
        guard !trimmedArtist.isEmpty,
              normalizedComparisonText(trimmedArtist) != "unknown artist" else { return [] }

        let flattenedArtist = trimmedArtist
            .replacingOccurrences(of: #"[()\[\]{}]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let strippedArtist = removingFeatureClauses(from: flattenedArtist)

        var variants: [String] = [trimmedArtist, flattenedArtist, strippedArtist]
        let artistComponents = separatedArtistComponents(from: strippedArtist)
        if let primaryArtist = artistComponents.first {
            variants.append(primaryArtist)
        }
        variants.append(contentsOf: artistComponents)

        return deduplicatedNonEmptyValues(variants)
    }

    private func separatedArtistComponents(from artist: String) -> [String] {
        let separatedArtist = normalizedSearchSource(artist)
            .replacingOccurrences(of: #"(?i)\b(feat\.?|ft\.?|featuring|with|and|vs\.?|x)\b"#, with: ",", options: .regularExpression)
            .replacingOccurrences(of: "&", with: ",")
            .replacingOccurrences(of: "/", with: ",")
            .replacingOccurrences(of: ";", with: ",")

        return deduplicatedNonEmptyValues(
            separatedArtist
                .split(separator: ",")
                .map(String.init)
        )
    }

    private func removingFeatureClauses(from value: String) -> String {
        normalizedSearchSource(value)
            .replacingOccurrences(
                of: #"(?i)(?:^|\s)(feat\.?|ft\.?|featuring|prod\.?|produced by)\s+.+$"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func removingVersionNoise(from value: String) -> String {
        normalizedSearchSource(value)
            .applyingSearchNoiseCleanup()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deduplicatedNonEmptyValues(_ values: [String]) -> [String] {
        var seenNormalizedValues: Set<String> = []
        var orderedValues: [String] = []

        for value in values {
            let cleanedValue = value
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedValue.isEmpty else { continue }

            let normalizedValue = cleanedValue.lowercased()
            guard seenNormalizedValues.insert(normalizedValue).inserted else { continue }
            orderedValues.append(cleanedValue)
        }

        return orderedValues
    }

    private func containsLyricsNoise(in value: String) -> Bool {
        let normalizedValue = normalizedSearchSource(value).lowercased()
        let markers = [
            "feat", "ft", "featuring", "prod", "produced by", "official audio", "official video",
            "lyrics video", "lyric video", "visualizer", "nightcore", "slowed", "sped up",
            "remix", "edit", "mix", "live", "version", "remaster", "radio edit",
            "extended mix", "instrumental", "karaoke", "acoustic"
        ]

        return markers.contains { normalizedValue.contains($0) }
    }

    private func strippedSyncedLyrics(from value: String) -> String? {
        let plainText = value
            .replacingOccurrences(of: #"(?m)^\[[^\]]+\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)

        return cleanedLyricsText(plainText)
    }
}

private extension String {
    func applyingSearchNoiseCleanup() -> String {
        self
            .replacingOccurrences(
                of: #"(?i)(?:^|\s)(feat\.?|ft\.?|featuring)\s+.+$"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)(?:^|\s)(prod\.?|produced by)\s+.+$"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)(official audio|official video|lyrics video|lyric video|visualizer|nightcore|sped up(?:\s*\+\s*reverb)?|slowed(?:\s*\+\s*reverb)?|radio edit|extended mix|remix|mix|edit|live|version|remaster(?:ed)?|instrumental|karaoke|acoustic)"#,
                with: " ",
                options: .regularExpression
            )
    }
}

private struct GeniusSearchEnvelope: Decodable {
    let response: GeniusSearchPayload
}

private struct GeniusSearchPayload: Decodable {
    let sections: [GeniusSearchSection]
}

private struct GeniusSearchSection: Decodable {
    let hits: [GeniusSearchHit]?
}

private struct GeniusSearchHit: Decodable {
    let result: GeniusSongHitResult
}

private struct GeniusSongHitResult: Decodable {
    let id: Int
    let resultType: String?
    let title: String?
    let fullTitle: String?
    let titleWithFeatured: String?
    let artistNames: String?
    let primaryArtist: GeniusPrimaryArtist?
    let path: String?
    let url: String?
    let lyricsState: String?

    enum CodingKeys: String, CodingKey {
        case id
        case resultType = "_type"
        case title
        case fullTitle = "full_title"
        case titleWithFeatured = "title_with_featured"
        case artistNames = "artist_names"
        case primaryArtist = "primary_artist"
        case path
        case url
        case lyricsState = "lyrics_state"
    }
}

private struct GeniusPrimaryArtist: Decodable {
    let name: String?
}

private struct GeniusSongPageState: Decodable {
    let songPage: GeniusSongPageLyricsData?
}

private struct GeniusSongPageLyricsData: Decodable {
    let lyricsData: GeniusLyricsPayload?
}

private struct GeniusLyricsPayload: Decodable {
    let body: GeniusLyricsBody?
}

private struct GeniusLyricsBody: Decodable {
    let html: String?
}

private struct LyricsLookupMetadata {
    let titleVariants: [String]
    let artistVariants: [String]
    let normalizedTitleCandidates: Set<String>
    let normalizedArtistCandidates: Set<String>

    var geniusSearchQueries: [String] {
        var queries: [String] = []

        for query in providerQueries.prefix(10) {
            queries.append("\(query.artist) \(query.title)")
        }

        for title in titleVariants.prefix(2) {
            queries.append(title)
        }

        return deduplicatedQueries(queries)
    }

    var providerQueries: [(artist: String, title: String)] {
        var queries: [(artist: String, title: String)] = []

        for artist in artistVariants.prefix(3) {
            for title in titleVariants.prefix(6) {
                queries.append((artist: artist, title: title))
            }
        }

        var seenKeys: Set<String> = []
        var orderedQueries: [(artist: String, title: String)] = []

        for query in queries {
            let identity = "\(query.artist.lowercased())::\(query.title.lowercased())"
            guard seenKeys.insert(identity).inserted else { continue }
            orderedQueries.append(query)
        }

        return orderedQueries
    }

    private func deduplicatedQueries(_ queries: [String]) -> [String] {
        var seenValues: Set<String> = []
        var orderedValues: [String] = []

        for query in queries {
            let cleanedQuery = query
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedQuery.isEmpty else { continue }

            let normalizedQuery = cleanedQuery.lowercased()
            guard seenValues.insert(normalizedQuery).inserted else { continue }
            orderedValues.append(cleanedQuery)
        }

        return orderedValues
    }
}

private struct LRCLibLyricsResult: Decodable {
    let trackName: String?
    let artistName: String?
    let plainLyrics: String?
    let syncedLyrics: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case trackName
        case artistName
        case plainLyrics
        case syncedLyrics
        case url
    }
}

private struct LyricsOVHResponse: Decodable {
    let lyrics: String?
}

#Preview {
    PlayerView(isPresented: .constant(true))
        .environmentObject(AudioPlayer.shared)
        .environmentObject(AppRouter())
}
