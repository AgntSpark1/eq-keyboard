import Foundation

enum APIError: LocalizedError {
    case quotaExceeded
    case refused
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .quotaExceeded: String(localized: "error.quota")
        case .refused: String(localized: "error.refused")
        case .server: String(localized: "error.server")
        }
    }
}

struct AuthSession: Decodable {
    var sessionToken: String
    var userId: String
}

struct AccountStatus: Decodable {
    var subscribed: Bool
    /// 毫秒时间戳
    var subscriptionExpiresAt: Double?
    var quotaRemaining: Int?
}

struct APIClient {
    var baseURL: URL = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "EQAPIBaseURL") as? String
        return URL(string: raw ?? "") ?? URL(string: "http://localhost:8787")!
    }()
    var session: URLSession = .shared
    var store: SharedStore = .shared

    func suggestReplies(_ request: ReplyRequest) async throws -> ReplySuggestions {
        var redacted = request
        redacted.conversation = request.conversation.map {
            ChatTurn(speaker: $0.speaker, text: Redactor.redact($0.text))
        }
        redacted.draft = request.draft.map(Redactor.redact)

        var urlRequest = request("v1/replies")
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(redacted)
        return try await send(urlRequest)
    }

    /// 用 Apple 返回的 identityToken 换后端会话
    func signInWithApple(identityToken: String) async throws -> AuthSession {
        try await post("v1/auth/apple", body: ["identityToken": identityToken])
    }

    func account() async throws -> AccountStatus {
        try await send(request("v1/me"))
    }

    /// 把 StoreKit 交易的 JWS 交给后端校验，返回最新订阅状态
    func verifySubscription(signedTransaction: String) async throws -> AccountStatus {
        try await post("v1/subscription/verify", body: ["signedTransaction": signedTransaction])
    }

    private func post<T: Decodable>(_ path: String, body: [String: String]) async throws -> T {
        var urlRequest = request(path)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return try await send(urlRequest)
    }

    private func request(_ path: String) -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appending(path: path))
        urlRequest.timeoutInterval = 30
        urlRequest.setValue(store.deviceId, forHTTPHeaderField: "X-Device-Id")
        if let token = store.sessionToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return urlRequest
    }

    private func send<T: Decodable>(_ urlRequest: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: return try JSONDecoder().decode(T.self, from: data)
        case 429: throw APIError.quotaExceeded
        case 422: throw APIError.refused
        default: throw APIError.server(status)
        }
    }

    /// 解释文字使用的界面语言，如 zh-Hans、en
    static var uiLanguage: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }
}
