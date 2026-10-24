package com.linktomacos.android.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream

class ProtocolTest {
    @Test
    fun roundTripsThroughFrames() {
        val messages = listOf(
            Hello(deviceId = "id", deviceName = "S23U", model = "SM-S9180", osVersion = "15", appVersion = "0.1"),
            HelloAck(accepted = true, macName = "Mac"),
            Ping(1), Pong(2), Goodbye("quit"),
            DeviceStatus(80, true, 3, "5G", "CMHK", true, 512, 100, 1),
            PhoneNotification("k", "com.x", "X", "标题", "内容", null, 1, "AAAA"),
            NotificationRemoved("k"),
        )
        val bytes = ByteArrayOutputStream()
        DataOutputStream(bytes).use { out -> messages.forEach { Frames.write(out, it) } }
        val input = DataInputStream(ByteArrayInputStream(bytes.toByteArray()))
        messages.forEach { assertEquals(it, Frames.read(input)) }
    }

    @Test
    fun matchesSwiftJsonShape() {
        // Swift 端编码出的 ping / helloAck
        assertEquals(Ping(42), MessageCodec.decode("""{"t":42,"type":"ping"}"""))
        assertEquals(HelloAck(true, "Mac"), MessageCodec.decode("""{"type":"helloAck","accepted":true,"macName":"Mac"}"""))
        val encoded = MessageCodec.encode(Goodbye("sleep"))
        assertTrue(encoded.contains("\"type\":\"goodbye\""))
        assertTrue(encoded.contains("\"reason\":\"sleep\""))
    }

    @Test
    fun binaryFramesRoundTrip() {
        val payload = ByteArray(1000) { (it % 251).toByte() }
        val bytes = ByteArrayOutputStream()
        DataOutputStream(bytes).use { out ->
            Frames.write(out, DataChunk(0x01020304, payload, 600))
            Frames.write(out, StreamEnd(7, true))
        }
        val raw = bytes.toByteArray()
        // [长度 = 600 + 5][0x01][streamId 大端]
        assertEquals(605, ((raw[0].toInt() and 0xFF) shl 24) or ((raw[1].toInt() and 0xFF) shl 16) or
            ((raw[2].toInt() and 0xFF) shl 8) or (raw[3].toInt() and 0xFF))
        assertEquals(BINARY_FRAME_MARKER, raw[4].toInt())
        val input = DataInputStream(ByteArrayInputStream(raw))
        val chunk = Frames.read(input) as DataChunk
        assertEquals(0x01020304, chunk.streamId)
        assertEquals(payload.copyOfRange(0, 600).toList(), chunk.bytes.toList())
        assertEquals(StreamEnd(7, true), Frames.read(input))
    }

    @Test
    fun requestAndResponseMatchSwiftShape() {
        val request = MessageCodec.decode(
            """{"type":"request","id":4,"method":"listMedia","params":{"offset":0,"limit":300,"kind":"image","album":null}}""")
        request as Request
        assertEquals(4, request.id)
        assertEquals("listMedia", request.method)
        assertEquals("image", request.params["kind"]!!.jsonPrimitive.content)
        val ok = MessageCodec.encode(Response(4, true, buildJsonObject { put("total", 3) }))
        assertTrue(ok.contains("\"type\":\"response\""))
        assertTrue(ok.contains("\"result\":{\"total\":3}"))
        val failed = MessageCodec.decode(MessageCodec.encode(Response(5, false, null, "没有权限")))
        assertEquals(Response(5, false, null, "没有权限"), failed)
    }

    @Test
    fun unknownTypeIsTolerated() {
        assertEquals(Unknown("future"), MessageCodec.decode("""{"type":"future","x":1}"""))
    }

    @Test
    fun parsesPairingUri() {
        // 与 Swift URLComponents 生成的格式一致（空格、中文按百分号编码）
        val uri = "linktomacos://pair?v=1&n=Jackson%E7%9A%84%20MacBook&h=192.168.1.2,10.0.0.3&p=47152&fp=AB12&t=cd"
        val payload = PairingPayload.parse(uri)!!
        assertEquals("Jackson的 MacBook", payload.macName)
        assertEquals(listOf("192.168.1.2", "10.0.0.3"), payload.hosts)
        assertEquals(47152, payload.port)
        assertEquals("ab12", payload.fingerprint)
        assertNull(PairingPayload.parse("https://example.com"))
    }
}
