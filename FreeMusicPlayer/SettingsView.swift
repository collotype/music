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
    @State private var showingMyWaveSettings = false
    @State private var actionInfo: SettingsActionInfo?

    private var spotifyConfigured: Bool {
        OnlineMusicService.shared.isSpotifyConfigured
    }

    private var appVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, build != version {
            return "\(version) (\(build))"
        }

        return version
    }

    private var myWaveSummary: String {
        let labels = dataManager.myWaveSettings.selectedLabels
        return labels.isEmpty ? "Default profile from your listening activity." : labels.joined(separator: " / ")
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

                    VStack(alignment: .leading, spacing: 10) {
                        settingsLabel(
                            title: "Audio quality",
                            subtitle: "Saved preference for online playback and downloads."
                        )

                        Picker("Audio quality", selection: audioQualityBinding) {
                            ForEach(AppSettings.AudioQuality.allCases, id: \.self) { quality in
                                Text(audioQualityTitle(quality)).tag(quality)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.white)
                    }
                    .padding(.vertical, 8)

                    settingsValueRow(
                        title: "Playback speed",
                        subtitle: "Current player speed",
                        value: String(format: "%.2gx", Double(audioPlayer.playbackSpeed))
                    )
                }

                settingsSection(title: "Discovery", icon: "waveform.path.ecg") {
                    Button {
                        debugLog("Open My Wave settings from Settings")
                        showingMyWaveSettings = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles.rectangle.stack")
                                .foregroundColor(.white)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("My Wave")
                                    .foregroundColor(.white)
                                Text(myWaveSummary)
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                                    .lineLimit(2)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }

                settingsSection(title: "Services", icon: "cloud.fill") {
                    settingsValueRow(
                        title: "SoundCloud",
                        subtitle: "Online search and playback are available.",
                        value: "Enabled",
                        valueColor: .green
                    )

                    Button {
                        debugLog("Spotify status row pressed")
                        actionInfo = SettingsActionInfo(
                            title: "Spotify",
                            message: spotifyConfigured
                                ? "Spotify credentials are configured. Search support exists in the service layer."
                                : "Spotify service code exists, but credentials are not configured for this build yet."
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.white)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Spotify")
                                    .foregroundColor(.white)
                                Text(spotifyConfigured ? "Configured for this build." : "Not configured for this build.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            Text(spotifyConfigured ? "Ready" : "Unavailable")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(spotifyConfigured ? .green : .orange)

                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
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
        .sheet(isPresented: $showingMyWaveSettings) {
            MyWaveSettingsView()
                .environmentObject(dataManager)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
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
        .alert(item: $actionInfo) { info in
            Alert(
                title: Text(info.title),
                message: Text(info.message),
                dismissButton: .default(Text("OK"))
            )
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

    private var audioQualityBinding: Binding<AppSettings.AudioQuality> {
        Binding(
            get: { dataManager.settings.quality },
            set: { newValue in
                dataManager.setAudioQualityPreference(newValue)
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

    private func audioQualityTitle(_ quality: AppSettings.AudioQuality) -> String {
        switch quality {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        case .lossless:
            return "Lossless"
        }
    }
}

struct SettingsActionInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    SettingsView()
        .environmentObject(AudioPlayer.shared)
        .environmentObject(DataManager.shared)
}
