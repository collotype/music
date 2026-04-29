//
//  VKAuthService.swift
//  FreeMusicPlayer
//
//  VK manual credential storage and lightweight capability checks.
//

import Foundation
import Security

enum VKCredentialSource: String, Codable, Equatable, Sendable {
    case oauth
    case manual
}

struct VKCredentials: Codable, Equatable, Sendable {
    let accessToken: String
    let expiresAt: Date?
    let userId: String?
    let userAgent: String
    let source: VKCredentialSource

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    var maskedAccessToken: String {
        guard accessToken.count > 14 else {
            return "***"
        }

        return "\(accessToken.prefix(11))...\(accessToken.suffix(3))"
    }

    var shortenedUserAgent: String? {
        let cleanedValue = userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedValue.isEmpty else { return nil }
        guard cleanedValue.count > 42 else { return cleanedValue }
        return "\(cleanedValue.prefix(28))...\(cleanedValue.suffix(10))"
    }
}

struct VKCredentialSnapshot: Equatable, Sendable {
    let hasCredentials: Bool
    let maskedAccessToken: String?
    let userId: String?
    let userAgent: String?
    let shortenedUserAgent: String?
    let source: VKCredentialSource?
    let expiresAt: Date?
    let isExpired: Bool
}

enum VKConnectionStatus: Equatable, Sendable {
    case notConfigured
    case validBasicToken
    case musicAccessAvailable
    case musicAccessUnavailable
    case invalidCredentials
    case expired
    case networkError

    var title: String {
        switch self {
        case .notConfigured:
            return "Не подключено"
        case .validBasicToken:
            return "VK аккаунт подключён"
        case .musicAccessAvailable:
            return "Подключено"
        case .musicAccessUnavailable:
            return "Нужен VK Music доступ"
        case .invalidCredentials:
            return "Ошибка подключения"
        case .expired:
            return "Сессия VK истекла"
        case .networkError:
            return "Ошибка подключения"
        }
    }

    var detail: String {
        switch self {
        case .notConfigured:
            return "Чтобы искать музыку во VK, приложению нужен access token и User-Agent. Сейчас их нужно добавить вручную."
        case .validBasicToken:
            return "VK аккаунт подключён. Доступ к VK Music проверяется отдельно."
        case .musicAccessAvailable:
            return "VK Music подключён. Поиск готов к работе."
        case .musicAccessUnavailable:
            return "VK аккаунт подключён, но этот токен не даёт доступ к VK Music. Попробуйте другой token/User-Agent."
        case .invalidCredentials:
            return "VK не принял эти данные. Проверьте access token и User-Agent."
        case .expired:
            return "Срок действия access token истёк. Получите новый token и вставьте его в настройках."
        case .networkError:
            return "Не удалось подключиться к VK. Проверьте интернет."
        }
    }
}

final class VKCredentialsStore {
    private let service = "FreeMusicPlayer.VKCredentials"
    private let credentialsAccount = "VKCredentials"
    private let legacyService = "FreeMusicPlayer.VKMusicService"
    private let legacyAccessTokenAccount = "VKMobileAudioAccessToken"
    private let legacyUserAgentAccount = "VKMobileAudioUserAgent"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func credentials() -> VKCredentials? {
        if let data = data(for: credentialsAccount, service: service),
           let credentials = try? decoder.decode(VKCredentials.self, from: data),
           !credentials.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return credentials
        }

