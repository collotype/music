//
//  HomeView.swift
//  FreeMusicPlayer
//
//  Home screen.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var router: AppRouter

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.6, green: 0.1, blue: 0.1),
                    Color(red: 0.3, green: 0.05, blue: 0.05),
                    Color.black
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    WaveCard()
                    ListenTogetherCard()
                    PlaylistsSection()
                    PopularSection()
                    RecentSection()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                    Text("FreeMusic")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        debugLog("Home search button pressed")
                        router.navigate(to: .search)
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        debugLog("Home profile button pressed")
                        router.navigate(to: .settings)
                    } label: {
                        AsyncImage(url: URL(string: "https://via.placeholder.com/40")) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Circle()
                                .fill(Color.white.opacity(0.15))
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct WaveCard: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var viewModel = MyWaveViewModel()
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("My Wave")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)

                    Text(viewModel.summaryLine)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))

                    if dataManager.myWaveSettings.isCustomized {
                        Text(dataManager.myWaveSettings.selectedLabels.joined(separator: " / "))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 10) {
                    Button {
                        debugLog("Wave play button pressed")
                        Task {
                            await viewModel.playPrimaryRecommendation()
                        }
                    } label: {
                        Circle()
                            .fill(viewModel.hasRecommendations ? Color.white : Color.white.opacity(0.18))
                            .frame(width: 56, height: 56)
                            .overlay(
                                Group {
                                    if viewModel.isLoading && !viewModel.hasRecommendations {
                                        ProgressView()
                                            .tint(.black)
                                    } else {
                                        Image(systemName: "play.fill")
                                            .foregroundColor(.black)
                                            .font(.system(size: 20))
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.hasRecommendations && !viewModel.isLoading)

                    Button {
                        debugLog("My Wave settings button pressed")
                        showingSettings = true
                    } label: {
                        Text("Настроить")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if viewModel.isShowingCachedData || viewModel.isRefreshing {
                HStack(spacing: 8) {
                    if viewModel.isRefreshing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white.opacity(0.82))
                    }

                    Text(viewModel.isShowingCachedData ? "Showing cached recommendations while My Wave refreshes." : "Refreshing recommendations from your latest activity.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                }
            }

            if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.58))
                    .padding(.top, 2)
            } else if viewModel.items.isEmpty {
                Text("Listen to a few tracks, save favorites, or finish songs to train My Wave.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.58))
                    .padding(.top, 2)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.items.prefix(4))) { item in
                        Button {
                            Task {
                                await viewModel.play(item: item)
                            }
                        } label: {
                            MyWaveRecommendationRow(item: item)
                        }
                        .buttonStyle(.plain)

                        if item.id != viewModel.items.prefix(4).last?.id {
                            Divider()
                                .background(Color.white.opacity(0.08))
                                .padding(.leading, 58)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .task {
            await viewModel.loadIfNeeded()
        }
        .sheet(isPresented: $showingSettings) {
            MyWaveSettingsView()
                .environmentObject(dataManager)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

struct MyWaveRecommendationRow: View {
    let item: MyWaveRecommendationItem

    var body: some View {
        HStack(spacing: 12) {
            MyWaveArtworkView(item: item)
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(item.displayArtist)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.58))
                    .lineLimit(1)

                Text(item.reasonSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.44))
                    .lineLimit(1)
            }

            Spacer()

            Text(item.formattedDuration)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.05))
                )
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct MyWaveArtworkView: View {
    let item: MyWaveRecommendationItem

    var body: some View {
        Group {
            if let track = item.track {
                TrackArtworkView(track: track, size: 46, cornerRadius: 10, showsSourceBadge: true)
            } else if let onlineResult = item.onlineResult {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [
                                    onlineResult.provider.accentColor,
                                    onlineResult.provider.secondaryAccentColor
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    if let artworkReference = onlineResult.coverArtURL,
                       let artworkURL = URL(string: artworkReference) {
                        AsyncImage(url: artworkURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                Image(systemName: "music.note")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.82))
                            }
                        }
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.82))
                    }

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ProviderIconView(provider: onlineResult.provider, size: 11)
                                .padding(4)
                                .background(Circle().fill(Color.black.opacity(0.82)))
                        }
                    }
                    .padding(4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.white.opacity(0.5))
                    )
            }
        }
    }
}

