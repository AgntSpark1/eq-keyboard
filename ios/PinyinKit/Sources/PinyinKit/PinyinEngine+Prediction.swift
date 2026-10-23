import Foundation

extension PinyinEngine {
    /// 词库联想只用常见词，过滤掉人名、地名这类低频词
    static let predictionMinFreq: Int32 = 200
    /// 没有合适的联想时，给聊天里最常接在后面的字
    static let fallbackPredictions = ["的", "了", "吗", "呢", "吧", "啊", "是", "在", "我", "你"]

    static func buildPredictionIndex(words: [String], freqs: [Int32]) -> [Character: [Int32]] {
        var index: [Character: [Int32]] = [:]
        for (i, word) in words.enumerated() where word.count >= 2 && freqs[i] >= predictionMinFreq {
            index[word.first!, default: []].append(Int32(i))
        }
        for (char, indices) in index {
            index[char] = indices.sorted { (freqs[Int($0)], $1) > (freqs[Int($1)], $0) }
        }
        return index
    }

    static func parseChatPredictions(_ text: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: "\t")
            guard fields.count == 2 else { continue }
            // 同一个上文出现多行时合并，保持先后顺序
            var list = result[String(fields[0])] ?? []
            for word in fields[1].split(separator: " ").map(String.init) where !list.contains(word) {
                list.append(word)
            }
            result[String(fields[0])] = list
        }
        return result
    }

    /// 输入联想：根据刚上屏的文字推荐接下来的字词。依次用：
    /// 1. 聊天接续词表，取上文最长能匹配的结尾（“今天” -> 晚上、怎么样）；
    /// 2. 词库里以上文结尾开头的词，从最长的结尾（最多四个字）往短里找，
    ///    碰到已经成词的结尾就不再变短（“喜欢” -> 喜欢你；“你好” 不会按 “好” 去联想）；
    /// 3. 常用虚词兜底。
    public func predictions(after context: String, limit: Int = 40) -> [String] {
        let chars = Array(Array(context.suffix(4).reversed().prefix { Self.isHanzi($0) }).reversed())
        guard !chars.isEmpty else { return [] }

        var result: [String] = []
        var seen = Set<String>()
        func add(_ word: String) {
            if result.count < limit, seen.insert(word).inserted { result.append(word) }
        }

        var tails: [String] = []
        for length in stride(from: chars.count, through: 1, by: -1) {
            let tail = String(chars.suffix(length))
            tails.append(tail)
            if length >= 2, wordSet.contains(tail) { break }
        }

        for tail in tails {
            if let list = chatPredictions[tail] {
                list.forEach(add)
                break
            }
        }

        for tail in tails {
            guard let indices = predictionIndex[tail.first!] else { continue }
            for index in indices {
                let word = words[Int(index)]
                // 最多接三个字，太长的成语、专有名词不适合当联想
                guard word.count > tail.count, word.count - tail.count <= 3, word.hasPrefix(tail) else { continue }
                add(String(word.dropFirst(tail.count)))
            }
        }

        Self.fallbackPredictions.forEach(add)
        return result
    }

    static func isHanzi(_ char: Character) -> Bool {
        char.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) }
    }
}
