import Foundation
import ZeroFSManagerDomain
import ZeroFSManagerHelperClient

public struct HelperRuntimeFileSet: Equatable, Sendable {
    public var profile: MountProfile
    public var paths: ProfileRuntimePaths

    public init(profile: MountProfile, paths: ProfileRuntimePaths) {
        self.profile = profile
        self.paths = paths
    }

    public var configContents: String {
        let storagePrefix = profile.prefix.isEmpty ? "" : "/\(profile.prefix)"
        return """
        [cache]
        dir = "${ZEROFS_CACHE_DIR}"
        disk_size_gb = \(profile.cache.diskGigabytes)
        memory_size_gb = \(profile.cache.memoryGigabytes)

        [storage]
        url = \(tomlString("s3://\(profile.bucket)\(storagePrefix)"))
        encryption_password = "${ZEROFS_PASSWORD}"

        [filesystem]
        max_size_gb = \(profile.quota.gigabytes)
        compression = "zstd-3"

        [aws]
        access_key_id = "${AWS_ACCESS_KEY_ID}"
        secret_access_key = "${AWS_SECRET_ACCESS_KEY}"
        endpoint = \(tomlString(profile.endpoint))
        region = \(tomlString(profile.region))

        [servers.nfs]
        addresses = [\(tomlString("127.0.0.1:\(profile.ports.nfs)"))]

        [servers.rpc]
        addresses = [\(tomlString("127.0.0.1:\(profile.ports.rpc)"))]
        unix_socket = \(tomlString("/var/run/zerofs-manager-\(profile.id.rawValue).rpc.sock"))

        [prometheus]
        addresses = [\(tomlString("127.0.0.1:\(profile.ports.metrics)"))]

        [telemetry]
        enabled = false
        """
    }

    public func envContents(accessKeyVariable: String, secretKeyVariable: String, encryptionPasswordVariable: String) -> String {
        """
        AWS_ACCESS_KEY_ID=\(shellQuote(accessKeyVariable))
        AWS_SECRET_ACCESS_KEY=\(shellQuote(secretKeyVariable))
        ZEROFS_PASSWORD=\(shellQuote(encryptionPasswordVariable))
        ZEROFS_CACHE_DIR=\(shellQuote(paths.cachePath))
        ZEROFS_CONFIG=\(shellQuote(paths.configPath))
        ZEROFS_ENV_FILE=\(shellQuote(paths.envPath))
        """
    }

    public func runScriptContents(binary: ZeroFSBinary) -> String {
        """
        #!/bin/zsh
        set -euo pipefail

        set -a
        source \(shellQuote(paths.envPath))
        set +a

        exec \(shellQuote(binary.path)) run --config \(shellQuote(paths.configPath))
        """
    }

    public var mountScriptContents: String {
        """
        #!/bin/zsh
        set -euo pipefail

        MOUNT_POINT=\(shellQuote(profile.mountPath.rawValue))
        NFS_HOST="127.0.0.1"
        NFS_PORT="\(profile.ports.nfs)"
        NFS_SOURCE="127.0.0.1:/"
        NFS_OPTIONS="\(ExternalZeroFSCommandFactory.nfsMountOptions(for: profile))"

        if /sbin/mount | /usr/bin/grep -Fq " on ${MOUNT_POINT} "; then
          exit 0
        fi

        /bin/mkdir -p "${MOUNT_POINT}"

        ready="false"
        for _ in {1..60}; do
          if /usr/bin/nc -z "${NFS_HOST}" "${NFS_PORT}" >/dev/null 2>&1; then
            ready="true"
            break
          fi
          /bin/sleep 1
        done

        if [[ "${ready}" != "true" ]]; then
          echo "ZeroFS NFS port ${NFS_HOST}:${NFS_PORT} did not become ready within 60 seconds" >&2
          exit 1
        fi

        /sbin/mount -t nfs -o "${NFS_OPTIONS}" "${NFS_SOURCE}" "${MOUNT_POINT}"
        """
    }

    public func flushScriptContents(binary: ZeroFSBinary) -> String {
        """
        #!/bin/zsh
        set -euo pipefail

        set -a
        source \(shellQuote(paths.envPath))
        set +a

        exec \(shellQuote(binary.path)) flush --config \(shellQuote(paths.configPath))
        """
    }
}

