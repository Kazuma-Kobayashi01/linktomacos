package com.linktomacos.android.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
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
