import XCTest
@testable import RecordoKit

final class TermKeyTests: XCTestCase {
    func testNormalizesCaseSpacesAndQuestionSuffixes() {
        XCTAssertEqual(TermKey.normalize("  Foo-Rate "), "foo-rate")
        XCTAssertEqual(TermKey.normalize("foo-rate とは？"), "foo-rate")
        XCTAssertEqual(TermKey.normalize("Bar   Cache"), "bar cache")
        XCTAssertEqual(TermKey.normalize("bar cache って何?"), "bar cache")
        XCTAssertEqual(TermKey.normalize("BAZ\n"), "baz")
    }
}
