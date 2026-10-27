package com.linktomacos.android.mirror

import android.content.Context
import android.util.Log
import androidx.core.content.edit
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

private const val TAG = "EnhancedBridge"
const val ENHANCED_PORT = 47153

/** App 需要的 shell 服务版本，和 ShellMain.VERSION 一致。服务进程重装 App 后不会自己重启，版本不对时要重新启动它。 */
const val SHELL_VERSION = 5
private const val TYPE_JSON = 1
private const val TYPE_VIDEO = 2
private const val TYPE_AUDIO = 3
private const val TYPE_MIC = 4
private const val MAX_FRAME = 4 * 1024 * 1024

/** 来自 shell 服务的一个视频或音频包。[flags]：1 = 配置（视频是 SPS/PPS，音频是 Opus 头），2 = 关键帧（只有视频）。 */
class VideoPacket(val flags: Int, val ptsUs: Long, val data: ByteArray) {
    val isConfig get() = flags and 1 != 0
    val isKey get() = flags and 2 != 0
}

interface ShellListener {
    fun onVideo(packet: VideoPacket)
    /** Opus 音频包（没有投屏音频时不会来）。 */
    fun onAudio(packet: VideoPacket) {}
    fun onEvent(event: JSONObject)
}

/**
 * 与 shell 服务（由 Mac 通过 USB 启动的常驻进程）的本机桥。
 *
 * App 在 127.0.0.1 上监听，shell 服务主动连进来。握手是挑战应答：shell 发随机数，这里用共享密钥算 HMAC-SHA256
 * 回应，验证通过后 shell 才接受指令。密钥只通过加密的 Mac 连接交给 Mac，再由 Mac 经 USB 交给 shell。
 */
