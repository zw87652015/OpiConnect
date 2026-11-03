import Foundation

// BLE chunking per docs/PROTOCOL.md:
// chunk = [flag byte: 0x01 more follow, 0x00 last] + up to (maxLen - 1) bytes of sealed data.
enum Chunker {
    static func split(_ sealed: Data, maxLen: Int) -> [Data] {
        precondition(maxLen >= 2)
        var chunks: [Data] = []
        var offset = 0
        while offset < sealed.count {
            let part = sealed.subdata(in: offset ..< min(offset + maxLen - 1, sealed.count))
            offset += maxLen - 1
            var chunk = Data([offset >= sealed.count ? 0x00 : 0x01])
            chunk.append(part)
            chunks.append(chunk)
        }
        return chunks
    }
}

// Reassembles inbound chunks; push() returns the complete message on a 0x00 flag.
final class Reassembler {
    private var buffer = Data()

    func push(_ chunk: Data) -> Data? {
        guard let flag = chunk.first, flag == 0x00 || flag == 0x01 else {
            buffer.removeAll()
            return nil
        }
        buffer.append(chunk.dropFirst())
        if flag == 0x00 {
            defer { buffer.removeAll() }
            return buffer
        }
        return nil
    }

    func reset() { buffer.removeAll() }
}
