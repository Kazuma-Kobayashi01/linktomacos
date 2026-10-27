package com.linktomacos.android.ipc

import android.Manifest
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.PowerManager
import com.linktomacos.android.LinkApp
import com.linktomacos.android.link.AirSend
import com.linktomacos.android.link.DndController
import com.linktomacos.android.link.DndStatus
import com.linktomacos.android.link.LinkService
import com.linktomacos.android.link.LinkStatus
import com.linktomacos.android.link.PhoneNotificationListener
import com.linktomacos.android.protocol.PairingPayload
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.launch
import java.util.concurrent.CopyOnWriteArraySet

/**
 * 给界面 App 用的控制入口：只在界面绑定时存在，不常驻（常驻的是 [LinkService]）。
 * 状态都在进程级的单例里，所以这里不依赖 LinkService 是否在运行。
 */
class ControlService : Service() {
    private val app get() = application as LinkApp
    private val clients = CopyOnWriteArraySet<Messenger>()
    private val messenger = Messenger(Handler(Looper.getMainLooper()) { handle(it); true })
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val dirty = Channel<Unit>(Channel.CONFLATED)

    override fun onCreate() {
        super.onCreate()
        val settings = app.settings
        val flows: List<Flow<Any?>> = listOf(
            LinkStatus.state, app.pairingStore.paired, settings.allowedApps, settings.dndOnConnect, settings.ringCalls,
            settings.clipboardSync, settings.tileAdded, DndStatus.active, DndStatus.error, app.bridge.ready,
        )
        scope.launch { merge(*flows.map { f -> f.map { } }.toTypedArray()).collect { dirty.trySend(Unit) } }
        scope.launch { for (ignored in dirty) broadcast() }
    }

    override fun onBind(intent: Intent?): IBinder = messenger.binder

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun snapshot(): ServiceSnapshot {
        val settings = app.settings
        return ServiceSnapshot(
            link = LinkStatus.state.value,
            paired = app.pairingStore.paired.value,
            allowedApps = settings.allowedApps.value,
            dndOnConnect = settings.dndOnConnect.value,
            ringCalls = settings.ringCalls.value,
            clipboardSync = settings.clipboardSync.value,
            tileAdded = settings.tileAdded.value,
            dndActive = DndStatus.active.value,
            dndError = DndStatus.error.value,
            enhancedReady = app.bridge.ready.value,
            notificationAccess = PhoneNotificationListener.isEnabled(this),
            dndAccess = DndController.hasAccess(this),
            mediaAccess = checkSelfPermission(Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED,
            allFilesAccess = Environment.isExternalStorageManager(),
            batteryIgnored = getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName),
        )
    }

    private fun send(client: Messenger, bundle: Bundle) {
        try {
            client.send(Message.obtain(null, Control.SNAPSHOT).apply { data = bundle })
        } catch (e: Exception) {
            clients.remove(client)
        }
    }

    private fun broadcast() {
        if (clients.isEmpty()) return
        val bundle = snapshot().toBundle()
        clients.forEach { send(it, bundle) }
    }

    private fun handle(message: Message) {
        val data = message.data.apply { classLoader = ControlService::class.java.classLoader }
        when (message.what) {
            Control.REGISTER -> message.replyTo?.let { clients.add(it); send(it, snapshot().toBundle()) }
            Control.UNREGISTER -> clients.remove(message.replyTo)
            Control.REFRESH -> broadcast()
            Control.PAIR -> PairingPayload.parse(data.getString("text").orEmpty())?.let { app.pairingStore.pair(it) }
            Control.UNPAIR -> {
                app.pairingStore.unpair()
                LinkService.stop(this)
            }
            Control.SET -> {
                val value = data.getBoolean("bool")
                when (data.getString("key")) {
                    Control.SET_DND_ON_CONNECT -> app.settings.setDndOnConnect(value)
                    Control.SET_RING_CALLS -> app.settings.setRingCalls(value)
                    Control.SET_CLIPBOARD -> app.settings.setClipboardSync(value)
                    Control.SET_TILE_ADDED -> app.settings.setTileAdded(value)
                }
            }
            Control.SET_APP -> app.settings.setAllowed(data.getString("pkg").orEmpty(), data.getBoolean("bool"))
            Control.CLIPBOARD -> app.clipboard.onForeground(data.getString("text").orEmpty())
            Control.AIRSEND -> app.airSend.send(AirSend.Prepared.fromBundle(data))
        }
    }
}
