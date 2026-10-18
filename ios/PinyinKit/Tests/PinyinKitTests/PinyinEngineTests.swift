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
}
