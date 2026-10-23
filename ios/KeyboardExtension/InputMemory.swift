import Foundation

/// 记住用户自己的用词习惯，只存在键盘扩展本机的 UserDefaults 里，不上传：
/// - 打某串拼音时选了哪个词（下次排到最前）；
/// - 某个词后面接着打了哪个词（下次联想排到最前）。
/// 只记词和次数，不记整句话。
final class InputMemory {
    private static let picksKey = "inputMemory.picks"
    private static let nextKey = "inputMemory.next"
    /// 每张表最多记这么多条上文，超出后丢掉用得最少的一半
    private static let maxEntries = 3000

    private let defaults: UserDefaults
    private var picks: [String: [String: Int]]
    private var next: [String: [String: Int]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        picks = defaults.dictionary(forKey: Self.picksKey) as? [String: [String: Int]] ?? [:]
        next = defaults.dictionary(forKey: Self.nextKey) as? [String: [String: Int]] ?? [:]
    }

    /// input 是选词时消耗掉的拼音（全键）或数字（九键，带 "t9:" 前缀）
    func recordPick(_ word: String, input: String) {
        guard !input.isEmpty else { return }
        picks[input, default: [:]][word, default: 0] += 1
        Self.trim(&picks)
        defaults.set(picks, forKey: Self.picksKey)
    }

    func recordNext(_ word: String, after previous: String) {
        guard !previous.isEmpty, previous != word else { return }
        next[previous, default: [:]][word, default: 0] += 1
        Self.trim(&next)
        defaults.set(next, forKey: Self.nextKey)
    }

    /// 用过的词按次数提到前面，其余保持引擎给的顺序
    func rank(_ candidates: [String], input: String) -> [String] {
        Self.promote(candidates, counts: picks[input])
    }

    /// 联想：先给用户在这个词后面打过的词，再接引擎的联想
    func predictions(after previous: String, base: [String]) -> [String] {
        guard let counts = next[previous], !counts.isEmpty else { return base }
        let learned = counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
        return learned + base.filter { counts[$0] == nil }
    }

    private static func promote(_ items: [String], counts: [String: Int]?) -> [String] {
        guard let counts, !counts.isEmpty else { return items }
        let used = items.filter { counts[$0] != nil }.sorted { counts[$0]! > counts[$1]! }
        return used + items.filter { counts[$0] == nil }
    }

    private static func trim(_ table: inout [String: [String: Int]]) {
        guard table.count > maxEntries else { return }
        let ranked = table.sorted { $0.value.values.reduce(0, +) > $1.value.values.reduce(0, +) }
        table = Dictionary(uniqueKeysWithValues: ranked.prefix(maxEntries / 2).map { ($0.key, $0.value) })
    }
}
