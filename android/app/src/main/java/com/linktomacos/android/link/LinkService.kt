package com.linktomacos.android.link

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import com.linktomacos.android.LinkApp
import com.linktomacos.android.MainActivity
import com.linktomacos.android.R
import com.linktomacos.android.data.PairedMac
import com.linktomacos.android.data.isSamePairing
import com.linktomacos.android.protocol.DeviceStatus
import com.linktomacos.android.protocol.Frames
import com.linktomacos.android.protocol.Goodbye
import com.linktomacos.android.protocol.Hello
import com.linktomacos.android.protocol.HelloAck
import com.linktomacos.android.protocol.LinkMessage
import com.linktomacos.android.protocol.Ping
import com.linktomacos.android.protocol.Pong
import com.linktomacos.android.security.Identity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.net.InetSocketAddress
import javax.net.ssl.SSLSocket

private const val TAG = "LinkService"
private const val NOTIFICATION_ID = 1
private const val CONNECT_TIMEOUT_MS = 3_000
private const val HANDSHAKE_TIMEOUT_MS = 10_000
/** Mac 每 5 秒发一次 ping；20 秒收不到任何帧即视为断开。 */
private const val READ_TIMEOUT_MS = 20_000
/** 非主动断开（断网、崩溃）时，等多久才关闭免打扰。 */
private const val DND_GRACE_MS = 10_000L
/** Mac 主动离开（退出、睡眠）后，等多久再尝试重连。 */
private const val MAC_LEFT_RETRY_SECONDS = 8

/**
 * 常驻前台服务（connectedDevice 类型）：发现并连接已配对的 Mac，维持心跳，上报设备状态，断线自动重连。
 */
