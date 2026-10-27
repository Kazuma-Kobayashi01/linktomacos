package com.linktomacos.android

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import com.linktomacos.android.data.LinkSettings
import com.linktomacos.android.data.PairingStore
import com.linktomacos.android.link.AirSend
import com.linktomacos.android.link.ClipboardSync
import com.linktomacos.android.mirror.EnhancedBridge

class LinkApp : Application() {
    val pairingStore by lazy { PairingStore(this) }
    val settings by lazy { LinkSettings(this) }
    val bridge by lazy { EnhancedBridge(this) }
    val clipboard by lazy { ClipboardSync(this, settings, bridge) }
    val airSend by lazy { AirSend(this) }

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_LINK, getString(R.string.channel_name), NotificationManager.IMPORTANCE_LOW).apply {
                description = getString(R.string.channel_desc)
                setShowBadge(false)
            },
        )
        manager.createNotificationChannel(NotificationChannel(CHANNEL_AIRSEND, getString(R.string.airsend_channel), NotificationManager.IMPORTANCE_DEFAULT))
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_AIRSEND_STATUS, getString(R.string.airsend_channel_status), NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) },
        )
    }

    companion object {
        const val CHANNEL_LINK = "link"
        /** AirSend 收到的文件和文字。 */
        const val CHANNEL_AIRSEND = "airsend"
        /** AirSend 的进度和发送结果，不打扰。 */
        const val CHANNEL_AIRSEND_STATUS = "airsend_status"
    }
}
