import Foundation

public final class OneHandLexiconSession: OneHandSession {
    public let lexicon: OneHandLexicon
    public let pageSize: Int

    public private(set) var compositionText = ""
    public private(set) var allCandidates: [String] = []

    private var isAsciiMode = false
    private var currentPageIndex = 0
    private var pendingClientActions: [OneHandClientAction] = []

    public var displayedCandidates: [String] {
        guard !allCandidates.isEmpty else {
            return []
        }

        let start = currentPageIndex * pageSize
        let end = min(start + pageSize, allCandidates.count)
        guard start < end else {
            return []
        }
        return Array(allCandidates[start..<end])
    }

    public var context: OneHandContext {
        OneHandContext(
            isComposing: !compositionText.isEmpty,
            hasCandidates: !allCandidates.isEmpty,
            isAsciiMode: isAsciiMode
        )
    }

    public init(lexicon: OneHandLexicon, pageSize: Int = 4) {
        self.lexicon = lexicon
        self.pageSize = pageSize
    }

    public func apply(_ action: OneHandAction) {
        switch action {
        case .enterSymbolLayer, .exitSymbolLayer, .cancelPendingSpace:
            break
        case .cancelComposition:
            compositionText.removeAll()
            allCandidates.removeAll()
            currentPageIndex = 0
        case .insertSyllableDelimiter:
            guard !compositionText.isEmpty else {
                return
            }
            compositionText.append("'")
            refreshCandidates(resetPage: true)
        case let .inputT9Code(code):
            compositionText.append(code)
            refreshCandidates(resetPage: true)
        case let .inputDigit(digit):
            flushCompositionBeforeDirectOutput()
            pendingClientActions.append(.insertText(String(digit)))
        case let .insertText(text):
            flushCompositionBeforeDirectOutput()
            pendingClientActions.append(.insertText(text))
        case .deleteBackward:
            if !compositionText.isEmpty {
                compositionText.removeLast()
                refreshCandidates(resetPage: true)
            } else {
                pendingClientActions.append(.deleteBackward)
            }
        case .pageUp:
            if currentPageIndex > 0 {
                currentPageIndex -= 1
            }
        case .pageDown:
            if hasNextPage {
                currentPageIndex += 1
            }
        case let .selectCandidate(index):
            commitDisplayedCandidate(at: index)
        case .commitFirstCandidate:
            commitDisplayedCandidate(at: 0)
        case .commitComposition:
            commitCurrentComposition()
        case .insertSpace:
            flushCompositionBeforeDirectOutput()
            pendingClientActions.append(.insertText(" "))
        case .insertNewline:
            flushCompositionBeforeDirectOutput()
            pendingClientActions.append(.insertText("\n"))
        }
    }

    public func takeClientActions() -> [OneHandClientAction] {
        defer {
            pendingClientActions.removeAll()
        }
        return pendingClientActions
    }

    public func commitCurrentComposition() {
        if let candidate = displayedCandidates.first {
            queueCommit(candidate)
            return
        }

        guard !compositionText.isEmpty else {
            return
        }

        queueCommit(compositionText)
    }

    public func reset() {
        compositionText.removeAll()
        allCandidates.removeAll()
        currentPageIndex = 0
        pendingClientActions.removeAll()
    }

    public func commitDisplayedCandidate(matching text: String) {
        guard let index = displayedCandidates.firstIndex(of: text) else {
            return
        }
        commitDisplayedCandidate(at: index)
    }

    public func setAsciiMode(_ enabled: Bool) {
        isAsciiMode = enabled
        compositionText.removeAll()
        allCandidates.removeAll()
        currentPageIndex = 0
    }

    private var hasNextPage: Bool {
        (currentPageIndex + 1) * pageSize < allCandidates.count
    }

    private func commitDisplayedCandidate(at index: Int) {
        guard displayedCandidates.indices.contains(index) else {
            return
        }

        queueCommit(displayedCandidates[index])
    }

    private func queueCommit(_ text: String) {
        pendingClientActions.append(.insertText(text))
        compositionText.removeAll()
        allCandidates.removeAll()
        currentPageIndex = 0
    }

    private func refreshCandidates(resetPage: Bool) {
        allCandidates = lexicon.candidates(matching: compositionText).map(\.text)

        if resetPage {
            currentPageIndex = 0
            return
        }

        let lastPageIndex = max((allCandidates.count - 1) / pageSize, 0)
        currentPageIndex = min(currentPageIndex, lastPageIndex)
    }

    private func flushCompositionBeforeDirectOutput() {
        guard !compositionText.isEmpty else {
            return
        }
        commitCurrentComposition()
    }
}
