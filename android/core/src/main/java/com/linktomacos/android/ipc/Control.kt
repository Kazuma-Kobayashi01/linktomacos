package com.linktomacos.android.ipc

import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import com.linktomacos.android.data.PairedMac
import com.linktomacos.android.link.LinkState

/**
 * 界面 App 和服务 App 之间的约定。界面通过绑定 [ControlService] 拿到一个 Messenger：
 * 往里发命令，同时登记自己的 Messenger 接收服务推来的状态快照。
 * 两个 App 同一签名，绑定权限是 signature 级。
 */
object Control {
    const val PERMISSION = "com.linktomacos.android.permission.CONTROL"
    const val UI_PACKAGE = "com.linktomacos.android"
    const val SERVICE_PACKAGE = "com.linktomacos.android.service"
    private const val UI_MAIN = "com.linktomacos.android.MainActivity"

    /** 服务 App 里的通知、规则等要打开界面 App 时用。 */
    fun uiIntent(): Intent = Intent().setClassName(UI_PACKAGE, UI_MAIN).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    val linkService = ComponentName(SERVICE_PACKAGE, "com.linktomacos.android.link.LinkService")
    val controlService = ComponentName(SERVICE_PACKAGE, "com.linktomacos.android.ipc.ControlService")
    val actionActivity = ComponentName(SERVICE_PACKAGE, "com.linktomacos.android.ipc.ActionActivity")

    // 界面 → 服务
    const val REGISTER = 1
    const val UNREGISTER = 2
    const val REFRESH = 3
    /** data: text = 扫到的配对内容 */
    const val PAIR = 4
    const val UNPAIR = 5
    /** data: key, bool = 开关设置 */
    const val SET = 6
    /** data: pkg, bool = 是否转发该应用的通知 */
    const val SET_APP = 7
    /** data: text = 界面刚回到前台时读到的剪贴板文字 */
    const val CLIPBOARD = 8
    /** data: files(ArrayList<Bundle>) / text = 分享来的内容，见 [com.linktomacos.android.link.AirSend.Prepared.toBundle] */
    const val AIRSEND = 9

    // 服务 → 界面
    const val SNAPSHOT = 100

    // ActionActivity 的操作
    const val EXTRA_KIND = "kind"
    const val KIND_NOTIFY = "notify"
    const val KIND_MEDIA = "media"
    const val KIND_BATTERY = "battery"

    const val SET_DND_ON_CONNECT = "dnd_on_connect"
    const val SET_RING_CALLS = "ring_calls"
    const val SET_CLIPBOARD = "clipboard_sync"
    const val SET_TILE_ADDED = "tile_added"
}

/** 服务 App 当前的全部状态，界面只读这个。 */
data class ServiceSnapshot(
    val link: LinkState,
    val paired: PairedMac?,
    val allowedApps: Set<String>,
    val dndOnConnect: Boolean,
    val ringCalls: Boolean,
    val clipboardSync: Boolean,
    val tileAdded: Boolean,
    val dndActive: Boolean,
    val dndError: String?,
    val enhancedReady: Boolean,
    val notificationAccess: Boolean,
    val dndAccess: Boolean,
    val mediaAccess: Boolean,
    val allFilesAccess: Boolean,
    val batteryIgnored: Boolean,
) {
    fun toBundle() = Bundle().apply {
        val (kind, a, b, n) = when (link) {
            LinkState.NotPaired -> Quad("notPaired", "", "", 0)
            is LinkState.Searching -> Quad("searching", link.macName, "", 0)
            is LinkState.Connected -> Quad("connected", link.macName, link.host, 0)
            is LinkState.Waiting -> Quad("waiting", link.macName, link.reason, link.retryInSeconds)
            is LinkState.Rejected -> Quad("rejected", link.macName, link.reason, 0)
        }
        putString("link", kind); putString("linkA", a); putString("linkB", b); putInt("linkN", n)
        paired?.let {
            putBundle("paired", Bundle().apply {
                putString("name", it.name); putStringArrayList("hosts", ArrayList(it.hosts)); putInt("port", it.port)
                putString("fingerprint", it.fingerprint); putString("token", it.pendingToken)
            })
        }
        putStringArrayList("apps", ArrayList(allowedApps))
        putBooleanArray("flags", booleanArrayOf(
            dndOnConnect, ringCalls, clipboardSync, tileAdded, dndActive, enhancedReady,
            notificationAccess, dndAccess, mediaAccess, allFilesAccess, batteryIgnored,
        ))
        putString("dndError", dndError)
    }

    private data class Quad(val kind: String, val a: String, val b: String, val n: Int)

    companion object {
        fun fromBundle(bundle: Bundle): ServiceSnapshot {
            val a = bundle.getString("linkA").orEmpty()
            val b = bundle.getString("linkB").orEmpty()
            val link = when (bundle.getString("link")) {
                "searching" -> LinkState.Searching(a)
                "connected" -> LinkState.Connected(a, b)
                "waiting" -> LinkState.Waiting(a, b, bundle.getInt("linkN"))
                "rejected" -> LinkState.Rejected(a, b)
                else -> LinkState.NotPaired
            }
            val paired = bundle.getBundle("paired")?.let {
                PairedMac(it.getString("name").orEmpty(), it.getStringArrayList("hosts").orEmpty(), it.getInt("port"),
                    it.getString("fingerprint").orEmpty(), it.getString("token"))
            }
            val f = bundle.getBooleanArray("flags") ?: BooleanArray(11)
            return ServiceSnapshot(
                link, paired, bundle.getStringArrayList("apps").orEmpty().toSet(),
                dndOnConnect = f[0], ringCalls = f[1], clipboardSync = f[2], tileAdded = f[3], dndActive = f[4],
                dndError = bundle.getString("dndError"), enhancedReady = f[5],
                notificationAccess = f[6], dndAccess = f[7], mediaAccess = f[8], allFilesAccess = f[9], batteryIgnored = f[10],
            )
        }
    }
}
