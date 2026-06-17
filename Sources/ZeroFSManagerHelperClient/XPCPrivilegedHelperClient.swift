import Foundation
#if canImport(ServiceManagement)
import ServiceManagement
#endif
import Security
import ZeroFSManagerDomain

@objc public protocol HelperXPCServiceProtocol {
    func handleRequest(_ requestData: Data, withReply reply: @escaping (Data) -> Void)
}

public enum HelperXPCMessageCodec {
    public static func encodeRequest(_ request: HelperRequest) throws -> Data {
        try JSONEncoder().encode(request)
    }

    public static func decodeRequest(_ data: Data) throws -> HelperRequest {
        try JSONDecoder().decode(HelperRequest.self, from: data)
    }

    public static func encodeResponse(_ response: HelperResponse) throws -> Data {
        try JSONEncoder().encode(response)
    }

    public static func decodeResponse(_ data: Data) throws -> HelperResponse {
        try JSONDecoder().decode(HelperResponse.self, from: data)
    }
}

public struct ClientCodeSigningInfo: Equatable, Sendable {
    public var bundleIdentifier: String?
    public var teamIdentifier: String?

    public init(bundleIdentifier: String?, teamIdentifier: String?) {
        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
    }
}

public struct HelperClientAuthorizationPolicy: Equatable, Sendable {
    public var allowedBundleIdentifier: String
    public var allowedTeamIdentifier: String?

    public init(allowedBundleIdentifier: String, allowedTeamIdentifier: String?) {
        self.allowedBundleIdentifier = allowedBundleIdentifier
        self.allowedTeamIdentifier = allowedTeamIdentifier
    }

    public func accepts(_ signingInfo: ClientCodeSigningInfo) -> Bool {
        guard signingInfo.bundleIdentifier == allowedBundleIdentifier else {
            return false
        }
        if let allowedTeamIdentifier {
            return signingInfo.teamIdentifier == allowedTeamIdentifier
        }
        return true
    }
}

public protocol HelperClientAuthorizing: Sendable {
    func accepts(processIdentifier: pid_t) -> Bool
}

public struct CodeSigningHelperClientAuthorizer: HelperClientAuthorizing {
    public var policy: HelperClientAuthorizationPolicy

    public init(policy: HelperClientAuthorizationPolicy = .zeroFSManagerApp()) {
        self.policy = policy
    }

    public func accepts(processIdentifier: pid_t) -> Bool {
        guard processIdentifier > 0,
              let signingInfo = Self.signingInfo(processIdentifier: processIdentifier) else {
            return false
        }
        return policy.accepts(signingInfo)
    }

    public static func signingInfo(processIdentifier: pid_t) -> ClientCodeSigningInfo? {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: processIdentifier)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else {
            return nil
        }

        return ClientCodeSigningInfo(
            bundleIdentifier: dictionary[kSecCodeInfoIdentifier as String] as? String,
            teamIdentifier: dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        )
    }

    public static func currentProcessTeamIdentifier() -> String? {
        signingInfo(processIdentifier: getpid())?.teamIdentifier
    }
}

public extension HelperClientAuthorizationPolicy {
    static func zeroFSManagerApp(currentTeamIdentifier: String? = CodeSigningHelperClientAuthorizer.currentProcessTeamIdentifier()) -> HelperClientAuthorizationPolicy {
        HelperClientAuthorizationPolicy(
            allowedBundleIdentifier: "com.zerofs.manager",
            allowedTeamIdentifier: currentTeamIdentifier
        )
    }
}

public final class XPCPrivilegedHelperClient: PrivilegedHelperClient, @unchecked Sendable {
    public static let machServiceName = "com.zerofs.manager.helper"

    private let machServiceName: String

    public init(machServiceName: String = XPCPrivilegedHelperClient.machServiceName) {
        self.machServiceName = machServiceName
    }

    public func installOrUpdate(_ profile: MountProfile) async throws {
        try await expectAccepted(.installOrUpdate(profile), operation: .installOrUpdate)
    }

    public func syncRuntimeSecrets(profileID: ProfileID, secrets: RuntimeSecretPayload) async throws {
        try await expectAccepted(.syncRuntimeSecrets(profileID: profileID, secrets: secrets), operation: .syncRuntimeSecrets)
    }

    public func start(profileID: ProfileID) async throws {
        try await expectAccepted(.start(profileID), operation: .start)
    }

    public func stop(profileID: ProfileID) async throws {
        try await expectAccepted(.stop(profileID), operation: .stop)
    }

    public func restart(profileID: ProfileID) async throws {
        try await expectAccepted(.restart(profileID), operation: .restart)
    }

