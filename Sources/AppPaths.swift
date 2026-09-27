import Foundation

enum AppPaths {
    static var resultsRoot: URL {
        let parent = Bundle.main.bundleURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: parent.appendingPathComponent("build.sh").path) {
            return parent.appendingPathComponent("results", isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jev Clipboard/results", isDirectory: true)
    }

    static func diagnostic(_ name: String) -> URL {
        let directory = resultsRoot.appendingPathComponent("jev-app", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return directory.appendingPathComponent(name)
    }
}
