//
//  SettingsView.swift
//  FreeMusicPlayer
//
//  Settings screen.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var audioPlayer: AudioPlayer
    @Environment(\.openURL) private var openURL

    @State private var showClearConfirm = false

    private var appVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, build != version {
            return "\(version) (\(build))"
        }

        return version
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            List {
                settingsSection(title: "Playback", icon: "play.circle.fill") {
                    Toggle(isOn: lyricsBinding) {
                        settingsLabel(
                            title: "Show lyrics in player",
                            subtitle: "Controls the lyrics entry point from the full player."
                        )
                    }
                    .tint(.red)

                    Toggle(isOn: shuffleBinding) {
                        settingsLabel(
                            title: "Shuffle playback",
                            subtitle: "Applies to queue and collection playback."
                        )
                    }
                    .tint(.red)

                    VStack(alignment: .leading, spacing: 10) {
                        settingsLabel(
                            title: "Repeat mode",
                            subtitle: "Choose how playback continues after the current track."
                        )

                        Picker("Repeat mode", selection: repeatModeBinding) {
                            ForEach(AppSettings.RepeatMode.allCases, id: \.self) { mode in
                                Text(repeatModeTitle(mode)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 8)

                    settingsValueRow(
                        title: "Playback speed",
                        subtitle: "Current player speed",
                        value: String(format: "%.2gx", Double(audioPlayer.playbackSpeed))
                    )
                }

                settingsSection(title: "Library", icon: "books.vertical.fill") {
                    settingsValueRow(
                        title: "Tracks",
                        subtitle: "Saved in your local library",
                        value: "\(dataManager.tracks.count)"
                    )
                    settingsValueRow(
                        title: "Playlists",
                        subtitle: "Total collections in your library",
                        value: "\(dataManager.playlists.count)"
                    )
                    settingsValueRow(
                        title: "Starred playlists",
                        subtitle: "Pinned for faster access",
                        value: "\(dataManager.favoritePlaylists.count)"
                    )
                    settingsValueRow(
                        title: "Favorite artists",
                        subtitle: "Saved from online artist pages",
                        value: "\(dataManager.favoriteArtists.count)"
                    )
                    settingsValueRow(
                        title: "Linked folders",
                        subtitle: "Imported by bookmark refresh",
                        value: "\(dataManager.importFolders.count)"
                    )

                    Toggle(isOn: cacheBinding) {
                        settingsLabel(
                            title: "Artwork and metadata cache",
                            subtitle: "Saved preference for keeping local cache enabled."
                        )
                    }
                    .tint(.red)

                    Button(role: .destructive) {
                        debugLog("Clear library data button pressed")
                        showClearConfirm = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Clear library data")
                                    .foregroundColor(.white)
                                Text("Remove tracks, playlists, favorite artists, and saved settings.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }

                settingsSection(title: "About", icon: "info.circle.fill") {
                    settingsValueRow(
                        title: "Version",
                        subtitle: "Current build",
                        value: appVersionLabel
                    )

                    Button {
                        debugLog("Open source code button pressed")
                        guard let url = URL(string: "https://github.com/collotype/music") else {
                            return
                        }
                        openURL(url)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.white)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Open source code")
                                    .foregroundColor(.white)
                                Text("Open the active GitHub repository for this app.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.black)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .accentColor(.white)
        .confirmationDialog("Clear all local data?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                debugLog("Clear cache confirmed")
                dataManager.clearAllData()
                audioPlayer.stop()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes imported tracks, playlists, favorite artists, and saved settings.")
        }
    }

    private var lyricsBinding: Binding<Bool> {
        Binding(
            get: { dataManager.settings.showLyrics },
            set: { newValue in
                dataManager.setShowLyricsPreference(newValue)
            }
        )
    }

    private var shuffleBinding: Binding<Bool> {
        Binding(
            get: { dataManager.settings.shuffle },
            set: { newValue in
                dataManager.setShufflePreference(newValue)
                audioPlayer.applySavedPlaybackPreferences(dataManager.settings)
            }
        )
    }

    private var repeatModeBinding: Binding<AppSettings.RepeatMode> {
        Binding(
            get: { dataManager.settings.repeatMode },
            set: { newValue in
                dataManager.setRepeatModePreference(newValue)
                audioPlayer.applySavedPlaybackPreferences(dataManager.settings)
            }
        )
    }

    private var cacheBinding: Binding<Bool> {
        Binding(
            get: { dataManager.settings.cacheEnabled },
            set: { newValue in
                dataManager.setCacheEnabledPreference(newValue)
            }
        )
    }

    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            content()
        } header: {
            Label(title, systemImage: icon)
                .foregroundColor(.gray)
                .font(.system(size: 13, weight: .semibold))
        }
    }

    private func settingsLabel(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .foregroundColor(.white)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
        .padding(.vertical, 2)
    }

    private func settingsValueRow(
        title: String,
        subtitle: String,
        value: String,
        valueColor: Color = .white.opacity(0.76)
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(valueColor)
        }
        .padding(.vertical, 8)
    }

    private func repeatModeTitle(_ mode: AppSettings.RepeatMode) -> String {
        switch mode {
        case .off:
            return "Off"
        case .all:
            return "All"
        case .one:
            return "One"
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AudioPlayer.shared)
        .environmentObject(DataManager.shared)
}
