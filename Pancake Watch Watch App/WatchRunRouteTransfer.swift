import Foundation
import WatchConnectivity

/// Keep the archive until iPhone acknowledges saving it. Relaunches retry
/// files that were saved before the system could enqueue them.
enum WatchRunRouteTransfer {
    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OutgoingRunRoutes", isDirectory: true)
    }

    static func save(_ archive: RunRouteArchive) throws {
        guard !archive.points.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(archive.runID.uuidString).json")
        try JSONEncoder().encode(archive).write(to: url, options: .atomic)
        retryPending()
    }

    static func retryPending() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let session = WCSession.default
        let queued = Set(session.outstandingFileTransfers.map { $0.file.fileURL.lastPathComponent })
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension == "json" && !queued.contains(url.lastPathComponent) {
            session.transferFile(url, metadata: ["type": "runRoute"])
        }
    }

    static func finished(_ transfer: WCSessionFileTransfer, error: Error?) {
        guard transfer.file.metadata?["type"] as? String == "runRoute" else { return }
        // Transport success alone does not mean iPhone committed the history.
        // Keep our copy until the phone sends a durable-save acknowledgment.
        if error != nil {
            print("Run route transfer will retry on the next connection.")
        }
    }

    static func acknowledge(runID: UUID) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(runID.uuidString).json"))
    }
}
