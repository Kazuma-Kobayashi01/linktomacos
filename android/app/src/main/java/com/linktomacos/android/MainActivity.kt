package com.linktomacos.android

import androidx.compose.ui.res.stringResource
import android.Manifest
import android.content.pm.PackageManager
import android.app.StatusBarManager
import android.content.ComponentName
import android.graphics.drawable.Icon
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.linktomacos.android.link.LinkTileService
import android.content.ClipDescription
import android.content.ClipboardManager
import android.os.Bundle as AndroidBundle
import com.linktomacos.android.ipc.Control
import com.linktomacos.android.link.LinkState
import com.linktomacos.android.protocol.PairingPayload
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import com.linktomacos.android.ui.AppPickerScreen
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.IntOffset
import com.linktomacos.android.ui.LinkTheme
import com.linktomacos.android.ui.Page
import com.linktomacos.android.ui.screenWash
import com.linktomacos.android.ui.UiActions
import com.linktomacos.android.ui.NotificationsPage
import com.linktomacos.android.ui.ClipboardPage
import com.linktomacos.android.ui.FilesPage
import com.linktomacos.android.ui.MirrorPage
import com.linktomacos.android.ui.DndPage
import com.linktomacos.android.ui.KeepAlivePage
import com.linktomacos.android.ui.AboutPage
import com.linktomacos.android.ui.AirSendPage

import com.linktomacos.android.ui.HomeScreen
import com.linktomacos.android.ui.QrScanner
import com.linktomacos.android.ui.SettingsUiState

