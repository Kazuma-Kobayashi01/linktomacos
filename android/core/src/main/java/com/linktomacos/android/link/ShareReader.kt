package com.linktomacos.android.link

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log

/**
 * 读分享来的 Intent。必须在分享页面还在时（onCreate 里）调用：系统给的读取权限在页面关闭后会失效，
 * 但这里立刻打开的文件描述符还能继续读。没有可发的内容返回 null。
 */
object ShareReader {
    private const val TAG = "ShareReader"

    fun read(context: Context, intent: Intent): AirSend.Prepared? {
        val uris = buildList {
            when (intent.action) {
                Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)?.let(::add)
                Intent.ACTION_SEND_MULTIPLE -> addAll(intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java).orEmpty())
            }
            val clip = intent.clipData
            if (isEmpty() && clip != null) for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let(::add)
        }
        val files = uris.mapNotNull { open(context, it, intent.type) }
        if (files.isNotEmpty()) return AirSend.Prepared(files, null)
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        return if (text.isNullOrBlank()) null else AirSend.Prepared(emptyList(), text)
    }

    private fun open(context: Context, uri: Uri, fallbackMime: String?): AirSend.OutFile? = try {
        val resolver = context.contentResolver
        val pfd = resolver.openFileDescriptor(uri, "r") ?: return null
        var name: String? = null
        var size = -1L
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                name = c.getString(0)
                if (!c.isNull(1)) size = c.getLong(1)
            }
        }
        if (size < 0) size = pfd.statSize.coerceAtLeast(0)
        val mime = resolver.getType(uri) ?: fallbackMime?.takeIf { !it.contains('*') } ?: "application/octet-stream"
        AirSend.OutFile(name ?: uri.lastPathSegment ?: "file", size, mime, pfd)
    } catch (e: Exception) {
        Log.w(TAG, "cannot open shared item: $e")
        null
    }
}
