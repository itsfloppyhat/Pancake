import Foundation
import HealthKit
import CoreLocation
import CoreMotion
import WatchConnectivity
import WatchKit

// MARK: - GPS Status
enum GPSStatus: String, CaseIterable {
    case unknown = "unknown"
    case excellent = "excellent"
    case good = "good"
    case fair = "fair"
    case poor = "poor"
    case unavailable = "unavailable"
    
    var icon: String {
        switch self {
        case .excellent: return "location.fill"
        case .good: return "location.fill"
        case .fair: return "location"
        case .poor: return "location.slash"
        case .unavailable: return "location.slash.fill"
        case .unknown: return "location.circle"
        }
    }
    
    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "blue"
        case .fair: return "orange"
        case .poor: return "red"
        case .unavailable: return "gray"
        case .unknown: return "gray"
        }
    }
    
    var description: String {
        switch self {
        case .excellent: return "Excellent GPS"
        case .good: return "Good GPS"
        case .fair: return "Fair GPS"
        case .poor: return "Poor GPS"
        case .unavailable: return "No GPS"
        case .unknown: return "GPS Unknown"
        }
    }
    
    static func from(accuracy: CLLocationAccuracy) -> GPSStatus {
        switch accuracy {
        case 0..<5: return .excellent
        case 5..<10: return .good
        case 10..<20: return .fair
        case 20..<50: return .poor
        default: return .unavailable
        }
    }
}

// MARK: - Workout Errors
enum WorkoutError: LocalizedError {
    case alreadyRunning
    case noSegments
    case healthKitUnavailable
    case locationDenied
    
    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "A workout is already in progress"
        case .noSegments:
            return "No workout segments planned"
        case .healthKitUnavailable:
            return "HealthKit is not available on this device"
        case .locationDenied:
            return "Location access is required for outdoor workouts"
        }
    }
}

