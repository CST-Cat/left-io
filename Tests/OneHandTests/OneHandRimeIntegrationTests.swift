import Foundation
import XCTest
@testable import OneHand

final class OneHandRimeIntegrationTests: XCTestCase {
    func testVendoredLibrimeBridgeSupportsBaselineLunaPinyin() throws {
        try configureVendoredLibrime()

        let applicationSupportDirectory = makeTemporaryDirectory()
        let repositoryRoot = try self.repositoryRoot()
        var bridge: LiveOneHandRimeBridge?
        defer {
            bridge = nil
            try? FileManager.default.removeItem(at: applicationSupportDirectory)
        }

        let layout = try OneHandRimeDataProvider.prepareLayout(
            bundle: Bundle.main,
            currentDirectoryPath: repositoryRoot.path,
            applicationSupportDirectory: applicationSupportDirectory
        )

        bridge = try LiveOneHandRimeBridge(
            sharedDataDirectory: layout.sharedDataDirectory,
            userDataDirectory: layout.userDataDirectory,
            schemaId: "luna_pinyin",
            appName: "rime.leftio.tests"
        )

        XCTAssertTrue(try XCTUnwrap(bridge).setInput("ni"))

        let liveBridge = try XCTUnwrap(bridge)
        let candidates = (0..<liveBridge.candidateCount()).compactMap { index in
            liveBridge.copyCandidate(at: index)
        }
        XCTAssertTrue(
            candidates.contains("你"),
            "Expected baseline luna_pinyin candidate '你', got \(candidates)"
        )
    }

    func testVendoredLibrimeFindsAndCommitsSeedCandidate() throws {
        try configureVendoredLibrime()

        let applicationSupportDirectory = makeTemporaryDirectory()
        let repositoryRoot = try self.repositoryRoot()
        var session: OneHandRimeSession?
        defer {
            session = nil
            try? FileManager.default.removeItem(at: applicationSupportDirectory)
        }

        let layout = try OneHandRimeDataProvider.prepareLayout(
            bundle: Bundle.main,
            currentDirectoryPath: repositoryRoot.path,
            applicationSupportDirectory: applicationSupportDirectory
        )

        session = try OneHandRimeSession(
            sharedDataDirectory: layout.sharedDataDirectory,
            userDataDirectory: layout.userDataDirectory,
            schemaId: "onehand_t9",
            appName: "rime.leftio.tests"
        )

        session?.apply(.inputT9Code("6"))
        session?.apply(.inputT9Code("4"))

        let liveSession = try XCTUnwrap(session)
        XCTAssertTrue(liveSession.context.isComposing)
        XCTAssertFalse(liveSession.compositionText.isEmpty)
        XCTAssertTrue(
            liveSession.displayedCandidates.contains("你"),
            "Expected seed candidate '你' for numeric input 64, got \(liveSession.displayedCandidates)"
        )

        liveSession.commitDisplayedCandidate(matching: "你")

        XCTAssertEqual(liveSession.takeClientActions(), [.insertText("你")])
        XCTAssertFalse(liveSession.context.isComposing)
        XCTAssertTrue(liveSession.displayedCandidates.isEmpty)
    }

    func testVendoredLibrimeSupportsMultiSyllableDelimiterMatches() throws {
        try configureVendoredLibrime()

        let applicationSupportDirectory = makeTemporaryDirectory()
        let repositoryRoot = try self.repositoryRoot()
        var session: OneHandRimeSession?
        defer {
            session = nil
            try? FileManager.default.removeItem(at: applicationSupportDirectory)
        }

        let layout = try OneHandRimeDataProvider.prepareLayout(
            bundle: Bundle.main,
            currentDirectoryPath: repositoryRoot.path,
            applicationSupportDirectory: applicationSupportDirectory
        )

        session = try OneHandRimeSession(
            sharedDataDirectory: layout.sharedDataDirectory,
            userDataDirectory: layout.userDataDirectory,
            schemaId: "onehand_t9",
            appName: "rime.leftio.tests"
        )

        session?.apply(.inputT9Code("6"))
        session?.apply(.inputT9Code("4"))
        session?.apply(.insertSyllableDelimiter)
        session?.apply(.inputT9Code("4"))
        session?.apply(.inputT9Code("2"))
        session?.apply(.inputT9Code("6"))

        let liveSession = try XCTUnwrap(session)
        XCTAssertEqual(liveSession.compositionText, "64'426")
        XCTAssertTrue(
            liveSession.displayedCandidates.contains("你好"),
            "Expected multi-syllable candidate '你好' for numeric input 64'426, got \(liveSession.displayedCandidates)"
        )

        liveSession.commitDisplayedCandidate(matching: "你好")

        XCTAssertEqual(liveSession.takeClientActions(), [.insertText("你好")])
        XCTAssertFalse(liveSession.context.isComposing)
        XCTAssertTrue(liveSession.displayedCandidates.isEmpty)
    }