private func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

private func tomlString(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\t", with: "\\t")
    return "\"\(escaped)\""
}

public enum HelperRuntimeValidationError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidProfile([ValidationIssue])
    case invalidPrivilegedMountPath([ValidationIssue])
    case invalidRuntimeRoot(String)
    case invalidServiceLabel(String)
    case invalidPortSet

    public var description: String {
        switch self {
        case .invalidProfile(let issues):
            "Invalid profile: \(issues.map(\.description).joined(separator: ", "))"
        case .invalidPrivilegedMountPath(let issues):
            "Invalid privileged mount path: \(issues.map(\.description).joined(separator: ", "))"
        case .invalidRuntimeRoot(let path):
            "Invalid runtime root: \(path)"
        case .invalidServiceLabel(let label):
            "Invalid service label: \(label)"
        case .invalidPortSet:
            "Invalid or duplicate port set"
        }
    }
}

public enum HelperRuntimeValidator {
    public static func validate(
        profile: MountProfile,
        runtimePaths: ProfileRuntimePaths,
        serviceNames: ServiceNames,
        allowedRuntimeRoots: [String] = ["/Library/Application Support/ZeroFSManager/Profiles"]
    ) throws {
        let profileIssues = ProfileValidator.validate(profile)
        if !profileIssues.isEmpty {
            throw HelperRuntimeValidationError.invalidProfile(profileIssues)
        }

        let mountIssues = PrivilegedMountPathPolicy().issues(for: profile.mountPath)
        if !mountIssues.isEmpty {
            throw HelperRuntimeValidationError.invalidPrivilegedMountPath(mountIssues)
        }

        let standardizedRuntimeRoot = URL(fileURLWithPath: runtimePaths.runtimeRoot).standardizedFileURL.path
        let allowedProfileRoots = allowedRuntimeRoots.map { root in
            URL(fileURLWithPath: "\(root)/\(profile.id.rawValue)").standardizedFileURL.path
        }
        guard standardizedRuntimeRoot == runtimePaths.runtimeRoot,
              allowedProfileRoots.contains(runtimePaths.runtimeRoot) else {
            throw HelperRuntimeValidationError.invalidRuntimeRoot(runtimePaths.runtimeRoot)
        }

        let labels = [
            serviceNames.helperLaunchDaemonLabel,
            serviceNames.profileRuntimeLabel,
            serviceNames.profileMountLabel
        ]
        guard labels.allSatisfy({ $0.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) != nil }) else {
            throw HelperRuntimeValidationError.invalidServiceLabel(labels.joined(separator: ","))
        }

        let ports = profile.ports.values
        guard ports.allSatisfy({ (1...65_535).contains($0) }), Set(ports).count == ports.count else {
            throw HelperRuntimeValidationError.invalidPortSet
        }
    }
}

public enum HelperRuntimeGenerator {
    public static func makeFileSet(profile: MountProfile) throws -> HelperRuntimeFileSet {
        let paths = ProfileRuntimePaths(profile: profile)
        return try makeFileSet(profile: profile, paths: paths)
    }

    public static func makeFileSet(
        profile: MountProfile,
        paths: ProfileRuntimePaths,
        allowedRuntimeRoots: [String] = ["/Library/Application Support/ZeroFSManager/Profiles"]
    ) throws -> HelperRuntimeFileSet {
        let services = ServiceNames(profile: profile)
        try HelperRuntimeValidator.validate(
            profile: profile,
            runtimePaths: paths,
            serviceNames: services,
            allowedRuntimeRoots: allowedRuntimeRoots
        )
        return HelperRuntimeFileSet(profile: profile, paths: paths)
    }
}

public struct ExternalZeroFSRuntimeDependency: Equatable, Sendable {
    public var binary: ZeroFSBinary

    public init(binary: ZeroFSBinary) {
        self.binary = binary
    }

    public func runArguments(configPath: String) -> [String] {
        [binary.path, "run", "--config", configPath]
    }

    public func flushArguments(configPath: String) -> [String] {
        [binary.path, "flush", "--config", configPath]
    }
}

