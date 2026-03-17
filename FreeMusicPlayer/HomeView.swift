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
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var dataManager: DataManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("My Wave")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)

                    Text("Start a quick mix from the tracks already in your library.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                Button {
                    debugLog("Wave play button pressed")
                    if let firstTrack = dataManager.tracks.randomElement() {
                        audioPlayer.playTrack(firstTrack, in: dataManager.tracks, contextName: "home:wave")
                    } else {
                        debugLog("Wave play ignored because library is empty")
                    }
                } label: {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "play.fill")
                                .foregroundColor(.black)
                                .font(.system(size: 20))
                        )
                }
                .buttonStyle(.plain)
            }

            WaveformView()
                .frame(height: 40)
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
    }
}

struct WaveformView: View {
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<40, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 3, height: CGFloat.random(in: 8...25))
            }
        }
        .frame(maxWidth: .infinity)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.7, green: 0.2, blue: 0.2),
                            Color(red: 0.3, green: 0.1, blue: 0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 140, height: 140)
                .overlay(
                    ZStack {
                        Image(systemName: playlist.isStarred ? "star.circle.fill" : "music.note.list")
                            .font(.system(size: 40))
                            .foregroundColor(playlist.isStarred ? .yellow.opacity(0.9) : .white.opacity(0.3))

                        VStack {
                            HStack {
                                Spacer()
                                if playlist.isStarred {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.yellow)
                                        .padding(8)
                                }
                            }
                            Spacer()
                        }
                    }
                )

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

            Button {
                debugLog("Recent favorite button pressed: \(track.displayTitle)")
                dataManager.toggleFavorite(track)
            } label: {
                Image(systemName: dataManager.favorites.contains(track.id) ? "heart.fill" : "heart")
                    .foregroundColor(dataManager.favorites.contains(track.id) ? .red : .white.opacity(0.5))
            }
            .buttonStyle(.plain)
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
        .sheet(isPresented: $showingTrackActions) {
            TrackActionSheet(
                track: track,
                contextTracks: contextTracks,
                contextName: "home:recent",
                playlistContext: nil
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AudioPlayer.shared)
        .environmentObject(DataManager.shared)
        .environmentObject(AppRouter())
}
