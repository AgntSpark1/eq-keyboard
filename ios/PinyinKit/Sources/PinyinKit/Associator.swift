import Foundation

/// 输入联想：上屏一个词后，按词库里以它结尾那几个字开头的常用词，推荐接下来的字（“你” -> 好、们、的…）。
public final class Associator: Sendable {
    /// 词的第一个字 -> 以它开头的多字词下标，按词频从高到低
    private let byFirstCharacter: [Character: [Int32]]
    private let words: [String]

    /// 由拼音引擎的词库生成索引，建议在后台线程调用
    public init(engine: PinyinEngine) {
        var index: [Character: [Int32]] = [:]
        for (position, word) in engine.words.enumerated() where word.count >= 2 {
            index[word.first!, default: []].append(Int32(position))
        }
        let freqs = engine.freqs
        for (character, positions) in index {
            index[character] = positions.sorted { (freqs[Int($0)], $1) > (freqs[Int($1)], $0) }
        }
        byFirstCharacter = index
        words = engine.words
    }

    /// 根据刚输入的文字推荐后续内容。先用最后两个字匹配（“喜欢” -> 你），再用最后一个字补足。
    public func suggestions(after text: String, limit: Int = 12) -> [String] {
        let tail = Array(text.suffix(2))
        guard let last = tail.last else { return [] }
        var result: [String] = []
        var seen = Set<String>()
        var contexts: [String] = []
        if tail.count == 2 { contexts.append(String(tail)) }
        contexts.append(String(last))
        for context in contexts {
            guard let first = context.first, let positions = byFirstCharacter[first] else { continue }
            for position in positions {
                let word = words[Int(position)]
                // 不推荐太长的成语尾巴（“你” -> 死我活）
                guard word.count > context.count, word.count - context.count <= 2, word.hasPrefix(context) else { continue }
                let rest = String(word.dropFirst(context.count))
                if seen.insert(rest).inserted {
                    result.append(rest)
                    if result.count >= limit { return result }
                }
            }
        }
        return result
    }
}
