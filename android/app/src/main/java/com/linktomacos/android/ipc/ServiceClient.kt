package com.linktomacos.android.ipc

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull

/** 界面 App 这一侧：绑定服务 App 的 [ControlService]，收状态快照、发命令。 */
class ServiceClient(private val context: Context) {
    private val _snapshot = MutableStateFlow<ServiceSnapshot?>(null)
    val snapshot: StateFlow<ServiceSnapshot?> = _snapshot.asStateFlow()

    /** 绑定失败：多半是服务 App 没装。 */
    private val _missing = MutableStateFlow(false)
    val missing: StateFlow<Boolean> = _missing.asStateFlow()

    private val _connected = MutableStateFlow<Messenger?>(null)
    private var bound = false

    private val reply = Messenger(Handler(Looper.getMainLooper()) { message ->
        if (message.what == Control.SNAPSHOT) _snapshot.value = ServiceSnapshot.fromBundle(message.data)
        true
    })

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            val messenger = Messenger(binder)
            _connected.value = messenger
            runCatching { messenger.send(Message.obtain(null, Control.REGISTER).apply { replyTo = reply }) }
        }

        override fun onServiceDisconnected(name: ComponentName) {
            _connected.value = null
        }
    }

    /** 界面可见时调用。重复调用无害。 */
    fun connect() {
        if (bound) return
        bound = runCatching {
            context.bindService(Intent().setComponent(Control.controlService), connection, Context.BIND_AUTO_CREATE)
        }.getOrDefault(false)
        _missing.value = !bound
    }

    fun disconnect() {
        if (!bound) return
        runCatching { _connected.value?.send(Message.obtain(null, Control.UNREGISTER).apply { replyTo = reply }) }
        runCatching { context.unbindService(connection) }
        bound = false
        _connected.value = null
    }

    fun send(what: Int, data: Bundle = Bundle()) {
        runCatching { _connected.value?.send(Message.obtain(null, what).apply { this.data = data }) }
    }

    /** 等到连上服务（用于分享入口：此时界面 App 刚被拉起）。超时返回 false。 */
    suspend fun awaitConnected(timeoutMs: Long = 3_000): Boolean {
        connect()
        return withTimeoutOrNull(timeoutMs) { _connected.filterNotNull().first() } != null
    }

    /** 等第一份状态快照到达（连上服务后很快就会推来）。超时返回 null。 */
    suspend fun awaitSnapshot(timeoutMs: Long = 1_500): ServiceSnapshot? =
        withTimeoutOrNull(timeoutMs) { snapshot.filterNotNull().first() }

    fun refresh() = send(Control.REFRESH)

    fun set(key: String, value: Boolean) = send(Control.SET, Bundle().apply { putString("key", key); putBoolean("bool", value) })

    fun setApp(packageName: String, allowed: Boolean) =
        send(Control.SET_APP, Bundle().apply { putString("pkg", packageName); putBoolean("bool", allowed) })

    /** 拉起服务 App 的前台服务。必须在界面可见时调用（前台服务的启动限制）。 */
    fun startLink() {
        runCatching { context.startForegroundService(Intent().setComponent(Control.linkService)) }
    }

    /** 让服务 App 的透明页去办只有它自己能办的事（申请权限等）。 */
    fun runAction(kind: String) {
        runCatching {
            context.startActivity(Intent().setComponent(Control.actionActivity).putExtra(Control.EXTRA_KIND, kind).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}
