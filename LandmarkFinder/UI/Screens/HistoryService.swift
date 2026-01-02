// New file suggestion: HistoryService.swift
import Foundation

final class HistoryService {
    private let api = APIClient.shared

    func fetch(page: Int = 1, pageSize: Int = 20) async throws -> ServerHistoryPage {
        let query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(pageSize))
        ]

        // Use a custom decoder with ISO8601 for this endpoint
        var components = URLComponents(url: Endpoints.url("/v1/predictions/history"), resolvingAgainstBaseURL: false)
        if var c = components {
            var existing = c.queryItems ?? []
            existing.append(contentsOf: query)
            c.queryItems = existing
            components = c
        }
        guard let url = components?.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        // Auth header will be set by APIClient if we go through it,
        // but since we are custom-decoding here, we set it ourselves:
        if let access = AuthTokenStore.shared.accessToken {
            req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.http(-1, data) }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode, data) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ServerHistoryPage.self, from: data)
    }
}
