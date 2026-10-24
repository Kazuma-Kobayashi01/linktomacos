package com.linktomacos.android

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import com.linktomacos.android.data.PairingStore

class LinkApp : Application() {
    val pairingStore by lazy { PairingStore(this) }

    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL_LINK, "连接状态", NotificationManager.IMPORTANCE_LOW).apply {
                description = "与 Mac 的连接状态（常驻）"
                setShowBadge(false)
            },
        )
    }

    companion object {
        const val CHANNEL_LINK = "link"
    }
}
