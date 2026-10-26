package com.linktomacos.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.linktomacos.android.R
import com.linktomacos.android.data.PairedMac
import com.linktomacos.android.link.LinkState

/** 首页：没配对时是介绍和配对入口，配对后是连接状态、快捷开关和各功能的入口。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    state: LinkState,
    paired: PairedMac?,
    ui: SettingsUiState,
    actions: UiActions,
    modifier: Modifier = Modifier,
) {
    var showPaste by remember { mutableStateOf(false) }
    if (paired == null) {
        OnboardingScreen(onScan = actions.onScan, onPaste = { showPaste = true }, modifier = modifier)
    } else {
        var menuOpen by remember { mutableStateOf(false) }
        Scaffold(
            modifier = modifier,
            containerColor = Color.Transparent,
            topBar = {
                TopAppBar(
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent, scrolledContainerColor = Color.Transparent),
                    title = { Text("Link to macOS", style = MaterialTheme.typography.titleLarge) },
                    actions = {
                        IconButton(onClick = { menuOpen = true }) {
                            Icon(LinkIcons.MoreVert, contentDescription = stringResource(R.string.more))
                        }
                        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.re_pair)) },
                                onClick = { menuOpen = false; actions.onScan() },
                            )
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.about_title)) },
                                onClick = { menuOpen = false; actions.onOpen(Page.About) },
                            )
                        }
                    },
                )
            },
        ) { padding ->
            Column(
                modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                StatusHero(state, paired.name)
                QuickTiles(ui, actions)
                FeatureList(ui, actions)
                Box(Modifier.size(8.dp))
            }
        }
    }
    if (showPaste) PasteDialog(onDismiss = { showPaste = false }, onSubmit = actions.onPairLink)
}

// MARK: 连接状态

@Composable
private fun StatusHero(state: LinkState, macName: String) {
    val (title, detail, tone) = when (state) {
        LinkState.NotPaired -> Triple(stringResource(R.string.state_not_paired_title), stringResource(R.string.state_not_paired_detail), Tone.Neutral)
        is LinkState.Searching -> Triple(stringResource(R.string.state_searching_title), null, Tone.Busy)
        is LinkState.Connected -> Triple(stringResource(R.string.state_connected_title), state.host, Tone.Good)
        is LinkState.Waiting -> Triple(stringResource(R.string.state_waiting_title), stringResource(R.string.state_waiting_detail, state.reason, state.retryInSeconds), Tone.Neutral)
        is LinkState.Rejected -> Triple(stringResource(R.string.state_rejected_title), stringResource(R.string.state_rejected_detail, state.macName, state.reason), Tone.Bad)
    }
    val colors = MaterialTheme.colorScheme
    val onContainer = if (tone == Tone.Bad) colors.onErrorContainer else colors.onPrimaryContainer
    HeroCard {
        HeroIllustration(listOf(LinkIcons.Bell, LinkIcons.Clipboard, LinkIcons.Monitor), Modifier.fillMaxWidth(0.78f))
        Text(macName, style = MaterialTheme.typography.headlineSmall, textAlign = TextAlign.Center, color = onContainer)
        // 状态胶囊：颜色随状态变
        Surface(
            shape = RoundedCornerShape(50),
            color = when (tone) {
                Tone.Good -> colors.primary
                Tone.Bad -> colors.errorContainer
                else -> colors.surface.copy(alpha = 0.7f)
            },
            contentColor = when (tone) {
                Tone.Good -> colors.onPrimary
                Tone.Bad -> colors.onErrorContainer
                else -> colors.onSurface
            },
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp),
            ) {
                when (tone) {
                    Tone.Busy -> CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp, color = LocalContentColor.current)
                    Tone.Good -> Icon(LinkIcons.Check, contentDescription = null, modifier = Modifier.size(16.dp))
                    else -> Box(Modifier.size(8.dp).background(LocalContentColor.current.copy(alpha = 0.6f), CircleShape))
                }
                Text(title, style = MaterialTheme.typography.labelLarge)
            }
        }
        if (detail != null) {
            Text(detail, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center, color = onContainer.copy(alpha = 0.8f))
        }
    }
}

private enum class Tone { Good, Busy, Neutral, Bad }

// MARK: 快捷开关

@Composable
private fun QuickTiles(ui: SettingsUiState, actions: UiActions) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
        QuickTile(
            icon = LinkIcons.Clipboard,
            accent = Accent.Primary,
            label = stringResource(R.string.tile_clipboard),
            status = stringResource(if (ui.clipboardSync) R.string.switch_on else R.string.switch_off),
            active = ui.clipboardSync,
            onClick = { actions.onClipboardChange(!ui.clipboardSync) },
            modifier = Modifier.weight(1f),
        )
        QuickTile(
            icon = LinkIcons.Moon,
            accent = Accent.Tertiary,
            label = stringResource(R.string.tile_dnd),
            status = stringResource(if (ui.dndOnConnect) R.string.switch_on else R.string.switch_off),
            active = ui.dndOnConnect,
            onClick = { actions.onDndOnConnectChange(!ui.dndOnConnect) },
            modifier = Modifier.weight(1f),
        )
        QuickTile(
            icon = LinkIcons.Monitor,
            accent = Accent.Secondary,
            label = stringResource(R.string.tile_mirror),
            status = stringResource(if (ui.enhancedReady) R.string.tile_running else R.string.tile_stopped),
            active = ui.enhancedReady,
            onClick = { actions.onOpen(Page.Mirror) },
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun QuickTile(
    icon: ImageVector,
    accent: Accent,
    label: String,
    status: String,
    active: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.colorScheme
    Surface(
        onClick = onClick,
        modifier = modifier,
        shape = RoundedCornerShape(24.dp),
        color = if (active) accent.solid() else colors.surfaceContainerHigh,
        contentColor = if (active) accent.onSolid() else colors.onSurfaceVariant,
    ) {
        Column(
            modifier = Modifier.padding(vertical = 16.dp, horizontal = 8.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(26.dp))
            Text(label, style = MaterialTheme.typography.labelLarge, maxLines = 1)
            Text(status, style = MaterialTheme.typography.bodySmall, maxLines = 1, color = LocalContentColor.current.copy(alpha = 0.8f))
        }
    }
}

// MARK: 功能入口

@Composable
private fun FeatureList(ui: SettingsUiState, actions: UiActions) {
    ListCard {
        NavRow(
            LinkIcons.Bell, stringResource(R.string.notif_title),
            when {
                !ui.notificationAccess -> stringResource(R.string.row_notif_off)
                ui.allowedCount == 0 -> stringResource(R.string.row_notif_none)
                else -> pluralStringResource(R.plurals.apps_forwarding, ui.allowedCount, ui.allowedCount)
            },
            onClick = { actions.onOpen(Page.Notifications) },
            accent = Accent.Primary,
            attention = !ui.notificationAccess,
        )
        RowDivider()
        NavRow(
            LinkIcons.Clipboard, stringResource(R.string.clip_title),
            stringResource(
                if (!ui.clipboardSync) R.string.switch_off
                else if (ui.enhancedReady) R.string.row_clip_realtime else R.string.row_clip_limited,
            ),
            onClick = { actions.onOpen(Page.Clipboard) },
            accent = Accent.Tertiary,
        )
        RowDivider()
        NavRow(
            LinkIcons.Phone2Mac, stringResource(R.string.airsend_name), stringResource(R.string.airsend_row_sub),
            onClick = { actions.onOpen(Page.AirSend) },
            accent = Accent.Primary,
        )
        RowDivider()
        val missing = listOf(ui.mediaAccess, ui.allFilesAccess).count { !it }
        NavRow(
            LinkIcons.Folder, stringResource(R.string.files_title),
            if (missing == 0) stringResource(R.string.row_files_ok) else stringResource(R.string.row_files_missing, missing),
            onClick = { actions.onOpen(Page.Files) },
            accent = Accent.Secondary,
            attention = missing > 0,
        )
        RowDivider()
        NavRow(
            LinkIcons.Monitor, stringResource(R.string.enhanced_title),
            stringResource(if (ui.enhancedReady) R.string.row_mirror_running else R.string.row_mirror_stopped),
            onClick = { actions.onOpen(Page.Mirror) },
            accent = Accent.Primary,
        )
        RowDivider()
        val dndNeedsAccess = ui.dndOnConnect && !ui.dndAccess
        NavRow(
            LinkIcons.Moon, stringResource(R.string.dnd_title),
            when {
                dndNeedsAccess -> stringResource(R.string.row_dnd_need_access)
                ui.dndOnConnect -> stringResource(R.string.row_dnd_on)
                else -> stringResource(R.string.switch_off)
            },
            onClick = { actions.onOpen(Page.Dnd) },
            accent = Accent.Tertiary,
            attention = dndNeedsAccess,
        )
        RowDivider()
        NavRow(
            LinkIcons.Bolt, stringResource(R.string.keepalive_title),
            stringResource(if (ui.batteryOptimizationIgnored) R.string.battery_opt_off else R.string.row_battery_suggest),
            onClick = { actions.onOpen(Page.KeepAlive) },
            accent = Accent.Secondary,
            attention = !ui.batteryOptimizationIgnored,
        )
    }
    if (!ui.tileAdded) {
        ListCard {
            NavRow(LinkIcons.Link, stringResource(R.string.qs_add_title), stringResource(R.string.qs_add_sub), onClick = actions.onAddTile)
        }
    }
}

// MARK: 配对链接

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
