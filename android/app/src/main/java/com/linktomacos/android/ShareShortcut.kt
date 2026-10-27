package com.linktomacos.android

import android.content.Context
import android.content.Intent
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import androidx.core.graphics.drawable.toBitmap

/**
 * 在系统分享面板最上面一排（“直接分享”）放一个以 Mac 命名的目标；点它就是 AirSend 给这台 Mac。
 * 需要配合 res/xml/shortcuts.xml 里的 share-target（它挂在带桌面图标的 MainActivity 上，所以这件事归界面 App）。
 */
object ShareShortcut {
    private const val CATEGORY = "com.linktomacos.android.category.AIRSEND"
    private const val ID = "airsend_mac"

    /** [macName] 为 null（没配对）时去掉。 */
    fun publish(context: Context, macName: String?) {
        if (macName == null) {
            ShortcutManagerCompat.removeDynamicShortcuts(context, listOf(ID))
            return
        }
        val icon = IconCompat.createWithAdaptiveBitmap(context.getDrawable(R.mipmap.ic_launcher)!!.toBitmap(432, 432))
        val shortcut = ShortcutInfoCompat.Builder(context, ID)
            .setShortLabel(macName)
            .setLongLabel(context.getString(R.string.airsend_shortcut_long, macName))
            .setIcon(icon)
            .setCategories(setOf(CATEGORY))
            .setLongLived(true)
            .setRank(0)
            .setIntent(Intent(context, MainActivity::class.java).setAction(Intent.ACTION_VIEW))
            .build()
        ShortcutManagerCompat.pushDynamicShortcut(context, shortcut)
    }

    /** 用户通过“直接分享”目标发了东西，告诉系统这个目标有人用，排名会靠前。 */
    fun reportUsed(context: Context) = ShortcutManagerCompat.reportShortcutUsed(context, ID)
}
