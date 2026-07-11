import Foundation
import XCTest

final class OneHandDictionaryGeneratorTests: XCTestCase {
    func testGeneratorAcceptsSpacesApostrophesAndUmlautForms() throws {
        let repositoryRoot = try self.repositoryRoot()
        let temporaryDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let inputURL = temporaryDirectory.appendingPathComponent("input.tsv")
        try """
        你好\tni hao\t1000
        你号\tni'hao\t900
        旅\tlü\t800
        绿\tlu:\t700
        """.write(to: inputURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3",
            repositoryRoot.appendingPathComponent("scripts/generate_onehand_t9_dict.py").path,
            inputURL.path
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        XCTAssertEqual(process.terminationStatus, 0, output)
        XCTAssertTrue(output.contains("你好\t64'426\t1000"), output)
        XCTAssertTrue(output.contains("你号\t64'426\t900"), output)
        XCTAssertTrue(output.contains("旅\t58\t800"), output)
        XCTAssertTrue(output.contains("绿\t58\t700"), output)
    }

    func testGeneratorUsesSiblingEssayFrequenciesForRimeRows() throws {
        let repositoryRoot = try self.repositoryRoot()
        let temporaryDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let inputURL = temporaryDirectory.appendingPathComponent("luna_pinyin.dict.yaml")
        try """
        # Rime dictionary
        ---
        name: luna_pinyin
        ...

        ㄕ\tshi
        你\tni
        什\tshi\t15.8%
        好\thao
        亽\txx
        """.write(to: inputURL, atomically: true, encoding: .utf8)

        let essayURL = temporaryDirectory.appendingPathComponent("essay.txt")
        try """
        你\t972978
        你好\t21493
        什\t1000
        好\t456789
        """.write(to: essayURL, atomically: true, encoding: .utf8)

        let result = try runGenerator(
            repositoryRoot: repositoryRoot,
            inputURL: inputURL
        )

        XCTAssertEqual(result.status, 0, result.output + result.error)
        XCTAssertTrue(result.output.contains("你\t64\t972978"), result.output)
        XCTAssertTrue(result.output.contains("你好\t64'426\t21493000"), result.output)
        XCTAssertTrue(result.output.contains("什\t744\t158"), result.output)
        XCTAssertTrue(result.output.contains("好\t426\t456789"), result.output)
        XCTAssertFalse(result.output.contains("ㄕ"), result.output)
        XCTAssertFalse(result.output.contains("亽"), result.output)
        XCTAssertTrue(result.error.isEmpty, result.error)
    }

    func testGeneratorDoesNotInventPhraseCodesForPolyphonicCharacters() throws {
        let repositoryRoot = try self.repositoryRoot()
        let temporaryDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let inputURL = temporaryDirectory.appendingPathComponent("luna_pinyin.dict.yaml")
        try """
        銀\tyin\t100
        行\txing\t200
        行\thang\t50
        銀行\tyin hang\t22074
        """.write(to: inputURL, atomically: true, encoding: .utf8)
        try "銀行\t22074\n".write(
            to: temporaryDirectory.appendingPathComponent("essay.txt"),
            atomically: true,
            encoding: .utf8
        )

        let result = try runGenerator(repositoryRoot: repositoryRoot, inputURL: inputURL)

        XCTAssertEqual(result.status, 0, result.output + result.error)
        XCTAssertTrue(result.output.contains("銀行\t946'4264\t22074"), result.output)
        XCTAssertFalse(result.output.contains("銀行\t946'9464"), result.output)
    }

    func testGeneratorUsesExplicitSupplementForAmbiguousPhrase() throws {
        let repositoryRoot = try self.repositoryRoot()
        let temporaryDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let inputURL = temporaryDirectory.appendingPathComponent("luna_pinyin.dict.yaml")
        try """
        大\tda\t99.85%
        大\tdai\t0.15%
        家\tjia
        好\thao
        """.write(to: inputURL, atomically: true, encoding: .utf8)
        try "大家好\t1813\n".write(
            to: temporaryDirectory.appendingPathComponent("essay.txt"),
            atomically: true,
            encoding: .utf8
        )
        let supplementURL = temporaryDirectory.appendingPathComponent("phrases.tsv")
        try "大家好\tda jia hao\n".write(
            to: supplementURL,
            atomically: true,
            encoding: .utf8
        )

        let result = try runGenerator(
            repositoryRoot: repositoryRoot,
            inputURL: inputURL,
            additionalArguments: ["--supplement", supplementURL.path]
        )

        XCTAssertEqual(result.status, 0, result.output + result.error)
        XCTAssertTrue(result.output.contains("大家好\t32'542'426\t1813"), result.output)
        XCTAssertFalse(result.output.contains("大家好\t324'542'426"), result.output)
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

    private func runGenerator(
        repositoryRoot: URL,
        inputURL: URL,
        additionalArguments: [String] = []
    ) throws -> (
        status: Int32,
        output: String,
        error: String
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3",
            repositoryRoot.appendingPathComponent("scripts/generate_onehand_t9_dict.py").path,
            inputURL.path
        ] + additionalArguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        return (
            process.terminationStatus,
            String(
                data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "",
            String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
        )
    }
}
