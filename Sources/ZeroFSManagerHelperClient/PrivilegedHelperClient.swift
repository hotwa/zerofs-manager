import Foundation
import ZeroFSManagerDomain

public enum HelperOperation: String, Codable, Sendable {
    case installOrUpdate
    case syncRuntimeSecrets
    case start
    case stop
    case restart
    case mount
    case unmount
    case flush
    case status
    case logs
}

public enum HelperRegistrationState: String, Codable, Sendable {
    case notRegistered
    case requiresApproval
    case enabled
    case disabled
    case notFound
    case failed
}

public enum ZeroFSServiceState: String, Codable, Sendable {
    case running
    case stopped
    case failed
    case unknown
}

public enum MountState: String, Codable, Sendable {
    case mounted
    case unmounted
    case stale
    case failed
    case unknown
}

public enum ServiceManagementRegistrationStatus: String, Codable, Equatable, Sendable {
    case notRegistered
    case requiresApproval
    case enabled
    case disabled
    case notFound
    case failed
}

public enum ServiceManagementStatusMapper {
    public static func map(_ status: ServiceManagementRegistrationStatus) -> HelperRegistrationState {
        switch status {
        case .notRegistered:
            .notRegistered
        case .requiresApproval:
            .requiresApproval
        case .enabled:
            .enabled
        case .disabled:
            .disabled
        case .notFound:
            .notFound
        case .failed:
            .failed
        }
    }
}

public struct HelperStatus: Codable, Equatable, Sendable {
    public var registration: HelperRegistrationState
    public var service: ZeroFSServiceState
    public var mount: MountState
    public var metricsReachable: Bool
    public var lastError: String?

    public init(
        registration: HelperRegistrationState,
        service: ZeroFSServiceState,
        mount: MountState,
        metricsReachable: Bool,
        lastError: String?
    ) {
        self.registration = registration
        self.service = service
        self.mount = mount
        self.metricsReachable = metricsReachable
        self.lastError = lastError
    }
}

public struct RuntimeSecretPayload: Codable, Equatable, Sendable {
    public var accessKeyID: String
    public var secretAccessKey: String
    public var zeroFSEncryptionPassword: String

    public init(accessKeyID: String, secretAccessKey: String, zeroFSEncryptionPassword: String) {
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
        self.zeroFSEncryptionPassword = zeroFSEncryptionPassword
    }
}

public enum HelperRequest: Codable, Equatable, Sendable {
    case installOrUpdate(MountProfile)
    case syncRuntimeSecrets(profileID: ProfileID, secrets: RuntimeSecretPayload)
    case start(ProfileID)
    case stop(ProfileID)
    case restart(ProfileID)
    case mount(MountProfile)
    case unmount(ProfileID)
    case flush(ProfileID)
    case status(ProfileID)
    case logs(profileID: ProfileID, limitBytes: Int)

    public var operation: HelperOperation {
        switch self {
        case .installOrUpdate:
            .installOrUpdate
        case .syncRuntimeSecrets:
            .syncRuntimeSecrets
        case .start:
            .start
        case .stop:
            .stop
        case .restart:
            .restart
        case .mount:
            .mount
        case .unmount:
            .unmount
        case .flush:
            .flush
        case .status:
            .status
        case .logs:
            .logs
        }
    }
}

public enum HelperResponse: Codable, Equatable, Sendable {
    case accepted(HelperOperation)
    case status(HelperStatus)
    case logs(String)
    case failure(HelperErrorPayload)
}

public struct HelperErrorPayload: Codable, Equatable, Sendable {
    public var operation: HelperOperation
    public var message: String
    public var logExcerpt: String?

    public init(operation: HelperOperation, message: String, logExcerpt: String?) {
        self.operation = operation
        self.message = message
        self.logExcerpt = logExcerpt
    }
}

public enum HelperClientError: Error, Equatable, CustomStringConvertible, Sendable {
    case unavailable
    case requiresApproval
    case operationFailed(operation: HelperOperation, message: String, logExcerpt: String?)
    case validationFailed(String)

    public var description: String {
        switch self {
        case .unavailable:
            "Privileged helper is unavailable"
        case .requiresApproval:
            "Privileged helper requires approval in System Settings"
        case .operationFailed(let operation, let message, let logExcerpt):
            if let logExcerpt, !logExcerpt.isEmpty {
                "\(operation.rawValue) failed: \(message). Recent log: \(logExcerpt)"
            } else {
                "\(operation.rawValue) failed: \(message)"
            }
        case .validationFailed(let message):
            "Validation failed: \(message)"
        }
    }
}

public protocol PrivilegedHelperClient: Sendable {
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

public final class MockPrivilegedHelperClient: PrivilegedHelperClient, @unchecked Sendable {
    public var statusResult = HelperStatus(
        registration: .notRegistered,
        service: .unknown,
        mount: .unknown,
        metricsReachable: false,
        lastError: nil
    )
    public var installOrUpdateResult: Result<Void, HelperClientError> = .success(())
    public var statusResultOverride: Result<HelperStatus, HelperClientError>?
    public var startResult: Result<Void, HelperClientError> = .success(())
    public var stopResult: Result<Void, HelperClientError> = .success(())
    public var restartResult: Result<Void, HelperClientError> = .success(())
    public var mountResult: Result<Void, HelperClientError> = .success(())
    public var unmountResult: Result<Void, HelperClientError> = .success(())
    public var flushResult: Result<Void, HelperClientError> = .success(())
    public var logsResult = ""
    public private(set) var recordedOperations: [HelperOperation] = []

