import Foundation

/// 九键拼音：数字 2-9 各对应几个字母（2=abc ... 9=wxyz），按数字串在拼音词库里查候选。
/// 和全拼一样，先给覆盖全部数字的词，再给覆盖前面一部分数字的词，选中后剩下的数字继续输入。
public final class T9Engine: Sendable {
    public static let letters: [Character: String] = [
        "2": "abc", "3": "def", "4": "ghi", "5": "jkl", "6": "mno", "7": "pqrs", "8": "tuv", "9": "wxyz",
    ]
    private static let digitOf: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (digit, letters) in letters {
            for letter in letters { map[letter] = digit }
        }
        return map
    }()

    private struct Entry: Sendable {
        let digits: String
        /// 除最后一个音节外的数字个数，输入超过它就算打到了最后一个音节里
        let lastSyllableStart: Int
        let word: String
        let freq: Int32
    }

    /// 按数字串排序
    private let entries: [Entry]
    private let syllableDigits: [(syllable: String, digits: String)]

    /// 由拼音引擎的词库生成索引，约 13 万条，建议在后台线程调用
    public init(engine: PinyinEngine) {
        var entries: [Entry] = []
        entries.reserveCapacity(engine.keys.count)
        for index in engine.keys.indices {
            let parts = engine.keys[index].split(separator: " ")
            guard !parts.contains(where: { PinyinEngine.ignoredSyllables.contains(String($0)) }) else { continue }
            let digits = parts.map(Self.digits(for:))
            entries.append(Entry(
                digits: digits.joined(),
                lastSyllableStart: digits.dropLast().reduce(0) { $0 + $1.count },
                word: engine.words[index],
                freq: engine.freqs[index]
            ))
        }
        entries.sort { $0.digits < $1.digits }
        self.entries = entries
        syllableDigits = engine.syllables.sorted().map { ($0, Self.digits(for: Substring($0))) }
    }

    static func digits(for pinyin: Substring) -> String {
        String(pinyin.compactMap { digitOf[$0] })
    }

    /// 候选词。输入两位以上时，数字正好用完的词排在没打完最后一个音节的词前面，让 64 先出“你”而不是“年”。
    public func candidates(for input: String, limit: Int = 60) -> [Candidate] {
        let digits = String(input.filter { Self.letters[$0] != nil })
        guard !digits.isEmpty else { return [] }
        var result: [Candidate] = []
        var seen = Set<String>()
        for length in stride(from: digits.count, through: 1, by: -1) {
            let prefix = String(digits.prefix(length))
            let whole = length == digits.count
            var exact: [Entry] = []
            var partial: [Entry] = []
            var index = lowerBound(prefix)
            while index < entries.count, entries[index].digits.hasPrefix(prefix) {
                let entry = entries[index]
                if entry.digits.count == length {
                    exact.append(entry)
                } else if whole && entry.lastSyllableStart < length {
                    partial.append(entry)
                }
                index += 1
            }
            exact.sort { $0.freq > $1.freq }
            partial.sort { $0.freq > $1.freq }
            let ranked = digits.count >= 2
                ? exact + partial.prefix(limit)
                : (exact + partial).sorted { $0.freq > $1.freq }
            for entry in ranked where seen.insert(entry.word).inserted {
                result.append(Candidate(text: entry.word, consumedLength: length))
                if result.count >= limit { return result }
            }
        }
        return result
    }

    /// 开头几位数字可能是哪些音节，长的在前，给键盘左侧的拼音选择栏用（64 -> ni, mi, o...）
    public func spellings(for input: String) -> [String] {
        let digits = String(input.filter { Self.letters[$0] != nil })
        return syllableDigits
            .filter { !$0.digits.isEmpty && digits.hasPrefix($0.digits) }
            .sorted { ($0.digits.count, $1.syllable) > ($1.digits.count, $0.syllable) }
            .map(\.syllable)
    }

    private func lowerBound(_ key: String) -> Int {
        var low = 0
        var high = entries.count
        while low < high {
            let mid = (low + high) / 2
            if entries[mid].digits < key { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
