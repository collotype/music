//
//  SettingsView.swift
//  FreeMusicPlayer
//
//  Settings screen.
//

import SwiftUI

private enum VKConnectionStatus: Equatable {
    case notConnected
    case connected
    case needsSetup
    case connectionError

    var title: String {
        switch self {
        case .notConnected:
            return "Не подключено"
        case .connected:
            return "Подключено"
        case .needsSetup:
            return "Нужна настройка"
        case .connectionError:
            return "Ошибка подключения"
        }
    }

    var color: Color {
        switch self {
        case .notConnected:
            return .gray
        case .connected:
            return .green
        case .needsSetup:
            return .orange
        case .connectionError:
            return .red
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var audioPlayer: AudioPlayer
    @Environment(\.openURL) private var openURL

    @State private var showClearConfirm = false
    @State private var showVKSetup = false
    @State private var isCheckingVKConnection = false
    @State private var vkCredentialSnapshot = OnlineMusicService.shared.vkCredentialSnapshot
    @State private var vkConnectionStatus: VKConnectionStatus = OnlineMusicService.shared.isVKConfigured ? .needsSetup : .notConnected
    @State private var vkCredentialMessage: String?

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

                settingsSection(title: "VK Music", icon: "music.note") {
                    settingsValueRow(
                        title: "Статус подключения",
                        subtitle: "Поиск VK Music",
                        value: vkConnectionStatus.title,
                        valueColor: vkConnectionStatus.color
                    )

                    Text("Чтобы искать музыку во VK, приложению нужен доступ к VK Music. Сейчас автоматический вход ещё не настроен, поэтому можно добавить access token и User-Agent вручную.")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                        .padding(.vertical, 6)

                    if let maskedAccessToken = vkCredentialSnapshot.maskedAccessToken {
                        settingsValueRow(
                            title: "Access token",
                            subtitle: "Сохранён в Keychain",
                            value: maskedAccessToken,
                            valueColor: .white.opacity(0.72)
                        )
                    }

                    Button {
                        showVKSetup = true
                    } label: {
                        settingsActionRow(
                            icon: "slider.horizontal.3",
                            title: "Настроить VK",
                            subtitle: "Добавить token и User-Agent вручную."
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        checkVKConnection()
                    } label: {
                        settingsActionRow(
                            icon: isCheckingVKConnection ? "hourglass" : "checkmark.seal",
                            title: "Проверить подключение",
                            subtitle: "Выполнить лёгкий запрос к VK Music."
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isCheckingVKConnection)

                    if vkCredentialSnapshot.hasCredentials {
                        Button(role: .destructive) {
                            clearVKCredentials()
                        } label: {
                            settingsActionRow(
                                icon: "power",
                                title: "Отключить VK",
                                subtitle: "Удалить сохранённые данные VK из Keychain.",
                                iconColor: .red
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if let vkCredentialMessage {
                        Text(vkCredentialMessage)
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .padding(.vertical, 4)
                    }
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
        .onAppear {
            refreshVKCredentialState()
        }
        .sheet(isPresented: $showVKSetup) {
            VKConnectionSetupView { status, message in
                applyVKConnectionUpdate(status: status, message: message)
            }
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

    private func settingsActionRow(
        icon: String,
        title: String,
        subtitle: String,
        iconColor: Color = .white
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }

            Spacer()
        }
        .padding(.vertical, 10)
    }

    private func clearVKCredentials() {
        OnlineMusicService.shared.clearVKMobileAudioCredentials()
        vkCredentialSnapshot = OnlineMusicService.shared.vkCredentialSnapshot
        vkConnectionStatus = .notConnected
        vkCredentialMessage = "VK Music отключён. Сохранённые token и User-Agent удалены."
    }

    private func checkVKConnection() {
        guard !isCheckingVKConnection else { return }

        isCheckingVKConnection = true
        vkCredentialMessage = nil

        Task {
            do {
                try await OnlineMusicService.shared.checkVKConnection()
                await MainActor.run {
                    vkCredentialSnapshot = OnlineMusicService.shared.vkCredentialSnapshot
                    vkConnectionStatus = .connected
                    vkCredentialMessage = "VK Music подключён. Поиск готов к работе."
                    isCheckingVKConnection = false
                }
            } catch let error as OnlineMusicServiceError {
                await MainActor.run {
                    handleVKConnectionError(error)
                    isCheckingVKConnection = false
                }
            } catch {
                await MainActor.run {
                    vkConnectionStatus = .connectionError
                    vkCredentialMessage = "Не удалось подключиться к VK. Проверьте интернет."
                    isCheckingVKConnection = false
                }
            }
        }
    }

    private func handleVKConnectionError(_ error: OnlineMusicServiceError) {
        refreshVKCredentialState()
        switch error {
        case .vkNotConfigured:
            vkConnectionStatus = .notConnected
        default:
            vkConnectionStatus = .connectionError
        }
        vkCredentialMessage = error.localizedDescription
    }

    private func applyVKConnectionUpdate(status: VKConnectionStatus, message: String?) {
        vkCredentialSnapshot = OnlineMusicService.shared.vkCredentialSnapshot
        vkConnectionStatus = status
        vkCredentialMessage = message
    }

    private func refreshVKCredentialState() {
        vkCredentialSnapshot = OnlineMusicService.shared.vkCredentialSnapshot
        if !vkCredentialSnapshot.hasCredentials {
            vkConnectionStatus = .notConnected
        } else if vkConnectionStatus == .notConnected {
            vkConnectionStatus = .needsSetup
        }
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

private struct VKConnectionSetupView: View {
    @Environment(\.dismiss) private var dismiss

    let onCredentialsChanged: (VKConnectionStatus, String?) -> Void

    @State private var accessTokenInput = ""
    @State private var userAgentInput = OnlineMusicService.shared.vkCredentialSnapshot.userAgent ?? ""
    @State private var snapshot = OnlineMusicService.shared.vkCredentialSnapshot
    @State private var statusMessage: String?
    @State private var isCheckingConnection = false
    @State private var showLoginUnavailableAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                List {
                    Section {
                        Text("VK Music требует специальный access token и User-Agent. Обычный токен из браузера может не работать.")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .padding(.vertical, 6)

                        Button {
                            showLoginUnavailableAlert = true
                        } label: {
                            setupActionRow(
                                icon: "person.crop.circle.badge.plus",
                                title: "Войти через VK",
                                subtitle: "Автоматический вход появится позже."
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Access token")
                                .foregroundColor(.white)

                            SecureField(
                                snapshot.maskedAccessToken.map { "Сохранён: \($0)" } ?? "Access token",
                                text: $accessTokenInput
                            )
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundColor(.white)

                            if let maskedAccessToken = snapshot.maskedAccessToken {
                                Text("Сейчас сохранён: \(maskedAccessToken)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.vertical, 8)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("User-Agent")
                                .foregroundColor(.white)

                            TextField("User-Agent", text: $userAgentInput)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundColor(.white)
                        }
                        .padding(.vertical, 8)

                        Text("Если вы не знаете, что сюда вводить, оставьте поля пустыми. Позже здесь появится вход через VK.")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .padding(.vertical, 6)
                    }

                    Section {
                        Button {
                            _ = saveCredentials(showSuccessMessage: true)
                        } label: {
                            setupActionRow(
                                icon: "checkmark.circle",
                                title: "Сохранить",
                                subtitle: "Token и User-Agent будут сохранены в Keychain."
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            checkConnection()
                        } label: {
                            setupActionRow(
                                icon: isCheckingConnection ? "hourglass" : "checkmark.seal",
                                title: "Проверить",
                                subtitle: "Проверить, принимает ли VK эти данные."
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isCheckingConnection)

                        Button(role: .destructive) {
                            clearCredentials()
                        } label: {
                            setupActionRow(
                                icon: "trash",
                                title: "Очистить",
                                subtitle: "Удалить сохранённые данные VK.",
                                iconColor: .red
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if let statusMessage {
                        Section {
                            Text(statusMessage)
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.black)
            }
            .navigationTitle("Подключение VK")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                refreshSnapshot()
            }
            .alert("Автоматический вход VK пока не настроен.", isPresented: $showLoginUnavailableAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Сейчас можно добавить token и User-Agent вручную.")
            }
        }
    }

    private func setupActionRow(
        icon: String,
        title: String,
        subtitle: String,
        iconColor: Color = .white
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }

            Spacer()
        }
        .padding(.vertical, 10)
    }

    private func saveCredentials(showSuccessMessage: Bool) -> Bool {
        let cleanedAccessToken = cleanedText(accessTokenInput)
        let cleanedUserAgent = cleanedText(userAgentInput)

        guard cleanedAccessToken != nil || snapshot.hasCredentials else {
            OnlineMusicService.shared.clearVKMobileAudioCredentials()
            refreshSnapshot(resetUserAgent: false)
            let message = "Добавьте access token и User-Agent, чтобы подключить VK Music."
            statusMessage = message
            onCredentialsChanged(.notConnected, message)
            return false
        }

        guard let cleanedUserAgent else {
            let message = "Добавьте User-Agent, чтобы подключить VK Music."
            statusMessage = message
            onCredentialsChanged(snapshot.hasCredentials ? .needsSetup : .notConnected, message)
            return false
        }

        do {
            try OnlineMusicService.shared.saveVKMobileAudioCredentials(
                accessToken: cleanedAccessToken ?? "",
                userAgent: cleanedUserAgent
            )
            accessTokenInput = ""
            refreshSnapshot(resetUserAgent: true)

            if showSuccessMessage {
                let message = "Данные VK сохранены в Keychain. Нажмите «Проверить», чтобы проверить подключение."
                statusMessage = message
                onCredentialsChanged(.needsSetup, message)
            } else {
                onCredentialsChanged(.needsSetup, nil)
            }

            return true
        } catch let error as OnlineMusicServiceError {
            let message = error.localizedDescription
            statusMessage = message
            onCredentialsChanged(.connectionError, message)
            return false
        } catch {
            let message = "Не удалось сохранить данные VK."
            statusMessage = message
            onCredentialsChanged(.connectionError, message)
            return false
        }
    }

    private func checkConnection() {
        guard !isCheckingConnection else { return }
        guard saveCredentials(showSuccessMessage: false) else { return }

        isCheckingConnection = true
        statusMessage = nil

        Task {
            do {
                try await OnlineMusicService.shared.checkVKConnection()
                await MainActor.run {
                    refreshSnapshot(resetUserAgent: true)
                    let message = "VK Music подключён. Поиск готов к работе."
                    statusMessage = message
                    onCredentialsChanged(.connected, message)
                    isCheckingConnection = false
                }
            } catch let error as OnlineMusicServiceError {
                await MainActor.run {
                    refreshSnapshot(resetUserAgent: true)
                    let status: VKConnectionStatus = error == .vkNotConfigured ? .notConnected : .connectionError
                    let message = error.localizedDescription
                    statusMessage = message
                    onCredentialsChanged(status, message)
                    isCheckingConnection = false
                }
            } catch {
                await MainActor.run {
                    refreshSnapshot(resetUserAgent: true)
                    let message = "Не удалось подключиться к VK. Проверьте интернет."
                    statusMessage = message
                    onCredentialsChanged(.connectionError, message)
                    isCheckingConnection = false
                }
            }
        }
    }

    private func clearCredentials() {
        OnlineMusicService.shared.clearVKMobileAudioCredentials()
        accessTokenInput = ""
        userAgentInput = ""
        refreshSnapshot(resetUserAgent: false)

        let message = "VK Music отключён. Сохранённые token и User-Agent удалены."
        statusMessage = message
        onCredentialsChanged(.notConnected, message)
    }

    private func refreshSnapshot(resetUserAgent: Bool = true) {
        snapshot = OnlineMusicService.shared.vkCredentialSnapshot
        if resetUserAgent {
            userAgentInput = snapshot.userAgent ?? ""
        }
    }

    private func cleanedText(_ value: String) -> String? {
        let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedValue.isEmpty ? nil : cleanedValue
    }
}

#Preview {
    SettingsView()
        .environmentObject(AudioPlayer.shared)
        .environmentObject(DataManager.shared)
}
