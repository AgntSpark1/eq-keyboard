import XCTest
@testable import PinyinKit

final class T9EngineTests: XCTestCase {
    static let engine = T9Engine(engine: try! PinyinEngine.bundled())
    var engine: T9Engine { Self.engine }

    func testWholeWord() {
        XCTAssertEqual(engine.candidates(for: "64426").first, Candidate(text: "你好", consumedLength: 5))
    }

    func testExactSyllableBeforeUnfinished() {
        XCTAssertEqual(engine.candidates(for: "64").first, Candidate(text: "你", consumedLength: 2))
    }

    func testUnfinishedLastSyllable() {
        XCTAssertEqual(engine.candidates(for: "6442").first?.text, "你好")
    }

    func testShorterPrefixesFollow() {
        let candidates = engine.candidates(for: "64426")
        XCTAssertTrue(candidates.contains(Candidate(text: "你", consumedLength: 2)))
    }

    func testSpellings() {
        let spellings = engine.spellings(for: "64")
        XCTAssertEqual(Array(spellings.prefix(2)).sorted(), ["mi", "ni"])
        XCTAssertTrue(spellings.contains("o"))
    }

    func testIgnoresNonDigits() {
        XCTAssertEqual(engine.candidates(for: "1"), [])
    }
}
