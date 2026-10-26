package com.linktomacos.android

import androidx.compose.ui.res.stringResource
import android.Manifest
import android.content.pm.PackageManager
import android.app.StatusBarManager
import android.content.ComponentName
import android.graphics.drawable.Icon
import android.os.Bundle
import android.os.Environment
import android.os.PowerManager
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
import com.linktomacos.android.link.DndController
import com.linktomacos.android.link.DndStatus
import com.linktomacos.android.link.LinkService
import com.linktomacos.android.link.LinkStatus
import com.linktomacos.android.link.LinkTileService
import com.linktomacos.android.link.PhoneNotificationListener
import com.linktomacos.android.protocol.PairingPayload
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
    private val store by lazy { (application as LinkApp).pairingStore }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            LinkTheme { App() }
        }
    }

    private val settings by lazy { (application as LinkApp).settings }
    private var listenerEnabled by mutableStateOf(false)
    private var dndAccess by mutableStateOf(false)
    private var mediaAccess by mutableStateOf(false)
    private var allFilesAccess by mutableStateOf(false)
    private var batteryIgnored by mutableStateOf(false)
    private val versionName by lazy { packageManager.getPackageInfo(packageName, 0).versionName ?: "" }

    override fun onResume() {
        super.onResume()
        listenerEnabled = PhoneNotificationListener.isEnabled(this)
        dndAccess = DndController.hasAccess(this)
        allFilesAccess = Environment.isExternalStorageManager()
        mediaAccess = checkSelfPermission(Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED
        batteryIgnored = getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName)
        if (store.paired.value != null) LinkService.start(this)
    }

    /** 回到前台时读一次剪贴板：没有增强服务时，这是手机上复制的文字能传给 Mac 的唯一时机。 */
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) (application as LinkApp).clipboard.onForeground()
    }

    /** 弹出系统对话框，问用户要不要把磁贴加到下拉面板。 */
    private fun requestTile() {
        getSystemService(StatusBarManager::class.java).requestAddTileService(
            ComponentName(this, LinkTileService::class.java),
            getString(R.string.tile_label),
            Icon.createWithResource(this, R.drawable.ic_launcher_monochrome),
            mainExecutor,
        ) { result ->
            if (result == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED ||
                result == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED
            ) settings.setTileAdded(true)
        }
    }

    private fun pair(text: String): Boolean {
        val payload = PairingPayload.parse(text) ?: return false
        store.pair(payload)
        LinkService.start(this)
        return true
    }

    @androidx.compose.runtime.Composable
    private fun App() {
        val state by LinkStatus.state.collectAsStateWithLifecycle()
        val paired by store.paired.collectAsStateWithLifecycle()
        var scanning by remember { mutableStateOf(false) }
        var page by rememberSaveable { mutableStateOf(Page.Home) }
        val allowedApps by settings.allowedApps.collectAsStateWithLifecycle()
        val dndOnConnect by settings.dndOnConnect.collectAsStateWithLifecycle()
        val ringCalls by settings.ringCalls.collectAsStateWithLifecycle()
        val clipboardSync by settings.clipboardSync.collectAsStateWithLifecycle()
        val tileAdded by settings.tileAdded.collectAsStateWithLifecycle()
        val dndActive by DndStatus.active.collectAsStateWithLifecycle()
        val dndError by DndStatus.error.collectAsStateWithLifecycle()
        val enhancedReady by (application as LinkApp).bridge.ready.collectAsStateWithLifecycle()

        val notificationPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {}
        LaunchedEffect(Unit) {
            notificationPermission.launch(arrayOf(Manifest.permission.POST_NOTIFICATIONS, Manifest.permission.READ_PHONE_STATE))
        }
        val mediaPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
            mediaAccess = checkSelfPermission(Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED
        }
        val cameraPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) scanning = true
            else Toast.makeText(this, getString(R.string.need_camera), Toast.LENGTH_SHORT).show()
        }

        val ui = SettingsUiState(
            notificationAccess = listenerEnabled,
            allowedCount = allowedApps.size,
            dndOnConnect = dndOnConnect,
            ringCalls = ringCalls,
            dndAccess = dndAccess,
            dndActive = dndActive,
            dndError = dndError,
            mediaAccess = mediaAccess,
            allFilesAccess = allFilesAccess,
            enhancedReady = enhancedReady,
            clipboardSync = clipboardSync,
            batteryOptimizationIgnored = batteryIgnored,
            versionName = versionName,
            tileAdded = tileAdded,
        )
        val actions = UiActions(
            onOpen = { page = it },
            onScan = { cameraPermission.launch(Manifest.permission.CAMERA) },
            onPairLink = ::pair,
            onUnpair = {
                store.unpair()
                LinkService.stop(this)
            },
            onGrantMedia = {
                mediaPermission.launch(arrayOf(
                    Manifest.permission.READ_MEDIA_IMAGES,
                    Manifest.permission.READ_MEDIA_VIDEO,
                    Manifest.permission.ACCESS_MEDIA_LOCATION,
                ))
            },
            onDndOnConnectChange = settings::setDndOnConnect,
            onRingCallsChange = settings::setRingCalls,
            onClipboardChange = settings::setClipboardSync,
            onToggleApp = settings::setAllowed,
            onAddTile = ::requestTile,
        )

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
                    Page.Apps -> AppPickerScreen(allowedApps, settings::setAllowed, back)
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
