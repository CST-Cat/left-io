import XCTest
@testable import OneHand

final class OneHandRimeDataProviderTests: XCTestCase {
    func testUsesBundledRimeDirectoryWhenComplete() throws {
        let fixtureRoot = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let bundleRoot = fixtureRoot.appendingPathComponent("Bundle", isDirectory: true)
        let rimeDirectory = bundleRoot.appendingPathComponent("Rime", isDirectory: true)
        let applicationSupportDirectory = fixtureRoot.appendingPathComponent("Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: rimeDirectory, withIntermediateDirectories: true)
        try createFiles(
            in: rimeDirectory,
            names: [
                "default.yaml",
                "symbols.yaml",
                "essay.txt",
                "onehand_t9.schema.yaml",
                "onehand_t9.dict.yaml",
                "onehand_symbols.yaml"
            ]
        )

        let bundle = Bundle(url: bundleRoot)
        let layout = try OneHandRimeDataProvider.prepareLayout(
            bundle: try XCTUnwrap(bundle),
            currentDirectoryPath: fixtureRoot.path,
            applicationSupportDirectory: applicationSupportDirectory
        )

        XCTAssertEqual(layout.sharedDataDirectory.path, rimeDirectory.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.userDataDirectory.path))
    }

    func testStagesVendoredMinimalDataAndOverlayIntoUserSupport() throws {
        let fixtureRoot = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let overlay = fixtureRoot.appendingPathComponent("data", isDirectory: true)
        let minimal = fixtureRoot.appendingPathComponent("vendor/librime/data/minimal", isDirectory: true)
        let applicationSupportDirectory = fixtureRoot.appendingPathComponent("Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: overlay, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: minimal, withIntermediateDirectories: true)

        try createFiles(in: minimal, names: ["default.yaml", "symbols.yaml", "essay.txt"])
        try createFiles(in: overlay, names: ["onehand_t9.schema.yaml", "onehand_t9.dict.yaml", "onehand_symbols.yaml"])

        let emptyBundleRoot = fixtureRoot.appendingPathComponent("EmptyBundle", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyBundleRoot, withIntermediateDirectories: true)
        let bundle = try XCTUnwrap(Bundle(url: emptyBundleRoot))

        let layout = try OneHandRimeDataProvider.prepareLayout(
            bundle: bundle,
            currentDirectoryPath: fixtureRoot.path,
            applicationSupportDirectory: applicationSupportDirectory
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.sharedDataDirectory.appendingPathComponent("default.yaml").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.sharedDataDirectory.appendingPathComponent("onehand_t9.schema.yaml").path))
    }

    func testThrowsWhenVendoredMinimalDataIsMissing() throws {
        let fixtureRoot = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let overlay = fixtureRoot.appendingPathComponent("data", isDirectory: true)
        let applicationSupportDirectory = fixtureRoot.appendingPathComponent("Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: overlay, withIntermediateDirectories: true)
        try createFiles(in: overlay, names: ["onehand_t9.schema.yaml", "onehand_t9.dict.yaml", "onehand_symbols.yaml"])

        let emptyBundleRoot = fixtureRoot.appendingPathComponent("EmptyBundle", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyBundleRoot, withIntermediateDirectories: true)
        let bundle = try XCTUnwrap(Bundle(url: emptyBundleRoot))

        XCTAssertThrowsError(
            try OneHandRimeDataProvider.prepareLayout(
                bundle: bundle,
                currentDirectoryPath: fixtureRoot.path,
                applicationSupportDirectory: applicationSupportDirectory
            )
        ) { error in
            XCTAssertEqual(error as? OneHandRimeDataProvider.Error, .missingBaseData)
        }
    }

    private func makeTemporaryDirectory() -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func createFiles(in directory: URL, names: [String]) throws {
        for name in names {
            try "".write(
                to: directory.appendingPathComponent(name),
                atomically: true,
                encoding: .utf8
            )
        }
    }
}
