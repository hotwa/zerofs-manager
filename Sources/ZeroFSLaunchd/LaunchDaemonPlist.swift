import Foundation

public struct LaunchDaemonPlist: Equatable, Sendable {
    public var label: String
    public var bundleProgram: String
    public var machServiceName: String
    public var associatedBundleIdentifier: String
    public var runAtLoad: Bool
    public var keepAlive: Bool

    public init(
        label: String,
        bundleProgram: String,
        machServiceName: String,
        associatedBundleIdentifier: String,
        runAtLoad: Bool,
        keepAlive: Bool
    ) {
        self.label = label
        self.bundleProgram = bundleProgram
        self.machServiceName = machServiceName
        self.associatedBundleIdentifier = associatedBundleIdentifier
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
    }

    public var dictionary: [String: Any] {
        [
            "Label": label,
            "BundleProgram": bundleProgram,
            "RunAtLoad": runAtLoad,
            "KeepAlive": keepAlive,
            "MachServices": [
                machServiceName: true
            ],
            "AssociatedBundleIdentifiers": [
                associatedBundleIdentifier
            ]
        ]
    }

    public func xmlData() throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .xml,
            options: 0
        )
    }
}
