import XCTest
@testable import OpiConnect_Watch_App

@MainActor
final class RelayRegistrationTests: XCTestCase {
    private let pairing = RelayRegistration.Pairing(id: "pair", secret: "secret")

    func testFirstLaunchRecoversFromMissingTokenAndFailedRelayRequest() async {
        let tokenRetried = expectation(description: "APNs token request retried")
        let registered = expectation(description: "relay confirmed registration")
        var tokenRequests = 0
        var relayRequests = 0
        let registration = RelayRegistration(
            requestDeviceToken: {
                tokenRequests += 1
                if tokenRequests == 2 { tokenRetried.fulfill() }
            },
            currentPairing: { self.pairing },
            register: { pairing, token in
                XCTAssertEqual(pairing, self.pairing)
                XCTAssertEqual(token, "01ab")
                relayRequests += 1
                if relayRequests == 1 { throw URLError(.notConnectedToInternet) }
            },
            updateStatus: { success in
                XCTAssertTrue(success)
                XCTAssertEqual(relayRequests, 2)
                registered.fulfill()
            },
            retryDelays: [.zero]
        )

        registration.start()
        await fulfillment(of: [tokenRetried], timeout: 3)
        registration.receivedDeviceToken(Data([0x01, 0xab]))
        await fulfillment(of: [registered], timeout: 3)
        XCTAssertEqual(tokenRequests, 2)
    }

    func testPairingRetriesAfterLaunchAttemptsAreExhausted() async {
        let initialAttempt = expectation(description: "first request failed")
        let registered = expectation(description: "pairing triggered a successful retry")
        var relayRequests = 0
        let registration = RelayRegistration(
            requestDeviceToken: {},
            currentPairing: { self.pairing },
            register: { _, _ in
                relayRequests += 1
                if relayRequests == 1 {
                    initialAttempt.fulfill()
                    throw URLError(.timedOut)
                }
            },
            updateStatus: { success in
                XCTAssertTrue(success)
                registered.fulfill()
            },
            retryDelays: []
        )

        registration.start()
        registration.receivedDeviceToken(Data([0xab]))
        await fulfillment(of: [initialAttempt], timeout: 3)
        registration.retryNow()
        await fulfillment(of: [registered], timeout: 3)
        XCTAssertEqual(relayRequests, 2)
    }
}
