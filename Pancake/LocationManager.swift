import Foundation
import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    
    private let locationManager = CLLocationManager()
    
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isAuthorized: Bool = false
    @Published var lastError: Error?
    
    private override init() {
        super.init()
        locationManager.delegate = self
        authorizationStatus = locationManager.authorizationStatus
        updateAuthorizationState()
    }
    
    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    private func updateAuthorizationState() {
        DispatchQueue.main.async { [weak self] in
            self?.isAuthorized = self?.authorizationStatus == .authorizedWhenInUse || self?.authorizationStatus == .authorizedAlways
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.authorizationStatus = status
            self?.isAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.lastError = error
        }
    }
}
