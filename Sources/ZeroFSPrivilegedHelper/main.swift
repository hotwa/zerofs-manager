import Foundation
import ZeroFSManagerHelperClient
import ZeroFSPrivilegedHelperCore

private final class HelperXPCService: NSObject, HelperXPCServiceProtocol {
    private let coordinator: HelperOperationCoordinator

    init(coordinator: HelperOperationCoordinator) {
        self.coordinator = coordinator
    }

    func handleRequest(_ requestData: Data, withReply reply: @escaping (Data) -> Void) {
        let coordinator = coordinator
        let replyBox = HelperXPCReply(reply)
        Task {
            let response: HelperResponse
            do {
                let request = try HelperXPCMessageCodec.decodeRequest(requestData)
                response = await coordinator.handle(request)
            } catch {
                response = .failure(HelperErrorPayload(
                    operation: .status,
                    message: "Could not decode helper request: \(error)",
                    logExcerpt: nil
                ))
            }

            do {
                replyBox.send(try HelperXPCMessageCodec.encodeResponse(response))
            } catch {
                let fallback = HelperResponse.failure(HelperErrorPayload(
                    operation: .status,
                    message: "Could not encode helper response: \(error)",
                    logExcerpt: nil
                ))
                replyBox.send((try? HelperXPCMessageCodec.encodeResponse(fallback)) ?? Data())
            }
        }
    }
}

private final class HelperXPCReply: @unchecked Sendable {
    private let reply: (Data) -> Void

    init(_ reply: @escaping (Data) -> Void) {
        self.reply = reply
    }

    func send(_ data: Data) {
        reply(data)
    }
}

private final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: HelperXPCService
    private let authorizer: HelperClientAuthorizing

    init(service: HelperXPCService, authorizer: HelperClientAuthorizing) {
        self.service = service
        self.authorizer = authorizer
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard authorizer.accepts(processIdentifier: newConnection.processIdentifier) else {
            newConnection.invalidate()
            return false
        }
        newConnection.exportedInterface = NSXPCInterface(with: HelperXPCServiceProtocol.self)
        newConnection.exportedObject = service
        newConnection.resume()
        return true
    }
}

if CommandLine.arguments.contains("--health") {
    print("ZeroFSPrivilegedHelper ok")
    exit(0)
}

private let defaultMachServiceName = XPCPrivilegedHelperClient.machServiceName
private let requestedMachServiceName = ProcessInfo.processInfo.environment["ZEROFS_MANAGER_HELPER_MACH_SERVICE_NAME"]
private let machServiceName: String
if let requestedMachServiceName,
   requestedMachServiceName == defaultMachServiceName || requestedMachServiceName == "\(defaultMachServiceName).debug" {
    machServiceName = requestedMachServiceName
} else {
    machServiceName = defaultMachServiceName
}
private let environment = ExternalZeroFSOperationEnvironment()
private let service = HelperXPCService(coordinator: HelperOperationCoordinator(environment: environment))
private let authorizer = CodeSigningHelperClientAuthorizer()
private let listener = NSXPCListener(machServiceName: machServiceName)
private let delegate = HelperListenerDelegate(service: service, authorizer: authorizer)
listener.delegate = delegate
listener.resume()

FileHandle.standardError.write(Data("ZeroFSPrivilegedHelper listening on \(machServiceName)\n".utf8))
RunLoop.main.run()
