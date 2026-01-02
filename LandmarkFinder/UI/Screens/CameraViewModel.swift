import Foundation
import UIKit
import AVFoundation
import Combine
import Network
import CoreLocation

@MainActor
final class CameraViewModel: ObservableObject {
    @Published var predictions: [Prediction] = []
    @Published var statusText: String = "Starting..."
    @Published var isUnknown: Bool = true
    @Published var isLoading: Bool = false
    @Published var isReady: Bool = true

    // Feedback related
    @Published var predictionId: String?
    @Published var serverThreshold: Double?
    private let feedbackService = FeedbackService()
    private var pendingFeedbackRetry: FeedbackRequestEnvelope?

    // New feedback UI states
    @Published var isSendingFeedback: Bool = false
    @Published var hasSentFeedback: Bool = false
    @Published var feedbackStatus: String?

    private let camera = CameraManager()
    private let throttler = FrameThrottler(maxFPS: 1.5)
    private let api = APIClient.shared
    private var isRequestInFlight = false
    var onAuthFailure: (() -> Void)?

    // History storage
    let history = HistoryStore.shared

    // Tunables
    var defaultThreshold: Double = 0.65
    var defaultTopK: Int = 3

    // Context providers
    private let deviceIdStore = DeviceIDStore.shared
    private let network = NetworkContext()
    private let locationService = LocationService()

    // Cached geo for session
    private var cachedCountryCode: String?
    private var cachedCity: String?

    init() {}

    func start() {
        Task { await preflight() }
        Task { await fetchGeoIfNeeded() }

        do {
            statusText = "Camera running..."
            try camera.start { [weak self] frame in
                guard let self else { return }
                guard self.isReady else { return }
                guard !self.isRequestInFlight else { return }
                guard self.throttler.shouldProcess() else { return }
                self.process(frame: frame, imageSource: "camera")
            }
        } catch {
            statusText = "Camera error: \(error.localizedDescription)"
        }
    }

    func stop() {
        camera.stop()
    }

    func submit(image: UIImage) {
        guard isReady else {
            statusText = "Model warming up. Try again."
            return
        }
        guard !isRequestInFlight else { return }
        Task { await fetchGeoIfNeeded() }
        process(frame: image, imageSource: "gallery")
    }

    private func preflight() async {
        do {
            let health: HealthResponse = try await api.request(method: "GET", path: "/health")
            let ready: HealthResponse = try await api.request(method: "GET", path: "/ready")
            await MainActor.run {
                self.isReady = health.ok && ready.ok
                if !self.isReady {
                    self.statusText = "Model warming up. Try again."
                }
            }
        } catch let APIError.http(status, _) where status == 503 {
            await MainActor.run {
                self.isReady = false
                self.statusText = "Model warming up. Try again."
            }
        } catch {
            await MainActor.run {
                self.isReady = true
            }
        }
    }

    private func fetchGeoIfNeeded() async {
        if cachedCountryCode != nil || cachedCity != nil { return }
        do {
            let geo = try await locationService.requestCoarseGeo()
            await MainActor.run {
                self.cachedCountryCode = geo.countryCode
                self.cachedCity = geo.city
            }
        } catch {
            // ignore
        }
    }

