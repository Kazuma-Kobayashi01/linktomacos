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
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import com.linktomacos.android.data.PairedMac
import com.linktomacos.android.link.LinkState

@Composable
fun HomeScreen(
    state: LinkState,
    paired: PairedMac?,
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
