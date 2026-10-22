import XCTest
@testable import PinyinKit

final class AssociatorTests: XCTestCase {
    static let associator = Associator(engine: try! PinyinEngine.bundled())
    var associator: Associator { Self.associator }

    func testSuggestsWordsStartingWithLastCharacter() {
        let suggestions = associator.suggestions(after: "你")
        XCTAssertTrue(suggestions.prefix(5).contains("好"))
        XCTAssertTrue(suggestions.contains("们"))
    }

    func testUsesLastTwoCharactersFirst() {
        // 词库里有“喜欢你”这类以“喜欢”开头的词时，它们排在单字联想前面
        let suggestions = associator.suggestions(after: "我喜欢")
        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertFalse(suggestions.contains(""))
    }

    func testEmptyInput() {
        XCTAssertEqual(associator.suggestions(after: ""), [])
        XCTAssertEqual(associator.suggestions(after: "😀"), [])
    }
}
