import Foundation
import UIKit
import Combine

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [HistoryEntry] = []

    // Persistence
    private let fileManager = FileManager.default
    private let baseURL: URL
    private let imagesURL: URL
    private let indexURL: URL
    private let maxEntries = 200

    private init() {
        // Prepare directories
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        baseURL = docs.appendingPathComponent("History", isDirectory: true)
        imagesURL = baseURL.appendingPathComponent("images", isDirectory: true)
        indexURL = baseURL.appendingPathComponent("index.json")

        // Ensure folders exist
        try? fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: true, attributes: nil)

        // Load persisted entries
        loadFromDisk()
    }

    // MARK: - Public API

    func add(image: UIImage,
             predictions: [Prediction],
             isUnknown: Bool,
             maxConfidence: Double,
             predictionId: String) async {
        // Persist image as JPEG
        let id = UUID()
        let filename = "\(id.uuidString).jpg"
        let imageURL = imagesURL.appendingPathComponent(filename)

        let jpegData = image.jpegData(compressionQuality: 0.85) ?? image.pngData() ?? Data()
        try? jpegData.write(to: imageURL, options: [.atomic])

        let entry = HistoryEntry(
            id: id,
            date: Date(),
            imageFilename: filename,
            predictions: predictions,
            isUnknown: isUnknown,
            maxConfidence: maxConfidence,
            isConfirmedCorrect: false,
            predictionId: predictionId
        )

        entries.insert(entry, at: 0)
        trimIfNeeded()
        saveToDisk()
    }

    func clear() {
        entries.removeAll()
        // Remove persisted files
        try? fileManager.removeItem(at: baseURL)
        try? fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: true, attributes: nil)
        saveToDisk()
    }

    func image(for entry: HistoryEntry) -> UIImage? {
        let url = imagesURL.appendingPathComponent(entry.imageFilename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    // Helper for server history merging
    func thumbnail(predictionId: String) -> UIImage? {
        guard let entry = entries.first(where: { $0.predictionId == predictionId }) else { return nil }
        return image(for: entry)
    }

    func markConfirmed(entryID: UUID) {
        if let idx = entries.firstIndex(where: { $0.id == entryID }) {
            var e = entries[idx]
            e.isConfirmedCorrect = true
            entries[idx] = e
            saveToDisk()
        }
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: indexURL) else {
            entries = []
            return
        }
        do {
            let decoded = try JSONDecoder().decode([HistoryEntry.CodableEntry].self, from: data)
            let mapped = decoded.map { $0.toEntry() }
            // Keep most-recent-first invariant
            entries = mapped.sorted(by: { $0.date > $1.date })
        } catch {
            entries = []
        }
    }

    private func saveToDisk() {
        let codable = entries.map { HistoryEntry.CodableEntry(from: $0) }
        do {
            let data = try JSONEncoder().encode(codable)
            try data.write(to: indexURL, options: [.atomic])
        } catch {
            // ignore write failures
        }
    }

    private func trimIfNeeded() {
        if entries.count > maxEntries {
            // Remove the tail entries and their images
            let toRemove = entries.suffix(from: maxEntries)
            for e in toRemove {
                let url = imagesURL.appendingPathComponent(e.imageFilename)
                try? fileManager.removeItem(at: url)
            }
            entries = Array(entries.prefix(maxEntries))
        }
    }
}

struct HistoryEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    let imageFilename: String
    let predictions: [Prediction]
    let isUnknown: Bool
    let maxConfidence: Double
    var isConfirmedCorrect: Bool
    let predictionId: String

    // Codable helpers to avoid embedding raw images in JSON
    struct CodableEntry: Codable {
        let id: UUID
        let date: Date
        let imageFilename: String
        let predictions: [Prediction]
        let isUnknown: Bool
        let maxConfidence: Double
        let isConfirmedCorrect: Bool
        let predictionId: String

        init(from entry: HistoryEntry) {
            id = entry.id
            date = entry.date
            imageFilename = entry.imageFilename
            predictions = entry.predictions
            isUnknown = entry.isUnknown
            maxConfidence = entry.maxConfidence
            isConfirmedCorrect = entry.isConfirmedCorrect
            predictionId = entry.predictionId
        }

        func toEntry() -> HistoryEntry {
            HistoryEntry(
                id: id,
                date: date,
                imageFilename: imageFilename,
                predictions: predictions,
                isUnknown: isUnknown,
                maxConfidence: maxConfidence,
                isConfirmedCorrect: isConfirmedCorrect,
                predictionId: predictionId
            )
        }
    }
}

