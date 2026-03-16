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
    @State private var showClearConfirm: Bool = false
    @State private var actionInfo: SettingsActionInfo?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            List {
                settingsSection(title: "General", icon: "gear") {
                    settingRow(title: "Basics", icon: "gearshape") {
                        showPlaceholder(for: "Basics")
                    }
                    settingRow(title: "Storage", icon: "externaldrive") {
                        showPlaceholder(for: "Storage")
                    }
                    settingRow(title: "Gestures", icon: "hand.tap") {
                        showPlaceholder(for: "Gestures")
                    }
                }
                
                settingsSection(title: "Appearance", icon: "paintbrush") {
                    settingRow(title: "Interface", icon: "display") {
                        showPlaceholder(for: "Interface")
                    }
                    settingRow(title: "Customization", icon: "slider.horizontal.3") {
                        showPlaceholder(for: "Customization")
                    }
                    settingRow(title: "Player", icon: "play.circle") {
                        showPlaceholder(for: "Player")
                    }
                    settingRow(title: "Artwork", icon: "photo") {
                        showPlaceholder(for: "Artwork")
                    }
                }
                
                settingsSection(title: "Integrations", icon: "link") {
                    settingRow(title: "Proxy", icon: "shield") {
                        showPlaceholder(for: "Proxy")
                    }
                    settingRow(title: "Last.fm", icon: "waveform") {
                        showPlaceholder(for: "Last.fm")
                    }
                }
                
                settingsSection(title: "Services", icon: "cloud") {
                    settingRow(title: "YouTube Music", icon: "play.circle", configured: true) {
                        showPlaceholder(for: "YouTube Music")
                    }
                    settingRow(title: "SoundCloud", icon: "cloud") {
                        showPlaceholder(for: "SoundCloud")
                    }
                    settingRow(title: "Spotify", icon: "sparkles") {
                        showPlaceholder(for: "Spotify")
                    }
                }
                
                settingsSection(title: "Storage", icon: "externaldrive") {
                    storageInfoRow
                    
                    Button {
                        debugLog("Clear cache button pressed")
                        showClearConfirm = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Clear library data")
                                    .foregroundColor(.white)
                                Text("Remove tracks, playlists, and saved settings.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                settingsSection(title: "About", icon: "info.circle") {
                    HStack {
                        Text("Version")
                            .foregroundColor(.white)
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 12)
                    
                    Button {
                        debugLog("Open source code button pressed")
                        guard let url = URL(string: "https://github.com/collotype/FreeMusicPlayer-iOS") else {
                            return
                        }
                        openURL(url)
                    } label: {
                        HStack {
                            Text("Open source code")
                                .foregroundColor(.white)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.gray)
                        }
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
            Text("This removes imported tracks, playlists, favorites, and app settings.")
        }
        .alert(item: $actionInfo) { info in
            Alert(
                title: Text(info.title),
                message: Text(info.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    func settingsSection<Content: View>(
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
    
    func settingRow(
        title: String,
        icon: String,
        configured: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            debugLog("Settings row pressed: \(title)")
            action()
        } label: {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.white)
                    .frame(width: 30)
                
                Text(title)
                    .foregroundColor(.white)
                
                Spacer()
                
                if configured {
                    Text("Connected")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                }
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
    
    var storageInfoRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Used")
                        .foregroundColor(.white)
                    Text("0 MB")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Available")
                        .foregroundColor(.gray)
                    Text("Unlimited")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.gray)
                }
            }
            
            GeometryReader { _ in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.red, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 0, height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 12)
    }
    
    private func showPlaceholder(for title: String) {
        actionInfo = SettingsActionInfo(
            title: title,
            message: "\(title) is wired up and receiving taps. The detailed screen is not implemented yet."
        )
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
