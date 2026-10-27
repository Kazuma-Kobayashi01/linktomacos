package com.linktomacos.android.ui

import android.annotation.SuppressLint
import android.content.Intent
import com.linktomacos.android.UiApp
import com.linktomacos.android.ipc.Control
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import com.linktomacos.android.R
import com.linktomacos.android.data.PairedMac

@Composable
fun NotificationsPage(ui: SettingsUiState, actions: UiActions, onBack: () -> Unit) {
    val context = LocalContext.current
    FeaturePage(stringResource(R.string.notif_title), listOf(LinkIcons.Bell, LinkIcons.Phone, LinkIcons.Laptop), stringResource(R.string.notif_summary), onBack) {
        ListCard {
            PermissionRow(stringResource(R.string.notif_access_title), ui.notificationAccess, onGrant = {
                context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
            })
            RowDivider()
            NavRow(
                LinkIcons.Bell, stringResource(R.string.choose_apps),
                if (ui.allowedCount == 0) stringResource(R.string.notif_none_selected)
                else pluralStringResource(R.plurals.apps_forwarding, ui.allowedCount, ui.allowedCount),
                onClick = { actions.onOpen(Page.Apps) },
            )
        }
        if (!ui.notificationAccess) Hint(stringResource(R.string.notif_need_access))
    }
}

@Composable
fun ClipboardPage(ui: SettingsUiState, actions: UiActions, onBack: () -> Unit) {
    FeaturePage(stringResource(R.string.clip_title), listOf(LinkIcons.Clipboard, LinkIcons.Link, LinkIcons.Laptop), stringResource(R.string.clip_summary), onBack) {
        ListCard {
            ToggleRow(stringResource(R.string.clip_toggle), stringResource(R.string.clip_toggle_sub), ui.clipboardSync, actions.onClipboardChange)
        }
        if (ui.clipboardSync) {
            ListCard {
                NavRow(
                    LinkIcons.Bolt,
                    stringResource(if (ui.enhancedReady) R.string.clip_mode_realtime else R.string.clip_mode_limited),
                    stringResource(if (ui.enhancedReady) R.string.clip_mode_realtime_sub else R.string.clip_mode_limited_sub),
                    onClick = { actions.onOpen(Page.Mirror) },
                    attention = false,
                )
            }
        }
        Hint(stringResource(R.string.clip_privacy))
    }
}

@Composable
fun AirSendPage(onBack: () -> Unit) {
    FeaturePage(stringResource(R.string.airsend_name), listOf(LinkIcons.Phone2Mac, LinkIcons.Folder, LinkIcons.Clipboard), stringResource(R.string.airsend_summary), onBack) {
        SectionLabel(stringResource(R.string.airsend_howto_title))
        Hint(stringResource(R.string.airsend_howto))
        Hint(stringResource(R.string.airsend_saved_to))
    }
}

@Composable
fun FilesPage(ui: SettingsUiState, actions: UiActions, onBack: () -> Unit) {
    val context = LocalContext.current
    FeaturePage(stringResource(R.string.files_title), listOf(LinkIcons.Folder, LinkIcons.Shield, LinkIcons.Laptop), stringResource(R.string.files_desc), onBack) {
        ListCard {
            PermissionRow(stringResource(R.string.files_media), ui.mediaAccess, actions.onGrantMedia)
            RowDivider()
            PermissionRow(stringResource(R.string.files_all), ui.allFilesAccess, onGrant = {
                val packageUri = "package:${Control.SERVICE_PACKAGE}".toUri()
                runCatching { context.startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, packageUri)) }
                    .onFailure { context.startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)) }
            })
        }
    }
}

@Composable
fun MirrorPage(ui: SettingsUiState, onBack: () -> Unit) {
    FeaturePage(stringResource(R.string.enhanced_title), listOf(LinkIcons.Monitor, LinkIcons.Bolt, LinkIcons.Phone), stringResource(R.string.mirror_summary), onBack) {
        ListCard {
            NavRow(
                LinkIcons.Bolt, stringResource(if (ui.enhancedReady) R.string.row_mirror_running else R.string.row_mirror_stopped),
                stringResource(if (ui.enhancedReady) R.string.enhanced_running else R.string.enhanced_stopped),
                onClick = {},
            )
        }
        if (!ui.enhancedReady) {
            SectionLabel(stringResource(R.string.mirror_howto_title))
            Hint(stringResource(R.string.mirror_howto))
        }
        Hint(stringResource(R.string.mirror_features))
    }
}

