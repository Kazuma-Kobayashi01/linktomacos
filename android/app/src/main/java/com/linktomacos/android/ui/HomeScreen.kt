package com.linktomacos.android.ui

import com.linktomacos.android.R
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
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
    val mediaAccess: Boolean,
    val allFilesAccess: Boolean,
    val enhancedReady: Boolean,
)

@Composable
fun HomeScreen(
    state: LinkState,
    paired: PairedMac?,
    settings: SettingsUiState,
    onManageApps: () -> Unit,
    onGrantMedia: () -> Unit,
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
        Text("Link to macOS", style = MaterialTheme.typography.headlineMedium)
        StatusCard(state)
        if (paired == null) {
            Button(onClick = onScan, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.pair_scan)) }
            OutlinedButton(onClick = { showPaste = true }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.pair_paste)) }
        } else {
            Text(stringResource(R.string.paired_with, paired.name), style = MaterialTheme.typography.bodyMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(onClick = onScan) { Text(stringResource(R.string.re_pair)) }
                OutlinedButton(onClick = onUnpair) { Text(stringResource(R.string.unpair)) }
            }
        }
        NotificationAccessCard(settings.notificationAccess, settings.allowedCount, onManageApps)
        DndCard(settings, onDndOnConnectChange, onRingCallsChange)
        FilesAccessCard(settings.mediaAccess, settings.allFilesAccess, onGrantMedia)
        EnhancedCard(settings.enhancedReady)
        KeepAliveCard()
    }
    if (showPaste) PasteDialog(onDismiss = { showPaste = false }, onSubmit = onPairLink)
}

@Composable
private fun StatusCard(state: LinkState) {
    val (title, detail) = when (state) {
        LinkState.NotPaired -> stringResource(R.string.state_not_paired_title) to stringResource(R.string.state_not_paired_detail)
        is LinkState.Searching -> stringResource(R.string.state_searching_title) to state.macName
        is LinkState.Connected -> stringResource(R.string.state_connected_title) to "${state.macName} · ${state.host}"
        is LinkState.Waiting -> stringResource(R.string.state_waiting_title) to stringResource(R.string.state_waiting_detail, state.reason, state.retryInSeconds)
        is LinkState.Rejected -> stringResource(R.string.state_rejected_title) to stringResource(R.string.state_rejected_detail, state.macName, state.reason)
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
            Text(stringResource(R.string.notif_title), style = MaterialTheme.typography.titleMedium)
            Text(
                when {
                    !enabled -> stringResource(R.string.notif_need_access)
                    allowedCount == 0 -> stringResource(R.string.notif_none_selected)
                    else -> pluralStringResource(R.plurals.apps_selected, allowedCount, allowedCount)
                },
                style = MaterialTheme.typography.bodySmall,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                if (!enabled) {
                    OutlinedButton(onClick = {
                        context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    }) { Text(stringResource(R.string.go_enable)) }
                }
                OutlinedButton(onClick = onManageApps) { Text(stringResource(R.string.choose_apps)) }
            }
        }
    }
}

@Composable
private fun DndCard(settings: SettingsUiState, onDndOnConnectChange: (Boolean) -> Unit, onRingCallsChange: (Boolean) -> Unit) {
    val context = LocalContext.current
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.dnd_title), style = MaterialTheme.typography.titleMedium)
            SwitchRow(stringResource(R.string.dnd_auto), stringResource(R.string.dnd_auto_sub), settings.dndOnConnect, onDndOnConnectChange)
            if (settings.dndOnConnect) {
                SwitchRow(stringResource(R.string.dnd_ring), null, settings.ringCalls, onRingCallsChange)
                if (!settings.dndAccess) {
                    Text(stringResource(R.string.dnd_need_policy), style = MaterialTheme.typography.bodySmall)
                    OutlinedButton(onClick = {
                        context.startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                    }) { Text(stringResource(R.string.go_grant)) }
                } else {
                    Text(
                        settings.dndError?.let { stringResource(R.string.dnd_error, it) }
                            ?: if (settings.dndActive) stringResource(R.string.dnd_active) else stringResource(R.string.dnd_inactive),
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        }
    }
}

@Composable
private fun FilesAccessCard(mediaAccess: Boolean, allFilesAccess: Boolean, onGrantMedia: () -> Unit) {
    val context = LocalContext.current
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.files_title), style = MaterialTheme.typography.titleMedium)
            Text(stringResource(R.string.files_desc), style = MaterialTheme.typography.bodySmall)
            AccessRow(stringResource(R.string.files_media), mediaAccess, onGrantMedia)
            AccessRow(stringResource(R.string.files_all), allFilesAccess) {
                val packageUri = "package:${context.packageName}".toUri()
                runCatching { context.startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, packageUri)) }
                    .onFailure { context.startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)) }
            }
        }
    }
}

@Composable
private fun EnhancedCard(ready: Boolean) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.enhanced_title), style = MaterialTheme.typography.titleMedium)
            Text(
                stringResource(if (ready) R.string.enhanced_running else R.string.enhanced_stopped),
                style = MaterialTheme.typography.bodySmall,
                color = if (ready) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun AccessRow(title: String, granted: Boolean, onGrant: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyMedium)
            Text(
                if (granted) stringResource(R.string.granted) else stringResource(R.string.not_granted),
                style = MaterialTheme.typography.bodySmall,
                color = if (granted) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
            )
        }
        if (!granted) OutlinedButton(onClick = onGrant) { Text(stringResource(R.string.go_grant)) }
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
            Text(stringResource(R.string.keepalive_title), style = MaterialTheme.typography.titleMedium)
            Text(
                stringResource(R.string.keepalive_steps),
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
                ) { Text(if (ignoring) stringResource(R.string.battery_opt_off) else stringResource(R.string.battery_opt_turn_off)) }
                TextButton(onClick = {
                    context.startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, "package:${context.packageName}".toUri()),
                    )
                }) { Text(stringResource(R.string.app_info)) }
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
        title = { Text(stringResource(R.string.pair_paste)) },
        text = {
            OutlinedTextField(
                value = text,
                onValueChange = { text = it; error = false },
                isError = error,
                supportingText = { if (error) Text(stringResource(R.string.link_invalid)) },
                placeholder = { Text("linktomacos://pair?…") },
            )
        },
        confirmButton = {
            TextButton(onClick = { if (onSubmit(text)) onDismiss() else error = true }) { Text(stringResource(R.string.pair)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}