public struct HelperRuntimeWriter {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func write(fileSet: HelperRuntimeFileSet, envContents: String) throws {
        let runtimeURL = URL(fileURLWithPath: fileSet.paths.runtimeRoot, isDirectory: true)
        try fileManager.createDirectory(at: runtimeURL, withIntermediateDirectories: true)
        try write(fileSet.configContents, to: URL(fileURLWithPath: fileSet.paths.configPath), permissions: 0o644)
        try write(envContents, to: URL(fileURLWithPath: fileSet.paths.envPath), permissions: 0o600)
    }

    public func writeRuntimeFiles(fileSet: HelperRuntimeFileSet, binary: ZeroFSBinary) throws {
        try fileManager.createDirectory(
            at: URL(fileURLWithPath: fileSet.paths.runtimeRoot, isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: URL(fileURLWithPath: fileSet.paths.logPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: URL(fileURLWithPath: fileSet.paths.runtimeLaunchDaemonPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try write(fileSet.configContents, to: URL(fileURLWithPath: fileSet.paths.configPath), permissions: 0o644)
        try write(fileSet.runScriptContents(binary: binary), to: URL(fileURLWithPath: fileSet.paths.runScriptPath), permissions: 0o700)
        try write(fileSet.mountScriptContents, to: URL(fileURLWithPath: fileSet.paths.mountScriptPath), permissions: 0o700)
        try write(fileSet.flushScriptContents(binary: binary), to: URL(fileURLWithPath: fileSet.paths.flushScriptPath), permissions: 0o700)
        try write(
            String(decoding: try ProfileLaunchDaemonPlistGenerator.runtimePlistData(fileSet: fileSet), as: UTF8.self),
            to: URL(fileURLWithPath: fileSet.paths.runtimeLaunchDaemonPath),
            permissions: 0o644
        )
        try write(
            String(decoding: try ProfileLaunchDaemonPlistGenerator.mountPlistData(fileSet: fileSet), as: UTF8.self),
            to: URL(fileURLWithPath: fileSet.paths.mountLaunchDaemonPath),
            permissions: 0o644
        )
    }

    public func writeSecrets(fileSet: HelperRuntimeFileSet, secrets: RuntimeSecretPayload) throws {
        try fileManager.createDirectory(
            at: URL(fileURLWithPath: fileSet.paths.runtimeRoot, isDirectory: true),
            withIntermediateDirectories: true
        )
        try write(
            fileSet.envContents(
                accessKeyVariable: secrets.accessKeyID,
                secretKeyVariable: secrets.secretAccessKey,
                encryptionPasswordVariable: secrets.zeroFSEncryptionPassword
            ),
            to: URL(fileURLWithPath: fileSet.paths.envPath),
            permissions: 0o600
        )
    }

    private func write(_ contents: String, to url: URL, permissions: Int) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }
}

public struct HelperCommand: Equatable, Sendable {
    public var executablePath: String
    public var arguments: [String]

    public init(executablePath: String, arguments: [String]) {
        self.executablePath = executablePath
        self.arguments = arguments
    }
}

public struct HelperCommandResult: Equatable, Sendable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public init(exitCode: Int32, standardOutput: String = "", standardError: String = "") {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public static let success = HelperCommandResult(exitCode: 0)
}

public protocol HelperCommandRunner: AnyObject, Sendable {
    func run(_ command: HelperCommand) async throws -> HelperCommandResult
}

public final class ProcessHelperCommandRunner: HelperCommandRunner, @unchecked Sendable {
    public init() {}

    public func run(_ command: HelperCommand) async throws -> HelperCommandResult {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command.executablePath)
            process.arguments = command.arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()

            let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let error = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return HelperCommandResult(exitCode: process.terminationStatus, standardOutput: output, standardError: error)
        }.value
    }
}

public final class RecordingHelperCommandRunner: HelperCommandRunner, @unchecked Sendable {
    public private(set) var commands: [HelperCommand] = []
    public var queuedResults: [HelperCommandResult]

    public init(queuedResults: [HelperCommandResult] = []) {
        self.queuedResults = queuedResults
    }

