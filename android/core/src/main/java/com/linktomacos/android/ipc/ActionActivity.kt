package com.linktomacos.android.ipc

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import androidx.core.net.toUri

/**
 * 服务 App 没有桌面图标，也没有界面，但有些操作只能由它自己发起：申请运行时权限、申请忽略电池优化。
 * 界面 App 拉起这个透明页，办完就关。另外系统“模式”里点“已连接 Mac”规则的设置时也会落到这里，转去界面 App。
 */
class ActionActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent.action == "android.app.action.AUTOMATIC_ZEN_RULE") {
            startActivity(Control.uiIntent())
            finish()
            return
        }
        when (intent.getStringExtra(Control.EXTRA_KIND)) {
            Control.KIND_NOTIFY -> requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS, Manifest.permission.READ_PHONE_STATE), 1)
            Control.KIND_MEDIA -> requestPermissions(
                arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO, Manifest.permission.ACCESS_MEDIA_LOCATION), 2,
            )
            Control.KIND_BATTERY -> {
                startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, "package:$packageName".toUri()))
                finish()
            }
            else -> finish()
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        finish()
    }
}
