import Foundation

/// 键盘里正在进行的一段对话。在微信里每复制一条对方的消息就记一条，用过的回复记成自己说的，
/// 这样不切出微信也能带着前文连续回复。闲置 30 分钟后作废，避免串到和别人的聊天里。
struct ChatSession: Codable, Equatable {
    static let idleLimit: TimeInterval = 30 * 60
    static let maxTurns = 20

    var turns: [ChatTurn] = []
    var updatedAt = Date()

    var lastTheirs: String? { turns.last { $0.speaker == .them }?.text }

    func isExpired(now: Date = Date()) -> Bool {
        now.timeIntervalSince(updatedAt) > Self.idleLimit
    }

    /// 重复复制同一条消息、或复制了刚发出的回复时不再记一次
    mutating func add(_ speaker: Speaker, _ text: String, now: Date = Date()) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !turns.suffix(4).contains(where: { $0.text == text }) else { return }
        turns.append(ChatTurn(speaker: speaker, text: text))
        if turns.count > Self.maxTurns { turns.removeFirst(turns.count - Self.maxTurns) }
        updatedAt = now
    }
}
