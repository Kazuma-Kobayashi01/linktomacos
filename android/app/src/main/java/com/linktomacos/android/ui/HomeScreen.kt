package com.linktomacos.android.ui

import android.annotation.SuppressLint
import android.content.Intent
import android.os.PowerManager
import android.provider.Settings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import com.linktomacos.android.data.PairedMac
import com.linktomacos.android.link.LinkState

/** 首页要显示和修改的设置状态。 */
data class SettingsUiState(
    val notificationAccess: Boolean,
    val allowedCount: Int,
    val dndOnConnect: Boolean,
    val ringCalls: Boolean,
    val dndAccess: Boolean,
    val dndActive: Boolean,
    val dndError: String?,
)

@Composable
fun HomeScreen(
    state: LinkState,
    paired: PairedMac?,
    settings: SettingsUiState,
    onManageApps: () -> Unit,
    onDndOnConnectChange: (Boolean) -> Unit,
    onRingCallsChange: (Boolean) -> Unit,
    onScan: () -> Unit,
    onPairLink: (String) -> Boolean,
    onUnpair: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var showPaste by remember { mutableStateOf(false) }
    Column(
        modifier = modifier.verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("LinkToMacOS", style = MaterialTheme.typography.headlineMedium)
        StatusCard(state)
        if (paired == null) {
            Button(onClick = onScan, modifier = Modifier.fillMaxWidth()) { Text("扫码配对 Mac") }
            OutlinedButton(onClick = { showPaste = true }, modifier = Modifier.fillMaxWidth()) { Text("粘贴配对链接") }
        } else {
            Text("已配对：${paired.name}", style = MaterialTheme.typography.bodyMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(onClick = onScan) { Text("重新配对") }
                OutlinedButton(onClick = onUnpair) { Text("取消配对") }
            }
        }
        NotificationAccessCard(settings.notificationAccess, settings.allowedCount, onManageApps)
        DndCard(settings, onDndOnConnectChange, onRingCallsChange)
        KeepAliveCard()
    }
    if (showPaste) PasteDialog(onDismiss = { showPaste = false }, onSubmit = onPairLink)
}

@Composable
private fun StatusCard(state: LinkState) {
    val (title, detail) = when (state) {
        LinkState.NotPaired -> "未配对" to "在 Mac 菜单栏点击“配对新手机…”，然后扫描二维码"
        is LinkState.Searching -> "正在连接" to state.macName
        is LinkState.Connected -> "已连接" to "${state.macName} · ${state.host}"
        is LinkState.Waiting -> "未连接" to "${state.reason}，${state.retryInSeconds} 秒后重试"
        is LinkState.Rejected -> "被拒绝" to "${state.macName}：${state.reason}。请重新扫码配对"
    }
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = MaterialTheme.typography.titleLarge)
            Text(detail, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun NotificationAccessCard(enabled: Boolean, allowedCount: Int, onManageApps: () -> Unit) {
    val context = LocalContext.current
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("通知转发", style = MaterialTheme.typography.titleMedium)
            Text(
                when {
                    !enabled -> "需要开启“通知使用权”，才能把手机通知转发到 Mac"
                    allowedCount == 0 -> "还没有选择任何应用，请先选择要转发通知的应用"
                    else -> "已选择 $allowedCount 个应用，它们的新通知会显示在 Mac 上"
                },
                style = MaterialTheme.typography.bodySmall,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                if (!enabled) {
                    OutlinedButton(onClick = {
                        context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    }) { Text("去开启") }
                }
                OutlinedButton(onClick = onManageApps) { Text("选择应用") }
            }
        }
    }
}

@Composable
private fun DndCard(settings: SettingsUiState, onDndOnConnectChange: (Boolean) -> Unit, onRingCallsChange: (Boolean) -> Unit) {
    val context = LocalContext.current
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("免打扰", style = MaterialTheme.typography.titleMedium)
            SwitchRow("连接 Mac 时自动开启免打扰", "断开、Mac 退出或睡眠时自动关闭", settings.dndOnConnect, onDndOnConnectChange)
            if (settings.dndOnConnect) {
                SwitchRow("免打扰期间来电仍然响铃", null, settings.ringCalls, onRingCallsChange)
                if (!settings.dndAccess) {
                    Text("需要授予“勿扰权限”才能自动开关免打扰", style = MaterialTheme.typography.bodySmall)
                    OutlinedButton(onClick = {
                        context.startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                    }) { Text("去授权") }
                } else {
                    Text(
                        settings.dndError?.let { "免打扰出错：$it" }
                            ?: if (settings.dndActive) "免打扰已由本应用开启" else "当前未开启（连接 Mac 后自动开启）",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        }
    }
}

@Composable
private fun SwitchRow(title: String, subtitle: String?, checked: Boolean, onChecked: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyMedium)
            if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Switch(checked = checked, onCheckedChange = onChecked)
    }
}

/** One UI 会积极清理后台，这里引导关闭电池优化并加入“从不休眠的应用”。 */
@SuppressLint("BatteryLife")
@Composable
private fun KeepAliveCard() {
    val context = LocalContext.current
    val power = context.getSystemService(PowerManager::class.java)
    val ignoring = power.isIgnoringBatteryOptimizations(context.packageName)
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("保持连接", style = MaterialTheme.typography.titleMedium)
            Text(
                "1. 关闭电池优化（应用电池设为“不受限制”）\n" +
                    "2. 设置 → 电池 → 后台使用限制 → 将本应用加入“从不休眠的应用”\n" +
                    "3. 关闭“自动拦截器”",
                style = MaterialTheme.typography.bodySmall,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(
                    enabled = !ignoring,
                    onClick = {
                        context.startActivity(
                            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, "package:${context.packageName}".toUri()),
                        )
                    },
                ) { Text(if (ignoring) "电池优化已关闭" else "关闭电池优化") }
                TextButton(onClick = {
                    context.startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, "package:${context.packageName}".toUri()),
                    )
                }) { Text("应用信息") }
            }
        }
    }
}

@Composable
private fun PasteDialog(onDismiss: () -> Unit, onSubmit: (String) -> Boolean) {
    var text by remember { mutableStateOf("") }
    var error by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("粘贴配对链接") },
        text = {
            OutlinedTextField(
                value = text,
                onValueChange = { text = it; error = false },
                isError = error,
                supportingText = { if (error) Text("链接无效") },
                placeholder = { Text("linktomacos://pair?…") },
            )
        },
        confirmButton = {
            TextButton(onClick = { if (onSubmit(text)) onDismiss() else error = true }) { Text("配对") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } },
    )
}
