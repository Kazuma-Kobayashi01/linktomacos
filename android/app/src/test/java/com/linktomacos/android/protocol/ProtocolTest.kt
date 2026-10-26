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
    fun deviceStatusExtrasAreOptionalAndBackwardCompatible() {
        // 旧版本手机发来的状态没有新字段，新版 Mac 仍要能解析；反过来新字段对旧版 Mac 是被忽略的未知字段
        val old = MessageCodec.decode(
            """{"type":"deviceStatus","batteryLevel":50,"charging":false,"wifiConnected":true,"storageTotal":10,"storageFree":5,"timestamp":1}""")
        old as DeviceStatus
        assertNull(old.batteryTemperature)
        assertNull(old.memoryTotal)
        val full = DeviceStatus(
            80, true, 3, "5G", "CMHK", true, 512, 100, 1,
            batteryTemperature = 31.5, batteryVoltage = 4200, batteryHealth = "good", chargingType = "ac",
            memoryTotal = 12L shl 30, memoryAvailable = 5L shl 30, wifiLevel = 4, wifiLinkSpeed = 866, signalDbm = -92, uptime = 123456,
        )
        assertEquals(full, MessageCodec.decode(MessageCodec.encode(full)))
        assertTrue(MessageCodec.encode(full).contains("\"batteryTemperature\":31.5"))
    }

    @Test
    fun mirrorMessagesRoundTrip() {
        val touch = MirrorInput(k = "t", a = 0, x = 0.25, y = 0.75)
        assertEquals(touch, MessageCodec.decode(MessageCodec.encode(touch)))
        val key = MirrorInput(k = "key", a = 1, c = 66, m = 0x1000)
        assertEquals(key, MessageCodec.decode(MessageCodec.encode(key)))
        val resized = MirrorEvent("resized", 1080, 2312, 1080, 2316, 1)
        assertEquals(resized, MessageCodec.decode(MessageCodec.encode(resized)))
        // Swift 端编码出的 null 字段
        val fromSwift = MessageCodec.decode("""{"type":"mirrorInput","k":"s","x":0.5,"y":0.5,"v":-1.5,"a":null,"text":null}""") as MirrorInput
        assertEquals("s", fromSwift.k)
        assertEquals(-1.5, fromSwift.v!!, 0.0)
    }

    @Test
    fun callStateRoundTripsAndToleratesMissingName() {
        val ringing = CallState("ringing", "张三", 1_700_000_000_000)
        assertEquals(ringing, MessageCodec.decode(MessageCodec.encode(ringing)))
        assertEquals(
            CallState("idle", null, 5),
            MessageCodec.decode("""{"type":"callState","state":"idle","name":null,"timestamp":5}"""),
        )
    }

    @Test
    fun clipboardTextRoundTripsWithSpecialCharacters() {
        val clip = ClipboardText("第一行\n\"引号\" 😀\t末尾", 42)
        assertEquals(clip, MessageCodec.decode(MessageCodec.encode(clip)))
        // Swift 端不一定带 timestamp
        assertEquals(ClipboardText("x", 0), MessageCodec.decode("""{"type":"clipboard","text":"x"}"""))
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
