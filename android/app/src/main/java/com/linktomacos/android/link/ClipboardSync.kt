package com.linktomacos.android.link

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.util.Log
import com.linktomacos.android.data.LinkSettings
import com.linktomacos.android.mirror.EnhancedBridge
import com.linktomacos.android.protocol.CLIPBOARD_MAX_CHARS
import com.linktomacos.android.protocol.ClipboardText
import com.linktomacos.android.protocol.LinkMessage
import kotlinx.coroutines.flow.combine
import org.json.JSONObject

private const val TAG = "ClipboardSync"

/**
 * 和 Mac 互通剪贴板文本。
 *
 * - **Mac → 手机**：写剪贴板在后台也允许，直接写；连上了增强服务时交给它写（顺便让它记住这次写入，不把回声再发回去）。
 * - **手机 → Mac**：Android 10 起 App 在后台读不了剪贴板，所以靠增强服务（shell 身份）监听复制；
 *   没有增强服务时，只能在本 App 回到前台的那一刻读一次（[onForeground]）。
 *
 * 每次连接由 [LinkService] 调用 [attach] 开始、结束时调用 [detach]。
 */
class ClipboardSync(
    private val context: Context,
    private val settings: LinkSettings,
    private val bridge: EnhancedBridge,
) {
    private val manager = context.getSystemService(ClipboardManager::class.java)

    @Volatile private var send: ((LinkMessage) -> Unit)? = null
    /** 最近一次收发过的文本，用来挡住 Mac 刚发来的内容又被当成“手机上新复制的”回传。 */
    @Volatile private var last: String? = null

    /** 当前连接上要做的事：开关或增强服务状态变化时，通知增强服务开始或停止监听。会一直挂起，连接断开时取消。 */
    suspend fun attach(send: (LinkMessage) -> Unit) {
        this.send = send
        bridge.onClipboard = { text -> fromPhone(text) }
        try {
            combine(settings.clipboardSync, bridge.ready) { enabled, ready -> enabled && ready }
                .collect { watch -> bridge.send(JSONObject().put("t", "clip").put("on", watch)) }
        } finally {
            detach()
        }
    }

    private fun detach() {
        send = null
        bridge.onClipboard = null
        bridge.send(JSONObject().put("t", "clip").put("on", false))
    }

    /** Mac 发来的文本。 */
    fun fromMac(message: ClipboardText) {
        if (!settings.clipboardSync.value) return
        val text = message.text
        if (text.isEmpty() || text.length > CLIPBOARD_MAX_CHARS) return
        last = text
        if (bridge.ready.value && bridge.send(JSONObject().put("t", "clipSet").put("text", text))) return
        runCatching { manager.setPrimaryClip(ClipData.newPlainText("Link to macOS", text)) }
            .onFailure { Log.w(TAG, "cannot write clipboard: $it") }
    }

    /** 增强服务报告手机上复制了文本。 */
    private fun fromPhone(text: String) {
        if (!settings.clipboardSync.value || text.isEmpty() || text.length > CLIPBOARD_MAX_CHARS || text == last) return
        last = text
        // 发送失败（连接刚断）由读循环去处理；这里不能让异常传进增强服务的读线程
        runCatching { send?.invoke(ClipboardText(text, System.currentTimeMillis())) }
    }

    /**
     * 本 App 刚回到前台：此时允许读剪贴板。没有增强服务时，这是手机复制的文字唯一能传给 Mac 的时机
     * （用户在别的 App 复制后，切回来看一眼状态就会同步）。有增强服务时它已经实时同步过了，这里什么也不做。
     */
    fun onForeground() {
        if (!settings.clipboardSync.value || bridge.ready.value || send == null) return
        val clip = runCatching { manager.primaryClip }.getOrNull() ?: return
        if (clip.itemCount == 0) return
        if (clip.description?.extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE, false) == true) return
        val text = clip.getItemAt(0).text?.toString() ?: return
        fromPhone(text)
    }
}
