import Foundation
import HealthKit
import CoreLocation
import CoreMotion
import Observation
import WatchConnectivity

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
    
    // MARK: - Live Metrics
    @Published private(set) var heartRate: Double?
    @Published private(set) var activeCalories: Double = 0
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var workoutStartDate: Date?
    @Published private(set) var isRunning: Bool = false
    @Published var error: Error?
    
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
            
            guard !self.isRunning else {
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
            
            // Request location permissions if not granted
            if self.locationManager.authorizationStatus == .notDetermined {
                self.locationManager.requestWhenInUseAuthorization()
            }
            
            // Prepare HealthKit session
            let config = HKWorkoutConfiguration()
            config.activityType = .running
            config.locationType = .outdoor
            
            do {
                print("🏃 Creating HealthKit workout session...")
                self.session = try HKWorkoutSession(healthStore: self.healthStore, configuration: config)
                self.builder = self.session?.associatedWorkoutBuilder()
                self.builder?.dataSource = HKLiveWorkoutDataSource(healthStore: self.healthStore, workoutConfiguration: config)
                self.session?.delegate = self
                self.builder?.delegate = self
                
                print("🏃 Starting workout session...")
                self.workoutStartDate = Date()
                self.isRunning = true
                self.startWorkoutTimer()
                
                self.session?.startActivity(with: self.workoutStartDate!)
                self.builder?.beginCollection(withStart: self.workoutStartDate!) { [weak self] (_, err) in
                    DispatchQueue.main.async {
                        if let err = err {
                            print("❌ Failed to begin data collection: \(err)")
                            self?.error = err
                            self?.isRunning = false
                        } else {
                            print("✅ Data collection started successfully")
                        }
                    }
                }
                
                self.locationManager.startUpdatingLocation()
                self.startMotionTracking()
                
                // Start AI music curation
                self.startAIMusicCuration()
                
            } catch {
                print("❌ Failed to create HealthKit workout session: \(error)")
                self.error = error
                self.isRunning = false
            }
        }
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
                // Move to next segment
                currentSegmentIndex += 1
                print("🏃 Advanced to segment \(currentSegmentIndex + 1)/\(plannedSegments.count): \(currentSegment?.intensity.label ?? "Unknown")")
                
                // Reset segment tracking for new segment
                segmentStartTime = Date()
                segmentStartDistance = distanceMeters
                
                // Update music context for new segment
                updateMusicContextForSegmentChange()
            } else {
                // All segments complete - workout finished
                print("🏃 All segments completed - workout finished")
                // Could trigger workout completion here if needed
            }
        }
    }
    
    private func updateMusicContextForSegmentChange() {
        // Send updated music context to iPhone for new segment
        guard WCSession.default.isReachable else { return }
        
        let targetDescription: String
        if let segment = currentSegment {
            switch segment.target {
            case .time(let seconds):
                targetDescription = "\(seconds) seconds"
            case .distance(let meters):
                targetDescription = "\(meters) meters"
            }
        } else {
            targetDescription = "unknown"
        }
        
        let message: [String: Any] = [
            "type": "segment_changed",
            "currentSegmentIndex": currentSegmentIndex,
            "segmentIntensity": currentSegment?.intensity.rawValue ?? "unknown",
            "segmentTarget": targetDescription
        ]
        
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("Failed to send segment change to iPhone: \(error)")
        }
    }
    
    // MARK: - Music Curation
    
    private func startAIMusicCuration() {
        if isStandaloneMode() {
            startStandaloneMusic()
        } else {
            startConnectedMusic()
        }
    }
    
    private func isStandaloneMode() -> Bool {
        // Check if iPhone is nearby and connected
        return !WCSession.default.isReachable
    }
    
    private func startStandaloneMusic() {
        // Use standalone music manager for cellular Watch
        Task { @MainActor in
            let standaloneManager = StandaloneMusicManager.shared
            
            if let currentSegment = currentSegment {
                standaloneManager.selectWorkoutPlaylist(for: currentSegment.intensity)
            }
        }
    }
    
    private func startConnectedMusic() {
        // Send workout context to iPhone for AI music curation
        sendWorkoutContextToiPhone()
    }
    
    private func sendWorkoutContextToiPhone() {
        guard WCSession.default.isReachable,
              currentSegment != nil else { return }
        
        let message: [String: Any] = [
            "type": "workout_start",
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
        
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("Failed to send workout context to iPhone: \(error)")
        }
    }
    
    private func updateMusicContext() {
        if isStandaloneMode() {
            updateStandaloneMusic()
        } else {
            updateConnectedMusic()
        }
    }
    
    private func updateStandaloneMusic() {
        Task { @MainActor in
            let standaloneManager = StandaloneMusicManager.shared
            
            if let currentSegment = currentSegment {
                standaloneManager.selectSmartMusicForWorkout(
                    intensity: currentSegment.intensity,
                    heartRate: currentHeartRate,
                    timeRemaining: currentSegmentProgress * currentSegment.targetDuration
                )
            }
        }
    }
    
    private func updateConnectedMusic() {
        // Send updated context to iPhone
        guard WCSession.default.isReachable,
              currentSegment != nil else { return }
        
        let message: [String: Any] = [
            "type": "workout_update",
            "currentSegmentIndex": currentSegmentIndex,
            "totalDistance": totalDistance,
            "totalTime": totalTime,
            "heartRate": currentHeartRate as Any,
            "targetHeartRate": targetHeartRate as Any
        ]
        
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("Failed to send workout update to iPhone: \(error)")
        }
    }

    func stopWorkout() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            
            self.session?.end()
            self.locationManager.stopUpdatingLocation()
            self.stopMotionTracking()
            self.stopWorkoutTimer()
            self.isRunning = false
            
            // Reset state
            self.currentSegmentIndex = 0
            self.plannedSegments = []
            self.workoutStartDate = nil
            self.segmentStartTime = nil
            self.segmentStartDistance = 0
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
            print("🏃 Workout session state changed from \(fromState.rawValue) to \(toState.rawValue) at \(date)")
            
            switch toState {
            case .notStarted:
                print("🏃 Workout session not started")
            case .prepared:
                print("🏃 Workout session prepared")
            case .running:
                print("🏃 Workout session running")
                self?.isRunning = true
            case .paused:
                print("🏃 Workout session paused")
            case .stopped:
                print("🏃 Workout session stopped")
            case .ended:
                print("🏃 Workout session ended")
                self?.isRunning = false
            @unknown default:
                print("🏃 Workout session unknown state: \(toState.rawValue)")
            }
        }
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            print("❌ Workout session failed with error: \(error)")
            self?.error = error
            self?.isRunning = false
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

// MARK: - Target Extensions
extension Target {
    var isTime: Bool {
        if case .time = self { return true }
        return false
    }
    
    var isDistance: Bool {
        if case .distance = self { return true }
        return false
    }
    
    var timeSeconds: Int {
        if case .time(let seconds) = self { return seconds }
        return 0
    }
    
    var distanceMeters: Int {
        if case .distance(let meters) = self { return meters }
        return 0
    }
}

// MARK: - RunSegment Extensions
extension RunSegment {
    var targetDuration: TimeInterval {
        switch target {
        case .time(let seconds):
            return TimeInterval(seconds)
        case .distance:
            return 0 // Will be calculated based on pace
        }
    }
}