struct ListenTogetherCard: View {
    var body: some View {
        Button {
            debugLog("Listen together card pressed")
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.1))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Listen Together")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)

                    Text("Public rooms placeholder")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }
}

struct PlaylistsSection: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var router: AppRouter
    @State private var showingCreatePlaylistPrompt = false
    @State private var newPlaylistName: String = ""

    private var displayedPlaylists: [Playlist] {
        Array(dataManager.sortedPlaylists.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Playlists")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                if !dataManager.favoritePlaylists.isEmpty {
                    Text("\(dataManager.favoritePlaylists.count) favorites")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.45))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(displayedPlaylists) { playlist in
                        Button {
                            debugLog("Playlist card pressed: \(playlist.displayName)")
                            router.openPlaylist(playlist.id)
                        } label: {
                            PlaylistCard(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        debugLog("Create playlist button pressed")
                        newPlaylistName = "New Playlist"
                        showingCreatePlaylistPrompt = true
                    } label: {
                        VStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.05))
                                .frame(width: 140, height: 140)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.system(size: 32))
                                        .foregroundColor(.white.opacity(0.5))
                                )

                            Text("Create")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.top, 8)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .alert("Create Playlist", isPresented: $showingCreatePlaylistPrompt) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) {
                newPlaylistName = ""
            }
            Button("Create") {
                let playlist = dataManager.createPlaylist(name: newPlaylistName)
                newPlaylistName = ""
                router.openPlaylist(playlist.id)
            }
        } message: {
            Text("Choose a name for the new playlist.")
        }
    }
}

struct PlaylistCard: View {
    let playlist: Playlist
    @EnvironmentObject var dataManager: DataManager

    private var playlistTracks: [Track] {
        dataManager.tracks(for: playlist.id)
    }

    private var representativeTrack: Track? {
        playlistTracks.first(where: { $0.preferredArtworkReference != nil }) ?? playlistTracks.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlaylistArtworkView(
                coverArtURL: playlist.coverArtURL,
                representativeTrack: representativeTrack,
                fallbackTitle: playlist.displayName,
                size: 140,
                cornerRadius: 12
            )
            .overlay(alignment: .topTrailing) {
                if playlist.isStarred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)
                        .padding(8)
                }
            }

            Text(playlist.displayName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)

            Text("\(playlist.trackCount) tracks")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(width: 140, alignment: .leading)
    }
}

struct PopularSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Popular")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<5, id: \.self) { index in
                        PopularCard(index: index)
                    }
                }
            }
        }
    }
}

struct PopularCard: View {
    let index: Int

    var body: some View {
        Button {
            debugLog("Popular card pressed: \(index)")
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 140, height: 140)

                Text("Mix #\(index + 1)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

struct RecentSection: View {
    @EnvironmentObject var dataManager: DataManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)

            VStack(spacing: 0) {
                ForEach(Array(dataManager.tracks.prefix(10))) { track in
                    TrackRow(track: track, contextTracks: Array(dataManager.tracks.prefix(10)))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.03))
            )
        }
    }
}

struct TrackRow: View {
    let track: Track
    let contextTracks: [Track]
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var dataManager: DataManager
    @State private var showingTrackActions = false

    var isPlaying: Bool {
        audioPlayer.currentTrack?.id == track.id && audioPlayer.isPlaying
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.1))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "music.note")
                        .foregroundColor(.white.opacity(0.3))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isPlaying ? .red : .white)

                Text(track.displayArtist)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            Text(track.formattedDuration)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                )

            Image(systemName: dataManager.isTrackSaved(track) ? "heart.fill" : "heart")
                .foregroundColor(dataManager.isTrackSaved(track) ? .red : .white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            debugLog("Recent track row tapped: \(track.displayTitle)")
            audioPlayer.playTrack(track, in: contextTracks, contextName: "home:recent")
        }
        .onLongPressGesture(minimumDuration: 0.6) {
            debugLog("Long press menu opened: \(track.displayTitle)")
            showingTrackActions = true
        }
        .trackActionPopup(
            isPresented: $showingTrackActions,
            track: track,
            contextTracks: contextTracks,
            contextName: "home:recent",
            playlistContext: nil
        )
    }
}

#Preview {
    HomeView()
        .environmentObject(AudioPlayer.shared)
        .environmentObject(DataManager.shared)
        .environmentObject(AppRouter())
}
