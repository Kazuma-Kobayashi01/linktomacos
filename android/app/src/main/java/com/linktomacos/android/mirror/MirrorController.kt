package com.linktomacos.android.mirror

import android.content.Context
import android.util.Log
import com.linktomacos.android.R
import com.linktomacos.android.protocol.DataChunk
import com.linktomacos.android.protocol.LinkMessage
import com.linktomacos.android.protocol.MAX_FRAME_LENGTH
import com.linktomacos.android.protocol.MirrorEvent
import com.linktomacos.android.protocol.MirrorInput
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.atomic.AtomicLong

private const val TAG = "MirrorController"
/** 发送队列积压超过这个字节数，就丢掉后续的非关键帧，等下一个关键帧。 */
private const val MAX_QUEUED_BYTES = 1_500_000L
/** 一帧装不进一个数据帧（上限 1 MiB）时放弃，并请求更小的下一帧。 */
private const val MAX_PAYLOAD = MAX_FRAME_LENGTH - 5 - 9 - 64
/** 音频发送队列最多缓存的包数，每个约 20 ms。 */
private const val AUDIO_QUEUE_PACKETS = 100

class MirrorStarted(
    val streamId: Int,
    val width: Int,
    val height: Int,
    val deviceWidth: Int,
    val deviceHeight: Int,
    /** 被投显示器的编号：独立显示模式下是新建的虚拟显示器，镜像模式下是主屏（0）。 */
    val displayId: Int,
    val mode: String,
    /** 音频数据流的编号；没有开音频时是 0。 */
    val audioStreamId: Int = 0,
    /** Mac 麦克风数据流的编号（Mac 往这个流上发 PCM）；没有开麦克风时是 0。 */
    val micStreamId: Int = 0,
)

class MirrorOptions(
    /** "new" = 新建独立的虚拟显示器；"mirror" = 镜像手机主屏。 */
    val mode: String = "new",
    val maxSize: Int = 1920,
    val bitRate: Int = 8_000_000,
    val fps: Int = 60,
    /** 独立显示模式的初始尺寸（像素）。0 表示和手机屏幕同样的宽高比（长边不超过 maxSize）。 */
    val width: Int = 0,
    val height: Int = 0,
    /** 独立显示模式下，开始时自动打开的应用包名。 */
    val app: String? = null,
    val forceStop: Boolean = false,
    /** 把手机的声音（Opus）转发给 Mac，手机本体静音。 */
    val audio: Boolean = false,
    /** 把 Mac 麦克风的声音注入手机：手机上的应用录音时拿到的是 Mac 的声音。 */
    val mic: Boolean = false,
)

/**
 * 一次 Mac 连接上的投屏会话：把 shell 服务的视频包转发给 Mac，把 Mac 的输入转给 shell 服务。
 *
 * 流控：手机热点的带宽有限，Mac 读得慢时发送会阻塞。队列积压过多时丢掉非关键帧直到下一个关键帧，
 * 并让 shell 服务立刻出一个关键帧，这样画面延迟不会越积越大，丢帧后画面也能自己恢复。
 */
