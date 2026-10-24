package com.linktomacos.android.data

import android.content.Context
import androidx.core.content.edit
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** 用户可调的设置：转发白名单、连接 Mac 时的免打扰。 */
class LinkSettings(context: Context) {
    private val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    private val _allowedApps = MutableStateFlow(prefs.getStringSet(KEY_APPS, emptySet())!!.toSet())
    /** 允许转发通知的应用包名。白名单：不在其中的应用一律不转发，默认为空。 */
    val allowedApps: StateFlow<Set<String>> = _allowedApps.asStateFlow()

    private val _dndOnConnect = MutableStateFlow(prefs.getBoolean(KEY_DND, true))
    /** 连接 Mac 时自动开启免打扰。 */
    val dndOnConnect: StateFlow<Boolean> = _dndOnConnect.asStateFlow()

    private val _ringCalls = MutableStateFlow(prefs.getBoolean(KEY_RING, true))
    /** 免打扰期间来电仍然响铃。 */
    val ringCalls: StateFlow<Boolean> = _ringCalls.asStateFlow()

    fun isAllowed(packageName: String) = packageName in _allowedApps.value

    fun setAllowed(packageName: String, allowed: Boolean) {
        val next = if (allowed) _allowedApps.value + packageName else _allowedApps.value - packageName
        prefs.edit { putStringSet(KEY_APPS, next) }
        _allowedApps.value = next
    }

    fun setDndOnConnect(enabled: Boolean) {
        prefs.edit { putBoolean(KEY_DND, enabled) }
        _dndOnConnect.value = enabled
    }

    fun setRingCalls(enabled: Boolean) {
        prefs.edit { putBoolean(KEY_RING, enabled) }
        _ringCalls.value = enabled
    }

    private companion object {
        const val KEY_APPS = "allowed_apps"
        const val KEY_DND = "dnd_on_connect"
        const val KEY_RING = "ring_calls"
    }
}
