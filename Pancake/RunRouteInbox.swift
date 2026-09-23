import Foundation

/// WCSession's temporary file disappears when its delegate returns. Stage a
/// private, atomic copy first, then merge into history and delete only on success.
enum RunRouteInbox {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IncomingRunRoutes", isDirectory: true)
    }

    static func stage(_ data: Data, in directory: URL = directory) throws -> URL {
        guard data.count <= 12_000_000 else { throw CocoaError(.fileReadTooLarge) }
        let archive = try JSONDecoder().decode(RunRouteArchive.self, from: data)
        guard archive.points.count <= 50_000, archive.points.allSatisfy(\.isValid) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(archive.runID.uuidString).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func pending(in directory: URL = directory) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
    }
}
