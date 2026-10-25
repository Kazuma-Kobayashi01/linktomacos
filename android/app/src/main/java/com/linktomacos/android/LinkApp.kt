package com.linktomacos.android

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import com.linktomacos.android.data.LinkSettings
import com.linktomacos.android.data.PairingStore
import com.linktomacos.android.mirror.EnhancedBridge

class LinkApp : Application() {
    val pairingStore by lazy { PairingStore(this) }
    val settings by lazy { LinkSettings(this) }
    val bridge by lazy { EnhancedBridge(this) }

    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL_LINK, getString(R.string.channel_name), NotificationManager.IMPORTANCE_LOW).apply {
                description = getString(R.string.channel_desc)
                setShowBadge(false)
            },
        )
    }

    companion object {
        const val CHANNEL_LINK = "link"
    }
}