    public func run(_ command: HelperCommand) async throws -> HelperCommandResult {
        commands.append(command)
        if queuedResults.isEmpty {
            return .success
        }
        return queuedResults.removeFirst()
    }
}

public enum ExternalZeroFSCommandFactory {
    public static func runCommand(binary: ZeroFSBinary, configPath: String) -> HelperCommand {
        HelperCommand(executablePath: binary.path, arguments: ["run", "--config", configPath])
    }

    public static func flushCommand(binary: ZeroFSBinary, configPath: String) -> HelperCommand {
        HelperCommand(executablePath: binary.path, arguments: ["flush", "--config", configPath])
    }

    public static func nfsMountOptions(for profile: MountProfile) -> String {
        "async,nolocks,vers=3,tcp,port=\(profile.ports.nfs),mountport=\(profile.ports.nfs),hard,rsize=1048576,wsize=1048576"
    }

    public static func mountCommand(profile: MountProfile) -> HelperCommand {
        HelperCommand(
            executablePath: "/sbin/mount",
            arguments: [
                "-t",
                "nfs",
                "-o",
                nfsMountOptions(for: profile),
                "127.0.0.1:/",
                profile.mountPath.rawValue
            ]
        )
    }

    public static func unmountCommand(profile: MountProfile) -> HelperCommand {
        HelperCommand(executablePath: "/sbin/umount", arguments: [profile.mountPath.rawValue])
    }

    public static func launchctlBootstrapCommand(plistPath: String) -> HelperCommand {
        HelperCommand(executablePath: "/bin/launchctl", arguments: ["bootstrap", "system", plistPath])
    }

    public static func launchctlBootoutCommand(plistPath: String) -> HelperCommand {
        HelperCommand(executablePath: "/bin/launchctl", arguments: ["bootout", "system", plistPath])
    }

    public static func launchctlEnableCommand(label: String) -> HelperCommand {
        HelperCommand(executablePath: "/bin/launchctl", arguments: ["enable", "system/\(label)"])
    }

    public static func launchctlKickstartCommand(label: String) -> HelperCommand {
        HelperCommand(executablePath: "/bin/launchctl", arguments: ["kickstart", "-k", "system/\(label)"])
    }

    public static func launchctlPrintCommand(label: String) -> HelperCommand {
        HelperCommand(executablePath: "/bin/launchctl", arguments: ["print", "system/\(label)"])
    }
}

public enum ProfileLaunchDaemonPlistGenerator {
    public static func runtimePlistData(fileSet: HelperRuntimeFileSet) throws -> Data {
        let names = ServiceNames(profile: fileSet.profile)
        return try plistData([
            "Label": names.profileRuntimeLabel,
            "ProgramArguments": [fileSet.paths.runScriptPath],
            "RunAtLoad": false,
            "KeepAlive": true,
            "ThrottleInterval": 10,
            "StandardOutPath": fileSet.paths.logPath,
            "StandardErrorPath": fileSet.paths.logPath,
            "WorkingDirectory": "/var/empty"
        ])
    }

    public static func mountPlistData(fileSet: HelperRuntimeFileSet) throws -> Data {
        let names = ServiceNames(profile: fileSet.profile)
        return try plistData([
            "Label": names.profileMountLabel,
            "ProgramArguments": [fileSet.paths.mountScriptPath],
            "RunAtLoad": true,
            "StartInterval": 60,
            "StandardOutPath": fileSet.paths.logPath,
            "StandardErrorPath": fileSet.paths.logPath,
            "WorkingDirectory": "/var/empty"
        ])
    }

    private static func plistData(_ dictionary: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }
}

public protocol HelperProfileStore: AnyObject, Sendable {
    func save(_ profile: MountProfile) throws
    func load(profileID: ProfileID) throws -> MountProfile?
}

public final class InMemoryHelperProfileStore: HelperProfileStore, @unchecked Sendable {
    private var profiles: [ProfileID: MountProfile] = [:]

    public init() {}

    public func save(_ profile: MountProfile) throws {
        profiles[profile.id] = profile
    }

    public func load(profileID: ProfileID) throws -> MountProfile? {
        profiles[profileID]
    }
}

public final class FileHelperProfileStore: HelperProfileStore, @unchecked Sendable {
    private let root: String
    private let fileManager: FileManager

