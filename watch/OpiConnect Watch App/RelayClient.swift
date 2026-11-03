import Foundation

enum RelayClient {
    private static var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "OpiRelayURL") as? String ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func post(_ route: String, _ body: [String: Any]) async throws {
        guard let url = URL(string: baseURL + route) else { throw CocoaError(.coderInvalidValue) }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "OpiRelay", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? ""])
        }
    }

    static func register(token: String, env: String) async throws {
        try await post("/v1/register", [
            "pairId": PairingKeys.shared.pairId,
            "secret": PairingKeys.shared.secret,
            "token": token,
            "env": env,
        ])
    }

    static func unregister(pairId: String, secret: String) async throws {
        try await post("/v1/unregister", [
            "pairId": pairId,
            "secret": secret,
        ])
    }
}
