package com.linktomacos.android.link

import android.app.Notification
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.service.notification.NotificationListenerService
import android.util.Log
import android.service.notification.StatusBarNotification
import android.util.Base64
import androidx.core.app.NotificationManagerCompat
import androidx.core.graphics.createBitmap
import com.linktomacos.android.LinkApp
import com.linktomacos.android.protocol.NotificationRemoved
import com.linktomacos.android.protocol.PhoneNotification
import java.io.ByteArrayOutputStream

private const val TAG = "NotificationListener"
private const val ICON_SIZE = 96

/** 读取手机上的通知并交给 [NotificationBridge]，由连接服务转发给 Mac。 */
class PhoneNotificationListener : NotificationListenerService() {
    /** key → 上次转发内容的指纹，用来丢弃只刷新进度、内容没变的重复通知。 */
    private val lastSent = HashMap<String, Int>()
    private val iconCache = HashMap<String, String?>()

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val message = convert(sbn) ?: return
        val fingerprint = listOf(message.title, message.text, message.subText).hashCode()
        if (lastSent.put(sbn.key, fingerprint) == fingerprint) return
        Log.d(TAG, "forward ${sbn.packageName}")
        NotificationBridge.emit(message)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        if (lastSent.remove(sbn.key) != null) NotificationBridge.emit(NotificationRemoved(sbn.key))
    }

    private fun convert(sbn: StatusBarNotification): PhoneNotification? {
        if (sbn.packageName == packageName) return null
        // 白名单：只转发用户勾选的应用
        if (!(application as LinkApp).settings.isAllowed(sbn.packageName)) {
            Log.d(TAG, "skip ${sbn.packageName}: not in whitelist")
            return null
        }
        val n = sbn.notification
        // 常驻通知（音乐播放、导航、下载进度等）和分组摘要不转发
        if (n.flags and (Notification.FLAG_ONGOING_EVENT or Notification.FLAG_GROUP_SUMMARY or Notification.FLAG_FOREGROUND_SERVICE) != 0) return null

        val extras = n.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT))
            ?.toString().orEmpty()
        if (title.isBlank() && text.isBlank()) return null

        return PhoneNotification(
            key = sbn.key,
            packageName = sbn.packageName,
            appName = appLabel(sbn.packageName),
            title = title,
            text = text,
            subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.takeIf { it.isNotBlank() },
            timestamp = if (sbn.postTime > 0) sbn.postTime else System.currentTimeMillis(),
            iconPng = iconCache.getOrPut(sbn.packageName) { iconPng(sbn.packageName) },
        )
    }

    private fun appLabel(pkg: String): String = try {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
    } catch (_: PackageManager.NameNotFoundException) {
        pkg
    }

    private fun iconPng(pkg: String): String? = try {
        val drawable = packageManager.getApplicationIcon(pkg)
        val bitmap = createBitmap(ICON_SIZE, ICON_SIZE, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, ICON_SIZE, ICON_SIZE)
        drawable.draw(Canvas(bitmap))
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    } catch (_: Exception) {
        null
    }

    companion object {
        fun isEnabled(context: Context): Boolean =
            context.packageName in NotificationManagerCompat.getEnabledListenerPackages(context)
    }
}