@Composable
fun DndPage(ui: SettingsUiState, actions: UiActions, onBack: () -> Unit) {
    val context = LocalContext.current
    FeaturePage(stringResource(R.string.dnd_title), listOf(LinkIcons.Moon, LinkIcons.Bell, LinkIcons.Phone), stringResource(R.string.dnd_summary), onBack) {
        ListCard {
            ToggleRow(stringResource(R.string.dnd_auto), stringResource(R.string.dnd_auto_sub), ui.dndOnConnect, actions.onDndOnConnectChange)
            RowDivider()
            ToggleRow(stringResource(R.string.dnd_ring), null, ui.ringCalls, actions.onRingCallsChange, enabled = ui.dndOnConnect)
        }
        if (ui.dndOnConnect) {
            ListCard {
                PermissionRow(stringResource(R.string.dnd_access_title), ui.dndAccess, onGrant = {
                    context.startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                })
            }
            Hint(
                when {
                    !ui.dndAccess -> stringResource(R.string.dnd_need_policy)
                    ui.dndError != null -> stringResource(R.string.dnd_error, ui.dndError)
                    ui.dndActive -> stringResource(R.string.dnd_active)
                    else -> stringResource(R.string.dnd_inactive)
                },
            )
        }
        Hint(stringResource(R.string.dnd_calls_hint))
    }
}

/** One UI 会积极清理后台，这里引导关闭电池优化并加入“从不休眠的应用”。 */
@SuppressLint("BatteryLife")
@Composable
fun KeepAlivePage(ui: SettingsUiState, onBack: () -> Unit) {
    val context = LocalContext.current
    FeaturePage(stringResource(R.string.keepalive_title), listOf(LinkIcons.Bolt, LinkIcons.Phone, LinkIcons.Link), stringResource(R.string.keepalive_summary), onBack) {
        ListCard {
            PermissionRow(
                stringResource(R.string.battery_opt_title), ui.batteryOptimizationIgnored,
                onGrant = {
                    (context.applicationContext as UiApp).client.runAction(Control.KIND_BATTERY)
                },
                actionLabel = stringResource(R.string.battery_opt_turn_off),
            )
        }
        SectionLabel(stringResource(R.string.keepalive_more))
        Hint(stringResource(R.string.keepalive_steps))
        Row(Modifier.padding(horizontal = 4.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = {
                context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, "package:${Control.SERVICE_PACKAGE}".toUri()))
            }) { Text(stringResource(R.string.app_info)) }
        }
    }
}

@Composable
fun AboutPage(paired: PairedMac?, ui: SettingsUiState, actions: UiActions, onBack: () -> Unit) {
    var confirmUnpair by remember { mutableStateOf(false) }
    FeaturePage(stringResource(R.string.about_title), listOf(LinkIcons.Link, LinkIcons.Phone, LinkIcons.Laptop), stringResource(R.string.about_summary), onBack) {
        ListCard {
            InfoRow(stringResource(R.string.about_version), ui.versionName)
            RowDivider()
            ColorsRow()
            RowDivider()
            InfoRow(stringResource(R.string.about_license), "MIT")
            if (paired != null) {
                RowDivider()
                InfoRow(stringResource(R.string.about_paired_mac), paired.name)
            }
        }
        if (paired != null) {
            FilledTonalButton(
                onClick = { confirmUnpair = true },
                colors = ButtonDefaults.filledTonalButtonColors(
                    containerColor = MaterialTheme.colorScheme.errorContainer,
                    contentColor = MaterialTheme.colorScheme.onErrorContainer,
                ),
                modifier = Modifier.fillMaxWidth(),
            ) { Text(stringResource(R.string.unpair)) }
        }
    }
    if (confirmUnpair) {
        AlertDialog(
            onDismissRequest = { confirmUnpair = false },
            title = { Text(stringResource(R.string.unpair_confirm_title)) },
            text = { Text(stringResource(R.string.unpair_confirm_body, paired?.name.orEmpty())) },
            confirmButton = {
                TextButton(onClick = { confirmUnpair = false; actions.onUnpair(); onBack() }) { Text(stringResource(R.string.unpair)) }
            },
            dismissButton = { TextButton(onClick = { confirmUnpair = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 16.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = MaterialTheme.typography.titleMedium)
        Text(value, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** 显示当前取到的系统调色盘颜色。 */
@Composable
private fun ColorsRow() {
    val colors = MaterialTheme.colorScheme
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 16.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(stringResource(R.string.about_colors), style = MaterialTheme.typography.titleMedium)
            Text(stringResource(R.string.about_colors_sub), style = MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant)
        }
        Row(horizontalArrangement = Arrangement.spacedBy((-6).dp)) {
            for (color in listOf(colors.primary, colors.secondary, colors.tertiary, colors.primaryContainer)) {
                Box(
                    Modifier.size(26.dp)
                        .background(color, androidx.compose.foundation.shape.CircleShape)
                        .border(2.dp, colors.surfaceContainerLow, androidx.compose.foundation.shape.CircleShape),
                )
            }
        }
    }
}