class LinkService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    /** 网络变化或用户操作时立即重试，不必等退避结束。 */
    private val wakeups = Channel<Unit>(Channel.CONFLATED)
    private val store by lazy { (application as LinkApp).pairingStore }
    private val settings by lazy { (application as LinkApp).settings }
    private val dnd by lazy { DndController(this, settings, scope) }
    private val discovery by lazy { MacDiscovery(this) }
    private val statusCollector by lazy { DeviceStatusCollector(this) }

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            wakeups.trySend(Unit)
        }
    }

    override fun onCreate() {
        super.onCreate()
        startForeground(NOTIFICATION_ID, buildNotification("正在启动…"), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        getSystemService(ConnectivityManager::class.java).registerDefaultNetworkCallback(networkCallback)
        dnd.start()
        scope.launch { LinkStatus.state.collect { updateNotification(it) } }
        scope.launch { run() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        wakeups.trySend(Unit)
        return START_STICKY
    }

    override fun onDestroy() {
        getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(networkCallback)
        dnd.shutdown()
        scope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private suspend fun run() {
        // 握手成功后 onConnected 会更新地址并作废令牌，这不是重新配对，不能因此重启连接；
        // 只有换了 Mac（指纹变化）或重新扫码（拿到新令牌）才重启。
        store.paired.distinctUntilChanged(::isSamePairing).collectLatest { mac ->
            if (mac == null) {
                LinkStatus.set(LinkState.NotPaired)
                return@collectLatest
            }
            var failures = 0
            try {
                while (currentCoroutineContext().isActive) {
                    LinkStatus.set(LinkState.Searching(mac.name))
                    when (val end = connectAndServe(store.paired.value ?: mac)) {
                        is SessionEnd.Rejected -> {
                            dnd.onDisconnected(0)
                            LinkStatus.set(LinkState.Rejected(mac.name, end.reason))
                            wakeups.receive()
                            continue
                        }
                        is SessionEnd.Closed -> {
                            Log.i(TAG, "session closed: reason=${end.reason} wasConnected=${end.wasConnected} macLeft=${end.macLeft}")
                            // Mac 主动说再见（退出、睡眠）立即关免打扰；其他断开给 10 秒重连的机会
                            dnd.onDisconnected(if (end.macLeft) 0 else DND_GRACE_MS)
                            failures = if (end.wasConnected) 0 else failures + 1
                            val delaySeconds = if (end.macLeft) MAC_LEFT_RETRY_SECONDS
                            else listOf(1, 2, 5, 10, 15)[failures.coerceAtMost(4)]
                            LinkStatus.set(LinkState.Waiting(mac.name, end.reason, delaySeconds))
                            if (end.macLeft) {
                                // Mac 正在退出或睡眠，立刻重连只会连上一个半死的 Mac；也不理会网络变化的唤醒
                                delay(delaySeconds * 1000L)
                            } else {
                                withTimeoutOrNull(delaySeconds * 1000L) { wakeups.receive() }
                            }
                        }
                    }
                }
            } finally {
                // 换 Mac、取消配对或服务停止时，不等宽限期
                dnd.onDisconnected(0)
            }
        }
    }

    private sealed interface SessionEnd {
        data class Closed(val reason: String, val wasConnected: Boolean, val macLeft: Boolean = false) : SessionEnd
        data class Rejected(val reason: String) : SessionEnd
    }

    private suspend fun connectAndServe(mac: PairedMac): SessionEnd {
        val candidates = buildList {
            discovery.find(mac.fingerprint, timeoutMs = 2_500)?.let { add(it.host to it.port) }
            mac.hosts.forEach { add(it to mac.port) }
        }.distinct()
        val sslContext = Identity.sslContext(mac.fingerprint)
        for ((host, port) in candidates) {
            val socket = withContext(Dispatchers.IO) {
                runCatching {
                    (sslContext.socketFactory.createSocket() as SSLSocket).apply {
                        tcpNoDelay = true
                        connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)
                        soTimeout = HANDSHAKE_TIMEOUT_MS
                        startHandshake()
                    }
                }.onFailure { Log.d(TAG, "connect $host:$port failed: $it") }.getOrNull()
            } ?: continue
            return serve(Session(socket), mac, host, port)
        }
        return SessionEnd.Closed(if (candidates.isEmpty()) "未找到 Mac" else "无法连接 Mac", wasConnected = false)
    }

    private suspend fun serve(session: Session, mac: PairedMac, host: String, port: Int): SessionEnd = coroutineScope {
        try {
            val ack = withContext(Dispatchers.IO) {
                session.send(hello(mac.pendingToken))
                session.receive()
            }
            if (ack !is HelloAck) return@coroutineScope SessionEnd.Closed("握手失败", wasConnected = false)
            if (!ack.accepted) return@coroutineScope SessionEnd.Rejected(ack.reason ?: "Mac 拒绝连接")

            store.onConnected(host, port, ack.macName)
            LinkStatus.set(LinkState.Connected(ack.macName, host))
            dnd.onConnected()
            session.socket.soTimeout = READ_TIMEOUT_MS

            val statusJob = launch(Dispatchers.IO) {
                try {
                    statusCollector.updates().collect { session.send(it) }
                } catch (e: IOException) {
                    session.close()
                }
            }
            val notificationJob = launch(Dispatchers.IO) {
                try {
                    NotificationBridge.events.collect { session.send(it) }
                } catch (e: IOException) {
                    session.close()
                }
            }
            val reader = async(Dispatchers.IO) { readLoop(session) }
            try {
                SessionEnd.Closed(reader.await(), wasConnected = true, macLeft = session.macLeft)
            } finally {
                statusJob.cancel()
                notificationJob.cancel()
            }
        } catch (e: IOException) {
            SessionEnd.Closed(e.message ?: "连接中断", wasConnected = false)
        } finally {
            // 关闭 socket 也会让阻塞中的读取立即返回
            session.close()
        }
    }

    /** 返回连接结束的原因。 */
    private fun readLoop(session: Session): String {
        while (true) {
            val message = try {
                session.receive()
            } catch (e: IOException) {
                return if (e is java.net.SocketTimeoutException) "心跳超时" else (e.message ?: "连接中断")
            }
            when (message) {
                is Ping -> session.send(Pong(message.t))
                is Goodbye -> {
                    Log.i(TAG, "goodbye from Mac: ${message.reason}")
                    session.macLeft = true
                    return "Mac 已断开（${message.reason}）"
                }
                else -> Log.d(TAG, "unhandled $message")
            }
        }
    }

    private fun hello(token: String?) = Hello(
        deviceId = store.deviceId,
        deviceName = Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME) ?: Build.MODEL,
        model = Build.MODEL,
        osVersion = Build.VERSION.RELEASE,
        appVersion = packageManager.getPackageInfo(packageName, 0).versionName ?: "",
        pairingToken = token,
    )

    private class Session(val socket: SSLSocket) {
        /** 对端是否发过 goodbye（主动离开）。 */
        @Volatile var macLeft = false
        private val input = DataInputStream(BufferedInputStream(socket.inputStream))
        private val output = DataOutputStream(BufferedOutputStream(socket.outputStream))

        fun send(message: LinkMessage) = synchronized(output) {
            Frames.write(output, message)
            output.flush()
        }

        fun receive(): LinkMessage = Frames.read(input)

        fun close() {
            runCatching { socket.close() }
        }
    }

    // MARK: 通知

    private fun updateNotification(state: LinkState) {
        val text = when (state) {
            LinkState.NotPaired -> "尚未配对 Mac"
            is LinkState.Searching -> "正在连接 ${state.macName}…"
            is LinkState.Connected -> "已连接 ${state.macName}"
            is LinkState.Waiting -> "${state.reason}，${state.retryInSeconds} 秒后重试"
            is LinkState.Rejected -> "${state.macName} 拒绝连接：${state.reason}"
        }
        getSystemService(android.app.NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification(text))
    }

    private fun buildNotification(text: String): Notification {
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, LinkApp.CHANNEL_LINK)
            .setSmallIcon(R.drawable.ic_link)
            .setContentTitle("LinkToMacOS")
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .setSilent(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    companion object {
        fun start(context: Context) {
            context.startForegroundService(Intent(context, LinkService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LinkService::class.java))
        }
    }
}