    func testVendoredLibrimeRanksCommonEssayPhraseBeforeGeneratedSentence() throws {
        try configureVendoredLibrime()

        let applicationSupportDirectory = makeTemporaryDirectory()
        let repositoryRoot = try self.repositoryRoot()
        var session: OneHandRimeSession?
        defer {
            session = nil
            try? FileManager.default.removeItem(at: applicationSupportDirectory)
        }

        let layout = try OneHandRimeDataProvider.prepareLayout(
            bundle: Bundle.main,
            currentDirectoryPath: repositoryRoot.path,
            applicationSupportDirectory: applicationSupportDirectory
        )

        session = try OneHandRimeSession(
            sharedDataDirectory: layout.sharedDataDirectory,
            userDataDirectory: layout.userDataDirectory,
            schemaId: "onehand_t9",
            appName: "rime.leftio.tests"
        )

        for code in ["3", "2"] {
            session?.apply(.inputT9Code(code))
        }
        session?.apply(.insertSyllableDelimiter)
        for code in ["5", "4", "2"] {
            session?.apply(.inputT9Code(code))
        }
        session?.apply(.insertSyllableDelimiter)
        for code in ["4", "2", "6"] {
            session?.apply(.inputT9Code(code))
        }

        let liveSession = try XCTUnwrap(session)
        XCTAssertEqual(liveSession.compositionText, "32'542'426")
        XCTAssertEqual(
            liveSession.displayedCandidates.first,
            "大家好",
            "Expected common phrase '大家好' first, got \(liveSession.displayedCandidates)"
        )
    }

    func testVendoredLibrimeCanToggleAsciiMode() throws {
        try configureVendoredLibrime()

        let applicationSupportDirectory = makeTemporaryDirectory()
        let repositoryRoot = try self.repositoryRoot()
        var session: OneHandRimeSession?
        defer {
            session = nil
            try? FileManager.default.removeItem(at: applicationSupportDirectory)
        }

        let layout = try OneHandRimeDataProvider.prepareLayout(
            bundle: Bundle.main,
            currentDirectoryPath: repositoryRoot.path,
            applicationSupportDirectory: applicationSupportDirectory
        )

        session = try OneHandRimeSession(
            sharedDataDirectory: layout.sharedDataDirectory,
            userDataDirectory: layout.userDataDirectory,
            schemaId: "onehand_t9",
            appName: "rime.leftio.tests"
        )

        let liveSession = try XCTUnwrap(session)
        XCTAssertFalse(liveSession.context.isAsciiMode)

        liveSession.setAsciiMode(true)

        XCTAssertTrue(liveSession.context.isAsciiMode)
    }

    private func configureVendoredLibrime() throws {
        let fileManager = FileManager.default
        let repoRoot = try repositoryRoot()
        let candidates = [
            repoRoot.appendingPathComponent("vendor/librime/build/lib/librime.1.dylib"),
            repoRoot.appendingPathComponent("vendor/librime/build/lib/librime.dylib"),
            repoRoot.appendingPathComponent("vendor/librime/build/lib/Release/librime.1.dylib"),
            repoRoot.appendingPathComponent("vendor/librime/build/lib/Release/librime.dylib"),
            repoRoot.appendingPathComponent("vendor/librime/dist/lib/librime.1.dylib"),
            repoRoot.appendingPathComponent("vendor/librime/dist/lib/librime.dylib")
        ]

        guard let dylibURL = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("Vendored librime dylib is unavailable. Run scripts/build_vendored_librime.sh first.")
        }

        setenv("LEFTIO_LIBRIME_PATH", dylibURL.path, 1)
    }

    private func makeTemporaryDirectory() -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func repositoryRoot(file: StaticString = #filePath) throws -> URL {
        let fileManager = FileManager.default
        var url = URL(fileURLWithPath: "\(file)", isDirectory: false).deletingLastPathComponent()

        while url.path != "/" {
            if fileManager.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }

        throw XCTSkip("Unable to locate repository root from \(file).")
    }
}
