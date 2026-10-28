//
//  LocationService.swift
//  Soundprint
//
//  只有用户主动点击“使用当前位置”时才请求定位；不做持续定位。
//

import CoreLocation
import Foundation
import UIKit

final class LocationService: NSObject {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private var completion: ((Result<CLLocation, LocationError>) -> Void)?
    private var didRequestAuthorization = false
    private var timeoutWorkItem: DispatchWorkItem?
    private var isRequesting = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    func requestCurrentLocation(completion: @escaping (Result<CLLocation, LocationError>) -> Void) {
        guard !isRequesting else { return }
        isRequesting = true
        self.completion = completion
        didRequestAuthorization = false

        switch manager.authorizationStatus {
        case .notDetermined:
            didRequestAuthorization = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            requestOneShot()
        case .denied, .restricted:
            finish(.failure(.permissionDenied))
        @unknown default:
            finish(.failure(.unavailable))
        }
    }

    func cancel() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        manager.stopUpdatingLocation()
        completion = nil
        isRequesting = false
    }

    private func requestOneShot() {
        let item = DispatchWorkItem { [weak self] in
            self?.finish(.failure(.timeout))
        }
        timeoutWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: item)
        manager.requestLocation()
    }

    private func finish(_ result: Result<CLLocation, LocationError>) {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        manager.stopUpdatingLocation()
        let callback = completion
        completion = nil
        isRequesting = false
        DispatchQueue.main.async {
            callback?(result)
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        guard isRequesting, didRequestAuthorization else { return }
        didRequestAuthorization = false
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            requestOneShot()
        case .denied, .restricted:
            finish(.failure(.permissionDenied))
        case .notDetermined:
            break
        @unknown default:
            finish(.failure(.unavailable))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRequesting else { return }
        guard let location = locations.last, location.horizontalAccuracy >= 0 else {
            finish(.failure(.unavailable))
            return
        }
        finish(.success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard isRequesting else { return }
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                finish(.failure(.permissionDenied))
            case .locationUnknown:
                finish(.failure(.unavailable))
            default:
                finish(.failure(.unavailable))
            }
        } else {
            finish(.failure(.unavailable))
        }
    }
}

enum LocationError: LocalizedError {
    case permissionDenied
    case unavailable
    case timeout

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location access is not allowed. Allow it in the Settings app, or enter the place manually."
        case .unavailable:
            return "The current location could not be determined. Check your signal, or continue without location."
        case .timeout:
            return "Getting the current location is taking a while. You can continue without location."
        }
    }
}

// MARK: - 设备型号

enum DeviceInfo {
    static var modelIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = Mirror(reflecting: systemInfo.machine).children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        return machine
    }

    static var displayName: String {
        "\(UIDevice.current.model) (\(modelIdentifier))"
    }
}