    public init(root: String = "/Library/Application Support/ZeroFSManager/Profiles", fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
    }

    public func save(_ profile: MountProfile) throws {
        let profileDirectory = "\(root)/\(profile.id.rawValue)"
        try fileManager.createDirectory(atPath: profileDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(profile)
        try data.write(to: URL(fileURLWithPath: "\(profileDirectory)/profile.json"), options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: "\(profileDirectory)/profile.json")
    }

    public func load(profileID: ProfileID) throws -> MountProfile? {
        let url = URL(fileURLWithPath: "\(root)/\(profileID.rawValue)/profile.json")
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try JSONDecoder().decode(MountProfile.self, from: Data(contentsOf: url))
    }
}

public protocol MountTableReader: Sendable {
    func isMounted(_ path: MountPath) async -> Bool
}

public struct StaticMountTableReader: MountTableReader {
    public var mountedPaths: Set<String>

    public init(mountedPaths: Set<String>) {
        self.mountedPaths = mountedPaths
    }

    public init(mountedPaths: [String]) {
        self.mountedPaths = Set(mountedPaths)
    }

    public func isMounted(_ path: MountPath) async -> Bool {
        mountedPaths.contains(path.rawValue)
    }
}

public struct SystemMountTableReader: MountTableReader {
    public init() {}

    public func isMounted(_ path: MountPath) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount")
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return output.contains(" on \(path.rawValue) ")
    }
}

public protocol PortWaiter: Sendable {
    func wait(host: String, port: Int, timeoutSeconds: Int) async -> Bool
}

public struct ImmediatePortWaiter: PortWaiter {
    public init() {}

    public func wait(host: String, port: Int, timeoutSeconds: Int) async -> Bool {
        true
    }
}

public struct SystemPortWaiter: PortWaiter {
    public init() {}

    public func wait(host: String, port: Int, timeoutSeconds: Int) async -> Bool {
        guard timeoutSeconds > 0 else { return false }
        for _ in 0..<timeoutSeconds {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
            process.arguments = ["-z", host, "\(port)"]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    return true
                }
            } catch {
                return false
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }
}

public protocol HelperOperationEnvironment: AnyObject, Sendable {
    func installOrUpdate(_ profile: MountProfile) async throws
    func syncRuntimeSecrets(profileID: ProfileID, secrets: RuntimeSecretPayload) async throws
    func start(profileID: ProfileID) async throws
    func stop(profileID: ProfileID) async throws
    func restart(profileID: ProfileID) async throws
    func mount(_ profile: MountProfile) async throws
    func unmount(profileID: ProfileID) async throws
    func flush(profileID: ProfileID) async throws
    func status(profileID: ProfileID) async throws -> HelperStatus
    func logs(profileID: ProfileID, limitBytes: Int) async throws -> String
}

public final class ExternalZeroFSOperationEnvironment: HelperOperationEnvironment, @unchecked Sendable {
    private let binaryLocator: ZeroFSBinaryLocator
    private let commandRunner: HelperCommandRunner
    private let profileStore: HelperProfileStore
    private let runtimeBaseRoot: String
    private let launchDaemonRoot: String
    private let logRoot: String
    private let fileManager: FileManager
    private let writer: HelperRuntimeWriter
    private let mountTableReader: MountTableReader
    private let portWaiter: PortWaiter
    private let createMountDirectory: Bool

    public init(
        binaryLocator: ZeroFSBinaryLocator = ZeroFSBinaryLocator(),
        commandRunner: HelperCommandRunner = ProcessHelperCommandRunner(),
        profileStore: HelperProfileStore = FileHelperProfileStore(),
        runtimeBaseRoot: String = "/Library/Application Support/ZeroFSManager/Profiles",
        launchDaemonRoot: String = "/Library/LaunchDaemons",
        logRoot: String = "/Library/Logs/ZeroFSManager",
        fileManager: FileManager = .default,
        writer: HelperRuntimeWriter = HelperRuntimeWriter(),
        mountTableReader: MountTableReader = SystemMountTableReader(),
        portWaiter: PortWaiter = SystemPortWaiter(),
        createMountDirectory: Bool = true
    ) {
        self.binaryLocator = binaryLocator
        self.commandRunner = commandRunner
        self.profileStore = profileStore
        self.runtimeBaseRoot = runtimeBaseRoot
        self.launchDaemonRoot = launchDaemonRoot
        self.logRoot = logRoot
        self.fileManager = fileManager
        self.writer = writer
        self.mountTableReader = mountTableReader
        self.portWaiter = portWaiter
        self.createMountDirectory = createMountDirectory
    }

