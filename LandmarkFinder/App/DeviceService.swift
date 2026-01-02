import Foundation

final class DeviceService {
    private let api = APIClient.shared

    struct RegisterDeviceRequest: Codable {
        let device_id: String
        let platform: String
        let device_model: String
        let os_version: String
    }

    struct RegisterDeviceResponse: Codable {
        let ok: Bool?
    }

    func registerDevice(deviceId: String,
                        platform: String,
                        deviceModel: String,
                        osVersion: String) async throws {
        let body = RegisterDeviceRequest(
            device_id: deviceId,
            platform: platform,
            device_model: deviceModel,
            os_version: osVersion
        )
        // We don't care about the response content; decode to a trivial type.
        _ = try await api.request(
            method: "POST",
            path: Endpoints.User.devices,
            body: body,
            requiresAuth: true
        ) as RegisterDeviceResponse
    }
}