class MainActivity : ComponentActivity() {
    private val client by lazy { (application as UiApp).client }
    /** 每次回到前台加一，让“已配对就拉起服务”的副作用重新跑一遍。 */
    private var resumeTick by mutableStateOf(0)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            LinkTheme { App() }
        }
    }

    private val versionName by lazy { packageManager.getPackageInfo(packageName, 0).versionName ?: "" }

    override fun onStart() {
        super.onStart()
        client.connect()
    }

    override fun onResume() {
        super.onResume()
        client.refresh() // 权限可能刚在系统设置里改过
        resumeTick++
    }

    override fun onStop() {
        client.disconnect()
        super.onStop()
    }

    /** 回到前台时读一次剪贴板：没有增强服务时，这是手机上复制的文字能传给 Mac 的唯一时机。读到的交给服务 App 判断要不要用。 */
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) return
        val clip = runCatching { getSystemService(ClipboardManager::class.java).primaryClip }.getOrNull() ?: return
        if (clip.itemCount == 0) return
        if (clip.description?.extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE, false) == true) return
        val text = clip.getItemAt(0).text?.toString() ?: return
        client.send(Control.CLIPBOARD, AndroidBundle().apply { putString("text", text) })
    }

    /** 弹出系统对话框，问用户要不要把磁贴加到下拉面板。 */
    private fun requestTile() {
        getSystemService(StatusBarManager::class.java).requestAddTileService(
            ComponentName(this, LinkTileService::class.java),
            getString(R.string.tile_label),
            Icon.createWithResource(this, R.drawable.ic_tile),
            mainExecutor,
        ) { result ->
            if (result == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED ||
                result == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED
            ) client.set(Control.SET_TILE_ADDED, true)
        }
    }

    private fun pair(text: String): Boolean {
        if (PairingPayload.parse(text) == null) return false
        client.send(Control.PAIR, AndroidBundle().apply { putString("text", text) })
        client.startLink()
        return true
    }

    @androidx.compose.runtime.Composable
    private fun App() {
        val snapshot by client.snapshot.collectAsStateWithLifecycle()
        val missing by client.missing.collectAsStateWithLifecycle()
        var scanning by remember { mutableStateOf(false) }
        var page by rememberSaveable { mutableStateOf(Page.Home) }

        val snap = snapshot
        if (snap == null) {
            Column(
                Modifier.fillMaxSize().screenWash().systemBarsPadding().padding(32.dp),
                verticalArrangement = Arrangement.Center,
            ) {
                if (missing) {
                    Text(stringResource(R.string.service_missing), style = MaterialTheme.typography.titleLarge)
                    Text(stringResource(R.string.service_missing_detail), modifier = Modifier.padding(top = 8.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            return
        }
        val paired = snap.paired

        // 已配对就把服务 App 的前台服务拉起来（它没有图标，用户不会自己去打开）；回到前台时再确认一次
        LaunchedEffect(paired?.fingerprint, resumeTick) { if (paired != null) client.startLink() }
        // 分享面板最上面一排的“直接分享”目标，跟着配对走
        LaunchedEffect(paired?.name) { ShareShortcut.publish(this@MainActivity, paired?.name) }
        // 首次打开时让服务 App 申请通知和电话状态权限（只问一次）
        LaunchedEffect(Unit) {
            val prefs = getSharedPreferences("ui", MODE_PRIVATE)
            if (!prefs.getBoolean("asked_notify", false)) {
                prefs.edit().putBoolean("asked_notify", true).apply()
                client.runAction(Control.KIND_NOTIFY)
            }
        }
        val cameraPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) scanning = true
            else Toast.makeText(this, getString(R.string.need_camera), Toast.LENGTH_SHORT).show()
        }

        val ui = SettingsUiState(
            notificationAccess = snap.notificationAccess,
            allowedCount = snap.allowedApps.size,
            dndOnConnect = snap.dndOnConnect,
            ringCalls = snap.ringCalls,
            dndAccess = snap.dndAccess,
            dndActive = snap.dndActive,
            dndError = snap.dndError,
            mediaAccess = snap.mediaAccess,
            allFilesAccess = snap.allFilesAccess,
            enhancedReady = snap.enhancedReady,
            clipboardSync = snap.clipboardSync,
            batteryOptimizationIgnored = snap.batteryIgnored,
            versionName = versionName,
            tileAdded = snap.tileAdded,
        )
        val actions = UiActions(
            onOpen = { page = it },
            onScan = { cameraPermission.launch(Manifest.permission.CAMERA) },
            onPairLink = ::pair,
            onUnpair = {
                client.send(Control.UNPAIR)
                ShareShortcut.publish(this, null)
            },
            onGrantMedia = { client.runAction(Control.KIND_MEDIA) },
            onDndOnConnectChange = { client.set(Control.SET_DND_ON_CONNECT, it) },
            onRingCallsChange = { client.set(Control.SET_RING_CALLS, it) },
            onClipboardChange = { client.set(Control.SET_CLIPBOARD, it) },
            onToggleApp = client::setApp,
            onAddTile = ::requestTile,
        )
        val state = snap.link

        if (scanning) {
            BackHandler { scanning = false }
            Box(Modifier.fillMaxSize().background(Color.Black).systemBarsPadding()) {
                QrScanner(
                    modifier = Modifier.fillMaxSize(),
                    onResult = { text ->
                        scanning = false
                        if (!pair(text)) Toast.makeText(this@MainActivity, getString(R.string.not_pairing_code), Toast.LENGTH_SHORT).show()
                    },
                )
                Text(
                    stringResource(R.string.scan_hint),
                    modifier = Modifier.align(Alignment.BottomCenter).padding(32.dp),
                    color = darkColorScheme().onSurface,
                )
            }
        } else {
            // 没配对时回到首页（配对页只有首页的介绍）
            val current = if (paired == null) Page.Home else page
            current.parent?.let { parent -> BackHandler { page = parent } }
            AnimatedContent(
                targetState = current,
                transitionSpec = {
                    val deeper = targetState.depth() > initialState.depth()
                    val slide = tween<IntOffset>(260)
                    (slideInHorizontally(slide) { if (deeper) it / 4 else -it / 4 } + fadeIn(tween(220))) togetherWith
                        (slideOutHorizontally(slide) { if (deeper) -it / 4 else it / 4 } + fadeOut(tween(160)))
                },
                label = "page",
                modifier = Modifier.fillMaxSize().screenWash(),
            ) { target ->
                val back = { page = target.parent ?: Page.Home }
                when (target) {
                    Page.Home -> HomeScreen(state, paired, ui, actions)
                    Page.Notifications -> NotificationsPage(ui, actions, back)
                    Page.Apps -> AppPickerScreen(snap.allowedApps, client::setApp, back)
                    Page.Clipboard -> ClipboardPage(ui, actions, back)
                    Page.AirSend -> AirSendPage(back)
                    Page.Files -> FilesPage(ui, actions, back)
                    Page.Mirror -> MirrorPage(ui, back)
                    Page.Dnd -> DndPage(ui, actions, back)
                    Page.KeepAlive -> KeepAlivePage(ui, back)
                    Page.About -> AboutPage(paired, ui, actions, back)
                }
            }
        }
    }
}

private fun Page.depth(): Int = if (parent == null) 0 else parent!!.depth() + 1
