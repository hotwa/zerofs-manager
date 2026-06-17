import Foundation

public enum ProductDefaults {
    public static let firstRunAutoMountPolicy: AutoMountPolicy = .disabled
    public static let defaultPerformanceTestMegabytes = 64
}

public enum FirstRunProfilePolicy {
    public static func requireExplicitAutoMountOptIn(_ profiles: [MountProfile]) -> [MountProfile] {
        profiles.map { profile in
            var copy = profile
            copy.autoMount = .disabled
            return copy
        }
    }
}

public final class FileMountProfileStore: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public static func applicationSupport(fileManager: FileManager = .default) -> FileMountProfileStore {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return FileMountProfileStore(
            fileURL: baseDirectory
                .appendingPathComponent("ZeroFSManager", isDirectory: true)
                .appendingPathComponent("profiles.json"),
            fileManager: fileManager
        )
    }

    public func load() throws -> [MountProfile] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([MountProfile].self, from: data)
    }

    public func save(_ profiles: [MountProfile]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profiles)
        try data.write(to: fileURL, options: [.atomic])
    }
}