final class WorkoutSessionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WorkoutSessionManager()

    // MARK: - HealthKit Properties
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    // MARK: - Location Tracking
    private let locationManager = CLLocationManager()
    @Published private(set) var locations: [CLLocation] = []
    @Published private(set) var gpsAccuracy: CLLocationAccuracy?
    @Published private(set) var gpsStatus: GPSStatus = .unknown
    @Published private(set) var isGPSAvailable: Bool = false
    
    // GPS smoothing
    private var locationBuffer: [CLLocation] = []
    private let maxBufferSize = 10
    private let minAccuracyThreshold: CLLocationAccuracy = 100.0

    // MARK: - Motion Tracking
    private let motionManager = CMMotionManager()
    @Published private(set) var cadence: Double = 0 // steps per minute
    @Published private(set) var stepCount: Int = 0
    private var lastStepTime: Date?
    private var stepTimes: [Date] = []
    
    // Additional properties for music integration
    @Published private(set) var currentHeartRate: Int?
    @Published private(set) var targetHeartRate: Int?
    @Published private(set) var totalDistance: Double = 0
    @Published private(set) var totalTime: TimeInterval = 0
    
    // Timer for total time tracking
    private var workoutTimer: Timer?

    // Timer for sending updates to iPhone
    private var iPhoneUpdateTimer: Timer?

    // Km milestone notification
    @Published var showKmMilestone: Bool = false
    @Published var lastKmMilestone: Int = 0
    private var lastNotifiedKm: Int = 0
    private var kmDismissTimer: Timer?
    
    // MARK: - Live Metrics
    @Published private(set) var heartRate: Double?
    @Published private(set) var liveMetricsWarning: String?
    @Published private(set) var activeCalories: Double = 0
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var workoutStartDate: Date?
    @Published private(set) var isStarting: Bool = false
    @Published private(set) var isRunning: Bool = false
    @Published var error: Error?
    private var lastHeartRateSampleAt: Date?
    private var hasSentHeartRateWarningToPhone = false
    private static let heartRateSignalGracePeriod: TimeInterval = 90
    
    // MARK: - Workout State
    @Published private(set) var currentSegmentIndex: Int = 0
    @Published private(set) var plannedSegments: [RunSegment] = []
    
    // MARK: - Segment Tracking
    private var segmentStartTime: Date?
    private var segmentStartDistance: Double = 0

    private override init() {
        super.init()
        setupLocationManager()
        setupMotionManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone // Deliver all updates for maximum responsiveness
        #if !os(watchOS)
        // Background location behaviors are not available on watchOS
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        #endif
        
        // Check GPS availability
        updateGPSAvailability()
    }
    
    private func updateGPSAvailability() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if CLLocationManager.locationServicesEnabled() {
                switch self.locationManager.authorizationStatus {
                case .authorizedWhenInUse, .authorizedAlways:
                    self.isGPSAvailable = true
                    self.gpsStatus = .unknown
                case .denied, .restricted:
                    self.isGPSAvailable = false
                    self.gpsStatus = .unavailable
                case .notDetermined:
                    self.isGPSAvailable = false
                    self.gpsStatus = .unknown
                @unknown default:
                    self.isGPSAvailable = false
                    self.gpsStatus = .unknown
                }
            } else {
                self.isGPSAvailable = false
                self.gpsStatus = .unavailable
            }
        }
    }
    
    private func setupMotionManager() {
        motionManager.deviceMotionUpdateInterval = 0.01 // 100 Hz for maximum responsiveness
        motionManager.accelerometerUpdateInterval = 0.01 // 100 Hz for more precise step detection
    }

    func startOutdoorRun(segments: [RunSegment]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            guard !self.isRunning, !self.isStarting else {
                self.error = WorkoutError.alreadyRunning
                return
            }

            guard !segments.isEmpty else {
                self.error = WorkoutError.noSegments
                return
            }

            // Store planned segments
            self.plannedSegments = segments
            self.currentSegmentIndex = 0

            // Initialize segment tracking
            self.segmentStartTime = Date()
            self.segmentStartDistance = 0

            // Clear any previous errors
            self.error = nil
            self.isStarting = true
            self.heartRate = nil
            self.currentHeartRate = nil
            self.liveMetricsWarning = nil
            self.lastHeartRateSampleAt = nil
            self.hasSentHeartRateWarningToPhone = false

            // Request location permissions if not granted
            if self.locationManager.authorizationStatus == .notDetermined {
                self.locationManager.requestWhenInUseAuthorization()
            }

            // Give SwiftUI a frame to render the starting screen before HealthKit setup begins.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.beginOutdoorRunSession()
            }
        }
    }

    private func beginOutdoorRunSession() {
        guard isStarting else { return }

        // Prepare HealthKit session
        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = .outdoor

        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            builder = session?.associatedWorkoutBuilder()
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            session?.delegate = self
            builder?.delegate = self

            let startDate = Date()
            workoutStartDate = startDate
            segmentStartTime = startDate

            session?.startActivity(with: startDate)
            builder?.beginCollection(withStart: startDate) { [weak self] (_, err) in
                DispatchQueue.main.async {
                    guard let self else { return }

                    if let err = err {
                        print("❌ Failed to begin data collection: \(err)")
                        self.failWorkoutStart(err)
                        return
                    }

                    self.confirmWorkoutStarted()
                }
            }
        } catch {
            print("❌ Failed to create HealthKit workout session: \(error)")
            failWorkoutStart(error)
        }
    }

    private func confirmWorkoutStarted() {
        guard isStarting else { return }

        isStarting = false
        isRunning = true

        startWorkoutTimer()
        locationManager.startUpdatingLocation()
        startMotionTracking()

        // Start AI music curation only after the Watch workout is actually running.
        startAIMusicCuration()

        // Start periodic updates to iPhone (HR, distance, time)
        startIPhoneUpdateTimer()
    }

    private func failWorkoutStart(_ error: Error) {
        self.error = error
        isStarting = false
        isRunning = false

        session?.end()
        session = nil
        builder = nil

        locationManager.stopUpdatingLocation()
        stopMotionTracking()
        stopWorkoutTimer()
        stopIPhoneUpdateTimer()

        workoutStartDate = nil
        segmentStartTime = nil
        segmentStartDistance = 0
        liveMetricsWarning = nil
        lastHeartRateSampleAt = nil
        hasSentHeartRateWarningToPhone = false
    }
    
    private func startMotionTracking() {
        guard motionManager.isAccelerometerAvailable else { return }
        
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self, let data = data else { return }
            
            // Simple step detection using accelerometer
            let acceleration = sqrt(pow(data.acceleration.x, 2) + 
                                  pow(data.acceleration.y, 2) + 
                                  pow(data.acceleration.z, 2))
            
            // Threshold for step detection (adjust based on testing)
            let stepThreshold: Double = 1.2
            
            if acceleration > stepThreshold {
                let now = Date()
                
                // Avoid duplicate steps within 0.3 seconds
                if let lastStep = self.lastStepTime, now.timeIntervalSince(lastStep) < 0.3 {
                    return
                }
                
                self.lastStepTime = now
                self.stepCount += 1
                self.stepTimes.append(now)
                
                // Keep only recent step times (last 10 seconds)
                self.stepTimes = self.stepTimes.filter { now.timeIntervalSince($0) <= 10.0 }
                
                // Calculate cadence (steps per minute)
                if self.stepTimes.count >= 2 {
                    let timeSpan = self.stepTimes.last!.timeIntervalSince(self.stepTimes.first!)
                    if timeSpan > 0 {
                        self.cadence = Double(self.stepTimes.count - 1) * 60.0 / timeSpan
                    }
                }
            }
        }
    }
    
    private func stopMotionTracking() {
        motionManager.stopAccelerometerUpdates()
        stepCount = 0
        cadence = 0
        stepTimes.removeAll()
        lastStepTime = nil
    }
    
    // MARK: - Workout Timer
    
    private func startWorkoutTimer() {
        workoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, let startDate = self.workoutStartDate else { return }
                self.totalTime = Date().timeIntervalSince(startDate)

                // Check for segment completion
                self.checkForSegmentCompletion()

                // Check for km milestones
                self.checkForKmMilestone()

                // Warn if HealthKit never starts delivering heart-rate samples.
                self.checkForHeartRateSignal()
            }
        }
    }
    
    private func stopWorkoutTimer() {
        workoutTimer?.invalidate()
        workoutTimer = nil
    }
    
    private func checkForSegmentCompletion() {
        // Check if current segment is complete (progress >= 1.0)
        if currentSegmentProgress >= 1.0 {
            // Check if there are more segments
            if currentSegmentIndex + 1 < plannedSegments.count {
                WKInterfaceDevice.current().play(.success)

                // Move to next segment
                currentSegmentIndex += 1
                
                // Reset segment tracking for new segment
                segmentStartTime = Date()
                segmentStartDistance = distanceMeters
                
                // Update music context for new segment
                updateMusicContextForSegmentChange()
            } else {
                // All segments complete - workout finished
                // Could trigger workout completion here if needed
            }
        }
    }
    
    private func checkForKmMilestone() {
        let currentKm = Int(displayedDistanceKm)
        guard currentKm > lastNotifiedKm && currentKm > 0 else { return }

        lastNotifiedKm = currentKm
        lastKmMilestone = currentKm
        showKmMilestone = true

        // Haptic feedback
        WKInterfaceDevice.current().play(.notification)

        // Auto-dismiss after 4 seconds
        kmDismissTimer?.invalidate()
        kmDismissTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.showKmMilestone = false
            }
        }
    }

    private func checkForHeartRateSignal() {
        guard isRunning,
              lastHeartRateSampleAt == nil,
              workoutDuration >= Self.heartRateSignalGracePeriod else { return }

        liveMetricsWarning = "No heart-rate signal yet. Music is using your run plan and segment intensity until Apple Watch heart-rate data starts."

        guard !hasSentHeartRateWarningToPhone else { return }
        hasSentHeartRateWarningToPhone = true
        sendWorkoutSnapshotToiPhone(reason: "heart-rate signal warning")
    }

    private func updateMusicContextForSegmentChange() {
        sendWorkoutSnapshotToiPhone(reason: "segment change")
    }
    
    // MARK: - Music Curation

    private func startAIMusicCuration() {
        // Send workout context to iPhone for AI music curation
        sendWorkoutContextToiPhone()
    }
    
    private func sendWorkoutContextToiPhone() {
        guard currentSegment != nil else { return }
        
        let message: [String: Any] = [
            "type": WatchMessageType.workoutStart.rawValue,
            "segments": plannedSegments.map { segment in
                [
                    "intensity": segment.intensity.rawValue,
                    "target": [
                        "type": segment.target.isTime ? "time" : "distance",
                        "value": segment.target.isTime ? segment.target.timeSeconds : segment.target.distanceMeters
                    ]
                ]
            }
        ]

        sendToiPhone(
            message,
            preferLatestStateFallback: false,
            guaranteeDeliveryWhenUnreachable: true,
            errorLabel: "initial workout context"
        )
    }
    
    private func updateMusicContext() {
        sendWorkoutSnapshotToiPhone(reason: "live workout update")
    }

    // MARK: - Periodic iPhone Updates

    private func startIPhoneUpdateTimer() {
        stopIPhoneUpdateTimer()
        iPhoneUpdateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.sendPeriodicUpdateToiPhone()
            }
        }
    }

    private func stopIPhoneUpdateTimer() {
        iPhoneUpdateTimer?.invalidate()
        iPhoneUpdateTimer = nil
    }

    private func sendPeriodicUpdateToiPhone() {
        guard isRunning else { return }
        sendWorkoutSnapshotToiPhone(reason: "periodic workout update")
    }

    private func sendWorkoutSnapshotToiPhone(reason: String) {
        guard currentSegment != nil else { return }

        var updateMessage: [String: Any] = [
            "type": WatchMessageType.workoutUpdate.rawValue,
            "currentSegmentIndex": currentSegmentIndex,
            "totalDistance": totalDistance,
            "totalTime": totalTime
        ]

        if let currentHeartRate {
            updateMessage["heartRate"] = currentHeartRate
        }

        if let liveMetricsWarning {
            updateMessage["heartRateUnavailable"] = true
            updateMessage["metricsWarning"] = liveMetricsWarning
        }

        if let targetHeartRate {
            updateMessage["targetHeartRate"] = targetHeartRate
        }

        sendToiPhone(
            updateMessage,
            preferLatestStateFallback: true,
            guaranteeDeliveryWhenUnreachable: false,
            errorLabel: reason
        )
    }

    private func sendToiPhone(
        _ message: [String: Any],
        preferLatestStateFallback: Bool,
        guaranteeDeliveryWhenUnreachable: Bool,
        errorLabel: String
    ) {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("Failed to send \(errorLabel) to iPhone: \(error)")
            }
            return
        }

        if preferLatestStateFallback {
            do {
                try session.updateApplicationContext(message)
                return
            } catch {
                print("Failed to update application context for \(errorLabel): \(error)")
            }
        }

        if guaranteeDeliveryWhenUnreachable {
            session.transferUserInfo(message)
        }
    }

    func stopWorkout() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isRunning else { return }

            self.isStarting = false
            self.session?.end()
            self.locationManager.stopUpdatingLocation()
            self.stopMotionTracking()
            self.stopWorkoutTimer()
            self.stopIPhoneUpdateTimer()
            self.isRunning = false
            
            // Reset state
            self.currentSegmentIndex = 0
            self.plannedSegments = []
            self.workoutStartDate = nil
            self.segmentStartTime = nil
            self.segmentStartDistance = 0
            self.lastNotifiedKm = 0
            self.showKmMilestone = false
            self.lastKmMilestone = 0
            self.heartRate = nil
            self.currentHeartRate = nil
            self.liveMetricsWarning = nil
            self.lastHeartRateSampleAt = nil
            self.hasSentHeartRateWarningToPhone = false
            self.kmDismissTimer?.invalidate()
            self.kmDismissTimer = nil
        }
    }
    
    // MARK: - Computed Properties
    
    /// Current workout duration in seconds
    var workoutDuration: TimeInterval {
        guard let startDate = workoutStartDate else { return 0 }
        return Date().timeIntervalSince(startDate)
    }
    
    /// Current segment (if any)
    var currentSegment: RunSegment? {
        guard currentSegmentIndex < plannedSegments.count else { return nil }
        return plannedSegments[currentSegmentIndex]
    }
    
    /// Progress through current segment (0.0 to 1.0)
    var currentSegmentProgress: Double {
        guard let segment = currentSegment else { return 0.0 }
        
        switch segment.target {
        case .time(let seconds):
            guard let startTime = segmentStartTime else { return 0.0 }
            let segmentElapsed = Date().timeIntervalSince(startTime)
            return min(segmentElapsed / Double(seconds), 1.0)
        case .distance(let meters):
            let segmentDistance = distanceMeters - segmentStartDistance
            return min(segmentDistance / Double(meters), 1.0)
        }
    }
    
    /// Total distance calculated from GPS locations
    var gpsDistance: Double {
        guard locations.count > 1 else { return 0 }
        
        var total: CLLocationDistance = 0
        for i in 1..<locations.count {
            total += locations[i].distance(from: locations[i - 1])
        }
        return total
    }

    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Filter and smooth locations
        let validLocations = locations.filter { $0.horizontalAccuracy <= minAccuracyThreshold }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update GPS status based on best accuracy
            if let bestLocation = validLocations.min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy }) {
                self.gpsAccuracy = bestLocation.horizontalAccuracy
                self.gpsStatus = GPSStatus.from(accuracy: bestLocation.horizontalAccuracy)
            }
            
            // Add to buffer for smoothing
            self.locationBuffer.append(contentsOf: validLocations)
            
            // Keep buffer size manageable
            if self.locationBuffer.count > self.maxBufferSize {
                self.locationBuffer.removeFirst(self.locationBuffer.count - self.maxBufferSize)
            }
            
            // Apply smoothing and add to main locations array
            if let smoothedLocation = self.smoothLocation() {
                self.locations.append(smoothedLocation)
            }
        }
    }
    
    private func smoothLocation() -> CLLocation? {
        guard !locationBuffer.isEmpty else { return nil }
        
        // If we have only one location, return it
        if locationBuffer.count == 1 {
            return locationBuffer.first
        }
        
        // Calculate weighted average based on accuracy
        var totalWeight: Double = 0
        var weightedLat: Double = 0
        var weightedLon: Double = 0
        var weightedAccuracy: Double = 0
        var latestTimestamp: Date = Date.distantPast
        
        for location in locationBuffer {
            // Weight inversely proportional to accuracy (better accuracy = higher weight)
            let weight = 1.0 / max(location.horizontalAccuracy, 1.0)
            
            totalWeight += weight
            weightedLat += location.coordinate.latitude * weight
            weightedLon += location.coordinate.longitude * weight
            weightedAccuracy += location.horizontalAccuracy * weight
            
            if location.timestamp > latestTimestamp {
                latestTimestamp = location.timestamp
            }
        }
        
        guard totalWeight > 0 else { return nil }
        
        let smoothedLat = weightedLat / totalWeight
        let smoothedLon = weightedLon / totalWeight
        let smoothedAccuracy = weightedAccuracy / totalWeight
        
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: smoothedLat, longitude: smoothedLon),
            altitude: locationBuffer.last?.altitude ?? 0,
            horizontalAccuracy: smoothedAccuracy,
            verticalAccuracy: locationBuffer.last?.verticalAccuracy ?? -1,
            timestamp: latestTimestamp
        )
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.error = error
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch status {
            case .denied, .restricted:
                self.error = WorkoutError.locationDenied
                self.isGPSAvailable = false
                self.gpsStatus = .unavailable
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
                self.isGPSAvailable = false
                self.gpsStatus = .unknown
            case .authorizedWhenInUse, .authorizedAlways:
                self.isGPSAvailable = true
                self.gpsStatus = .unknown
            @unknown default:
                self.isGPSAvailable = false
                self.gpsStatus = .unknown
            }
        }
    }
}

