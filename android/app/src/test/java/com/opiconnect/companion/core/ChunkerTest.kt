package com.opiconnect.companion.core

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ChunkerTest {

    @Test
    fun vector() {
        val vectors = Vectors.root
        val sealed = Crypto.base64urlDecode(
            vectors.getJSONArray("seal").getJSONObject(1).getString("sealedBase64url"),
        )
        val maxLen = vectors.getJSONObject("chunking").getInt("maxLen")
        val expected = vectors.getJSONObject("chunking").getJSONArray("chunksHex")
            .let { arr -> (0 until arr.length()).map { arr.getString(it) } }

        val chunks = Chunker.split(sealed, maxLen)
        assertEquals(expected.size, chunks.size)
        chunks.forEachIndexed { i, chunk ->
            assertEquals(expected[i], chunk.joinToString("") { "%02x".format(it) })
        }

        val r = Reassembler()
        for (chunk in chunks.dropLast(1)) {
            assertNull(r.push(chunk))
        }
        assertArrayEquals(sealed, r.push(chunks.last()))
    }

    @Test
    fun roundTrip() {
        val data = ByteArray(500) { it.toByte() }
        val chunks = Chunker.split(data, 20)
        val r = Reassembler()
        var out: ByteArray? = null
        for (chunk in chunks) {
            out = r.push(chunk)
        }
        assertArrayEquals(data, out)
    }

    @Test
    fun singleChunk() {
        val data = ByteArray(10) { it.toByte() }
        val chunks = Chunker.split(data, 64)
        assertEquals(1, chunks.size)
        assertEquals(0x00.toByte(), chunks[0][0])
        assertArrayEquals(data, Reassembler().push(chunks[0]))
    }
}
