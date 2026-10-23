import XCTest
@testable import PinyinKit

final class PinyinEngineTests: XCTestCase {
    static let engine = try! PinyinEngine.bundled()
    var engine: PinyinEngine { Self.engine }

    func testSegmentsSyllables() {
        XCTAssertEqual(engine.segment("nihao"), ["ni", "hao"])
        XCTAssertEqual(engine.segment("xian"), ["xian"])
        XCTAssertEqual(engine.segment("xi'an"), ["xi", "an"])
        XCTAssertEqual(engine.segment("nih"), ["ni", "h"])
        XCTAssertEqual(engine.segment("zh"), ["zh"])
        XCTAssertEqual(engine.segment("zhd"), ["zh", "d"])
        XCTAssertEqual(engine.segment("nh"), ["n", "h"])
    }

    func testAbbreviations() {
        XCTAssertEqual(engine.candidates(for: "nh").first, Candidate(text: "你好", consumedLength: 2))
        XCTAssertEqual(engine.candidates(for: "zhd").first, Candidate(text: "知道", consumedLength: 3))
        XCTAssertEqual(engine.candidates(for: "xh").first?.text, "喜欢")
        XCTAssertEqual(engine.candidates(for: "nhao").first?.text, "你好")
    }

    func testUnfinishedLastSyllableInLongerInput() {
        XCTAssertEqual(engine.candidates(for: "xihua").first?.text, "喜欢")
    }

    func testChatWordsOutrankNewsWords() {
        let candidates = engine.candidates(for: "xh").map(\.text)
        XCTAssertLessThan(candidates.firstIndex(of: "喜欢")!, candidates.firstIndex(of: "先后")!)
    }

    func testWholeWordComesFirst() {
        XCTAssertEqual(engine.candidates(for: "nihao").first, Candidate(text: "你好", consumedLength: 5))
        XCTAssertEqual(engine.candidates(for: "xihuan").first?.text, "喜欢")
        XCTAssertEqual(engine.candidates(for: "ni").first, Candidate(text: "你", consumedLength: 2))
    }

    func testPartialLastSyllable() {
        let candidates = engine.candidates(for: "nih")
        XCTAssertEqual(candidates.first(where: { $0.text == "你好" })?.consumedLength, 3)
    }

    func testFallsBackToFirstSyllable() {
        let candidates = engine.candidates(for: "woxihuanni")
        XCTAssertEqual(candidates.first, Candidate(text: "我", consumedLength: 2))
    }

    func testRareCharacters() {
        // 常用字表（GB2312）以外的字也能打出来，但排在同音常用字后面
        let yun = engine.candidates(for: "yun").map(\.text)
        XCTAssertEqual(yun.first, "云")
        XCTAssertTrue(yun.contains("赟"))
        XCTAssertTrue(engine.candidates(for: "ben").contains { $0.text == "犇" })
        XCTAssertTrue(engine.candidates(for: "yi").contains { $0.text == "燚" })
        XCTAssertTrue(engine.t9Candidates(for: "94").contains { $0.text == "燚" })
    }

    func testUmlautAsV() {
        XCTAssertTrue(engine.candidates(for: "lv").contains { $0.text == "绿" })
    }

    func testApostropheIsConsumed() {
        XCTAssertTrue(engine.candidates(for: "xi'an").contains(Candidate(text: "西安", consumedLength: 5)))
    }

    func testOrdersByFrequencyWithinKey() {
        let small = PinyinEngine(tsv: "hao\t好\t100\nhao\t号\t50\nhao ma\t好吗\t30\n")
        XCTAssertEqual(small.candidates(for: "hao").map(\.text), ["好", "号"])
        XCTAssertEqual(small.candidates(for: "haom").map(\.text), ["好吗", "好", "号"])
    }

    func testT9FullPinyin() {
        XCTAssertEqual(engine.t9Candidates(for: "64426").first?.text, "你好")
        XCTAssertEqual(engine.t9Candidates(for: "64").first?.text, "你")
        XCTAssertEqual(engine.t9Candidates(for: "944826").first?.text, "喜欢")
    }

    func testT9ShorterMatchesConsumePartOfInput() {
        let candidates = engine.t9Candidates(for: "64426")
        XCTAssertTrue(candidates.contains { $0.text == "你" && $0.consumedLength == 2 })
    }

    func testT9FirstSyllableFilter() {
        let candidates = engine.t9Candidates(for: "64", firstSyllable: "mi")
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.allSatisfy { $0.pinyin.hasPrefix("mi") })
    }

    func testT9Syllables() {
        let syllables = engine.t9Syllables(for: "64")
        XCTAssertTrue(syllables.contains("ni"))
        XCTAssertTrue(syllables.contains("mi"))
        XCTAssertEqual(Array(syllables.suffix(2)), ["m", "n"])
    }

    func testPredictions() {
        let afterNi = engine.predictions(after: "你")
        XCTAssertTrue(afterNi.contains("好"))
        XCTAssertTrue(afterNi.contains("们"))
        XCTAssertTrue(engine.predictions(after: "hello").isEmpty)
        XCTAssertEqual(engine.predictions(after: "今天").first, "晚上")
        // “你好”是完整的词，不应该按“好”去联想出“久不见”
        XCTAssertFalse(engine.predictions(after: "你好").contains("久不见"))
    }
}
