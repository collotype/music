//
//  HomeView.swift
//  FreeMusicPlayer
//
//  Home screen.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var router: AppRouter

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [AppTheme.paper, AppTheme.paperDeep]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    homeHeader
                    NowPlayingHomeCard()
                    PlaylistsSection()
                    RecentSection()
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 100)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var homeHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("FreeMusic")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(AppTheme.ink)
                Text("\(dataManager.tracks.count) tracks in your player")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.mutedInk)
            }

            Spacer()

            Button {
                debugLog("Home search button pressed")
                router.navigate(to: .search)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.ink)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(AppTheme.panel))
                    .overlay(Circle().stroke(AppTheme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

struct NowPlayingHomeCard: View {
    @EnvironmentObject var audioPlayer: AudioPlayer

    var body: some View {
        HStack(spacing: 18) {
            MiniVinylArtwork(track: audioPlayer.currentTrack, size: 104)

            VStack(alignment: .leading, spacing: 7) {
                Text("Now playing")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.mutedInk)
                    .textCase(.uppercase)

                Text(audioPlayer.currentTrack?.displayTitle ?? "Nothing selected")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(AppTheme.ink)
                    .lineLimit(2)

                Text(audioPlayer.currentTrack?.displayArtist ?? "Choose a track from search or library")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.mutedInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppTheme.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 22, x: 0, y: 12)
    }
}

struct MiniVinylArtwork: View {
    let track: Track?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.ink)
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)

            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    .frame(width: size - CGFloat(index * 15), height: size - CGFloat(index * 15))
            }

            if let track {
                TrackArtworkView(track: track, size: size * 0.42, cornerRadius: size * 0.21, showsSourceBadge: false)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(AppTheme.paperDeep)
                    .frame(width: size * 0.42, height: size * 0.42)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(AppTheme.mutedInk)
                    )
            }

            Circle()
                .fill(AppTheme.ink)
                .frame(width: size * 0.09, height: size * 0.09)
        }
        .frame(width: size, height: size)
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
                    .foregroundColor(AppTheme.ink)

                Spacer()

                if !dataManager.favoritePlaylists.isEmpty {
                    Text("\(dataManager.favoritePlaylists.count) favorites")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.mutedInk)
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
                                .fill(AppTheme.panel)
                                .frame(width: 140, height: 140)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.system(size: 32))
                                        .foregroundColor(AppTheme.mutedInk)
                                )

                            Text("Create")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.mutedInk)
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
                .foregroundColor(AppTheme.ink)
                .lineLimit(1)

            Text("\(playlist.trackCount) tracks")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.mutedInk)
        }
        .frame(width: 140, alignment: .leading)
    }
}

struct PopularSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Popular")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(AppTheme.ink)

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
                    .fill(AppTheme.panel)
                    .frame(width: 140, height: 140)

                Text("Mix #\(index + 1)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.ink)
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
                .foregroundColor(AppTheme.ink)

            VStack(spacing: 0) {
                ForEach(Array(dataManager.tracks.prefix(10))) { track in
                    TrackRow(track: track, contextTracks: Array(dataManager.tracks.prefix(10)))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.panel)
            )
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.line, lineWidth: 1))
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
                        .foregroundColor(AppTheme.mutedInk.opacity(0.5))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isPlaying ? AppTheme.accent : AppTheme.ink)

                Text(track.displayArtist)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.mutedInk)
            }

            Spacer()

            Text(track.formattedDuration)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.mutedInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.04))
                )

            Image(systemName: dataManager.isTrackSaved(track) ? "heart.fill" : "heart")
                .foregroundColor(dataManager.isTrackSaved(track) ? AppTheme.accent : AppTheme.mutedInk.opacity(0.55))
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
