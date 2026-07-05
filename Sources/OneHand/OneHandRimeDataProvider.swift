import Foundation

public enum OneHandRimeDataProvider {
    public struct Layout: Equatable, Sendable {
        public var sharedDataDirectory: URL
        public var userDataDirectory: URL

        public init(sharedDataDirectory: URL, userDataDirectory: URL) {
            self.sharedDataDirectory = sharedDataDirectory
            self.userDataDirectory = userDataDirectory
        }
    }

    public enum Error: Swift.Error, Equatable {
        case missingBaseData
        case missingOverlayData
    }

    private static let requiredBaseFiles = [
        "default.yaml",
        "symbols.yaml",
        "essay.txt"
    ]

    private static let requiredOverlayFiles = [
        "onehand_t9.schema.yaml",
        "onehand_t9.dict.yaml",
        "onehand_symbols.yaml"
    ]

    public static func prepareLayout(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) throws -> Layout {
        try prepareLayout(
            bundle: bundle,
            fileManager: fileManager,
            currentDirectoryPath: currentDirectoryPath,
            applicationSupportDirectory: nil
        )
    }

    public static func prepareLayout(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        applicationSupportDirectory: URL?
    ) throws -> Layout {
        let rootApplicationSupportDirectory = applicationSupportDirectory
            ?? (fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
        let userDataDirectory = rootApplicationSupportDirectory
            .appendingPathComponent("LeftIO", isDirectory: true)
            .appendingPathComponent("Rime", isDirectory: true)

        if let bundledRimeDirectory = bundle.url(forResource: "Rime", withExtension: nil),
           containsRequiredFiles(in: bundledRimeDirectory, names: requiredBaseFiles + requiredOverlayFiles, fileManager: fileManager) {
            try fileManager.createDirectory(at: userDataDirectory, withIntermediateDirectories: true)
            return Layout(
                sharedDataDirectory: bundledRimeDirectory,
                userDataDirectory: userDataDirectory
            )
        }

        let repoRoot = URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
        let overlayDirectory = repoRoot.appendingPathComponent("data", isDirectory: true)
        guard containsRequiredFiles(in: overlayDirectory, names: requiredOverlayFiles, fileManager: fileManager) else {
            throw Error.missingOverlayData
        }

        let baseCandidates = [
            repoRoot.appendingPathComponent("vendor/librime/data/minimal", isDirectory: true),
            repoRoot.appendingPathComponent("vendor/librime/data/preset", isDirectory: true)
        ]

        guard let baseDirectory = baseCandidates.first(where: {
            containsRequiredFiles(in: $0, names: requiredBaseFiles, fileManager: fileManager)
        }) else {
            throw Error.missingBaseData
        }

        let sharedDataDirectory = userDataDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("RimeSharedData", isDirectory: true)

        try rebuildSharedDataDirectory(
            at: sharedDataDirectory,
            baseDirectory: baseDirectory,
            overlayDirectory: overlayDirectory,
            fileManager: fileManager
        )
        try fileManager.createDirectory(at: userDataDirectory, withIntermediateDirectories: true)

        return Layout(
            sharedDataDirectory: sharedDataDirectory,
            userDataDirectory: userDataDirectory
        )
    }

    private static func rebuildSharedDataDirectory(
        at targetDirectory: URL,
        baseDirectory: URL,
        overlayDirectory: URL,
        fileManager: FileManager
    ) throws {
        if fileManager.fileExists(atPath: targetDirectory.path) {
            try fileManager.removeItem(at: targetDirectory)
        }

        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        try copyContents(of: baseDirectory, into: targetDirectory, fileManager: fileManager)
        try copyContents(of: overlayDirectory, into: targetDirectory, fileManager: fileManager)
    }

    private static func copyContents(
        of sourceDirectory: URL,
        into targetDirectory: URL,
        fileManager: FileManager
    ) throws {
        let normalizedSourceDirectory = sourceDirectory.resolvingSymlinksInPath().standardizedFileURL
        guard let enumerator = fileManager.enumerator(
            at: normalizedSourceDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues.isDirectory != true else {
                continue
            }

            let normalizedFileURL = fileURL.resolvingSymlinksInPath().standardizedFileURL
            let relativeComponents = normalizedFileURL.pathComponents.dropFirst(
                normalizedSourceDirectory.pathComponents.count
            )
            let relativePath = relativeComponents.joined(separator: "/")
            let targetURL = targetDirectory.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.copyItem(at: fileURL, to: targetURL)
        }
    }

    private static func containsRequiredFiles(
        in directory: URL,
        names: [String],
        fileManager: FileManager
    ) -> Bool {
        names.allSatisfy { name in
            fileManager.fileExists(atPath: directory.appendingPathComponent(name).path)
        }
    }
}
