import XCTest
@testable import OneHand

final class T9EncoderTests: XCTestCase {
    func testEncodesPinyinLettersToOneHandT9Digits() {
        XCTAssertEqual(OneHandT9Encoder.encode("ni"), "64")
        XCTAssertEqual(OneHandT9Encoder.encode("hao"), "426")
        XCTAssertEqual(OneHandT9Encoder.encode("shi"), "744")
        XCTAssertEqual(OneHandT9Encoder.encode("wo"), "96")
    }

    func testRejectsNonLetters() {
        XCTAssertNil(OneHandT9Encoder.encode("ni3"))
        XCTAssertNil(OneHandT9Encoder.encode("lü"))
    }
}
