import Foundation

public struct Candidate: Equatable, Hashable {
    public let text: String
    /// 选中后从输入中消耗掉的字符数（含分隔用的 '）
    public let consumedLength: Int

    public init(text: String, consumedLength: Int) {
        self.text = text
        self.consumedLength = consumedLength
    }
}

/// 全拼输入引擎：把字母切分成音节，再在按拼音排序的词库里查候选。
public final class PinyinEngine: Sendable {
    // 三个数组按下标对应，keys 按字典序排好，同一拼音内按词频从高到低
    private let keys: [String]
    private let words: [String]
    private let freqs: [Int32]

    let syllables: Set<String>
    private let syllablePrefixes: Set<String>
    private let maxSyllableLength: Int

    /// tsv 每行：以空格分隔的无声调拼音<TAB>词<TAB>词频，且已按拼音排序
    public init(tsv: String) {
        var keys: [String] = []
        var words: [String] = []
        var freqs: [Int32] = []
        var syllables = Set<String>()
        for line in tsv.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3 else { continue }
            let key = String(fields[0])
            keys.append(key)
            words.append(String(fields[1]))
            freqs.append(Int32(fields[2]) ?? 1)
            for syllable in key.split(separator: " ") where !syllables.contains(String(syllable)) {
                syllables.insert(String(syllable))
            }
        }
        self.keys = keys
        self.words = words
        self.freqs = freqs
        self.syllables = syllables
        self.maxSyllableLength = syllables.map(\.count).max() ?? 0
        var prefixes = Set<String>()
        for syllable in syllables {
            for length in 1...syllable.count {
                prefixes.insert(String(syllable.prefix(length)))
            }
        }
        self.syllablePrefixes = prefixes
    }

    /// 加载随包附带的词库，约 13 万条，建议在后台线程调用
    public static func bundled() throws -> PinyinEngine {
        guard let url = Bundle.module.url(forResource: "pinyin_dict", withExtension: "tsv") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return PinyinEngine(tsv: try String(contentsOf: url, encoding: .utf8))
    }

    /// 贪心切分音节；最后一段可以是未打完的音节（如 "nih" -> ["ni", "h"]）。' 强制分隔。
    public func segment(_ input: String) -> [String] {
        var result: [String] = []
        for chunk in input.lowercased().split(separator: "'") {
            let chars = Array(chunk)
            var i = 0
            while i < chars.count {
                var matched = 0
                let longest = min(maxSyllableLength, chars.count - i)
                if longest > 0 {
                    for length in stride(from: longest, through: 1, by: -1)
                    where syllables.contains(String(chars[i..<(i + length)])) {
                        matched = length
                        break
                    }
                }
                if matched == 0 {
                    let rest = String(chars[i...])
                    matched = syllablePrefixes.contains(rest) ? chars.count - i : 1
                }
                result.append(String(chars[i..<(i + matched)]))
                i += matched
            }
        }
        return result
    }

    /// 候选词：先给覆盖全部音节的词，再依次给覆盖前面更少音节的词，选中后剩下的拼音继续输入。
    public func candidates(for input: String, limit: Int = 60) -> [Candidate] {
        let normalized = input.lowercased()
        let segments = segment(normalized)
        guard !segments.isEmpty else { return [] }

        var result: [Candidate] = []
        var seen = Set<String>()
        for count in stride(from: segments.count, through: 1, by: -1) {
            let consumed = consumedLength(normalized, segments: segments, count: count)
            let matches = lookup(Array(segments[0..<count]), allowPrefix: count == segments.count, limit: limit)
            for word in matches where seen.insert(word).inserted {
                result.append(Candidate(text: word, consumedLength: consumed))
            }
            if result.count >= limit { break }
        }
        return result
    }

    private func lookup(_ segments: [String], allowPrefix: Bool, limit: Int) -> [String] {
        let key = segments.joined(separator: " ")
        var index = lowerBound(key)
        var exact: [String] = []
        while index < keys.count, keys[index] == key {
            exact.append(words[index])
            index += 1
        }
        guard allowPrefix else { return exact }

        // 最后一个音节没打完：收集同样音节数、最后一个音节以它开头的词
        var extended: [(word: String, freq: Int32)] = []
        while index < keys.count, keys[index].hasPrefix(key) {
            if !keys[index].dropFirst(key.count).contains(" ") {
                extended.append((words[index], freqs[index]))
            }
            index += 1
        }
        extended.sort { $0.freq > $1.freq }
        return exact + extended.prefix(limit).map(\.word)
    }

    private func lowerBound(_ key: String) -> Int {
        var low = 0
        var high = keys.count
        while low < high {
            let mid = (low + high) / 2
            if keys[mid] < key { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private func consumedLength(_ input: String, segments: [String], count: Int) -> Int {
        var consumed = 0
        var segmentIndex = 0
        var remaining = segments[0].count
        for char in input {
            if segmentIndex == count { break }
            consumed += 1
            if char == "'" { continue }
            remaining -= 1
            if remaining == 0 {
                segmentIndex += 1
                if segmentIndex < segments.count { remaining = segments[segmentIndex].count }
            }
        }
        return consumed
    }
}
