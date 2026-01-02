import Foundation

final class FeedbackService {
    private let api = APIClient.shared

    func postFeedback(predictionId: String, request: FeedbackRequest) async throws -> FeedbackResponse {
        // POST /v1/predictions/{predictionId}/feedback
        let path = Endpoints.Predictions.feedback(predictionId)
        let response: FeedbackResponse = try await api.request(
            method: "POST",
            path: path,
            body: request,
            requiresAuth: true,
            retryOn401: true
        )
        return response
    }
}