// MARK: - HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate
extension WorkoutSessionManager: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async { [weak self] in
            switch toState {
            case .running:
                if self?.isStarting == false {
                    self?.isRunning = true
                }
            case .ended:
                self?.isStarting = false
                self?.isRunning = false
            default:
                break
            }
        }
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            print("❌ Workout session failed with error: \(error)")
            self?.failWorkoutStart(error)
        }
    }
    
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle workout events if needed
    }
    
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf types: Set<HKSampleType>) {
        guard let builder = self.builder else { return }
        
        for type in types {
            switch type {
            case HKObjectType.quantityType(forIdentifier: .heartRate):
                updateHeartRate(from: builder)
            case HKObjectType.quantityType(forIdentifier: .activeEnergyBurned):
                updateActiveCalories(from: builder)
            case HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning):
                updateDistance(from: builder)
            default:
                break
            }
        }
    }
    
    private func updateHeartRate(from builder: HKLiveWorkoutBuilder) {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate),
              let stats = builder.statistics(for: heartRateType),
              let heartRate = stats.mostRecentQuantity()?.doubleValue(for: .init(from: "count/min")) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.heartRate = heartRate
            self?.currentHeartRate = Int(heartRate)
            self?.lastHeartRateSampleAt = Date()
            self?.liveMetricsWarning = nil
        }
    }
    
    private func updateActiveCalories(from builder: HKLiveWorkoutBuilder) {
        guard let caloriesType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
              let stats = builder.statistics(for: caloriesType),
              let calories = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.activeCalories = calories
        }
    }
    
    /// Best-effort distance in km, preferring HealthKit then falling back to CoreLocation.
    var displayedDistanceKm: Double {
        let hkKm = distanceMeters / 1000.0
        if hkKm > 0 { return hkKm }
        guard locations.count > 1 else { return 0 }
        var total: CLLocationDistance = 0
        for i in 1..<locations.count {
            total += locations[i].distance(from: locations[i - 1])
        }
        return total / 1000.0
    }

    private func updateDistance(from builder: HKLiveWorkoutBuilder) {
        guard let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
              let stats = builder.statistics(for: distanceType),
              let distance = stats.sumQuantity()?.doubleValue(for: .meter()) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.distanceMeters = distance
            self?.totalDistance = distance / 1000.0 // Convert to kilometers
        }
    }
}
