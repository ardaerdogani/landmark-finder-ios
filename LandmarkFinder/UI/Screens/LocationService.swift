import Foundation
import CoreLocation
import MapKit

struct CoarseGeo {
    let countryCode: String?
    let city: String?
}

@MainActor
final class LocationService: NSObject {
    private let manager: CLLocationManager

    override init() {
        self.manager = CLLocationManager()
        super.init()
        self.manager.delegate = self
        if #available(iOS 14.0, *) {
            self.manager.desiredAccuracy = kCLLocationAccuracyReduced
        } else {
            self.manager.desiredAccuracy = kCLLocationAccuracyKilometer
        }
        self.manager.distanceFilter = 1000 // 1 km
        self.manager.pausesLocationUpdatesAutomatically = true
    }

    func requestCoarseGeo(timeout: TimeInterval = 6.0) async throws -> CoarseGeo {
        // Ensure authorization
        let status = CLLocationManager.authorizationStatus()
        switch status {
        case .notDetermined:
            try await requestWhenInUseAuthorization()
        case .denied, .restricted:
            throw NSError(domain: "LocationService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Location permission denied"])
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            break
        }

        // Get one location update (best effort, coarse)
        let location = try await requestOneLocation(timeout: timeout)

        // Reverse geocode using MapKit on iOS 26+, fallback to CLGeocoder earlier
        if #available(iOS 26.0, *) {
            let result = try await reverseGeocodeMapKit(location: location, timeout: timeout)
            return result
        } else {
            let placemark = try await reverseGeocodeCoreLocation(location: location, timeout: timeout)
            let countryCode = placemark.isoCountryCode
            let city = placemark.locality ?? placemark.subAdministrativeArea
            return CoarseGeo(countryCode: countryCode, city: city)
        }
    }

    // MARK: - Helpers

    private func requestWhenInUseAuthorization() async throws {
        try await withCheckedThrowingContinuation { cont in
            self.authContinuation = cont
            self.manager.requestWhenInUseAuthorization()
        }
    }

    private func requestOneLocation(timeout: TimeInterval) async throws -> CLLocation {
        try await withThrowingTaskGroup(of: CLLocation.self) { group in
            group.addTask { [weak self] in
                try await withCheckedThrowingContinuation { cont in
                    guard let self else {
                        cont.resume(throwing: NSError(domain: "LocationService", code: -1))
                        return
                    }
                    Task { @MainActor in
                        self.locationContinuation = cont
                        self.manager.requestLocation()
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw NSError(domain: "LocationService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Location timeout"])
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MapKit reverse geocoding (iOS 26+)
    @available(iOS 26.0, *)
    private func reverseGeocodeMapKit(location: CLLocation, timeout: TimeInterval) async throws -> CoarseGeo {
        try await withThrowingTaskGroup(of: CoarseGeo.self) { group in
            group.addTask {
                let request = MKLocalSearch.Request()
                request.pointOfInterestFilter = .includingAll
                request.resultTypes = [.address, .pointOfInterest]
                request.region = MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 5000,
                    longitudinalMeters: 5000
                )
                let search = MKLocalSearch(request: request)
                let response = try await search.start()

                let items = response.mapItems

                guard let item = items.min(by: { lhs, rhs in
                    let l = lhs.location.distance(from: location)
                    let r = rhs.location.distance(from: location)
                    return l < r
                }) ?? items.first else {
                    throw NSError(domain: "LocationService", code: 5, userInfo: [NSLocalizedDescriptionKey: "No MapKit results"])
                }

                var countryCode: String?
                var city: String?

                // Preferred: MKMapItem.address (new in iOS 26)
                if let addr = item.address {
                    let mirror = Mirror(reflecting: addr)
                    for child in mirror.children {
                        switch child.label {
                        case "isoCountryCode", "countryCode":
                            if countryCode == nil, let v = child.value as? String { countryCode = v }
                        case "city", "locality":
                            if city == nil, let v = child.value as? String { city = v }
                        case "subAdministrativeArea":
                            if city == nil, let v = child.value as? String { city = v }
                        default:
                            break
                        }
                    }
                }

                // Note: MKMapItem.addressRepresentations is not a Sequence; do not iterate it.

                // Last resort: fall back to deprecated placemark if still needed
                if (countryCode == nil || city == nil) {
                    if let deprecatedPlacemark = item.value(forKey: "placemark") as? MKPlacemark {
                        if countryCode == nil { countryCode = deprecatedPlacemark.isoCountryCode }
                        if city == nil { city = deprecatedPlacemark.locality ?? deprecatedPlacemark.subAdministrativeArea }
                    }
                }

                if city == nil {
                    city = item.name
                }

                return CoarseGeo(countryCode: countryCode, city: city)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw NSError(domain: "LocationService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Geocode timeout"])
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // Core Location reverse geocoding (iOS <= 25)
    private func reverseGeocodeCoreLocation(location: CLLocation, timeout: TimeInterval) async throws -> CLPlacemark {
        try await withThrowingTaskGroup(of: CLPlacemark.self) { group in
            group.addTask {
                let geocoder = CLGeocoder()
                return try await withCheckedThrowingContinuation { cont in
                    geocoder.reverseGeocodeLocation(location) { placemarks, error in
                        if let error {
                            cont.resume(throwing: error)
                        } else if let pm = placemarks?.first {
                            cont.resume(returning: pm)
                        } else {
                            cont.resume(throwing: NSError(domain: "LocationService", code: 3, userInfo: [NSLocalizedDescriptionKey: "No placemark"]))
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw NSError(domain: "LocationService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Geocode timeout"])
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // Continuations
    private var authContinuation: CheckedContinuation<Void, Error>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
}

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = CLLocationManager.authorizationStatus()
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            authContinuation?.resume()
            authContinuation = nil
        case .denied, .restricted:
            authContinuation?.resume(throwing: NSError(domain: "LocationService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Location permission denied"]))
            authContinuation = nil
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            authContinuation?.resume()
            authContinuation = nil
        case .denied, .restricted:
            authContinuation?.resume(throwing: NSError(domain: "LocationService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Location permission denied"]))
            authContinuation = nil
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            locationContinuation?.resume(returning: loc)
            locationContinuation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }
}