    public init() {}

    public func installOrUpdate(_ profile: MountProfile) async throws {
        recordedOperations.append(.installOrUpdate)
        try installOrUpdateResult.get()
    }
    public func syncRuntimeSecrets(profileID: ProfileID, secrets: RuntimeSecretPayload) async throws {
        recordedOperations.append(.syncRuntimeSecrets)
    }
    public func start(profileID: ProfileID) async throws {
        recordedOperations.append(.start)
        try startResult.get()
    }
    public func stop(profileID: ProfileID) async throws {
        recordedOperations.append(.stop)
        try stopResult.get()
    }
    public func restart(profileID: ProfileID) async throws {
        recordedOperations.append(.restart)
        try restartResult.get()
    }

    public func mount(_ profile: MountProfile) async throws {
        recordedOperations.append(.mount)
        try mountResult.get()
    }

    public func unmount(profileID: ProfileID) async throws {
        recordedOperations.append(.unmount)
        try unmountResult.get()
    }

    public func flush(profileID: ProfileID) async throws {
        recordedOperations.append(.flush)
        try flushResult.get()
    }

    public func status(profileID: ProfileID) async throws -> HelperStatus {
        recordedOperations.append(.status)
        if let statusResultOverride {
            return try statusResultOverride.get()
        }
        return statusResult
    }

    public func logs(profileID: ProfileID, limitBytes: Int) async throws -> String {
        recordedOperations.append(.logs)
        return String(logsResult.prefix(max(0, limitBytes)))
    }
}

public enum LoginAutoMountOutcome: Equatable, Sendable {
    case skippedNoProfile
    case skippedDisabled
    case alreadyMounted
    case mounted
    case failed(AutoMountFailure)
}

public struct AutoMountFailure: Equatable, Sendable {
    public var profileID: ProfileID
    public var profileName: String
    public var operation: HelperOperation
    public var message: String
    public var logExcerpt: String?

    public init(
        profileID: ProfileID,
        profileName: String,
        operation: HelperOperation,
        message: String,
        logExcerpt: String?
    ) {
        self.profileID = profileID
        self.profileName = profileName
        self.operation = operation
        self.message = message
        self.logExcerpt = logExcerpt
    }
}

public struct LoginAutoMountReport: Equatable, Sendable {
    public var profileID: ProfileID?
    public var outcome: LoginAutoMountOutcome
    public var initialStatus: HelperStatus?

    public init(profileID: ProfileID?, outcome: LoginAutoMountOutcome, initialStatus: HelperStatus?) {
        self.profileID = profileID
        self.outcome = outcome
        self.initialStatus = initialStatus
    }

    public var failure: AutoMountFailure? {
        if case .failed(let failure) = outcome {
            return failure
        }
        return nil
    }
}

public struct LoginAutoMountCoordinator: Sendable {
    private let helper: PrivilegedHelperClient
    private let logLimitBytes: Int

    public init(helper: PrivilegedHelperClient, logLimitBytes: Int = 4096) {
        self.helper = helper
        self.logLimitBytes = logLimitBytes
    }

    public func run(activeProfile profile: MountProfile?) async -> LoginAutoMountReport {
        guard let profile else {
            return LoginAutoMountReport(profileID: nil, outcome: .skippedNoProfile, initialStatus: nil)
        }
        guard profile.autoMount == .afterLogin else {
            return LoginAutoMountReport(profileID: profile.id, outcome: .skippedDisabled, initialStatus: nil)
        }

        do {
            let status = try await helper.status(profileID: profile.id)
            guard status.registration == .enabled else {
                return LoginAutoMountReport(
                    profileID: profile.id,
                    outcome: .failed(AutoMountFailure(
                        profileID: profile.id,
                        profileName: profile.displayName,
                        operation: .status,
                        message: "Privileged helper is \(status.registration.rawValue). Approve ZeroFS Manager in System Settings > General > Login Items & Extensions.",
                        logExcerpt: status.lastError
                    )),
                    initialStatus: status
                )
            }

            if status.mount == .mounted {
                return LoginAutoMountReport(profileID: profile.id, outcome: .alreadyMounted, initialStatus: status)
            }

            if status.service != .running {
                try await helper.start(profileID: profile.id)
            }
            try await helper.mount(profile)
            return LoginAutoMountReport(profileID: profile.id, outcome: .mounted, initialStatus: status)
        } catch let error as HelperClientError {
            let operation = operationFor(error)
            let excerpt = (try? await helper.logs(profileID: profile.id, limitBytes: logLimitBytes))
            return LoginAutoMountReport(
                profileID: profile.id,
                outcome: .failed(AutoMountFailure(
                    profileID: profile.id,
                    profileName: profile.displayName,
                    operation: operation,
                    message: error.description,
                    logExcerpt: excerpt
                )),
                initialStatus: nil
            )
        } catch {
            return LoginAutoMountReport(
                profileID: profile.id,
                outcome: .failed(AutoMountFailure(
                    profileID: profile.id,
                    profileName: profile.displayName,
                    operation: .status,
                    message: String(describing: error),
                    logExcerpt: nil
                )),
                initialStatus: nil
            )
        }
    }

    private func operationFor(_ error: HelperClientError) -> HelperOperation {
        switch error {
        case .operationFailed(let operation, _, _):
            operation
        case .requiresApproval, .unavailable:
            .status
        case .validationFailed:
            .mount
        }
    }
}
