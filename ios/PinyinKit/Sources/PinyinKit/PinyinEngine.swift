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

/// 拼音输入引擎：把字母切分成音节，再在按拼音排序的词库里查候选。
/// 支持全拼、最后一个音节没打完（nih -> 你好）和简拼（nh -> 你好，zhd -> 知道）。
public final class PinyinEngine: Sendable {
    /// 只有辅音的冷门音节（嗯 n、哼 hng 等）。不当作完整音节，否则 nh 会被切成“嗯”+h，简拼就不灵了
    static let ignoredSyllables: Set<String> = ["hng", "hm", "ng", "m", "n"]

    // 三个数组按下标对应，keys 按字典序排好，同一拼音内按词频从高到低
    let keys: [String]
    let words: [String]
    let freqs: [Int32]

    let syllables: Set<String>
    private let syllablePrefixes: Set<String>
    private let maxSyllableLength: Int
    /// 简拼索引：每个音节的首字母连起来（如 ni hao -> "nh"）-> 词条下标，按词频从高到低；只收两个音节以上的词
    private let abbreviations: [String: [Int32]]

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
        syllables.subtract(Self.ignoredSyllables)

        var abbreviations: [String: [Int32]] = [:]
        for (index, key) in keys.enumerated() {
            let parts = key.split(separator: " ")
            guard parts.count >= 2 else { continue }
            abbreviations[String(parts.compactMap(\.first)), default: []].append(Int32(index))
        }
        for (initials, indices) in abbreviations {
            // 词频相同时按拼音顺序，保证结果稳定
            abbreviations[initials] = indices.sorted { (freqs[Int($0)], $1) > (freqs[Int($1)], $0) }
        }
        self.abbreviations = abbreviations
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

    /// 贪心切分音节；不成音节的字母当作声母或未打完的音节（"nih" -> ["ni", "h"]，"zhd" -> ["zh", "d"]）。' 强制分隔。
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
                    if syllablePrefixes.contains(rest) {
                        matched = chars.count - i
                    } else if chars.count - i >= 2, ["zh", "ch", "sh"].contains(String(chars[i..<(i + 2)])) {
                        matched = 2
                    } else {
                        matched = 1
                    }
                }
                result.append(String(chars[i..<(i + matched)]))
                i += matched
            }
        }
        return result
    }

    /// 候选词：先给覆盖全部音节的词，再依次给覆盖前面更少音节的词，选中后剩下的拼音继续输入。
    /// 同样音节数里，完整、简拼和没打完的匹配一起按词频排。
    public func candidates(for input: String, limit: Int = 60) -> [Candidate] {
        let normalized = input.lowercased()
        let segments = segment(normalized)
        guard !segments.isEmpty else { return [] }

        var result: [Candidate] = []
        var seen = Set<String>()
        for count in stride(from: segments.count, through: 1, by: -1) {
            let consumed = consumedLength(normalized, segments: segments, count: count)
            let prefix = Array(segments[0..<count])
            let partial = count == segments.count || prefix.contains { isPartial($0) }
            // 多音节且有没打完的部分时，完整匹配也在简拼索引里，统一按词频排
            let matches = partial && count >= 2
                ? abbreviationLookup(prefix, lastIsPrefix: count == segments.count, limit: limit)
                : lookup(prefix, allowPrefix: partial, limit: limit)
            for word in matches where seen.insert(word).inserted {
                result.append(Candidate(text: word, consumedLength: consumed))
            }
            if result.count >= limit { break }
        }
        return result
    }

    /// 单个字母或不成音节的片段，可以是任何以它开头的音节
    private func isPartial(_ segment: String) -> Bool {
        segment.count == 1 || !syllables.contains(segment)
    }

    /// lastIsPrefix：正在打的最后一个音节可能还没打完（xihua -> 喜欢）
    private func abbreviationLookup(_ segments: [String], lastIsPrefix: Bool, limit: Int) -> [String] {
        guard let indices = abbreviations[String(segments.compactMap(\.first))] else { return [] }
        var result: [String] = []
        for index in indices {
            let parts = keys[Int(index)].split(separator: " ")
            guard parts.count == segments.count else { continue }
            let matches = zip(segments, parts).enumerated().allSatisfy { item in
                let (segment, syllable) = item.element
                let canExtend = isPartial(segment) || (lastIsPrefix && item.offset == segments.count - 1)
                return segment == syllable || (canExtend && syllable.hasPrefix(segment))
            }
            if matches {
                result.append(words[Int(index)])
                if result.count >= limit { break }
            }
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
