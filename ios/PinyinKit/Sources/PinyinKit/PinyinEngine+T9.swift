import Foundation

public struct T9Candidate: Equatable, Hashable {
    public let text: String
    /// 选中后从输入中消耗掉的数字个数
    public let consumedLength: Int
    /// 这个词的拼音，音节之间用 ' 分隔，用来在候选栏上方显示
    public let pinyin: String
}

/// 九键索引：把每个词的拼音换成数字串（ni hao -> 64426），按数字串排序以便二分查找
struct T9Index: Sendable {
    static let digitForLetter: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (digit, letters) in ["2": "abc", "3": "def", "4": "ghi", "5": "jkl", "6": "mno", "7": "pqrs", "8": "tuv", "9": "wxyz"] {
            for letter in letters { map[letter] = Character(digit) }
        }
        return map
    }()

    static let lettersForDigit: [Character: String] = [
        "2": "abc", "3": "def", "4": "ghi", "5": "jkl", "6": "mno", "7": "pqrs", "8": "tuv", "9": "wxyz",
    ]

    static func code(_ pinyin: some StringProtocol) -> String {
        String(pinyin.compactMap { digitForLetter[$0] })
    }

    /// 每个词的数字串
    let codes: [String]
    /// 最后一个音节在数字串里的起点；输入只有越过这里，才允许最后一个音节没打完
    let lastSyllableStart: [Int16]
    /// 词条下标按数字串排序
    let order: [Int32]
    /// 音节 -> 最常用单字的词频，用来给九键左侧的音节列表排序
    let syllableFreq: [String: Int32]

    init(keys: [String], freqs: [Int32]) {
        var codes: [String] = []
        var lastStarts: [Int16] = []
        var syllableFreq: [String: Int32] = [:]
        codes.reserveCapacity(keys.count)
        lastStarts.reserveCapacity(keys.count)
        for (i, key) in keys.enumerated() {
            let code = Self.code(key)
            codes.append(code)
            let last = key.split(separator: " ").last ?? Substring(key)
            lastStarts.append(Int16(code.count - last.count))
            if !key.contains(" ") {
                syllableFreq[key] = max(syllableFreq[key] ?? 0, freqs[i])
            }
        }
        self.codes = codes
        self.lastSyllableStart = lastStarts
        self.order = (0..<Int32(keys.count)).sorted { (codes[Int($0)], $0) < (codes[Int($1)], $1) }
        self.syllableFreq = syllableFreq
    }

    /// 数字串以 prefix 开头的词条在 order 里的范围
    func range(prefix: String) -> Range<Int> {
        let start = lowerBound(prefix)
        var low = start
        var high = order.count
        while low < high {
            let mid = (low + high) / 2
            if codes[Int(order[mid])].hasPrefix(prefix) { low = mid + 1 } else { high = mid }
        }
        return start..<low
    }

    private func lowerBound(_ key: String) -> Int {
        var low = 0
        var high = order.count
        while low < high {
            let mid = (low + high) / 2
            if codes[Int(order[mid])] < key { low = mid + 1 } else { high = mid }
        }
        return low
    }
}

extension PinyinEngine {
    /// 九键候选：先给覆盖全部数字的词（完整匹配在前，最后一个音节没打完的在后，各自按词频），
    /// 再依次给覆盖前面更少数字的词。firstSyllable 是用户在左侧选定的第一个音节。
    public func t9Candidates(for digits: String, firstSyllable: String? = nil, limit: Int = 60) -> [T9Candidate] {
        guard !digits.isEmpty else { return [] }
        var result: [T9Candidate] = []
        var seen = Set<String>()

        func accepts(_ index: Int) -> Bool {
            guard let firstSyllable else { return true }
            // 选的是单个字母时，只要求第一个音节以它开头
            if !syllables.contains(firstSyllable) { return keys[index].hasPrefix(firstSyllable) }
            return keys[index] == firstSyllable || keys[index].hasPrefix(firstSyllable + " ")
        }

        func append(_ index: Int, consumed: Int) {
            let word = words[index]
            if seen.insert(word).inserted {
                result.append(T9Candidate(
                    text: word,
                    consumedLength: consumed,
                    pinyin: keys[index].replacingOccurrences(of: " ", with: "'")
                ))
            }
        }

        var full: [Int] = []
        for position in t9.range(prefix: digits) {
            let index = Int(t9.order[position])
            let code = t9.codes[index]
            guard code.count == digits.count || digits.count > Int(t9.lastSyllableStart[index]) else { continue }
            if accepts(index) { full.append(index) }
        }
        full.sort {
            let exact0 = t9.codes[$0].count == digits.count
            let exact1 = t9.codes[$1].count == digits.count
            if exact0 != exact1 { return exact0 }
            return (freqs[$0], $1) > (freqs[$1], $0)
        }
        for index in full.prefix(limit) { append(index, consumed: digits.count) }

        var length = digits.count - 1
        while length >= 1, result.count < limit {
            let prefix = String(digits.prefix(length))
            var exact: [Int] = []
            for position in t9.range(prefix: prefix) {
                let index = Int(t9.order[position])
                if t9.codes[index].count == length, accepts(index) { exact.append(index) }
            }
            exact.sort { (freqs[$0], $1) > (freqs[$1], $0) }
            for index in exact.prefix(limit - result.count) { append(index, consumed: length) }
            length -= 1
        }
        return result
    }

    /// 九键左侧的音节列表：数字串开头能拼成的完整音节，长的在前，同样长按常用程度；最后附上第一个键的字母
    public func t9Syllables(for digits: String) -> [String] {
        guard let first = digits.first else { return [] }
        let matches = t9.syllableFreq.keys.filter { syllable in
            let code = T9Index.code(syllable)
            return syllables.contains(syllable) && digits.hasPrefix(code)
        }
        let sorted = matches.sorted {
            ($0.count, t9.syllableFreq[$0] ?? 0, $1) > ($1.count, t9.syllableFreq[$1] ?? 0, $0)
        }
        let letters = (T9Index.lettersForDigit[first] ?? "").map(String.init).filter { !sorted.contains($0) }
        return sorted + letters
    }
}
