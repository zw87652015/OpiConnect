import XCTest
import CryptoKit
@testable import OpiConnect_Watch_App

final class VectorTests: XCTestCase {
    struct Vectors: Decodable {
        let masterKeyHex: String
        let qr: String
        let pairId: String
        let secret: String
        let encKeyHex: String
        let seal: [Seal]
        let notificationId: NotifId
        let chunking: Chunking
        struct Seal: Decodable {
            let nonceHex: String
            let plaintext: String
            let sealedBase64url: String
        }
        struct NotifId: Decodable {
            let sbnKey: String
            let id: String
        }
        struct Chunking: Decodable {
            let maxLen: Int
            let chunksHex: [String]
        }
    }

    private var vectors: Vectors!
    private var key: SymmetricKey!

    override func setUpWithError() throws {
        // docs/test-vectors.json lives at the repo root, relative to this file.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // OpiConnectTests
            .deletingLastPathComponent()   // watch
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("docs/test-vectors.json")
        vectors = try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
        key = SymmetricKey(data: Data(hex: vectors.masterKeyHex))
    }

    func testDerivations() throws {
        XCTAssertEqual("opi1:" + key.withUnsafeBytes { OpiCrypto.base64url(Data($0)) }, vectors.qr)
        XCTAssertEqual(OpiCrypto.base64url(OpiCrypto.hkdf(key: key, info: "opi/id", count: 16)), vectors.pairId)
        XCTAssertEqual(OpiCrypto.base64url(OpiCrypto.hkdf(key: key, info: "opi/auth", count: 32)), vectors.secret)
        XCTAssertEqual(OpiCrypto.hkdf(key: key, info: "opi/enc", count: 32).hexString, vectors.encKeyHex)
    }

    func testSealVectors() throws {
        let encKey = SymmetricKey(data: Data(hex: vectors.encKeyHex))
        for v in vectors.seal {
            let sealed = try XCTUnwrap(OpiCrypto.base64urlDecode(v.sealedBase64url))
            // open
            let opened = try OpiCrypto.open(sealed, using: encKey)
            XCTAssertEqual(String(decoding: opened, as: UTF8.self), v.plaintext)
            // re-seal with the fixed nonce reproduces the exact bytes
            let nonce = try AES.GCM.Nonce(data: Data(hex: v.nonceHex))
            let resealed = try OpiCrypto.seal(Data(v.plaintext.utf8), using: encKey, nonce: nonce)
            XCTAssertEqual(OpiCrypto.base64url(resealed), v.sealedBase64url)
        }
    }

    func testChunkingVector() throws {
        let encKey = SymmetricKey(data: Data(hex: vectors.encKeyHex))
        let sealed = try XCTUnwrap(OpiCrypto.base64urlDecode(vectors.seal[1].sealedBase64url))
        let chunks = Chunker.split(sealed, maxLen: vectors.chunking.maxLen)
        XCTAssertEqual(chunks.map { $0.hexString }, vectors.chunking.chunksHex)
        let r = Reassembler()
        var out: Data?
        for chunk in chunks.dropLast() { XCTAssertNil(r.push(chunk)) }
        out = r.push(chunks.last!)
        XCTAssertEqual(out, sealed)
        XCTAssertEqual(String(decoding: try OpiCrypto.open(out!, using: encKey), as: UTF8.self),
                       vectors.seal[1].plaintext)
    }

    func testNotificationId() throws {
        let digest = OpiCrypto.sha256(Data(vectors.notificationId.sbnKey.utf8))
        XCTAssertEqual(String(OpiCrypto.base64url(digest).prefix(22)), vectors.notificationId.id)
    }

    func testPayloadRoundTrip() throws {
        let text = vectors.seal[0].plaintext
        let payload = try JSONDecoder().decode(NotifPayload.self, from: Data(text.utf8))
        XCTAssertEqual(payload.a, "示例应用")
        XCTAssertTrue(payload.b.contains("👋"))
        XCTAssertEqual(payload.x?.count, 2)
        let reparsed = NotifPayload(jsonObject: payload.jsonObject)
        XCTAssertEqual(reparsed, payload)
    }

    func testCategoryIds() throws {
        let payload = try JSONDecoder().decode(NotifPayload.self, from: Data(vectors.seal[0].plaintext.utf8))
        let noActions = NotifPayload(i: "x", p: "p", a: "a", t: "t", b: "b", w: 0, x: nil)
        XCTAssertEqual(Categories.categoryId(for: noActions), "opi.none")
        let id1 = Categories.categoryId(for: payload)
        XCTAssertEqual(id1, Categories.categoryId(for: payload))
        XCTAssertTrue(id1.hasPrefix("opi.a."))
        var changed = payload
        changed.x = [OpiAction(l: "other", r: false)]
        XCTAssertNotEqual(id1, Categories.categoryId(for: changed))
    }
}

extension Data {
    init(hex: String) {
        var data = Data()
        var i = hex.startIndex
        while i < hex.endIndex {
            let byte = UInt8(hex[i...hex.index(after: i)], radix: 16)!
            data.append(byte)
            i = hex.index(i, offsetBy: 2)
        }
        self = data
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