    private func process(frame: UIImage, imageSource: String) {
        let frameCopy = frame
        Task(priority: .userInitiated) {
            let t0 = Date()
            await MainActor.run {
                self.isRequestInFlight = true
                self.isLoading = true
                self.statusText = "Sending..."
                // Reset feedback UI for new prediction
                self.hasSentFeedback = false
                self.isSendingFeedback = false
                self.feedbackStatus = nil
            }
            defer {
                Task { @MainActor in
                    self.isRequestInFlight = false
                    self.isLoading = false
                }
            }

            let deviceId = deviceIdStore.identifier
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            let networkType = network.currentType
            let countryCode = await MainActor.run { self.cachedCountryCode }
            let city = await MainActor.run { self.cachedCity }
            let threshold = await MainActor.run { self.defaultThreshold }
            let topK = await MainActor.run { self.defaultTopK }

            guard var jpegData = frameCopy.jpegData(compressionQuality: 0.75) else {
                await MainActor.run {
                    self.statusText = "Encoding error"
                    self.predictions = []
                    self.isUnknown = true
                    self.predictionId = nil
                    self.serverThreshold = nil
                }
                return
            }

            func makeParts(from data: Data) -> [APIClient.MultipartPart] {
                var parts: [APIClient.MultipartPart] = [
                    APIClient.MultipartPart(
                        name: "file",
                        filename: "frame.jpg",
                        contentType: "image/jpeg",
                        data: data
                    )
                ]
                parts.append(APIClient.MultipartPart(name: "threshold", filename: nil, contentType: nil, data: Data(String(threshold).utf8)))
                parts.append(APIClient.MultipartPart(name: "image_source", filename: nil, contentType: nil, data: Data(imageSource.utf8)))
                if let networkType {
                    parts.append(APIClient.MultipartPart(name: "network_type", filename: nil, contentType: nil, data: Data(networkType.utf8)))
                }
                parts.append(APIClient.MultipartPart(name: "device_identifier", filename: nil, contentType: nil, data: Data(deviceId.utf8)))
                if let appVersion {
                    parts.append(APIClient.MultipartPart(name: "app_version", filename: nil, contentType: nil, data: Data(appVersion.utf8)))
                }
                if let countryCode {
                    parts.append(APIClient.MultipartPart(name: "country_code", filename: nil, contentType: nil, data: Data(countryCode.utf8)))
                }
                if let city {
                    parts.append(APIClient.MultipartPart(name: "city", filename: nil, contentType: nil, data: Data(city.utf8)))
                }
                return parts
            }

            var headers: [String: String] = [
                "x-image-source": imageSource,
                "x-device-id": deviceId
            ]
            if let networkType { headers["x-network-type"] = networkType }
            if let appVersion { headers["x-app-version"] = appVersion }
            if let countryCode { headers["x-country-code"] = countryCode }
            if let city { headers["x-city"] = city }

            let query = [
                URLQueryItem(name: "top_k", value: String(topK))
            ]

            @MainActor
            func handlePredictResponse(_ response: PredictResponse, elapsedMs: Int) async {
                let mappedTop = response.top3.map { Prediction(label: $0.label, confidence: $0.conf) }
                let result = PredictionResult(
                    top: mappedTop,
                    maxConfidence: response.maxProb,
                    isUnknown: response.isUnknown
                )
                self.predictions = result.top
                self.isUnknown = result.isUnknown || (result.maxConfidence < response.threshold)
                self.predictionId = response.predictionId
                self.serverThreshold = response.threshold
                if self.isUnknown {
                    self.statusText = "Not sure"
                } else if let best = result.top.first {
                    self.statusText = "Recognized: \(best.label) (\(elapsedMs) ms)"
                } else {
                    self.statusText = "Recognized (\(elapsedMs) ms)"
                }

                await history.add(
                    image: frameCopy,
                    predictions: mappedTop,
                    isUnknown: result.isUnknown,
                    maxConfidence: response.maxProb,
                    predictionId: response.predictionId
                )
            }

            do {
                let response: PredictResponse = try await api.uploadMultipart(
                    path: Endpoints.Predictions.predict,
                    parts: makeParts(from: jpegData),
                    requiresAuth: true,
                    retryOn401: true,
                    headers: headers,
                    queryItems: query
                )

                let t1 = Date()
                let ms = Int(t1.timeIntervalSince(t0) * 1000)
                await handlePredictResponse(response, elapsedMs: ms)
            } catch let APIError.http(status, _) where status == 413 {
                if let smaller = frameCopy.jpegData(compressionQuality: 0.5) {
                    jpegData = smaller
                    do {
                        let response: PredictResponse = try await api.uploadMultipart(
                            path: Endpoints.Predictions.predict,
                            parts: makeParts(from: jpegData),
                            requiresAuth: true,
                            retryOn401: true,
                            headers: headers,
                            queryItems: query
                        )
                        let t1 = Date()
                        let ms = Int(t1.timeIntervalSince(t0) * 1000)
                        await handlePredictResponse(response, elapsedMs: ms)
                    } catch {
                        await MainActor.run {
                            self.statusText = "Image too large. Try a smaller photo."
                            self.predictions = []
                            self.isUnknown = true
                            self.predictionId = nil
                            self.serverThreshold = nil
                        }
                    }
                } else {
                    await MainActor.run {
                        self.statusText = "Image too large. Try a smaller photo."
                        self.predictions = []
                        self.isUnknown = true
                        self.predictionId = nil
                        self.serverThreshold = nil
                    }
                }
            } catch let APIError.http(status, _) where status == 415 {
                await MainActor.run {
                    self.statusText = "Invalid image type (use JPEG/PNG)"
                    self.predictions = []
                    self.isUnknown = true
                    self.predictionId = nil
                    self.serverThreshold = nil
                }
            } catch let APIError.http(status, _) where (500..<600).contains(status) {
                await MainActor.run {
                    self.statusText = "Server error (\(status))"
                    self.predictions = []
                    self.isUnknown = true
                    self.predictionId = nil
                    self.serverThreshold = nil
                }
            } catch let APIError.http(status, _) where status == 401 {
                await MainActor.run {
                    self.statusText = "Auth required"
                    self.predictions = []
                    self.isUnknown = true
                    self.predictionId = nil
                    self.serverThreshold = nil
                    self.onAuthFailure?()
                }
            } catch {
                await MainActor.run {
                    self.statusText = "Connection error"
                    self.predictions = []
                    self.isUnknown = true
                    self.predictionId = nil
                    self.serverThreshold = nil
                }
            }
        }
    }