class MirrorController(
    private val context: Context,
    private val bridge: EnhancedBridge,
    private val scope: CoroutineScope,
    private val send: (LinkMessage) -> Unit,
    private val allocateStreamId: () -> Int,
) {
    private class Packet(val flags: Int, val data: ByteArray)

    private val lock = Any()
    private var streamId = 0
    private var pump: Job? = null
    private var queue: Channel<Packet>? = null
    private var audioQueue: Channel<ByteArray>? = null
    private var audioPump: Job? = null
    @Volatile private var micStreamId = 0
    private val queuedBytes = AtomicLong()
    @Volatile private var waitingForKey = false
    private var started: CompletableDeferred<JSONObject>? = null
    private val launches = java.util.concurrent.ConcurrentHashMap<String, CompletableDeferred<JSONObject>>()
    private var wakeLock: android.os.PowerManager.WakeLock? = null

    val isActive: Boolean get() = synchronized(lock) { queue != null }

    suspend fun start(options: MirrorOptions): MirrorStarted {
        if (!bridge.ready.value) throw IllegalStateException(context.getString(R.string.err_enhanced_not_ready))
        stop()
        val id = allocateStreamId()
        val audioId = if (options.audio) allocateStreamId() else 0
        val micId = if (options.mic) allocateStreamId() else 0
        micStreamId = micId
        val channel = Channel<Packet>(Channel.UNLIMITED)
        // 音频包很小（约 20 ms 一个），积压太多就丢最旧的：声音过时了就没有意义
        val audioChannel = if (options.audio) Channel<ByteArray>(AUDIO_QUEUE_PACKETS, BufferOverflow.DROP_OLDEST) else null
        val deferred = CompletableDeferred<JSONObject>()
        synchronized(lock) {
            streamId = id
            queue = channel
            audioQueue = audioChannel
            started = deferred
        }
        if (audioChannel != null) {
            audioPump = scope.launch(Dispatchers.IO) {
                try {
                    for (payload in audioChannel) send(DataChunk(audioId, payload))
                } catch (e: IOException) {
                    Log.d(TAG, "audio pump ended: $e")
                }
            }
        }
        queuedBytes.set(0)
        waitingForKey = false

        pump = scope.launch(Dispatchers.IO) {
            try {
                for (packet in channel) {
                    queuedBytes.addAndGet(-packet.data.size.toLong())
                    send(DataChunk(id, packet.data))
                }
            } catch (e: IOException) {
                Log.d(TAG, "pump ended: $e")
            }
        }
        bridge.listener = object : ShellListener {
            override fun onVideo(packet: VideoPacket) = this@MirrorController.onVideo(packet)
            override fun onAudio(packet: VideoPacket) = this@MirrorController.onAudio(packet)
            override fun onEvent(event: JSONObject) = this@MirrorController.onEvent(event)
        }
        acquireWakeLock()
        bridge.send(
            JSONObject().put("t", "start").put("mode", options.mode).put("display", 0)
                .put("maxSize", options.maxSize).put("bitRate", options.bitRate).put("fps", options.fps)
                .put("width", options.width).put("height", options.height)
                .put("app", options.app ?: "").put("forceStop", options.forceStop).put("audio", options.audio)
                .put("mic", options.mic),
        )
        val info = try {
            withTimeout(8_000) { deferred.await() }
        } catch (e: Exception) {
            stop()
            throw IllegalStateException(context.getString(R.string.err_mirror_start_failed, e.message ?: e.javaClass.simpleName))
        }
        return MirrorStarted(
            id, info.getInt("width"), info.getInt("height"),
            info.optInt("deviceWidth", info.getInt("width")), info.optInt("deviceHeight", info.getInt("height")),
            info.optInt("displayId", 0), if (info.optInt("mode", 1) == 0) "mirror" else "new", audioId, micId,
        )
    }

    fun stop() {
        val wasActive = synchronized(lock) {
            val active = queue != null
            queue?.close()
            queue = null
            audioQueue?.close()
            audioQueue = null
            started?.cancel()
            started = null
            active
        }
        pump?.cancel()
        pump = null
        audioPump?.cancel()
        audioPump = null
        micStreamId = 0
        if (wasActive) bridge.send(JSONObject().put("t", "stop"))
        if (bridge.listener != null) bridge.listener = null
        releaseWakeLock()
    }

    /** 独立显示模式：Mac 窗口大小变了，调整虚拟显示器。应用会重新排版。 */
    fun resize(width: Int, height: Int) {
        bridge.send(JSONObject().put("t", "resize").put("width", width).put("height", height))
    }

    /** 在虚拟显示器上打开应用。 */
    suspend fun launch(pkg: String, forceStop: Boolean) {
        val deferred = CompletableDeferred<JSONObject>()
        launches[pkg] = deferred
        try {
            bridge.send(JSONObject().put("t", "launch").put("pkg", pkg).put("forceStop", forceStop))
            val result = withTimeout(10_000) { deferred.await() }
            if (!result.optBoolean("ok")) {
                throw IllegalStateException(context.getString(R.string.err_launch_failed, result.optString("message", pkg)))
            }
        } finally {
            launches.remove(pkg)
        }
    }

    /**
     * 投屏期间持有唤醒锁：手机屏幕灭了、锁屏了，CPU 也不会睡着，投屏继续。
     * 设了 6 小时的保险超时，防止异常情况下一直持有。
     */
    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val power = context.getSystemService(android.os.PowerManager::class.java)
        wakeLock = power.newWakeLock(android.os.PowerManager.PARTIAL_WAKE_LOCK, "linktomacos:mirror").apply {
            setReferenceCounted(false)
            acquire(6 * 60 * 60 * 1000L)
        }
    }

    private fun releaseWakeLock() {
        runCatching { if (wakeLock?.isHeld == true) wakeLock?.release() }
        wakeLock = null
    }

    fun input(input: MirrorInput) {
        if (input.k == "cmd") {
            when (input.cmd) {
                "sync" -> { bridge.send(JSONObject().put("t", "sync")); return }
                "screenOff" -> { bridge.send(JSONObject().put("t", "screen").put("on", false)); return }
                "screenOn" -> { bridge.send(JSONObject().put("t", "screen").put("on", true)); return }
            }
        }
        val json = JSONObject().put("t", "input").put("k", input.k)
        input.a?.let { json.put("a", it) }
        input.x?.let { json.put("x", it) }
        input.y?.let { json.put("y", it) }
        input.c?.let { json.put("c", it) }
        input.m?.let { json.put("m", it) }
        input.h?.let { json.put("h", it) }
        input.v?.let { json.put("v", it) }
        input.text?.let { json.put("text", it) }
        input.cmd?.let { json.put("cmd", it) }
        bridge.send(json)
    }

    private fun onVideo(packet: VideoPacket) {
        val channel = synchronized(lock) { queue } ?: return
        if (packet.data.size > MAX_PAYLOAD) {
            Log.w(TAG, "video packet too large (${packet.data.size}), dropped")
            waitingForKey = true
            bridge.send(JSONObject().put("t", "sync"))
            return
        }
        if (!packet.isConfig) {
            if (waitingForKey) {
                if (!packet.isKey) return
                waitingForKey = false
            } else if (!packet.isKey && queuedBytes.get() > MAX_QUEUED_BYTES) {
                waitingForKey = true
                bridge.send(JSONObject().put("t", "sync"))
                return
            }
        }
        val payload = ByteArray(9 + packet.data.size)
        payload[0] = packet.flags.toByte()
        for (i in 0 until 8) payload[1 + i] = (packet.ptsUs shr (56 - 8 * i)).toByte()
        System.arraycopy(packet.data, 0, payload, 9, packet.data.size)
        queuedBytes.addAndGet(payload.size.toLong())
        channel.trySend(Packet(packet.flags, payload))
    }

    /** Mac 麦克风的一包 PCM（20 ms）。只收投屏时登记的那个数据流。 */
    fun onMicData(chunk: DataChunk) {
        val id = micStreamId
        if (id == 0 || chunk.streamId != id) return
        bridge.sendMic(if (chunk.length == chunk.bytes.size) chunk.bytes else chunk.bytes.copyOf(chunk.length))
    }

    private fun onAudio(packet: VideoPacket) {
        val channel = synchronized(lock) { audioQueue } ?: return
        if (packet.data.size > MAX_PAYLOAD) return
        val payload = ByteArray(9 + packet.data.size)
        payload[0] = packet.flags.toByte()
        for (i in 0 until 8) payload[1 + i] = (packet.ptsUs shr (56 - 8 * i)).toByte()
        System.arraycopy(packet.data, 0, payload, 9, packet.data.size)
        channel.trySend(payload)
    }

    private fun onEvent(event: JSONObject) {
        when (event.optString("t")) {
            "started" -> synchronized(lock) { started }?.complete(event)
            "launched" -> launches[event.optString("pkg")]?.complete(event)
            "resized" -> {
                // 尺寸变了，Mac 需要新的 SPS/PPS，shell 会随后发新的配置包
                waitingForKey = false
                send(
                    MirrorEvent(
                        "resized", event.optInt("width"), event.optInt("height"),
                        event.optInt("deviceWidth"), event.optInt("deviceHeight"), event.optInt("rotation"),
                    ),
                )
            }
            "error" -> {
                send(MirrorEvent("error", message = event.optString("message")))
                synchronized(lock) { started }?.completeExceptionally(IllegalStateException(event.optString("message")))
            }
            "stopped", "disconnected" -> {
                val wasActive = isActive
                if (wasActive) send(MirrorEvent("stopped", message = event.optString("t")))
                synchronized(lock) {
                    queue?.close()
                    queue = null
                    audioQueue?.close()
                    audioQueue = null
                }
                pump?.cancel()
                pump = null
                audioPump?.cancel()
                audioPump = null
            }
        }
    }
}
