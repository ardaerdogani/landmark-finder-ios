// New file suggestion: ServerHistoryModels.swift
import Foundation

struct ServerHistoryPage: Decodable {
    let items: [ServerHistoryItem]
    let has_more: Bool
    let next_page: Int?
}

struct ServerHistoryItem: Decodable, Identifiable {
    var id: String { prediction_id }
    let prediction_id: String
    let created_at: Date
    let model_version: String?
    let top1_label: String?
    let top1_prob: Double?
    let top3: [ServerHistoryTop3]?
    let is_unknown: Bool
    let image_source: String?
    let network_type: String?
    let country_code: String?
    let city: String?
    let latency_ms: Int?
    let app_version: String?
    let feedback: ServerFeedback?
}

struct ServerHistoryTop3: Decodable {
    let label: String
    let conf: Double
}

struct ServerFeedback: Decodable {
    let is_correct: Bool
    let selected_label: String?
    let comment: String?
    let created_at: Date
}

