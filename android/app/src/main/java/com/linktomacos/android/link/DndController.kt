package com.linktomacos.android.link

import android.app.AutomaticZenRule
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.service.notification.Condition
import android.service.notification.ZenPolicy
import android.util.Log
import androidx.core.content.edit
import androidx.core.net.toUri
import com.linktomacos.android.MainActivity
import com.linktomacos.android.data.LinkSettings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

private const val TAG = "DndController"

/** 免打扰是否正由本应用的规则开启，以及最近一次失败的原因，供界面显示。 */
object DndStatus {
    private val _active = MutableStateFlow(false)
    val active: StateFlow<Boolean> = _active.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    internal fun set(active: Boolean, error: String?) {
        _active.value = active
        _error.value = error
    }
}

/**
 * 连接 Mac 时自动开启免打扰，断开时关闭。
 *
 * 用 Android 15 的“模式”（AutomaticZenRule）实现，而不是直接改全局免打扰：
 * 只管理自己的规则，不会覆盖用户手动开的免打扰；用户也能在系统“模式”里看到它。
 * 免打扰只静音声音和振动，通知监听照常工作，所以通知仍会转发到 Mac。
 */
class DndController(
    private val context: Context,
    private val settings: LinkSettings,
    private val scope: CoroutineScope,
) {
    private val nm = context.getSystemService(NotificationManager::class.java)
    private val prefs = context.getSharedPreferences("dnd", Context.MODE_PRIVATE)
    private val lock = Any()
    private var connected = false
    private var pendingOff: Job? = null

    /** 服务启动时调用：先复位上个进程可能残留的状态，再随设置变化刷新。 */
    fun start() {
        apply()
        scope.launch {
            combine(settings.dndOnConnect, settings.ringCalls) { _, _ -> }.collect { apply() }
        }
    }

    fun onConnected() {
        synchronized(lock) {
            pendingOff?.cancel()
            connected = true
        }
        apply()
    }

    /** [graceMs] 内重新连上则不关闭，避免网络抖动时免打扰反复开关。 */
    fun onDisconnected(graceMs: Long) {
        Log.i(TAG, "onDisconnected(grace=$graceMs) connected=$connected")
        synchronized(lock) {
            if (!connected) return
            if (graceMs > 0) {
                // 宽限期从第一次断线算起；之后每次重连失败再调用，不能把期限往后推
                if (pendingOff?.isActive == true) return
                pendingOff = scope.launch {
                    delay(graceMs)
                    synchronized(lock) { connected = false }
                    apply()
                }
                return
            }
            pendingOff?.cancel()
            connected = false
        }
        apply()
    }

    /** 服务销毁时同步关闭，不能依赖协程。 */
    fun shutdown() {
        synchronized(lock) {
            pendingOff?.cancel()
            connected = false
        }
        apply()
    }

    private fun apply() = synchronized(lock) {
        val want = connected && settings.dndOnConnect.value
        if (!nm.isNotificationPolicyAccessGranted) {
            DndStatus.set(false, if (want) "未授予“勿扰权限”，无法自动开启免打扰" else null)
            return@synchronized
        }
        try {
            var ruleId = prefs.getString(KEY_RULE_ID, null)?.takeIf { nm.getAutomaticZenRule(it) != null }
            if (ruleId == null) {
                if (!want) {
                    DndStatus.set(false, null)
                    return@synchronized
                }
                ruleId = nm.addAutomaticZenRule(buildRule())
                prefs.edit { putString(KEY_RULE_ID, ruleId) }
            } else if (want) {
                // 每次开启前刷新规则，让“来电是否响铃”的修改立即生效
                nm.updateAutomaticZenRule(ruleId, buildRule())
            }
            val state = if (want) Condition.STATE_TRUE else Condition.STATE_FALSE
            nm.setAutomaticZenRuleState(ruleId, Condition(CONDITION_URI, SUMMARY, state))
            Log.i(TAG, "rule state -> ${if (want) "TRUE" else "FALSE"}")
            DndStatus.set(want, null)
        } catch (t: Throwable) {
            // 免打扰是附加功能：任何失败（包括系统 API 缺失导致的 Error）都不能影响与 Mac 的连接
            Log.w(TAG, "apply(want=$want) failed", t)
            DndStatus.set(false, t.message ?: t.javaClass.simpleName)
        }
    }

    private fun buildRule(): AutomaticZenRule {
        val ring = settings.ringCalls.value
        val policy = ZenPolicy.Builder()
            .allowAlarms(true)
            .allowMedia(true)
            .allowSystem(false)
            .allowReminders(false)
            .allowEvents(false)
            .allowMessages(ZenPolicy.PEOPLE_TYPE_NONE)
            .allowConversations(ZenPolicy.CONVERSATION_SENDERS_NONE)
            .allowCalls(if (ring) ZenPolicy.PEOPLE_TYPE_ANYONE else ZenPolicy.PEOPLE_TYPE_NONE)
            .allowRepeatCallers(ring)
            .build()
        // 不用 AutomaticZenRule.Builder：它的 (name, Uri) 构造方法在部分 Android 15 系统（含 One UI 7）上不存在
        @Suppress("DEPRECATION")
        return AutomaticZenRule(
            RULE_NAME,
            null,
            ComponentName(context, MainActivity::class.java),
            CONDITION_URI,
            policy,
            NotificationManager.INTERRUPTION_FILTER_PRIORITY,
            true,
        )
    }

    companion object {
        private const val KEY_RULE_ID = "rule_id"
        private const val RULE_NAME = "已连接 Mac"
        private const val SUMMARY = "已连接 Mac"
        private val CONDITION_URI: Uri = "linktomacos://dnd/connected".toUri()

        fun hasAccess(context: Context): Boolean =
            context.getSystemService(NotificationManager::class.java).isNotificationPolicyAccessGranted
    }
}
