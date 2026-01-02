import Foundation

enum Endpoints {
    static var baseURL: URL = URL(string: "http://localhost:8000")!

    static func url(_ path: String) -> URL {
        baseURL.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path)
    }

    enum Auth {
        static let register = "/v1/auth/register"
        static let login    = "/v1/auth/login"
        static let refresh  = "/v1/auth/refresh"
        static let logout   = "/v1/auth/logout"
        static let google   = "/v1/auth/google"
    }

    enum User {
        static let me = "/v1/me"
        static let devices = "/v1/me/devices"
    }

    enum Predictions {
        static let predict = "/v1/predict"
        static func feedback(_ predictionId: String) -> String {
            "/v1/predictions/\(predictionId)/feedback"
        }
    }

    // (Opsiyonel) Landmark events için
    enum Events {
        static let prediction = "/v1/predictions"
        static let feedback   = "/v1/feedback"
    }
}

