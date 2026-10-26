package com.linktomacos.android.ui

import com.linktomacos.android.data.PairedMac

/** 应用里的页面。[parent] 是按返回键回到的页面。 */
enum class Page(val parent: Page?) {
    Home(null),
    Notifications(Home),
    Apps(Notifications),
    Clipboard(Home),
    Files(Home),
    Mirror(Home),
    Dnd(Home),
    KeepAlive(Home),
    About(Home),
}

/** 各页面要显示的设置和权限状态。 */
data class SettingsUiState(
    val notificationAccess: Boolean,
    val allowedCount: Int,
    val dndOnConnect: Boolean,
    val ringCalls: Boolean,
    val dndAccess: Boolean,
    val dndActive: Boolean,
    val dndError: String?,
    val mediaAccess: Boolean,
    val allFilesAccess: Boolean,
    val enhancedReady: Boolean,
    val clipboardSync: Boolean,
    val batteryOptimizationIgnored: Boolean,
    val versionName: String,
)

/** 界面能触发的操作。 */
class UiActions(
    val onOpen: (Page) -> Unit,
    val onScan: () -> Unit,
    val onPairLink: (String) -> Boolean,
    val onUnpair: () -> Unit,
    val onGrantMedia: () -> Unit,
    val onDndOnConnectChange: (Boolean) -> Unit,
    val onRingCallsChange: (Boolean) -> Unit,
    val onClipboardChange: (Boolean) -> Unit,
    val onToggleApp: (packageName: String, allowed: Boolean) -> Unit,
)

/** 当前配对的 Mac，没配对为 null。 */
typealias Paired = PairedMac?