    public func installOrUpdate(_ profile: MountProfile) async throws {
        let binary = try locateBinary(operation: .installOrUpdate)
        let fileSet = try makeFileSet(profile: profile)
        try writer.writeRuntimeFiles(fileSet: fileSet, binary: binary)
        try profileStore.save(profile)
    }

    public func syncRuntimeSecrets(profileID: ProfileID, secrets: RuntimeSecretPayload) async throws {
        let profile = try loadProfile(profileID: profileID, operation: .syncRuntimeSecrets)
        let fileSet = try makeFileSet(profile: profile)
        try writer.writeSecrets(fileSet: fileSet, secrets: secrets)
    }

    public func start(profileID: ProfileID) async throws {
        let profile = try loadProfile(profileID: profileID, operation: .start)
        let fileSet = try makeFileSet(profile: profile)
        let names = ServiceNames(profile: profile)
        _ = try await run(ExternalZeroFSCommandFactory.launchctlBootoutCommand(plistPath: fileSet.paths.runtimeLaunchDaemonPath), operation: .start, allowFailure: true)
        try await run(ExternalZeroFSCommandFactory.launchctlBootstrapCommand(plistPath: fileSet.paths.runtimeLaunchDaemonPath), operation: .start)
        _ = try await run(ExternalZeroFSCommandFactory.launchctlEnableCommand(label: names.profileRuntimeLabel), operation: .start, allowFailure: true)
        try await run(ExternalZeroFSCommandFactory.launchctlKickstartCommand(label: names.profileRuntimeLabel), operation: .start)
    }

    public func stop(profileID: ProfileID) async throws {
        let profile = try loadProfile(profileID: profileID, operation: .stop)
        let fileSet = try makeFileSet(profile: profile)
        try await run(ExternalZeroFSCommandFactory.launchctlBootoutCommand(plistPath: fileSet.paths.runtimeLaunchDaemonPath), operation: .stop)
    }

    public func restart(profileID: ProfileID) async throws {
        _ = try? await stop(profileID: profileID)
        try await start(profileID: profileID)
    }

