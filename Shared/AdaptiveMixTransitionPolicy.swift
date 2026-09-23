import Foundation

/// Shared by the watch, phone, and sandbox so preparation and audible changes
/// use the same clock thresholds. Preparation must not interrupt playback.
enum AdaptiveMixTransitionPolicy {
    static let preparationLeadTime: TimeInterval = 45
    static let playbackLeadTime: TimeInterval = 12

    static func isWithin(_ leadTime: TimeInterval, secondsRemaining: TimeInterval?) -> Bool {
        guard let secondsRemaining, secondsRemaining.isFinite else { return false }
        return secondsRemaining > 0 && secondsRemaining <= leadTime
    }
}

/// The music target can lead the workout target, but can never move backwards.
/// A fresh session ID also invalidates work that finishes after a run restarts.
struct AdaptiveMixTransitionState {
    let sessionID = UUID()
    private(set) var targetSegmentIndex = 0
    private(set) var preparingSegmentIndex: Int?

    var curationSegmentIndex: Int { preparingSegmentIndex ?? targetSegmentIndex }

    mutating func prepare(for segmentIndex: Int) -> Bool {
        guard segmentIndex > curationSegmentIndex else { return false }
        preparingSegmentIndex = segmentIndex
        return true
    }

    @discardableResult
    mutating func advance(to segmentIndex: Int) -> Bool {
        guard segmentIndex > targetSegmentIndex else { return false }
        targetSegmentIndex = segmentIndex
        if let preparingSegmentIndex, preparingSegmentIndex <= segmentIndex {
            self.preparingSegmentIndex = nil
        }
        return true
    }

    func acceptsResult(sessionID: UUID, segmentIndex: Int) -> Bool {
        self.sessionID == sessionID &&
            (segmentIndex == targetSegmentIndex || segmentIndex == preparingSegmentIndex)
    }
}
