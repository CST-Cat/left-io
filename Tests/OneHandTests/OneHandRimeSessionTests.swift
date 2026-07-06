import XCTest
@testable import OneHand

final class OneHandRimeSessionTests: XCTestCase {
    func testInputAndDeleteUpdateBridgeBackedState() {
        let bridge = FakeOneHandRimeBridge()
        let session = OneHandRimeSession(bridge: bridge)

        session.apply(.inputT9Code("6"))
        session.apply(.inputT9Code("4"))

        XCTAssertEqual(bridge.setInputs, ["6", "64"])
        XCTAssertEqual(session.compositionText, "64")
        XCTAssertEqual(session.displayedCandidates, ["候选64", "次选64"])

        session.apply(.deleteBackward)

        XCTAssertEqual(bridge.setInputs.last, "6")
        XCTAssertEqual(session.compositionText, "6")
    }

    func testCommitFirstCandidateConsumesBridgeCommitText() {
        let bridge = FakeOneHandRimeBridge()
        let session = OneHandRimeSession(bridge: bridge)

        session.apply(.inputT9Code("2"))
        session.apply(.commitFirstCandidate)

        XCTAssertEqual(bridge.selectedIndices, [0])
        XCTAssertEqual(session.takeClientActions(), [.insertText("候选2")])
        XCTAssertTrue(session.displayedCandidates.isEmpty)
    }

    func testCommitCompositionFallsBackToLiteralTextWithoutCandidates() {
        let bridge = FakeOneHandRimeBridge(
            input: "64",
            preedit: "64",
            candidates: []
        )
        let session = OneHandRimeSession(bridge: bridge)

        session.commitCurrentComposition()

        XCTAssertEqual(session.takeClientActions(), [.insertText("64")])
        XCTAssertEqual(bridge.clearCompositionCalls, 1)
        XCTAssertTrue(session.displayedCandidates.isEmpty)
    }

    func testDeleteBackwardFallsBackToClientDeleteWhenInputIsEmpty() {
        let bridge = FakeOneHandRimeBridge()
        let session = OneHandRimeSession(bridge: bridge)

        session.apply(.deleteBackward)

        XCTAssertEqual(session.takeClientActions(), [.deleteBackward])
    }

    func testDirectOutputCommitsCompositionBeforeDigit() {
        let bridge = FakeOneHandRimeBridge()
        let session = OneHandRimeSession(bridge: bridge)

        session.apply(.inputT9Code("2"))
        session.apply(.inputDigit(3))

        XCTAssertEqual(session.takeClientActions(), [.insertText("候选2"), .insertText("3")])
        XCTAssertEqual(bridge.clearCompositionCalls, 1)
        XCTAssertFalse(session.context.isComposing)
    }

    func testCancelCompositionClearsBridgeState() {
        let bridge = FakeOneHandRimeBridge()
        let session = OneHandRimeSession(bridge: bridge)

        session.apply(.inputT9Code("6"))
        session.apply(.cancelComposition)

        XCTAssertEqual(bridge.clearCompositionCalls, 1)
        XCTAssertTrue(session.compositionText.isEmpty)
        XCTAssertTrue(session.displayedCandidates.isEmpty)
        XCTAssertFalse(session.context.isComposing)
    }

    func testContextTracksBridgeAsciiMode() {
        let bridge = FakeOneHandRimeBridge(asciiMode: true)
        let session = OneHandRimeSession(bridge: bridge)

        XCTAssertTrue(session.context.isAsciiMode)
    }

    func testSetAsciiModeUpdatesBridgeAndClearsComposition() {
        let bridge = FakeOneHandRimeBridge()
        let session = OneHandRimeSession(bridge: bridge)

        session.apply(.inputT9Code("6"))
        session.setAsciiMode(true)

        XCTAssertTrue(session.context.isAsciiMode)
        XCTAssertTrue(session.compositionText.isEmpty)
        XCTAssertTrue(session.displayedCandidates.isEmpty)
        XCTAssertEqual(bridge.clearCompositionCalls, 1)
    }

    func testExpandedCandidateWindowReadsFromAbsoluteCandidateListIndex() {
        let bridge = FakeOneHandRimeBridge(
            input: "2",
            preedit: "2",
            candidates: (1...12).map { "候选\($0)" }
        )
        let session = OneHandRimeSession(bridge: bridge)

        XCTAssertEqual(
            session.expandedCandidateWindow(startingAt: 4, limit: 4),
            ["候选5", "候选6", "候选7", "候选8"]
        )
    }

    func testCommitExpandedCandidateSelectsAbsoluteCandidateIndex() {
        let bridge = FakeOneHandRimeBridge(
            input: "2",
            preedit: "2",
            candidates: (1...8).map { "候选\($0)" }
        )
        let session = OneHandRimeSession(bridge: bridge)

        session.commitExpandedCandidate(at: 5)

        XCTAssertEqual(bridge.selectedAbsoluteIndices, [5])
        XCTAssertEqual(session.takeClientActions(), [.insertText("候选6")])
        XCTAssertTrue(session.displayedCandidates.isEmpty)
    }
}

private final class FakeOneHandRimeBridge: OneHandRimeBridgeClient {
    var input: String
    var preedit: String
    var candidates: [String]
    var pendingCommit: String?
    var asciiMode: Bool

    var setInputs: [String] = []
    var selectedIndices: [Int] = []
    var selectedAbsoluteIndices: [Int] = []
    var changePageCalls: [Bool] = []
    var clearCompositionCalls = 0

    init(
        input: String = "",
        preedit: String = "",
        candidates: [String] = [],
        asciiMode: Bool = false
    ) {
        self.input = input
        self.preedit = preedit
        self.candidates = candidates
        self.asciiMode = asciiMode
    }

    func setInput(_ input: String) -> Bool {
        self.input = input
        preedit = input
        candidates = input.isEmpty ? [] : ["候选\(input)", "次选\(input)"]
        setInputs.append(input)
        return true
    }

    func commitComposition() -> Bool {
        pendingCommit = candidates.first ?? input
        clearComposition()
        return true
    }

    func clearComposition() {
        clearCompositionCalls += 1
        input = ""
        preedit = ""
        candidates.removeAll()
    }

    func selectCandidateOnCurrentPage(_ index: Int) -> Bool {
        selectedIndices.append(index)
        guard candidates.indices.contains(index) else {
            return false
        }
        pendingCommit = candidates[index]
        clearComposition()
        return true
    }

    func selectCandidate(at index: Int) -> Bool {
        selectedAbsoluteIndices.append(index)
        guard candidates.indices.contains(index) else {
            return false
        }
        pendingCommit = candidates[index]
        clearComposition()
        return true
    }

    func changePage(backward: Bool) -> Bool {
        changePageCalls.append(backward)
        return true
    }

    func isAsciiMode() -> Bool {
        asciiMode
    }

    func setAsciiMode(_ enabled: Bool) -> Bool {
        asciiMode = enabled
        return true
    }

    func copyCommitText() -> String? {
        defer { pendingCommit = nil }
        return pendingCommit
    }

    func copyInput() -> String? {
        input
    }

    func copyPreedit() -> String? {
        preedit
    }

    func candidateCount() -> Int {
        candidates.count
    }

    func copyCandidate(at index: Int) -> String? {
        guard candidates.indices.contains(index) else {
            return nil
        }
        return candidates[index]
    }

    func copyCandidateListCandidate(at index: Int) -> String? {
        copyCandidate(at: index)
    }
}
