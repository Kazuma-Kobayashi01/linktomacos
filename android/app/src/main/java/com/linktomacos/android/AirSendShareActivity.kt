package com.linktomacos.android

import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import com.linktomacos.android.ipc.Control
import com.linktomacos.android.link.ShareReader
import kotlinx.coroutines.launch

/**
 * 系统分享面板里的 AirSend 入口。没有界面（透明、不留历史）：在这里读完分享内容（描述符此时才有读取权限），
 * 经 Binder 交给服务 App 去发，然后立刻关闭，回到用户刚才的应用。
 */
class AirSendShareActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val client = (application as UiApp).client
        val prepared = ShareReader.read(this, intent)
        if (prepared == null) {
            Toast.makeText(this, R.string.airsend_nothing, Toast.LENGTH_SHORT).show()
            finish()
            return
        }
        lifecycleScope.launch {
            client.startLink()
            val snapshot = if (client.awaitConnected()) client.awaitSnapshot() else null
            val mac = snapshot?.paired
            when {
                snapshot == null -> Toast.makeText(this@AirSendShareActivity, R.string.service_missing, Toast.LENGTH_LONG).show()
                mac == null -> Toast.makeText(this@AirSendShareActivity, R.string.airsend_not_paired, Toast.LENGTH_LONG).show()
                else -> {
                    client.send(Control.AIRSEND, prepared.toBundle())
                    ShareShortcut.reportUsed(this@AirSendShareActivity)
                    Toast.makeText(this@AirSendShareActivity, getString(R.string.airsend_sending, mac.name), Toast.LENGTH_SHORT).show()
                }
            }
            prepared.close()
            finish()
        }
    }
}
