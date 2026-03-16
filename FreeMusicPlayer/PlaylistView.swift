//
//  PlaylistView.swift
//  FreeMusicPlayer
//
//  Playlist detail screen.
//

import SwiftUI

struct PlaylistView: View {
    let playlistId: String

    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var audioPlayer: AudioPlayer

    private var playlist: Playlist? {
        dataManager.playlist(withID: playlistId)
    }

    private var playlistTracks: [Track] {
        dataManager.tracks(for: playlistId)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let playlist {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                Text(playlist.displayName)
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.white)

                                Spacer()

                                Button {
                                    debugLog("Playlist favorite toggle pressed: \(playlist.displayName)")
                                    dataManager.togglePlaylistFavorite(playlist)
                                } label: {
                                    Image(systemName: playlist.isStarred ? "star.fill" : "star")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(playlist.isStarred ? .yellow : .white.opacity(0.6))
                                        .padding(10)
                                        .background(
                                            Circle()
                                                .fill(Color.white.opacity(0.08))
                                        )
                                }
                                .buttonStyle(.plain)
                            }

                            HStack(spacing: 8) {
                                Text("\(playlistTracks.count) tracks")
                                    .foregroundColor(.gray)

                                if playlist.isStarred {
                                    Text("Favorite")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.yellow)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule()
                                                .fill(Color.yellow.opacity(0.12))
                                        )
                                }
                            }

                            if !playlistTracks.isEmpty {
                                Button {
                                    debugLog("Playlist play button pressed: \(playlist.name)")
                                    if let firstTrack = playlistTracks.first {
                                        audioPlayer.playTrack(firstTrack)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "play.fill")
                                        Text("Play playlist")
                                    }
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 12)
                                    .background(
                                        Capsule()
                                            .fill(Color.white)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(Color.clear)

                    if playlistTracks.isEmpty {
                        Section {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("This playlist is empty.")
                                    .foregroundColor(.gray)
                                Text("Add tracks from Library with the + button on a track row.")
                                    .font(.system(size: 13))
                                    .foregroundColor(.gray.opacity(0.75))
                            }
                            .padding(.vertical, 8)
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        Section("Tracks") {
                            ForEach(playlistTracks) { track in
                                PlaylistTrackRow(track: track, playlistName: playlist.name)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets())
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.black)
                .navigationTitle(playlist.displayName)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.2))
                    Text("Playlist not found")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .navigationTitle("Playlist")
            }
        }
    }
}

struct PlaylistTrackRow: View {
    let track: Track
    let playlistName: String

    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var dataManager: DataManager

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
                    .foregroundColor(.white)

                Text(track.displayArtist)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            Button {
                debugLog("Playlist favorite button pressed: \(track.displayTitle)")
                dataManager.toggleFavorite(track)
            } label: {
                Image(systemName: dataManager.favorites.contains(track.id) ? "heart.fill" : "heart")
                    .foregroundColor(dataManager.favorites.contains(track.id) ? .red : .white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            debugLog("Playlist track tapped: \(track.displayTitle) from \(playlistName)")
            audioPlayer.playTrack(track)
        }
    }
}

#Preview {
    NavigationStack {
        PlaylistView(playlistId: UUID().uuidString)
            .environmentObject(DataManager.shared)
            .environmentObject(AudioPlayer.shared)
    }
}
