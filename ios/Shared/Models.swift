import Foundation

enum Speaker: String, Codable, CaseIterable {
    case me
    case them
}

struct ChatTurn: Codable, Identifiable, Equatable {
    var id = UUID()
    var speaker: Speaker
    var text: String

    private enum CodingKeys: String, CodingKey { case speaker, text }
}

enum RelationshipStage: String, Codable, CaseIterable, Identifiable {
    case justMet = "just_met"
    case flirting
    case dating
    case relationship

    var id: String { rawValue }
}

struct PartnerProfile: Codable, Equatable {
    var name: String = ""
    var stage: RelationshipStage = .justMet
    var interests: [String] = []
    var notes: String = ""
}

struct TonePreferences: Codable, Equatable {
    var humor = false
    var warm = false
    var direct = false
    var brief = false
}

enum ReplyMode: String, Codable {
    case reply
    case polish
    case check
}

struct ReplyRequest: Encodable {
    var mode: ReplyMode
    var conversation: [ChatTurn]
    var draft: String?
    var profile: PartnerProfile?
    var tone: TonePreferences
    var uiLanguage: String
}

struct ReplySuggestion: Decodable, Identifiable {
    var id: String { text }
    let text: String
    let why: String
}

/// 发送前检查的结论：good 可以直接发，adjust 建议改一改，risky 发出去可能让对方不舒服
struct DraftCheck: Decodable, Equatable {
    enum Verdict: String, Decodable {
        case good, adjust, risky
    }

    let verdict: Verdict
    let note: String
}

struct ReplySuggestions: Decodable {
    let replyLanguage: String
    let replies: [ReplySuggestion]
    let check: DraftCheck?
    let quotaRemaining: Int?

    private enum CodingKeys: String, CodingKey {
        case replyLanguage = "reply_language"
        case replies
        case check
        case quotaRemaining = "quota_remaining"
    }
}
