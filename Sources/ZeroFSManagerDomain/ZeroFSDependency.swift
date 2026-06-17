import Foundation

public enum ZeroFSInstallGuidance {
    public static let recommendedShellCommand = "curl -sSfL https://sh.zerofs.net | sh"
    public static let sourceURL = URL(string: "https://github.com/Barre/zerofs")!
}

public struct ZeroFSBinary: Equatable, Sendable {
    public var path: String
    public var version: String?

    public init(path: String, version: String? = nil) {
        self.path = path
        self.version = version
    }
}

public struct ZeroFSBinaryLocator: Sendable {
    public var pathEnvironment: String
    public var additionalCandidatePaths: [String]
    public var versionTimeoutSeconds: TimeInterval

    public init(
        pathEnvironment: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        additionalCandidatePaths: [String] = Self.defaultCandidatePaths(),
        versionTimeoutSeconds: TimeInterval = 2
    ) {
        self.pathEnvironment = pathEnvironment
        self.additionalCandidatePaths = additionalCandidatePaths
        self.versionTimeoutSeconds = versionTimeoutSeconds
    }

    public func locate(fileManager: FileManager = .default) -> ZeroFSBinary? {
        for path in candidatePaths() {
            if fileManager.isExecutableFile(atPath: path) {
                return ZeroFSBinary(path: path, version: Self.version(at: path, timeoutSeconds: versionTimeoutSeconds))
            }
        }
        return nil
    }

    public func candidatePaths() -> [String] {
        let pathCandidates = pathEnvironment
            .split(separator: ":", omittingEmptySubsequences: true)
            .map { "\($0)/zerofs" }
        return Array(OrderedSet(pathCandidates + additionalCandidatePaths))
    }

    public static func defaultCandidatePaths() -> [String] {
        var paths = [
            "/opt/homebrew/bin/zerofs",
            "/usr/local/bin/zerofs",
            "/usr/bin/zerofs"
        ]
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            paths.append("\(home)/.local/bin/zerofs")
            paths.append("\(home)/bin/zerofs")
        }
        return paths
    }

    private static func version(at path: String, timeoutSeconds: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let deadline = Date().addingTimeInterval(timeoutSeconds)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                process.terminate()
                return nil
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)
            return output
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .first(where: { $0.localizedCaseInsensitiveContains("zerofs") })
                ?? output.split(whereSeparator: \.isNewline).first.map(String.init)
        } catch {
            return nil
        }
    }
}

private struct OrderedSet<Element: Hashable>: Sequence {
    private var values: [Element] = []

    init(_ values: [Element]) {
        var seen = Set<Element>()
        self.values = values.filter { seen.insert($0).inserted }
    }

    func makeIterator() -> Array<Element>.Iterator {
        values.makeIterator()
    }
}
