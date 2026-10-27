package com.linktomacos.android.link

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.linktomacos.android.LinkApp

/** 开机或应用更新后，若已配对则拉起前台服务。 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> {
                val app = context.applicationContext as LinkApp
                if (app.pairingStore.paired.value != null) LinkService.start(context)
            }
        }
    }
}