    public func mount(_ profile: MountProfile) async throws {
        let fileSet = try makeFileSet(profile: profile)
        try profileStore.save(profile)
        if createMountDirectory {
            try fileManager.createDirectory(
                at: URL(fileURLWithPath: profile.mountPath.rawValue, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        guard await portWaiter.wait(host: "127.0.0.1", port: profile.ports.nfs, timeoutSeconds: 60) else {
            throw HelperClientError.operationFailed(
                operation: .mount,
                message: "ZeroFS NFS port 127.0.0.1:\(profile.ports.nfs) did not become ready within 60 seconds",
                logExcerpt: try? await logs(profileID: profile.id, limitBytes: 4096)
            )
        }
        _ = fileSet
        try await run(ExternalZeroFSCommandFactory.mountCommand(profile: profile), operation: .mount)
    }

    public func unmount(profileID: ProfileID) async throws {
        let profile = try loadProfile(profileID: profileID, operation: .unmount)
        try await run(ExternalZeroFSCommandFactory.unmountCommand(profile: profile), operation: .unmount)
    }

    public func flush(profileID: ProfileID) async throws {
        let binary = try locateBinary(operation: .flush)
        let profile = try loadProfile(profileID: profileID, operation: .flush)
        let fileSet = try makeFileSet(profile: profile)
        try await run(ExternalZeroFSCommandFactory.flushCommand(binary: binary, configPath: fileSet.paths.configPath), operation: .flush)
    }

    public func status(profileID: ProfileID) async throws -> HelperStatus {
        guard let profile = try profileStore.load(profileID: profileID) else {
            return HelperStatus(
                registration: .notRegistered,
                service: .unknown,
                mount: .unknown,
                metricsReachable: false,
                lastError: "Profile runtime is not installed"
            )
        }
        let names = ServiceNames(profile: profile)
        let launchctlResult = try? await commandRunner.run(ExternalZeroFSCommandFactory.launchctlPrintCommand(label: names.profileRuntimeLabel))
        let serviceState = serviceState(from: launchctlResult)
        let mounted = await mountTableReader.isMounted(profile.mountPath)
        let metricsReachable = await portWaiter.wait(host: "127.0.0.1", port: profile.ports.metrics, timeoutSeconds: 1)
        return HelperStatus(
            registration: .enabled,
            service: serviceState,
            mount: mounted ? .mounted : .unmounted,
            metricsReachable: metricsReachable,
            lastError: nil
        )
    }

    public func logs(profileID: ProfileID, limitBytes: Int) async throws -> String {
        let profile = try loadProfile(profileID: profileID, operation: .logs)
        let fileSet = try makeFileSet(profile: profile)
        guard fileManager.fileExists(atPath: fileSet.paths.logPath) else {
            return ""
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: fileSet.paths.logPath))
        let bounded = data.suffix(max(0, limitBytes))
        return String(decoding: bounded, as: UTF8.self)
    }

    @discardableResult
    private func run(_ command: HelperCommand, operation: HelperOperation, allowFailure: Bool = false) async throws -> HelperCommandResult {
        let result = try await commandRunner.run(command)
        if result.exitCode != 0 && !allowFailure {
            let excerpt = [result.standardError, result.standardOutput]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw HelperClientError.operationFailed(
                operation: operation,
                message: "Command failed with exit code \(result.exitCode): \(([command.executablePath] + command.arguments).joined(separator: " "))",
                logExcerpt: String(excerpt.suffix(4096))
            )
        }
        return result
    }

    private func loadProfile(profileID: ProfileID, operation: HelperOperation) throws -> MountProfile {
        guard let profile = try profileStore.load(profileID: profileID) else {
            throw HelperClientError.operationFailed(
                operation: operation,
                message: "Profile \(profileID.rawValue) is not installed",
                logExcerpt: nil
            )
        }
        return profile
    }

    private func locateBinary(operation: HelperOperation) throws -> ZeroFSBinary {
        guard let binary = binaryLocator.locate(fileManager: fileManager) else {
            throw HelperClientError.operationFailed(
                operation: operation,
                message: "ZeroFS CLI is missing. Install it with: \(ZeroFSInstallGuidance.recommendedShellCommand)",
                logExcerpt: nil
            )
        }
        return binary
    }

    private func makeFileSet(profile: MountProfile) throws -> HelperRuntimeFileSet {
        let paths = ProfileRuntimePaths(
            profile: profile,
            baseRoot: runtimeBaseRoot,
            launchDaemonRoot: launchDaemonRoot,
            logRoot: logRoot
        )
        return try HelperRuntimeGenerator.makeFileSet(
            profile: profile,
            paths: paths,
            allowedRuntimeRoots: [runtimeBaseRoot]
        )
    }

    private func serviceState(from result: HelperCommandResult?) -> ZeroFSServiceState {
        guard let result else {
            return .unknown
        }
        guard result.exitCode == 0 else {
            return .stopped
        }
        let text = "\(result.standardOutput)\n\(result.standardError)"
        if text.contains("state = running") || text.contains("pid =") {
            return .running
        }
        if text.contains("state = exited") || text.contains("state = not running") {
            return .stopped
        }
        return .unknown
    }
}

public struct HelperOperationCoordinator: Sendable {
    private let environment: HelperOperationEnvironment

    public init(environment: HelperOperationEnvironment) {
        self.environment = environment
    }

    public func handle(_ request: HelperRequest) async -> HelperResponse {
        do {
            switch request {
            case .installOrUpdate(let profile):
                try await environment.installOrUpdate(profile)
                return .accepted(.installOrUpdate)
            case .syncRuntimeSecrets(let profileID, let secrets):
                try await environment.syncRuntimeSecrets(profileID: profileID, secrets: secrets)
                return .accepted(.syncRuntimeSecrets)
            case .start(let profileID):
                try await environment.start(profileID: profileID)
                return .accepted(.start)
            case .stop(let profileID):
                try await environment.stop(profileID: profileID)
                return .accepted(.stop)
            case .restart(let profileID):
                try await environment.restart(profileID: profileID)
                return .accepted(.restart)
            case .mount(let profile):
                try await environment.mount(profile)
                return .accepted(.mount)
            case .unmount(let profileID):
                try await environment.unmount(profileID: profileID)
                return .accepted(.unmount)
            case .flush(let profileID):
                try await environment.flush(profileID: profileID)
                return .accepted(.flush)
            case .status(let profileID):
                return .status(try await environment.status(profileID: profileID))
            case .logs(let profileID, let limitBytes):
                return .logs(try await environment.logs(profileID: profileID, limitBytes: limitBytes))
            }
        } catch let error as HelperClientError {
            return .failure(error.payload(defaultOperation: request.operation))
        } catch {
            return .failure(HelperErrorPayload(
                operation: request.operation,
                message: String(describing: error),
                logExcerpt: nil
            ))
        }
    }
}

private extension HelperClientError {
    func payload(defaultOperation: HelperOperation) -> HelperErrorPayload {
        switch self {
        case .operationFailed(let operation, let message, let logExcerpt):
            HelperErrorPayload(operation: operation, message: message, logExcerpt: logExcerpt)
        case .unavailable:
            HelperErrorPayload(operation: defaultOperation, message: description, logExcerpt: nil)
        case .requiresApproval:
            HelperErrorPayload(operation: defaultOperation, message: description, logExcerpt: nil)
        case .validationFailed(let message):
            HelperErrorPayload(operation: defaultOperation, message: message, logExcerpt: nil)
        }
    }
}

public final class RecordingHelperOperationEnvironment: HelperOperationEnvironment, @unchecked Sendable {
    public var operations: [HelperOperation] = []
    public var status = HelperStatus(
        registration: .enabled,
        service: .running,
        mount: .mounted,
        metricsReachable: true,
        lastError: nil
    )
    public var installResult: Result<Void, HelperClientError> = .success(())
    public var syncSecretsResult: Result<Void, HelperClientError> = .success(())
    public var startResult: Result<Void, HelperClientError> = .success(())
    public var stopResult: Result<Void, HelperClientError> = .success(())
    public var restartResult: Result<Void, HelperClientError> = .success(())
    public var mountResult: Result<Void, HelperClientError> = .success(())
    public var unmountResult: Result<Void, HelperClientError> = .success(())
    public var flushResult: Result<Void, HelperClientError> = .success(())
    public var statusResult: Result<HelperStatus, HelperClientError>?
    public var logsText = "bounded helper logs"

    public init() {}

    public func installOrUpdate(_ profile: MountProfile) async throws {
        operations.append(.installOrUpdate)
        try installResult.get()
    }

    public func syncRuntimeSecrets(profileID: ProfileID, secrets: RuntimeSecretPayload) async throws {
        operations.append(.syncRuntimeSecrets)
        try syncSecretsResult.get()
    }

    public func start(profileID: ProfileID) async throws {
        operations.append(.start)
        try startResult.get()
    }

    public func stop(profileID: ProfileID) async throws {
        operations.append(.stop)
        try stopResult.get()
    }

    public func restart(profileID: ProfileID) async throws {
        operations.append(.restart)
        try restartResult.get()
    }

    public func mount(_ profile: MountProfile) async throws {
        operations.append(.mount)
        try mountResult.get()
    }

    public func unmount(profileID: ProfileID) async throws {
        operations.append(.unmount)
        try unmountResult.get()
    }

    public func flush(profileID: ProfileID) async throws {
        operations.append(.flush)
        try flushResult.get()
    }

    public func status(profileID: ProfileID) async throws -> HelperStatus {
        operations.append(.status)
        if let statusResult {
            return try statusResult.get()
        }
        return status
    }

    public func logs(profileID: ProfileID, limitBytes: Int) async throws -> String {
        operations.append(.logs)
        return String(logsText.prefix(max(0, limitBytes)))
    }
}
