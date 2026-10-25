package com.linktomacos.android.shell

import com.linktomacos.android.mirror.EnhancedBridge
import com.linktomacos.android.mirror.SHELL_VERSION
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ShellHandshakeTest {
    @Test
    fun hmacMatchesRfc4231TestCase1() {
        val key = ByteArray(20) { 0x0b }
        val expected = "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
        assertEquals(expected, Link.hex(Link.hmac(key, "Hi There".toByteArray())))
        assertEquals(expected, EnhancedBridge.hmac(key, "Hi There".toByteArray()).joinToString("") { "%02x".format(it) })
    }

    /** App（Kotlin）和 shell 服务（Java）各算一遍，结果必须逐字节一致，否则握手永远失败。 */
    @Test
    fun appAndShellComputeTheSameMac() {
        val secret = ByteArray(32) { (it * 7 + 3).toByte() }
        val nonce = "00112233445566778899aabbccddeeff".toByteArray()
        assertArrayEquals(Link.hmac(secret, nonce), EnhancedBridge.hmac(secret, nonce))
    }

    /** 两边的版本号必须一起改，否则 App 会一直认为服务是旧的。 */
    @Test
    fun shellVersionMatchesWhatTheAppExpects() {
        assertEquals(SHELL_VERSION, ShellMain.VERSION)
    }

    @Test
    fun hexRoundTrips() {
        val bytes = ByteArray(256) { it.toByte() }
        assertArrayEquals(bytes, Link.fromHex(Link.hex(bytes)))
    }

    @Test
    fun differentSecretGivesDifferentMac() {
        val nonce = "abcd".toByteArray()
        assertFalse(EnhancedBridge.constantTimeEquals(Link.hmac(ByteArray(32) { 1 }, nonce), Link.hmac(ByteArray(32) { 2 }, nonce)))
        assertTrue(EnhancedBridge.constantTimeEquals(Link.hmac(ByteArray(32) { 1 }, nonce), Link.hmac(ByteArray(32) { 1 }, nonce)))
    }

    @Test
    fun fitKeepsAspectAndAlignsTo8() {
        // 你的手机：1080x2316 的逻辑尺寸，长边限制 1920
        val size = ScreenMirror.fit(1080, 2316, 1920)
        assertEquals(0, size[0] % 8)
        assertEquals(0, size[1] % 8)
        assertTrue(size[1] <= 1920 + 4)
        assertEquals(1080.0 / 2316.0, size[0].toDouble() / size[1], 0.01)
        // 不超过上限就不缩放
        assertEquals(listOf(720, 1280), ScreenMirror.fit(720, 1280, 1920).toList())
        // maxSize <= 0 表示不限制
        assertEquals(listOf(1080, 2312), ScreenMirror.fit(1080, 2312, 0).toList())
    }

    @Test
    fun sanitizeKeepsNewDisplaySizesValid() {
        // 太小的窗口也要给出编码器能接受的尺寸
        assertEquals(listOf(320, 320), ScreenMirror.sanitize(100, 100, 1920).toList())
        // 太大的按长边缩小
        val big = ScreenMirror.sanitize(4000, 2000, 1920)
        assertEquals(1920, big[0]); assertEquals(960, big[1])
        // 结果总是 8 的倍数
        val odd = ScreenMirror.sanitize(1001, 777, 1920)
        assertEquals(0, odd[0] % 8); assertEquals(0, odd[1] % 8)
    }
}