class EnhancedBridge(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("mirror", Context.MODE_PRIVATE)
    val apkPath: String = context.applicationInfo.sourceDir

    val secretHex: String = prefs.getString("secret", null) ?: ByteArray(32).also { SecureRandom().nextBytes(it) }
        .joinToString("") { "%02x".format(it) }
        .also { generated -> prefs.edit { putString("secret", generated) } }

    private val _ready = MutableStateFlow(false)
    /** shell 服务当前是否已连接并通过验证。 */
    val ready: StateFlow<Boolean> = _ready.asStateFlow()

    private val _outdated = MutableStateFlow(false)
    /** 连上来的 shell 服务是旧版本（App 重装后它还在跑旧代码）。此时 [ready] 为 false。 */
    val outdated: StateFlow<Boolean> = _outdated.asStateFlow()

    @Volatile var listener: ShellListener? = null
    /** 手机上复制了文字（shell 服务在后台监听剪贴板）。 */
    @Volatile var onClipboard: ((String) -> Unit)? = null
    @Volatile private var connection: Connection? = null
    private var server: ServerSocket? = null

    @Synchronized
    fun start() {
        if (server != null) return
        try {
            server = ServerSocket(ENHANCED_PORT, 4, InetAddress.getByName("127.0.0.1")).also { socket ->
                Thread({ acceptLoop(socket) }, "enhanced-accept").apply { isDaemon = true }.start()
            }
        } catch (e: IOException) {
            Log.w(TAG, "cannot listen on $ENHANCED_PORT: $e")
        }
    }

    @Synchronized
    fun stop() {
        runCatching { server?.close() }
        server = null
        connection?.close()
    }

    /** 向 shell 服务发一条指令。未连接时返回 false。 */
    fun send(command: JSONObject): Boolean = connection?.send(command) ?: false

    /** 把 Mac 麦克风的 PCM 交给 shell 服务去注入。 */
    fun sendMic(pcm: ByteArray): Boolean = connection?.sendBinary(TYPE_MIC, pcm) ?: false

    private fun acceptLoop(socket: ServerSocket) {
        while (!socket.isClosed) {
            val client = try {
                socket.accept()
            } catch (e: IOException) {
                break
            }
            Thread({ serve(client) }, "enhanced-conn").apply { isDaemon = true }.start()
        }
    }

    private fun serve(socket: Socket) {
        val conn = Connection(socket)
        try {
            socket.tcpNoDelay = true
            socket.soTimeout = 5000
            val version = conn.handshake(secretHex)
            socket.soTimeout = 0
            connection?.close() // 只保留最新的一个
            connection = conn
            _outdated.value = version != SHELL_VERSION
            _ready.value = version == SHELL_VERSION
            Log.i(TAG, "shell service connected, version $version (expected $SHELL_VERSION)")
            conn.readLoop(
                onVideo = { listener?.onVideo(it) },
                onAudio = { listener?.onAudio(it) },
                onEvent = {
                    if (it.optString("t") == "clip") onClipboard?.invoke(it.optString("text")) else listener?.onEvent(it)
                },
            )
        } catch (e: Exception) {
            Log.d(TAG, "shell connection ended: $e")
        } finally {
            conn.close()
            if (connection === conn) {
                connection = null
                _ready.value = false
                _outdated.value = false
                listener?.onEvent(JSONObject().put("t", "disconnected"))
            }
        }
    }

    private class Connection(private val socket: Socket) {
        private val input = DataInputStream(BufferedInputStream(socket.getInputStream(), 64 * 1024))
        private val output = DataOutputStream(BufferedOutputStream(socket.getOutputStream(), 16 * 1024))

        /** 返回 shell 服务报告的版本。 */
        fun handshake(secretHex: String): Int {
            val hello = readJsonFrame()
            if (hello.optString("t") != "hello") throw IOException("bad hello")
            val nonce = hello.getString("nonce")
            val mac = hmac(secretHex.hexToBytes(), nonce.toByteArray())
            send(JSONObject().put("t", "auth").put("mac", mac.joinToString("") { "%02x".format(it) }))
            val ready = readJsonFrame()
            if (ready.optString("t") != "ready") throw IOException("shell did not accept")
            return hello.optInt("v", 0)
        }

        private fun readJsonFrame(): JSONObject {
            val type = input.readUnsignedByte()
            val length = input.readInt()
            if (type != TYPE_JSON || length < 0 || length > 64 * 1024) throw IOException("bad handshake frame")
            return JSONObject(String(ByteArray(length).also(input::readFully), Charsets.UTF_8))
        }

        fun readLoop(onVideo: (VideoPacket) -> Unit, onAudio: (VideoPacket) -> Unit, onEvent: (JSONObject) -> Unit) {
            while (true) {
                val type = input.readUnsignedByte()
                val length = input.readInt()
                if (length < 0 || length > MAX_FRAME) throw IOException("bad frame length $length")
                val body = ByteArray(length).also(input::readFully)
                when (type) {
                    TYPE_JSON -> onEvent(JSONObject(String(body, Charsets.UTF_8)))
                    TYPE_VIDEO, TYPE_AUDIO -> {
                        if (length < 9) continue
                        var pts = 0L
                        for (i in 1..8) pts = (pts shl 8) or (body[i].toLong() and 0xFF)
                        val packet = VideoPacket(body[0].toInt() and 0xFF, pts, body.copyOfRange(9, length))
                        if (type == TYPE_VIDEO) onVideo(packet) else onAudio(packet)
                    }
                }
            }
        }

        @Synchronized
        fun send(command: JSONObject): Boolean = try {
            val body = command.toString().toByteArray(Charsets.UTF_8)
            output.writeByte(TYPE_JSON)
            output.writeInt(body.size)
            output.write(body)
            output.flush()
            true
        } catch (e: IOException) {
            false
        }

        @Synchronized
        fun sendBinary(type: Int, body: ByteArray): Boolean = try {
            output.writeByte(type)
            output.writeInt(body.size)
            output.write(body)
            output.flush()
            true
        } catch (e: IOException) {
            false
        }

        fun close() {
            runCatching { socket.close() }
        }
    }

    companion object {
        fun hmac(key: ByteArray, message: ByteArray): ByteArray =
            Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(key, "HmacSHA256")) }.doFinal(message)

        fun constantTimeEquals(a: ByteArray, b: ByteArray) = MessageDigest.isEqual(a, b)
    }
}

private fun String.hexToBytes(): ByteArray = ByteArray(length / 2) { substring(2 * it, 2 * it + 2).toInt(16).toByte() }
