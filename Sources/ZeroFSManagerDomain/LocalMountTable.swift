import Foundation

public enum LocalMountTable {
    public static func isMounted(path: String, mountOutput: String) -> Bool {
        line(for: path, mountOutput: mountOutput) != nil
    }

    public static func line(for path: String, mountOutput: String) -> String? {
        mountOutput
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { $0.contains(" on \(path) ") && isLocalZeroFSMountLine($0) }
    }

    public static func isLocalZeroFSMountLine(_ line: String) -> Bool {
        line.hasPrefix("127.0.0.1:/ ") && line.contains("(nfs")
    }

    public static func currentOutput() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount")
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self)
        } catch {
            return nil
        }
    }
}
