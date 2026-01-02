import Foundation

final class HealthService {
    private let api = APIClient.shared

    func health() async throws -> HealthResponse {
        try await api.request(method: "GET", path: "/health")
    }

    func ready() async throws -> HealthResponse {
        try await api.request(method: "GET", path: "/ready")
    }
}
