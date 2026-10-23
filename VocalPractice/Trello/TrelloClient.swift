import Foundation
import Security

/// Build-time configuration. The API key comes from the app's Trello Power-Up and identifies the app,
/// not a person; each person signs in to Trello and gets their own read-only token.
enum TrelloConfig {
    static let callbackScheme = "vocalpractice"
    static let tokenAccount = "trello-token"

    static var apiKey: String { infoString("TrelloAPIKey") }
    /// An https page on an allowed origin that bounces the token back to `vocalpractice://`.
    /// Empty means sign-in uses the paste-the-token flow instead.
    static var returnURL: String { infoString("TrelloReturnURL") }
    static var isConfigured: Bool { !apiKey.isEmpty }

    static func authorizeURL() -> URL? {
        var components = URLComponents(string: "https://trello.com/1/authorize")
        var items = [
            URLQueryItem(name: "expiration", value: "never"),
            URLQueryItem(name: "name", value: "Vocal Practice"),
            URLQueryItem(name: "scope", value: "read"),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "key", value: apiKey),
        ]
        if !returnURL.isEmpty {
            items.append(URLQueryItem(name: "return_url", value: returnURL))
            items.append(URLQueryItem(name: "callback_method", value: "fragment"))
        }
        components?.queryItems = items
        return components?.url
    }

    private static func infoString(_ key: String) -> String {
        let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.hasPrefix("$(") ? "" : value   // unexpanded build setting
    }
}

enum Keychain {
    private static let service = "app.haklo.vocalpractice"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for account: String) {
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum TrelloError: LocalizedError {
    case notConfigured, notConnected, notSetUp, unauthorized, badAttachment
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "This build has no Trello API key."
        case .notConnected: return "Connect Trello in Settings first."
        case .notSetUp: return "Pick your lesson board and warmups list in Settings."
        case .unauthorized: return "Trello access was revoked or expired. Connect again in Settings."
        case .badAttachment: return "A Trello attachment had an unreadable link."
        case .http(let code): return "Trello returned an error (\(code)). Try again in a minute."
        }
    }
}

struct TrelloMember: Decodable { let id: String; let fullName: String?; let username: String? }
struct TrelloBoard: Decodable, Identifiable, Hashable { let id: String; let name: String }
struct TrelloList: Decodable, Identifiable, Hashable { let id: String; let name: String }
struct TrelloAttachment: Decodable {
    let id: String
    let name: String
    let url: String
    let mimeType: String?
    let isUpload: Bool?
}
struct TrelloCard: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let desc: String?
    let attachments: [TrelloAttachment]?

    static func == (a: TrelloCard, b: TrelloCard) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// The first uploaded audio file on the card.
    var audioAttachment: TrelloAttachment? {
        attachments?.first { ($0.isUpload ?? true) && TrelloMapping.isAudio(name: $0.name, mimeType: $0.mimeType) }
    }
}

/// Read-only Trello REST client. Every request, including attachment downloads, carries the OAuth header,
/// since Trello requires authentication to download uploaded attachments.
struct TrelloClient {
    let key: String
    let token: String
    var session: URLSession = .shared

    static func current() -> TrelloClient? {
        guard TrelloConfig.isConfigured, let token = Keychain.get(TrelloConfig.tokenAccount) else { return nil }
        return TrelloClient(key: TrelloConfig.apiKey, token: token)
    }

    private var authHeader: String {
        "OAuth oauth_consumer_key=\"\(key)\", oauth_token=\"\(token)\""
    }

    func me() async throws -> TrelloMember {
        try await get("members/me", ["fields": "fullName,username"])
    }

    func boards() async throws -> [TrelloBoard] {
        try await get("members/me/boards", ["filter": "open", "fields": "name"])
    }

    func lists(board: String) async throws -> [TrelloList] {
        try await get("boards/\(board)/lists", ["filter": "open", "fields": "name"])
    }

    func cards(board: String) async throws -> [TrelloCard] {
        try await get("boards/\(board)/cards", ["filter": "open", "fields": "name,desc"])
    }

    func cards(list: String) async throws -> [TrelloCard] {
        try await get("lists/\(list)/cards", [
            "fields": "name,desc",
            "attachments": "true",
            "attachment_fields": "name,url,mimeType,isUpload",
        ])
    }

    func card(_ id: String) async throws -> TrelloCard {
        try await get("cards/\(id)", ["fields": "name,desc"])
    }

    /// Downloads an attachment into `folder` and returns the stored file name.
    func download(_ attachment: TrelloAttachment, into folder: URL) async throws -> String {
        guard let url = URL(string: attachment.url) else { throw TrelloError.badAttachment }
        var request = URLRequest(url: url)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        let (temp, response) = try await session.download(for: request)
        try check(response)
        let ext = (attachment.name as NSString).pathExtension.lowercased()
        let name = "trello-\(attachment.id.suffix(12)).\(ext.isEmpty ? "m4a" : ext)"
        let destination = folder.appending(path: name)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        return name
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> T {
        var components = URLComponents(string: "https://api.trello.com/1/\(path)")
        components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { throw TrelloError.http(0) }
        var request = URLRequest(url: url)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try check(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw TrelloError.unauthorized
        default: throw TrelloError.http(http.statusCode)
        }
    }
}
