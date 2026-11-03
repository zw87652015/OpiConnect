package com.opiconnect.companion.core

// BLE chunking per docs/PROTOCOL.md:
// chunk = [flag byte: 0x01 more follow, 0x00 last] + up to (maxLen - 1) bytes of sealed data.
object Chunker {
    fun split(sealed: ByteArray, maxLen: Int): List<ByteArray> {
        require(maxLen >= 2)
        val chunks = ArrayList<ByteArray>()
        var offset = 0
        while (offset < sealed.size) {
            val end = minOf(offset + maxLen - 1, sealed.size)
            val chunk = ByteArray(1 + end - offset)
            chunk[0] = if (end >= sealed.size) 0x00 else 0x01
            System.arraycopy(sealed, offset, chunk, 1, end - offset)
            chunks.add(chunk)
            offset = end
        }
        return chunks
    }
}

// Reassembles inbound chunks; push() returns the complete message on a 0x00 flag.
class Reassembler {
    private var buffer = ByteArray(0)

    fun push(chunk: ByteArray): ByteArray? {
        if (chunk.isEmpty() || (chunk[0] != 0.toByte() && chunk[0] != 1.toByte())) {
            buffer = ByteArray(0)
            return null
        }
        buffer += chunk.copyOfRange(1, chunk.size)
        if (chunk[0] == 0.toByte()) {
            val out = buffer
            buffer = ByteArray(0)
            return out
        }
        return null
    }

    fun reset() {
        buffer = ByteArray(0)
    }
}
