import Foundation

enum APIError: Error {
    case invalidURL
    case http(Int, Data?)
    case decoding(Error)
    case noRefreshToken
    case unauthorizedUserDeleted // /v1/me 401 User not found gibi
}

// Placeholder for requests without a body
private struct EmptyEncodable: Encodable {}

final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let tokens = AuthTokenStore.shared

    private var isRefreshing = false
    private var refreshWaiters: [CheckedContinuation<Void, Error>] = []

    private init() {
        let config = URLSessionConfiguration.default
        self.session = URLSession(configuration: config)
    }

    // Generic JSON request
    func request<T: Decodable, Body: Encodable>(
        method: String,
        path: String,
        body: Body? = nil,
        requiresAuth: Bool = false,
        retryOn401: Bool = true,
        headers: [String: String] = [:],
        queryItems: [URLQueryItem] = []
    ) async throws -> T {

        var components = URLComponents(url: Endpoints.url(path), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty {
            if var c = components {
                var existing = c.queryItems ?? []
                existing.append(contentsOf: queryItems)
                c.queryItems = existing
                components = c
            }
        }
        guard let url = components?.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        if requiresAuth, let access = tokens.accessToken {
            req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            req.httpBody = try JSONEncoder().encode(body)
        }

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.http(-1, data) }

        // Success
        if (200..<300).contains(http.statusCode) {
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        }

        // 401 handling
        if http.statusCode == 401, requiresAuth, retryOn401 {
            try await refreshIfNeeded()
            // retry once with new access token
            return try await request(
                method: method, path: path, body: body,
                requiresAuth: requiresAuth, retryOn401: false, headers: headers, queryItems: queryItems
            )
        }

        // özel case: /v1/me 401 user not found => kullanıcı silinmiş
        if http.statusCode == 401, path == Endpoints.User.me {
            throw APIError.unauthorizedUserDeleted
        }

        throw APIError.http(http.statusCode, data)
    }

    // No-body overload
    func request<T: Decodable>(
        method: String,
        path: String,
        requiresAuth: Bool = false,
        retryOn401: Bool = true,
        headers: [String: String] = [:],
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        return try await request(
            method: method,
            path: path,
            body: Optional<EmptyEncodable>.none,
            requiresAuth: requiresAuth,
            retryOn401: retryOn401,
            headers: headers,
            queryItems: queryItems
        )
    }

    // MARK: - Multipart upload

    struct MultipartPart {
        let name: String
        let filename: String?
        let contentType: String?
        let data: Data
    }

    func uploadMultipart<T: Decodable>(
        path: String,
        parts: [MultipartPart],
        requiresAuth: Bool = false,
        retryOn401: Bool = true,
        headers: [String: String] = [:],
        queryItems: [URLQueryItem] = []
    ) async throws -> T {

        let boundary = "Boundary-\(UUID().uuidString)"
        var components = URLComponents(url: Endpoints.url(path), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty {
            if var c = components {
                var existing = c.queryItems ?? []
                existing.append(contentsOf: queryItems)
                c.queryItems = existing
                components = c
            }
        }
        guard let url = components?.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        if requiresAuth, let access = tokens.accessToken {
            req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        }

        req.httpBody = makeMultipartBody(boundary: boundary, parts: parts)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.http(-1, data) }

        if (200..<300).contains(http.statusCode) {
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        }

        if http.statusCode == 401, requiresAuth, retryOn401 {
            try await refreshIfNeeded()
            return try await uploadMultipart(
                path: path,
                parts: parts,
                requiresAuth: requiresAuth,
                retryOn401: false,
                headers: headers,
                queryItems: queryItems
            ) as T
        }

        throw APIError.http(http.statusCode, data)
    }

    private func makeMultipartBody(boundary: String, parts: [MultipartPart]) -> Data {
        var body = Data()
        let lineBreak = "\r\n"

        for part in parts {
            body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
            if let filename = part.filename, let contentType = part.contentType {
                body.append("Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(filename)\"\(lineBreak)".data(using: .utf8)!)
                body.append("Content-Type: \(contentType)\(lineBreak)\(lineBreak)".data(using: .utf8)!)
            } else {
                body.append("Content-Disposition: form-data; name=\"\(part.name)\"\(lineBreak)\(lineBreak)".data(using: .utf8)!)
            }
            body.append(part.data)
            body.append(lineBreak.data(using: .utf8)!)
        }

        body.append("--\(boundary)--\(lineBreak)".data(using: .utf8)!)
        return body
    }

    // MARK: - Refresh

    private func refreshIfNeeded() async throws {
        // Zaten refresh ediliyorsa bekle
        if isRefreshing {
            try await withCheckedThrowingContinuation { cont in
                refreshWaiters.append(cont)
            }
            return
        }

        guard let refresh = tokens.getRefreshToken() else {
            tokens.clearAll()
            throw APIError.noRefreshToken
        }

        isRefreshing = true
        defer {
            isRefreshing = false
        }

        do {
            let resp: TokenResponse = try await request(
                method: "POST",
                path: Endpoints.Auth.refresh,
                body: RefreshRequest(refresh_token: refresh),
                requiresAuth: false,
                retryOn401: false
            )
            // rotate: eski refresh'i ASLA tekrar kullanma
            tokens.setAccessToken(resp.access_token)
            tokens.setRefreshToken(resp.refresh_token)

            // bekleyenleri serbest bırak
            let waiters = refreshWaiters
            refreshWaiters.removeAll()
            waiters.forEach { $0.resume() }
        } catch {
            // refresh başarısızsa local tokenları temizle
            tokens.clearAll()
            let waiters = refreshWaiters
            refreshWaiters.removeAll()
            waiters.forEach { $0.resume(throwing: error) }
            throw error
        }
    }
}
