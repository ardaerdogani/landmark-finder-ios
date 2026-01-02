// New file suggestion: HistoryViewModel.swift
import Foundation
import UIKit
import Combine

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var items: [MergedHistoryItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var reachedEnd = false

    private let historyService = HistoryService()
    private let store = HistoryStore.shared
    private var nextPage: Int? = 1
    private let pageSize: Int = 20

    func refresh() async {
        nextPage = 1
        reachedEnd = false
        items = []
        await loadMoreIfNeeded(currentItem: nil)
    }

    func loadMoreIfNeeded(currentItem item: MergedHistoryItem?) async {
        guard !isLoading, !reachedEnd, let page = nextPage else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let pageResp = try await historyService.fetch(page: page, pageSize: pageSize)
            let merged = pageResp.items.map { server in
                let thumbnail = store.thumbnail(predictionId: server.prediction_id)
                let top3 = (server.top3 ?? []).map { Prediction(label: $0.label, confidence: $0.conf) }
                return MergedHistoryItem(
                    predictionId: server.prediction_id,
                    createdAt: server.created_at,
                    isUnknown: server.is_unknown,
                    top3: top3,
                    feedback: server.feedback,
                    thumbnail: thumbnail
                )
            }
            if page == 1 {
                items = merged
            } else {
                items.append(contentsOf: merged)
            }
            if pageResp.has_more, let np = pageResp.next_page {
                nextPage = np
            } else {
                nextPage = nil
                reachedEnd = true
            }
        } catch {
            // On error, stop pagination but keep existing items.
            reachedEnd = true
        }
    }
}

struct MergedHistoryItem: Identifiable {
    var id: String { predictionId }
    let predictionId: String
    let createdAt: Date
    let isUnknown: Bool
    let top3: [Prediction]
    let feedback: ServerFeedback?
    let thumbnail: UIImage?
}
