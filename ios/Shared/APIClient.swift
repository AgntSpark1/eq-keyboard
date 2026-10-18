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

        var urlRequest = URLRequest(url: baseURL.appending(path: "v1/replies"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 30
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(store.deviceId, forHTTPHeaderField: "X-Device-Id")
        urlRequest.httpBody = try JSONEncoder().encode(redacted)

        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: return try JSONDecoder().decode(ReplySuggestions.self, from: data)
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
