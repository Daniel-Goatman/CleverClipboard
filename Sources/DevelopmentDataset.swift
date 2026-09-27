#if CUEKIT_DEVELOPMENT
import Foundation
import Darwin

/// Explicit development builds only, and still opt-in through an output directory.
/// Release builds do not contain this recorder or inspect this environment variable.
final class DevelopmentDataset {
    let root: URL
    let id = UUID().uuidString
    private init(root: URL) { self.root = root }

    static func begin(request: [String: Any], ids: [String]) throws -> DevelopmentDataset? {
        guard let path = ProcessInfo.processInfo.environment["CUEKIT_DATASET_ROOT"], !path.isEmpty else { return nil }
        let recorder = DevelopmentDataset(root: URL(fileURLWithPath: path, isDirectory: true))
        try recorder.write("request", ["schema_version": 2, "record_id": recorder.id,
            "created_at": ISO8601DateFormatter().string(from: Date()), "request": request,
            "candidate_id_map": Dictionary(uniqueKeysWithValues: ids.enumerated().map { ("C\($0.offset)", $0.element) }),
            "label": ["status": "unlabelled"], "transport_status": "prepared_send_not_confirmed",
            "paste_outcome": "not_observed_by_client"])
        return recorder
    }
    func finish(response: [String: Any]?, result: SelectionReply?, error: String?) throws {
        let value: Any = try result.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull()
        try write("result", ["schema_version": 2, "record_id": id,
            "response": response as Any? ?? NSNull(), "selection_result": value,
            "error": error as Any? ?? NSNull(), "paste_outcome": "not_observed_by_client"])
    }
    private func write(_ suffix: String, _ object: [String: Any]) throws {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var info = stat()
            guard lstat(root.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
                  info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw CocoaError(.fileWriteNoPermission) }
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
            let path = root.appendingPathComponent(id + "." + suffix + ".json").path
            let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            try handle.write(contentsOf: data); try handle.synchronize(); try handle.close()
        } catch { throw ClipboardError.message("Could not write the development dataset. Nothing was pasted.") }
    }
}
#endif
