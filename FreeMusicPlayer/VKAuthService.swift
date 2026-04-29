//
//  VKAuthService.swift
//  FreeMusicPlayer
//
//  VK OAuth login, credential storage, and lightweight capability checks.
//

import AuthenticationServices
import Foundation
import Security
import UIKit

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
}

struct VKCredentialSnapshot: Equatable, Sendable {
    let hasCredentials: Bool
    let maskedAccessToken: String?
    let userId: String?
    let userAgent: String?
    let source: VKCredentialSource?
    let expiresAt: Date?
    let isExpired: Bool

    var displayIdentity: String? {
        if let userId, !userId.isEmpty {
            return "user id \(userId)"
        }

        return maskedAccessToken
    }
}

enum VKConnectionStatus: Equatable, Sendable {
    case notConfigured
    case loggedIn
    case validBasicToken
    case musicAccessAvailable
    case musicAccessUnavailable
    case invalidCredentials
    case expired
    case networkError

    var title: String {
        switch self {
        case .notConfigured:
            return "VK Music не подключён"
        case .loggedIn:
            return "VK подключён"
        case .validBasicToken:
            return "VK login работает"
        case .musicAccessAvailable:
            return "VK Music подключён"
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
            return "Войдите в VK или добавьте данные вручную, чтобы включить поиск VK Music."
        case .loggedIn:
            return "Вход выполнен. Проверьте, доступен ли поиск VK Music."
        case .validBasicToken:
            return "Базовый VK login работает. Проверка VK Music выполняется отдельно."
        case .musicAccessAvailable:
            return "Поиск VK Music готов к работе."
        case .musicAccessUnavailable:
            return "Вход выполнен, но этот токен не даёт доступ к VK Music. Нужен токен, поддерживающий музыкальный API."
        case .invalidCredentials:
            return "VK не принял эти данные. Проверьте token и User-Agent."
        case .expired:
            return "Войдите в VK ещё раз."
        case .networkError:
            return "Не удалось подключиться к VK. Проверьте интернет."
        }
    }

    var canSearchVKMusic: Bool {
        self == .musicAccessAvailable
    }
}

struct VKAuthConfiguration: Equatable {
    let clientID: String
    let redirectURI: String
    let scope: String
    let apiVersion: String