        return migratedLegacyCredentials()
    }

    func snapshot() -> VKCredentialSnapshot {
        let credentials = credentials()
        return VKCredentialSnapshot(
            hasCredentials: credentials != nil,
            maskedAccessToken: credentials?.maskedAccessToken,
            userId: credentials?.userId,
            userAgent: credentials?.userAgent,
            shortenedUserAgent: credentials?.shortenedUserAgent,
            source: credentials?.source,
            expiresAt: credentials?.expiresAt,
            isExpired: credentials?.isExpired ?? false
        )
    }

    func save(_ credentials: VKCredentials) throws {
        guard !credentials.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OnlineMusicServiceError.vkNotConfigured
        }

        let data = try encoder.encode(credentials)
        try setData(data, for: credentialsAccount, service: service)
        clearLegacyCredentials()
    }

    func clear() {
        deleteData(for: credentialsAccount, service: service)
        clearLegacyCredentials()
    }

    private func migratedLegacyCredentials() -> VKCredentials? {
        guard let accessToken = string(for: legacyAccessTokenAccount, service: legacyService),
              let userAgent = string(for: legacyUserAgentAccount, service: legacyService) else {
            return nil
        }

        let credentials = VKCredentials(
            accessToken: accessToken,
            expiresAt: nil,
            userId: nil,
            userAgent: userAgent,
            source: .manual
        )
        try? save(credentials)
        return credentials
    }

    private func clearLegacyCredentials() {
        deleteData(for: legacyAccessTokenAccount, service: legacyService)
        deleteData(for: legacyUserAgentAccount, service: legacyService)
    }

    private func string(for account: String, service: String) -> String? {
        guard let data = data(for: account, service: service),
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedValue.isEmpty ? nil : cleanedValue
    }

    private func data(for account: String, service: String) -> Data? {
        var query = baseQuery(account: account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              !data.isEmpty else {
            return nil
        }

        return data
    }

    private func setData(_ data: Data, for account: String, service: String) throws {
        deleteData(for: account, service: service)

        var query = baseQuery(account: account, service: service)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw OnlineMusicServiceError.configurationMissing("VK credentials could not be saved to Keychain.")
        }
    }

    private func deleteData(for account: String, service: String) {
        SecItemDelete(baseQuery(account: account, service: service) as CFDictionary)
    }

    private func baseQuery(account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

final class VKAuthService {
    private let session: URLSession
    private let credentialsStore: VKCredentialsStore
    private let decoder = JSONDecoder()
    private let usersGetURL = URL(string: "https://api.vk.com/method/users.get")!
    private let apiVersion = "5.131"

    static let recommendedUserAgent = VKMusicService.defaultMobileUserAgent

    init(session: URLSession, credentialsStore: VKCredentialsStore) {
        self.session = session
        self.credentialsStore = credentialsStore
    }

    var manualAccessTokenURL: URL {
        var components = URLComponents(string: "https://oauth.vk.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: "2685278"),
            URLQueryItem(name: "display", value: "page"),
            URLQueryItem(name: "redirect_uri", value: "https://oauth.vk.com/blank.html"),
            URLQueryItem(name: "scope", value: "audio"),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "v", value: apiVersion)
        ]
        return components.url!
    }

    func saveManualCredentials(accessToken: String, userAgent: String) throws {
        let storedCredentials = credentialsStore.credentials()
        guard let resolvedAccessToken = sanitizedAccessToken(accessToken) ?? storedCredentials?.accessToken else {
            throw OnlineMusicServiceError.vkNotConfigured
        }

        guard looksLikeVKAccessToken(resolvedAccessToken) else {
            throw OnlineMusicServiceError.configurationMissing("Access token не похож на VK token.")
        }

        try credentialsStore.save(
            VKCredentials(
                accessToken: resolvedAccessToken,
                expiresAt: nil,
                userId: nil,
                userAgent: cleanedText(userAgent) ?? "",
                source: .manual
            )
        )
    }

    func clearCredentials() {
        credentialsStore.clear()
    }

    func checkBasicToken() async -> VKConnectionStatus {
        guard let credentials = credentialsStore.credentials() else {
            return .notConfigured
        }

        guard !credentials.isExpired else {
            return .expired
        }

        var components = URLComponents(url: usersGetURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "access_token", value: credentials.accessToken),
            URLQueryItem(name: "v", value: apiVersion)
        ]

        guard let url = components?.url else {
            return .networkError
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(resolvedUserAgent(from: credentials), forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return .networkError
            }

            let envelope = try decoder.decode(VKUsersGetEnvelope.self, from: data)
            if let apiError = envelope.error {
                return status(from: apiError)
            }

            return envelope.response?.isEmpty == false ? .validBasicToken : .invalidCredentials
        } catch {
            return .networkError
        }
    }

    private func status(from apiError: VKAPIErrorResponse) -> VKConnectionStatus {
        if apiError.errorCode == 5 {
            return .invalidCredentials
        }

        let message = apiError.errorMsg?.lowercased() ?? ""
        if message.contains("expired") {
            return .expired
        }

        return .invalidCredentials
    }

    private func resolvedUserAgent(from credentials: VKCredentials) -> String {
        cleanedText(credentials.userAgent) ?? Self.recommendedUserAgent
    }

    private func looksLikeVKAccessToken(_ value: String) -> Bool {
        if value.hasPrefix("vk1.") {
            return true
        }

        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return value.count >= 20 && value.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }

    private func sanitizedAccessToken(_ rawValue: String?) -> String? {
        guard let cleanedValue = cleanedText(rawValue) else { return nil }

        if let extractedToken = accessTokenFromOAuthRedirect(cleanedValue) {
            return extractedToken
        }

        let normalizedValue = cleanedValue.lowercased()
        let placeholderMarkers = [
            "your_vk_access_token",
            "<your vk access token>",
            "insert_vk_access_token"
        ]

        if placeholderMarkers.contains(where: normalizedValue.contains) {
            return nil
        }

        if cleanedValue.hasPrefix("$(") && cleanedValue.hasSuffix(")") {
            return nil
        }

        return cleanedValue
    }

    private func accessTokenFromOAuthRedirect(_ value: String) -> String? {
        guard let tokenRange = value.range(of: "access_token=") else {
            return nil
        }

        let tokenStart = tokenRange.upperBound
        let tokenEnd = value[tokenStart...].firstIndex(of: "&") ?? value.endIndex
        let tokenValue = String(value[tokenStart..<tokenEnd]).removingPercentEncoding
        return cleanedText(tokenValue)
    }

    private func cleanedText(_ value: String?) -> String? {
        guard let value else { return nil }

        let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedValue.isEmpty ? nil : cleanedValue
    }
}

private struct VKUsersGetEnvelope: Decodable {
    let response: [VKUserResponse]?
    let error: VKAPIErrorResponse?
}

private struct VKUserResponse: Decodable {
    let id: Int?
}

private struct VKAPIErrorResponse: Decodable {
    let errorCode: Int
    let errorMsg: String?

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case errorMsg = "error_msg"
    }
}