    public func mount(_ profile: MountProfile) async throws {
        try await expectAccepted(.mount(profile), operation: .mount)
    }

    public func unmount(profileID: ProfileID) async throws {
        try await expectAccepted(.unmount(profileID), operation: .unmount)
    }

    public func flush(profileID: ProfileID) async throws {
        try await expectAccepted(.flush(profileID), operation: .flush)
    }

    public func status(profileID: ProfileID) async throws -> HelperStatus {
        switch try await send(.status(profileID)) {
        case .status(let status):
            return status
        case .failure(let payload):
            throw HelperClientError.operationFailed(
                operation: payload.operation,
                message: payload.message,
                logExcerpt: payload.logExcerpt
            )
        case .accepted, .logs:
            throw HelperClientError.operationFailed(operation: .status, message: "Unexpected helper response", logExcerpt: nil)
        }
    }

    public func logs(profileID: ProfileID, limitBytes: Int) async throws -> String {
        switch try await send(.logs(profileID: profileID, limitBytes: limitBytes)) {
        case .logs(let text):
            return text
        case .failure(let payload):
            throw HelperClientError.operationFailed(
                operation: payload.operation,
                message: payload.message,
                logExcerpt: payload.logExcerpt
            )
        case .accepted, .status:
            throw HelperClientError.operationFailed(operation: .logs, message: "Unexpected helper response", logExcerpt: nil)
        }
    }

    private func expectAccepted(_ request: HelperRequest, operation: HelperOperation) async throws {
        switch try await send(request) {
        case .accepted(let acceptedOperation) where acceptedOperation == operation:
            return
        case .failure(let payload):
            throw HelperClientError.operationFailed(
                operation: payload.operation,
                message: payload.message,
                logExcerpt: payload.logExcerpt
            )
        default:
            throw HelperClientError.operationFailed(operation: operation, message: "Unexpected helper response", logExcerpt: nil)
        }
    }

    private func send(_ request: HelperRequest) async throws -> HelperResponse {
        let requestData = try HelperXPCMessageCodec.encodeRequest(request)
        return try await withCheckedThrowingContinuation { continuation in
            let replyState = XPCReplyState()
            let connection = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: HelperXPCServiceProtocol.self)
            connection.invalidationHandler = {
                replyState.resume {
                    continuation.resume(throwing: HelperClientError.unavailable)
                }
            }
            connection.interruptionHandler = {
                replyState.resume {
                    continuation.resume(throwing: HelperClientError.unavailable)
                }
            }
            connection.resume()

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                connection.invalidate()
                replyState.resume {
                    continuation.resume(throwing: HelperClientError.operationFailed(
                        operation: request.operation,
                        message: error.localizedDescription,
                        logExcerpt: nil
                    ))
                }
            } as? HelperXPCServiceProtocol

            guard let proxy else {
                connection.invalidate()
                replyState.resume {
                    continuation.resume(throwing: HelperClientError.unavailable)
                }
                return
            }

            proxy.handleRequest(requestData) { responseData in
                connection.invalidate()
                replyState.resume {
                    do {
                        continuation.resume(returning: try HelperXPCMessageCodec.decodeResponse(responseData))
                    } catch {
                        continuation.resume(throwing: HelperClientError.operationFailed(
                            operation: request.operation,
                            message: "Could not decode helper response: \(error)",
                            logExcerpt: nil
                        ))
                    }
                }
            }
        }
    }
}

private final class XPCReplyState: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(_ body: () -> Void) {
        lock.lock()
        if didResume {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()
        body()
    }
}

public enum HelperServiceRegistrar {
    public static let helperPlistName = "com.zerofs.manager.helper.plist"

    public static func registrationStatus() -> ServiceManagementRegistrationStatus {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            return map(SMAppService.daemon(plistName: helperPlistName).status)
        }
        #endif
        return .notFound
    }

    public static func register() throws {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            try SMAppService.daemon(plistName: helperPlistName).register()
            return
        }
        #endif
        throw HelperClientError.operationFailed(
            operation: .installOrUpdate,
            message: "ServiceManagement daemon registration requires macOS 13 or newer",
            logExcerpt: nil
        )
    }

    public static func unregister() throws {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            try SMAppService.daemon(plistName: helperPlistName).unregister()
            return
        }
        #endif
    }

    #if canImport(ServiceManagement)
    @available(macOS 13.0, *)
    private static func map(_ status: SMAppService.Status) -> ServiceManagementRegistrationStatus {
        switch status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .failed
        }
    }
    #endif
}
