import XCTest
@testable import OneHand

final class OneHandLexiconSessionTests: XCTestCase {
    func testLexiconParsesRimeDictionaryAndRanksExactMatchesFirst() {
        let lexicon = OneHandLexicon.parse(rimeDictionary: """
        ---
        name: onehand_t9
        version: "0.1.0"
        ...
        你\t64\t1000
        妮\t64\t900
        你好\t64'426\t1200
        逆\t64\t800
        """)

        XCTAssertEqual(
            lexicon.candidates(matching: "64").map(\.text),
            ["你", "妮", "逆", "你好"]
        )
    }

    func testSessionUpdatesCandidatesAndCommitsFirstCandidate() {
        let session = OneHandLexiconSession(lexicon: .seed)

        session.apply(.inputT9Code("6"))
        session.apply(.inputT9Code("4"))

        XCTAssertEqual(session.compositionText, "64")
        XCTAssertEqual(session.displayedCandidates, ["你", "你好"])

        session.apply(.commitComposition)

        XCTAssertEqual(session.takeClientActions(), [.insertText("你")])
        XCTAssertEqual(session.compositionText, "")
        XCTAssertEqual(session.displayedCandidates, [])
    }

    func testSessionSupportsMultiSyllableDelimiterMatches() {
        let session = OneHandLexiconSession(lexicon: .seed)

        session.apply(.inputT9Code("6"))
        session.apply(.inputT9Code("4"))
        session.apply(.insertSyllableDelimiter)
        session.apply(.inputT9Code("4"))
        session.apply(.inputT9Code("2"))
        session.apply(.inputT9Code("6"))

        XCTAssertEqual(session.compositionText, "64'426")
        XCTAssertEqual(session.displayedCandidates, ["你好"])

        session.apply(.commitComposition)

        XCTAssertEqual(session.takeClientActions(), [.insertText("你好")])
        XCTAssertFalse(session.context.isComposing)
    }

    func testSessionSupportsPagingAndRelativeCandidateSelection() {
        let lexicon = OneHandLexicon(entries: [
            .init(text: "一", code: "2", weight: 500),
            .init(text: "乙", code: "2", weight: 400),
            .init(text: "已", code: "2", weight: 300),
            .init(text: "以", code: "2", weight: 200),
            .init(text: "亿", code: "2", weight: 100)
        ])
        let session = OneHandLexiconSession(lexicon: lexicon, pageSize: 4)

        session.apply(.inputT9Code("2"))
        XCTAssertEqual(session.displayedCandidates, ["一", "乙", "已", "以"])

        session.apply(.pageDown)
        XCTAssertEqual(session.displayedCandidates, ["亿"])

        session.apply(.selectCandidate(0))
        XCTAssertEqual(session.takeClientActions(), [.insertText("亿")])
        XCTAssertEqual(session.displayedCandidates, [])
    }

    func testCommitDisplayedCandidateByIndexCommitsRequestedCandidate() {
        let session = OneHandLexiconSession(lexicon: .seed)
        session.apply(.inputT9Code("6"))
        session.apply(.inputT9Code("4"))

        session.commitDisplayedCandidate(at: 1)

        XCTAssertEqual(session.takeClientActions(), [.insertText("你好")])
    }

    func testDeleteBackwardRefreshesCandidatesAndFallsBackToClientDelete() {
        let session = OneHandLexiconSession(lexicon: .seed)

        session.apply(.inputT9Code("6"))
        session.apply(.inputT9Code("4"))
        XCTAssertEqual(session.displayedCandidates, ["你", "你好"])

        session.apply(.deleteBackward)
        XCTAssertEqual(session.compositionText, "6")
        XCTAssertEqual(session.displayedCandidates, ["你", "你好"])

        session.apply(.deleteBackward)
        session.apply(.deleteBackward)

        XCTAssertEqual(session.takeClientActions(), [.deleteBackward])
    }

    func testDirectOutputCommitsCompositionBeforeDigit() {
        let lexicon = OneHandLexicon(entries: [
            .init(text: "你", code: "64", weight: 1000)
        ])
        let session = OneHandLexiconSession(lexicon: lexicon)

        session.apply(.inputT9Code("6"))
        session.apply(.inputT9Code("4"))
        session.apply(.inputDigit(2))

        XCTAssertEqual(session.takeClientActions(), [.insertText("你"), .insertText("2")])
        XCTAssertFalse(session.context.isComposing)
    }

    func testCancelCompositionClearsPendingLexiconState() {
        let session = OneHandLexiconSession(lexicon: .seed)

        session.apply(.inputT9Code("6"))
        session.apply(.inputT9Code("4"))
        session.apply(.cancelComposition)

        XCTAssertEqual(session.compositionText, "")
        XCTAssertEqual(session.displayedCandidates, [])
        XCTAssertFalse(session.context.isComposing)
    }
}