    var session: AVCaptureSession { camera.session }

    // MARK: - Feedback

    struct FeedbackRequestEnvelope {
        let predictionId: String
        let request: FeedbackRequest
    }

    func sendFeedback(isCorrect: Bool, selectedLabel: String?, comment: String?) {
        guard let predictionId else { return }

        let trimmedLabel: String? = selectedLabel?.isEmpty == true ? nil : selectedLabel.map { String($0.prefix(128)) }
        let trimmedComment: String? = comment?.isEmpty == true ? nil : comment.map { String($0.prefix(2000)) }

        let req = FeedbackRequest(is_correct: isCorrect, selected_label: trimmedLabel, comment: trimmedComment)
        let envelope = FeedbackRequestEnvelope(predictionId: predictionId, request: req)

        isSendingFeedback = true
        feedbackStatus = nil

        Task.detached { [feedbackService] in
            do {
                _ = try await feedbackService.postFeedback(predictionId: envelope.predictionId, request: envelope.request)
                await MainActor.run {
                    self.isSendingFeedback = false
                    self.hasSentFeedback = true
                    self.feedbackStatus = "Thanks for your feedback!"
                    if isCorrect, let latest = self.history.entries.first {
                        self.history.markConfirmed(entryID: latest.id)
                    }
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    if self.feedbackStatus == "Thanks for your feedback!" {
                        self.feedbackStatus = nil
                    }
                }
            } catch {
                await self.queueSingleRetry(envelope, isCorrect: isCorrect)
                await MainActor.run {
                    self.isSendingFeedback = false
                    self.feedbackStatus = "Couldn’t send feedback. Will retry."
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    if self.feedbackStatus == "Couldn’t send feedback. Will retry." {
                        self.feedbackStatus = nil
                    }
                }
            }
        }
    }

    private func queueSingleRetry(_ envelope: FeedbackRequestEnvelope, isCorrect: Bool) async {
        await MainActor.run {
            self.pendingFeedbackRetry = envelope
        }
        Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self = self, let pending = await MainActor.run(body: { self.pendingFeedbackRetry }) else { return }
            do {
                _ = try await self.feedbackService.postFeedback(predictionId: pending.predictionId, request: pending.request)
                await MainActor.run {
                    self.pendingFeedbackRetry = nil
                    if self.feedbackStatus == nil {
                        self.feedbackStatus = "Thanks for your feedback!"
                        self.hasSentFeedback = true
                        if isCorrect, let latest = self.history.entries.first {
                            self.history.markConfirmed(entryID: latest.id)
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    if self.feedbackStatus == "Thanks for your feedback!" {
                        self.feedbackStatus = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.pendingFeedbackRetry = nil
                    if self.feedbackStatus == nil {
                        self.feedbackStatus = "Feedback failed."
                    }
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    if self.feedbackStatus == "Feedback failed." {
                        self.feedbackStatus = nil
                    }
                }
            }
        }
    }
}

// Health/Ready response model
struct HealthResponse: Codable { let ok: Bool }

// MARK: - Network context helper
final class NetworkContext {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "network.context.queue")
    private(set) var currentType: String?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status != .satisfied {
                self?.currentType = "offline"
            } else if path.usesInterfaceType(.wifi) {
                self?.currentType = "wifi"
            } else if path.usesInterfaceType(.cellular) {
                self?.currentType = "cellular"
            } else {
                self?.currentType = nil
            }
        }
        monitor.start(queue: queue)
    }
}
