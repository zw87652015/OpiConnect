import Foundation
import WatchKit

@MainActor
final class RelayRegistration {
    struct Pairing: Equatable {
        let id: String
        let secret: String
    }

    static let shared = RelayRegistration(
        requestDeviceToken: { WKApplication.shared().registerForRemoteNotifications() },
        currentPairing: {
            let keys = PairingKeys.shared
            return Pairing(id: keys.pairId, secret: keys.secret)
        },
        register: { pairing, token in
            try await RelayClient.register(pairId: pairing.id, secret: pairing.secret, token: token)
        },
        updateStatus: { AppModel.shared.relayRegistered = $0 }
    )

    private let requestDeviceToken: () -> Void
    private let currentPairing: () -> Pairing
    private let register: (Pairing, String) async throws -> Void
    private let updateStatus: (Bool) -> Void
    private let retryDelays: [Duration]

    private var started = false
    private var registered = false
    private var deviceToken: String?
    private var registrationTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retryIndex = 0

    init(requestDeviceToken: @escaping () -> Void,
         currentPairing: @escaping () -> Pairing,
         register: @escaping (Pairing, String) async throws -> Void,
         updateStatus: @escaping (Bool) -> Void,
         retryDelays: [Duration] = [.seconds(3), .seconds(10), .seconds(30)]) {
        self.requestDeviceToken = requestDeviceToken
        self.currentPairing = currentPairing
        self.register = register
        self.updateStatus = updateStatus
        self.retryDelays = retryDelays
    }

    func start() {
        started = true
        resume()
    }

    func resume() {
        guard started, !registered, registrationTask == nil, retryTask == nil else { return }
        retryIndex = 0
        attemptRegistration()
    }

    func retryNow() {
        retryTask?.cancel()
        retryTask = nil
        resume()
    }

    func receivedDeviceToken(_ data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        guard token != deviceToken else { return }
        deviceToken = token
        setRegistered(false)
        retryNow()
    }

    // Let an in-flight registration finish before removing the old pairing.
    func pairingDidReset(unregister: @escaping () async -> Void) {
        let previous = registrationTask
        setRegistered(false)
        retryNow()
        Task {
            await previous?.value
            await unregister()
        }
    }

    private func attemptRegistration() {
        guard let token = deviceToken else {
            // APNs may leave the request pending while the watch is offline.
            scheduleRetry()
            requestDeviceToken()
            return
        }
        let pairing = currentPairing()
        registrationTask = Task {
            defer {
                registrationTask = nil
                if !isCurrent(pairing, token) { resume() }
            }
            do {
                try await register(pairing, token)
                guard isCurrent(pairing, token) else { return }
                setRegistered(true)
            } catch {
                guard isCurrent(pairing, token) else { return }
                let error = error as NSError
                NSLog("[opi] relay registration failed: \(error.domain) \(error.code)")
                scheduleRetry()
            }
        }
    }

    private func isCurrent(_ pairing: Pairing, _ token: String) -> Bool {
        token == deviceToken && pairing == currentPairing()
    }

    private func scheduleRetry() {
        guard retryIndex < retryDelays.count else { return }
        let delay = retryDelays[retryIndex]
        retryIndex += 1
        retryTask = Task {
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            retryTask = nil
            attemptRegistration()
        }
    }

    private func setRegistered(_ value: Bool) {
        guard registered != value else { return }
        registered = value
        updateStatus(value)
    }
}
