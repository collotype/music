//
//  SettingsView.swift
//  FreeMusicPlayer
//
//  Settings screen.
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var audioPlayer: AudioPlayer
    @Environment(\.openURL) private var openURL

    @State private var showClearConfirm = false
    @State private var showVKTokenInstructions = false
    @State private var showVKUserAgentHelp = false
    @State private var showVKManualSetup = false
    @State private var isCheckingVKConnection = false
    @State private var vkCredentialSnapshot = OnlineMusicService.shared.vkCredentialSnapshot
    @State private var vkConnectionStatus = OnlineMusicService.shared.vkConnectionStatus
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

                vkMusicSection

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
        .sheet(isPresented: $showVKTokenInstructions) {
            VKTokenInstructionView(accessTokenURL: OnlineMusicService.shared.vkManualAccessTokenURL)
        }
        .sheet(isPresented: $showVKUserAgentHelp) {
            VKUserAgentHelpView()
        }
        .sheet(isPresented: $showVKManualSetup) {
            VKManualCredentialsView { status, message in
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

    private var vkMusicSection: some View {
        settingsSection(title: "VK Music", icon: "music.note") {
            settingsValueRow(
                title: "Статус",
                subtitle: "Ручное подключение",
                value: vkStatusTitle,
                valueColor: vkStatusColor
            )

            Text(vkStatusDescription)
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .padding(.vertical, 6)

            if vkCredentialSnapshot.hasCredentials {
                if let maskedAccessToken = vkCredentialSnapshot.maskedAccessToken {
                    settingsValueRow(
                        title: "Access token",
                        subtitle: "Сохранён в Keychain",
                        value: maskedAccessToken,
                        valueColor: .white.opacity(0.72)
                    )
                }

                settingsValueRow(
                    title: "User-Agent",
                    subtitle: "Сохранён в Keychain",
                    value: vkCredentialSnapshot.shortenedUserAgent ?? "Не указан",
                    valueColor: vkCredentialSnapshot.shortenedUserAgent == nil ? .orange : .white.opacity(0.72)
                )

                Button {
                    checkVKConnection()
                } label: {
                    settingsActionRow(
                        icon: isCheckingVKConnection ? "hourglass" : "checkmark.seal",
                        title: "Проверить подключение",
                        subtitle: "Проверить VK аккаунт и доступ к VK Music."
                    )
                }
                .buttonStyle(.plain)
                .disabled(isCheckingVKConnection)

                Button {
                    showVKManualSetup = true
                } label: {
                    settingsActionRow(
                        icon: "square.and.pencil",
                        title: "Изменить данные",
                        subtitle: "Обновить access token или User-Agent."
                    )
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    disconnectVK()
                } label: {
                    settingsActionRow(
                        icon: "power",
                        title: "Отключить VK",
                        subtitle: "Удалить VK credentials из Keychain.",
                        iconColor: .red
                    )
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    openURL(OnlineMusicService.shared.vkManualAccessTokenURL)
                    showVKTokenInstructions = true
                } label: {
                    settingsActionRow(
                        icon: "safari",
                        title: "Получить access token",
                        subtitle: "Открыть VK OAuth страницу в браузере."
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showVKUserAgentHelp = true
                } label: {
                    settingsActionRow(
                        icon: "questionmark.circle",
                        title: "Где взять User-Agent?",
                        subtitle: "Пояснение и рекомендуемый вариант."
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showVKManualSetup = true
                } label: {
                    settingsActionRow(
                        icon: "doc.on.clipboard",
                        title: "Вставить данные",
                        subtitle: "Сохранить access token и User-Agent."
                    )
                }
                .buttonStyle(.plain)

                Button {
                    checkVKConnection()
                } label: {
                    settingsActionRow(
                        icon: isCheckingVKConnection ? "hourglass" : "checkmark.seal",
                        title: "Проверить подключение",
                        subtitle: "Проверить сохранённые данные VK."
                    )
                }
                .buttonStyle(.plain)
                .disabled(isCheckingVKConnection)
            }

            if let vkCredentialMessage {
                Text(vkCredentialMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .padding(.vertical, 4)
            }
        }
    }

    private var vkStatusTitle: String {
        if !vkCredentialSnapshot.hasCredentials {
            return "Не подключено"
        }

        switch vkConnectionStatus {
        case .musicAccessUnavailable:
            return "Нужен VK Music доступ"
        case .invalidCredentials, .expired, .networkError:
            return vkConnectionStatus.title
        default:
            return "Подключено"
        }
    }

    private var vkStatusDescription: String {
        if !vkCredentialSnapshot.hasCredentials {
            return "Чтобы искать музыку во VK, приложению нужен access token и User-Agent. Сейчас их нужно добавить вручную."
        }

        return vkConnectionStatus.detail
    }

    private var vkStatusColor: Color {
        switch vkConnectionStatus {
        case .notConfigured:
            return .gray
        case .validBasicToken:
            return .orange
        case .musicAccessAvailable:
            return .green
        case .musicAccessUnavailable:
            return .orange
        case .invalidCredentials, .expired, .networkError:
            return .red
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
                .multilineTextAlignment(.trailing)
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

    private func checkVKConnection() {
        guard !isCheckingVKConnection else { return }

        isCheckingVKConnection = true
        vkCredentialMessage = nil

        Task {
            let status = await OnlineMusicService.shared.checkVKConnection()
            await MainActor.run {
                applyVKConnectionUpdate(status: status, message: status.detail)
                isCheckingVKConnection = false
            }
        }
    }

    private func disconnectVK() {
        OnlineMusicService.shared.clearVKMobileAudioCredentials()
        applyVKConnectionUpdate(status: .notConfigured, message: "VK отключён. Token и User-Agent удалены из Keychain.")
    }

    private func applyVKConnectionUpdate(status: VKConnectionStatus, message: String?) {
        vkCredentialSnapshot = OnlineMusicService.shared.vkCredentialSnapshot
        vkConnectionStatus = status
        vkCredentialMessage = message
    }

    private func refreshVKCredentialState() {
        vkCredentialSnapshot = OnlineMusicService.shared.vkCredentialSnapshot
        vkConnectionStatus = OnlineMusicService.shared.vkConnectionStatus
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

private struct VKTokenInstructionView: View {
    @Environment(\.dismiss) private var dismiss

    let accessTokenURL: URL

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                List {
                    Section {
                        Text("После входа VK откроет пустую страницу. В адресной строке появится ссылка вида:")
                            .foregroundColor(.white)
                        Text("https://oauth.vk.com/blank.html#access_token=...&expires_in=...&user_id=...")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.gray)
                            .textSelection(.enabled)
                        Text("Скопируйте значение после access_token= и вставьте его в поле Access token.")
                            .foregroundColor(.white)
                    }

                    Section {
                        Text(accessTokenURL.absoluteString)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.gray)
                            .textSelection(.enabled)
                    } header: {
                        Text("Открытая ссылка")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.black)
            }
            .navigationTitle("Access token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct VKUserAgentHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copyMessage: String?

    private let recommendedUserAgent = OnlineMusicService.shared.recommendedVKUserAgent

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                List {
                    Section {
                        Text("Для VK Music может понадобиться User-Agent мобильного клиента, который поддерживает музыкальный API. Если обычный токен не работает, укажите User-Agent, с которым был получен токен.")
                            .foregroundColor(.white)
                        Text("Если вы не знаете, что сюда вводить, попробуйте оставить поле пустым. Если VK вернёт ошибку music access, потребуется совместимый User-Agent.")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }

                    Section {
                        Text(recommendedUserAgent)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.gray)
                            .textSelection(.enabled)

                        Button {
                            UIPasteboard.general.string = recommendedUserAgent
                            copyMessage = "Рекомендуемый User-Agent скопирован."
                        } label: {
                            helpActionRow(icon: "doc.on.doc", title: "Скопировать рекомендуемый User-Agent")
                        }
                        .buttonStyle(.plain)

                        Button {
                            UIPasteboard.general.string = recommendedUserAgent
                            copyMessage = "Скопировано. Вставьте User-Agent на экране «Вставить данные»."
                        } label: {
                            helpActionRow(icon: "checkmark.circle", title: "Использовать рекомендуемый")
                        }
                        .buttonStyle(.plain)
                    } header: {
                        Text("Рекомендуемый")
                    }

                    if let copyMessage {
                        Section {
                            Text(copyMessage)
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.black)
            }
            .navigationTitle("User-Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func helpActionRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.white)
                .frame(width: 30)
            Text(title)
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.vertical, 10)
    }
}

private struct VKManualCredentialsView: View {
    @Environment(\.dismiss) private var dismiss

    let onCredentialsChanged: (VKConnectionStatus, String?) -> Void

    @State private var accessTokenInput = ""
    @State private var userAgentInput = OnlineMusicService.shared.vkCredentialSnapshot.userAgent ?? ""
    @State private var snapshot = OnlineMusicService.shared.vkCredentialSnapshot
    @State private var statusMessage: String?
    @State private var isCheckingConnection = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Access token")
                                .foregroundColor(.white)

                            SecureField(
                                snapshot.maskedAccessToken.map { "Сохранён: \($0)" } ?? "vk1.a...",
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

                            TextField("Можно оставить пустым", text: $userAgentInput)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundColor(.white)

                            if cleanedText(userAgentInput) == nil {
                                Text("Без User-Agent VK Music может не работать. Если получите ошибку music access, укажите совместимый User-Agent.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    Section {
                        Button {
                            saveCredentials(showSuccessMessage: true)
                        } label: {
                            setupActionRow(
                                icon: "checkmark.circle",
                                title: "Сохранить",
                                subtitle: "Token и User-Agent будут сохранены в Keychain."
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            saveAndCheckCredentials()
                        } label: {
                            setupActionRow(
                                icon: isCheckingConnection ? "hourglass" : "checkmark.seal",
                                title: "Сохранить и проверить",
                                subtitle: "Проверить VK аккаунт и VK Music доступ."
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
            .navigationTitle("Вставить данные")
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

    private func saveCredentials(showSuccessMessage: Bool) {
        let cleanedAccessToken = cleanedText(accessTokenInput)

        guard cleanedAccessToken != nil || snapshot.hasCredentials else {
            let message = "Введите access token."
            statusMessage = message
            onCredentialsChanged(.notConfigured, message)
            return
        }

        do {
            try OnlineMusicService.shared.saveVKMobileAudioCredentials(
                accessToken: cleanedAccessToken ?? "",
                userAgent: userAgentInput
            )
            accessTokenInput = ""
            refreshSnapshot(resetUserAgent: true)

            if showSuccessMessage {
                let message = "Данные VK сохранены в Keychain. Полный token в интерфейсе не показывается."
                statusMessage = message
                onCredentialsChanged(.validBasicToken, message)
            } else {
                onCredentialsChanged(.validBasicToken, nil)
            }
        } catch let error as OnlineMusicServiceError {
            let message = error.localizedDescription
            statusMessage = message
            onCredentialsChanged(.invalidCredentials, message)
        } catch {
            let message = "Не удалось сохранить данные VK."
            statusMessage = message
            onCredentialsChanged(.networkError, message)
        }
    }

    private func saveAndCheckCredentials() {
        guard !isCheckingConnection else { return }
        saveCredentials(showSuccessMessage: false)

        guard OnlineMusicService.shared.vkCredentialSnapshot.hasCredentials else {
            return
        }

        isCheckingConnection = true
        statusMessage = nil

        Task {
            let status = await OnlineMusicService.shared.checkVKConnection()
            await MainActor.run {
                refreshSnapshot(resetUserAgent: true)
                statusMessage = status.detail
                onCredentialsChanged(status, status.detail)
                isCheckingConnection = false
            }
        }
    }

    private func clearCredentials() {
        OnlineMusicService.shared.clearVKMobileAudioCredentials()
        accessTokenInput = ""
        userAgentInput = ""
        refreshSnapshot(resetUserAgent: false)

        let message = "VK credentials удалены из Keychain."
        statusMessage = message
        onCredentialsChanged(.notConfigured, message)
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
