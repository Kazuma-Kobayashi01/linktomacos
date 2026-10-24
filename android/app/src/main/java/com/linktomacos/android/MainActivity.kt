package com.linktomacos.android

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Environment
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
import androidx.compose.material3.Scaffold
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
import com.linktomacos.android.link.PhoneNotificationListener
import com.linktomacos.android.protocol.PairingPayload
import com.linktomacos.android.ui.AppPickerScreen
import com.linktomacos.android.ui.HomeScreen
import com.linktomacos.android.ui.QrScanner
import com.linktomacos.android.ui.SettingsUiState

class MainActivity : ComponentActivity() {
    private val store by lazy { (application as LinkApp).pairingStore }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val context = LocalContext.current
            val dark = isSystemInDarkTheme()
            val colors = if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
            MaterialTheme(colorScheme = colors) { App() }
        }
    }

    private val settings by lazy { (application as LinkApp).settings }
    private var listenerEnabled by mutableStateOf(false)
    private var dndAccess by mutableStateOf(false)
    private var mediaAccess by mutableStateOf(false)
    private var allFilesAccess by mutableStateOf(false)

    override fun onResume() {
        super.onResume()
        listenerEnabled = PhoneNotificationListener.isEnabled(this)
        dndAccess = DndController.hasAccess(this)
        allFilesAccess = Environment.isExternalStorageManager()
        mediaAccess = checkSelfPermission(Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED
        if (store.paired.value != null) LinkService.start(this)
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
        var pickingApps by remember { mutableStateOf(false) }
        val allowedApps by settings.allowedApps.collectAsStateWithLifecycle()
        val dndOnConnect by settings.dndOnConnect.collectAsStateWithLifecycle()
        val ringCalls by settings.ringCalls.collectAsStateWithLifecycle()
        val dndActive by DndStatus.active.collectAsStateWithLifecycle()
        val dndError by DndStatus.error.collectAsStateWithLifecycle()

        val notificationPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {}
        LaunchedEffect(Unit) {
            notificationPermission.launch(arrayOf(Manifest.permission.POST_NOTIFICATIONS, Manifest.permission.READ_PHONE_STATE))
        }
        val mediaPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
            mediaAccess = checkSelfPermission(Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED
        }
        val cameraPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) scanning = true
            else Toast.makeText(this, "需要相机权限才能扫码", Toast.LENGTH_SHORT).show()
        }

        Scaffold { padding ->
            if (scanning) {
                BackHandler { scanning = false }
                Box(Modifier.fillMaxSize().padding(padding)) {
                    QrScanner(
                        modifier = Modifier.fillMaxSize(),
                        onResult = { text ->
                            scanning = false
                            if (!pair(text)) Toast.makeText(this@MainActivity, "不是 LinkToMacOS 的配对码", Toast.LENGTH_SHORT).show()
                        },
                    )
                    Text(
                        "对准 Mac 上的配对二维码",
                        modifier = Modifier.align(Alignment.BottomCenter).padding(32.dp),
                        color = darkColorScheme().onSurface,
                    )
                }
            } else if (pickingApps) {
                BackHandler { pickingApps = false }
                AppPickerScreen(
                    allowed = allowedApps,
                    onToggle = settings::setAllowed,
                    onBack = { pickingApps = false },
                    modifier = Modifier.padding(padding),
                )
            } else {
                HomeScreen(
                    state = state,
                    paired = paired,
                    settings = SettingsUiState(
                        notificationAccess = listenerEnabled,
                        allowedCount = allowedApps.size,
                        dndOnConnect = dndOnConnect,
                        ringCalls = ringCalls,
                        dndAccess = dndAccess,
                        dndActive = dndActive,
                        dndError = dndError,
                        mediaAccess = mediaAccess,
                        allFilesAccess = allFilesAccess,
                    ),
                    onGrantMedia = {
                        mediaPermission.launch(arrayOf(
                            Manifest.permission.READ_MEDIA_IMAGES,
                            Manifest.permission.READ_MEDIA_VIDEO,
                            Manifest.permission.ACCESS_MEDIA_LOCATION,
                        ))
                    },
                    onManageApps = { pickingApps = true },
                    onDndOnConnectChange = settings::setDndOnConnect,
                    onRingCallsChange = settings::setRingCalls,
                    onScan = { cameraPermission.launch(Manifest.permission.CAMERA) },
                    onPairLink = ::pair,
                    onUnpair = {
                        store.unpair()
                        LinkService.stop(this)
                    },
                    modifier = Modifier.padding(padding),
                )
            }
        }
    }
}