    var callbackURLScheme: String? {
        URL(string: redirectURI)?.scheme
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
    private let oauthAuthorizationURL = URL(string: "https://oauth.vk.com/authorize")!
    private let usersGetURL = URL(string: "https://api.vk.com/method/users.get")!
    private let defaultAPIVersion = "5.131"
    @MainActor private var webAuthCoordinator: VKWebAuthCoordinator?
    static let defaultUserAgent = "FreeMusicPlayer/1.0 iOS"

    init(session: URLSession, credentialsStore: VKCredentialsStore) {
        self.session = session
        self.credentialsStore = credentialsStore
    }

    var configuration: VKAuthConfiguration? {
        guard let clientID = cleanedText(Bundle.main.object(forInfoDictionaryKey: VKAuthInfoPlistKeys.clientID) as? String),
              !clientID.hasPrefix("$(") else {
            return nil
        }

        return VKAuthConfiguration(
            clientID: clientID,
            redirectURI: cleanedText(Bundle.main.object(forInfoDictionaryKey: VKAuthInfoPlistKeys.redirectURI) as? String) ?? "freemusic://vk-auth",
            scope: cleanedText(Bundle.main.object(forInfoDictionaryKey: VKAuthInfoPlistKeys.scope) as? String) ?? "audio,offline",
            apiVersion: cleanedText(Bundle.main.object(forInfoDictionaryKey: VKAuthInfoPlistKeys.apiVersion) as? String) ?? defaultAPIVersion
        )
    }

    @MainActor
    func authorize() async throws -> VKCredentials {
        guard let configuration else {
            throw OnlineMusicServiceError.configurationMissing(
                "VK login is not configured. Add VKClientID to Info.plist or build settings."
            )
        }

        guard let callbackURLScheme = configuration.callbackURLScheme else {
            throw OnlineMusicServiceError.configurationMissing("VK redirect URI must include a URL scheme.")
        }

        guard let authURL = authorizationURL(configuration: configuration) else {
            throw OnlineMusicServiceError.configurationMissing("VK authorization URL could not be created.")
        }

        let coordinator = VKWebAuthCoordinator()
        webAuthCoordinator = coordinator
        defer {
            webAuthCoordinator = nil
        }

        let callbackURL = try await coordinator.authenticate(
            using: authURL,
            callbackURLScheme: callbackURLScheme
        )
        let credentials = try credentials(from: callbackURL)
        try credentialsStore.save(credentials)
        return credentials
    }

    func saveManualCredentials(accessToken: String, userAgent: String) throws {
        let storedCredentials = credentialsStore.credentials()
        guard let resolvedAccessToken = sanitizedAccessToken(accessToken) ?? storedCredentials?.accessToken else {
            throw OnlineMusicServiceError.vkNotConfigured
        }

        guard let resolvedUserAgent = cleanedText(userAgent) else {
            throw OnlineMusicServiceError.configurationMissing("Введите User-Agent для VK Music.")
        }

        try credentialsStore.save(
            VKCredentials(
                accessToken: resolvedAccessToken,
                expiresAt: nil,
                userId: nil,
                userAgent: resolvedUserAgent,
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
            URLQueryItem(name: "v", value: configuration?.apiVersion ?? defaultAPIVersion)
        ]

        guard let url = components?.url else {
            return .networkError
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(credentials.userAgent, forHTTPHeaderField: "User-Agent")
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

    private func authorizationURL(configuration: VKAuthConfiguration) -> URL? {
        var components = URLComponents(url: oauthAuthorizationURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "display", value: "mobile"),
            URLQueryItem(name: "scope", value: configuration.scope),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "v", value: configuration.apiVersion),
            URLQueryItem(name: "revoke", value: "1")
        ]
        return components?.url
    }

    private func credentials(from callbackURL: URL) throws -> VKCredentials {
        let values = callbackValues(from: callbackURL)

        if let errorDescription = values["error_description"] ?? values["error"] {
            throw OnlineMusicServiceError.authenticationRequired(errorDescription)
        }

        guard let accessToken = sanitizedAccessToken(values["access_token"]) else {
            throw OnlineMusicServiceError.authenticationRequired("VK login finished without an access token.")
        }

        let expiresAt: Date?
        if let expiresInRawValue = values["expires_in"],
           let expiresIn = TimeInterval(expiresInRawValue),
           expiresIn > 0 {
            expiresAt = Date().addingTimeInterval(expiresIn)
        } else {
            expiresAt = nil
        }

        return VKCredentials(
            accessToken: accessToken,
            expiresAt: expiresAt,
            userId: cleanedText(values["user_id"]),
            userAgent: Self.defaultUserAgent,
            source: .oauth
        )
    }

    private func callbackValues(from url: URL) -> [String: String] {
        var values: [String: String] = [:]

        if let fragment = url.fragment {
            mergeURLFormValues(fragment, into: &values)
        }

        if let query = url.query {
            mergeURLFormValues(query, into: &values)
        }

        return values
    }

    private func mergeURLFormValues(_ form: String, into values: inout [String: String]) {
        for pair in form.split(separator: "&") {
            let pieces = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard let name = pieces.first?.removingPercentEncoding else { continue }
            let value = pieces.count > 1 ? pieces[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding : nil
            values[name] = value ?? ""
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

    private func sanitizedAccessToken(_ rawValue: String?) -> String? {
        guard let cleanedValue = cleanedText(rawValue) else { return nil }

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

    private func cleanedText(_ value: String?) -> String? {
        guard let value else { return nil }

        let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedValue.isEmpty ? nil : cleanedValue
    }
}

@MainActor
private final class VKWebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authenticate(using url: URL, callbackURLScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let authenticationSession = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackURLScheme
            ) { [weak self] callbackURL, error in
                self?.session = nil

                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(
                        throwing: OnlineMusicServiceError.authenticationRequired("VK login was cancelled.")
                    )
                    return
                }

                if let error {
                    continuation.resume(
                        throwing: OnlineMusicServiceError.authenticationRequired("VK login failed: \(error.localizedDescription)")
                    )
                    return
                }

                guard let callbackURL else {
                    continuation.resume(
                        throwing: OnlineMusicServiceError.authenticationRequired("VK login finished without a callback URL.")
                    )
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            authenticationSession.presentationContextProvider = self
            authenticationSession.prefersEphemeralWebBrowserSession = false
            self.session = authenticationSession

            guard authenticationSession.start() else {
                self.session = nil
                continuation.resume(
                    throwing: OnlineMusicServiceError.authenticationRequired("VK login could not start.")
                )
                return
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

private enum VKAuthInfoPlistKeys {
    static let clientID = "VKClientID"
    static let redirectURI = "VKRedirectURI"
    static let scope = "VKAuthScope"
    static let apiVersion = "VKAPIVersion"
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
