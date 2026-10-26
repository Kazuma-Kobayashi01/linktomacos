package com.linktomacos.android

import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import com.linktomacos.android.link.LinkService

/**
 * 系统分享面板里的 AirSend 入口。没有界面（透明、不留历史）：读完分享内容就交给 [com.linktomacos.android.link.AirSend]，
 * 立刻关闭，回到用户刚才的应用。
 */
class AirSendShareActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val app = application as LinkApp
        val paired = app.pairingStore.paired.value
        val prepared = if (paired == null) null else app.airSend.prepare(intent)
        when {
            paired == null -> Toast.makeText(this, R.string.airsend_not_paired, Toast.LENGTH_LONG).show()
            prepared == null -> Toast.makeText(this, R.string.airsend_nothing, Toast.LENGTH_SHORT).show()
            else -> {
                if (!app.airSend.connected) LinkService.start(this)
                app.airSend.send(prepared)
                app.airSend.reportShortcutUsed()
                Toast.makeText(this, getString(R.string.airsend_sending, paired.name), Toast.LENGTH_SHORT).show()
            }
        }
        finish()
    }
}
