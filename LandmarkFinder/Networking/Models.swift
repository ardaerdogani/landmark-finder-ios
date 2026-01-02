import Foundation

struct AuthRequest: Codable {
    let email: String
    let password: String
}

struct RefreshRequest: Codable {
    let refresh_token: String
}

struct LogoutRequest: Codable {
    let refresh_token: String
}

struct TokenResponse: Codable {
    let access_token: String
    let refresh_token: String
    let token_type: String
}

struct MeResponse: Codable {
    let id: String?
    let email: String
}

struct PredictResponse: Codable {
    struct Item: Codable {
        let label: String
        let conf: Double
    }

    let predictionId: String
    let top3: [Item]
    let maxProb: Double
    let isUnknown: Bool
    let threshold: Double

    enum CodingKeys: String, CodingKey {
        case predictionId = "prediction_id"
        case top3
        case maxProb = "max_prob"
        case isUnknown = "is_unknown"
        case threshold
    }
}

// Feedback models
struct FeedbackRequest: Codable {
    let is_correct: Bool
    let selected_label: String?
    let comment: String?
}

struct FeedbackResponse: Codable {
    let feedback_id: String
    let prediction_id: String
    let is_correct: Bool
}

// Google auth exchange request
struct GoogleAuthRequest: Codable {
    let id_token: String
}

