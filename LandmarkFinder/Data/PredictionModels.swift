import Foundation

struct Prediction: Identifiable, Codable {
    let id: UUID
    let label: String
    let confidence: Double

    init(id: UUID = UUID(), label: String, confidence: Double) {
        self.id = id
        self.label = label
        self.confidence = confidence
    }
}

struct PredictionResult {
    let top: [Prediction]
    let maxConfidence: Double
    let isUnknown: Bool
}

