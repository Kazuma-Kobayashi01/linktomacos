package com.linktomacos.android.link

import android.app.Application
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.system.Os
import android.system.OsConstants
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import androidx.core.graphics.drawable.toBitmap
import com.linktomacos.android.LinkApp
import com.linktomacos.android.MainActivity
import com.linktomacos.android.R
import com.linktomacos.android.protocol.AirFile
import com.linktomacos.android.protocol.AirOffer
import com.linktomacos.android.protocol.AirPush
import com.linktomacos.android.protocol.AirText
import com.linktomacos.android.protocol.DataChunk
import com.linktomacos.android.protocol.LinkMessage
import com.linktomacos.android.protocol.StreamEnd
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

private const val TAG = "AirSend"
/** 分享目标的类别，要和 res/xml/shortcuts.xml 里的 share-target 一致。 */
const val AIRSEND_SHORTCUT_CATEGORY = "com.linktomacos.android.category.AIRSEND"
private const val SHORTCUT_ID = "airsend_mac"
/** 清单发出后，Mac 多久还没取走就作废。 */
private const val OFFER_TTL_MS = 10 * 60_000L
/** 等待连上 Mac 的时间：分享时应用可能刚被唤醒，连接服务还没建好。 */
private const val CONNECT_WAIT_MS = 10_000L

/**
 * AirSend：手机和 Mac 之间无感互传文件和文字。
 *
 * - **手机 → Mac**：分享菜单里选 AirSend（或 Mac 的名字，见 [publishShortcut]），[prepare] 立刻打开所有文件的描述符
 *   （系统给的读取权限在分享页面关闭后会失效，但已打开的描述符还能读），[send] 发一份清单；Mac 再逐个来取（`source = airsend`）。
 * - **Mac → 手机**：Mac 发 [AirPush] 和数据帧，这里直接写进“下载/AirSend”，收完发通知。文字放进剪贴板。
 */
class AirSend(private val app: Application) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val resolver = app.contentResolver
    private val notifications = app.getSystemService(NotificationManager::class.java)

    /** 当前连接上发消息的函数，没连上为 null。 */
    private val sender = MutableStateFlow<((LinkMessage) -> Unit)?>(null)
    val connected: Boolean get() = sender.value != null

    /** 每次连接调用：连接期间一直挂起，连接断开（协程取消）时清理。 */
    suspend fun attach(send: (LinkMessage) -> Unit) {
        sender.value = send
        try {
            awaitCancellation()
        } finally {
            sender.value = null
            abortIncoming()
        }
    }

    // MARK: 发送（手机 → Mac）

    class OutFile(val name: String, val size: Long, val mime: String, val pfd: ParcelFileDescriptor, var served: Boolean = false)

    class Prepared(val files: List<OutFile>, val text: String?) {
        fun close() = files.forEach { runCatching { it.pfd.close() } }
    }

    private class Offer(val files: List<OutFile>)

    private val offers = ConcurrentHashMap<String, Offer>()

    /** 读分享来的 Intent。必须在分享页面还在时（onCreate 里）调用。没有可发的内容返回 null。 */
    fun prepare(intent: Intent): Prepared? {
        val uris = buildList {
            when (intent.action) {
                Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)?.let(::add)
                Intent.ACTION_SEND_MULTIPLE -> addAll(intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java).orEmpty())
            }
            val clip = intent.clipData
            if (isEmpty() && clip != null) for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let(::add)
        }
        val files = uris.mapNotNull { open(it, intent.type) }
        if (files.isNotEmpty()) return Prepared(files, null)
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        return if (text.isNullOrBlank()) null else Prepared(emptyList(), text)
    }

    private fun open(uri: Uri, fallbackMime: String?): OutFile? = try {
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
        OutFile(name ?: uri.lastPathSegment ?: "file", size, mime, pfd)
    } catch (e: Exception) {
        Log.w(TAG, "cannot open shared item: $e")
        null
    }

    /** 把 [prepared] 发给 Mac。还没连上时最多等一会儿；等不到就放弃并通知。 */
    fun send(prepared: Prepared) {
        scope.launch {
            val send = withTimeoutOrNull(CONNECT_WAIT_MS) { sender.filterNotNull().first() }
            if (send == null) {
                prepared.close()
                status(app.getString(R.string.airsend_not_connected))
                return@launch
            }
            try {
                prepared.text?.let { send(AirText(it)) }
                if (prepared.files.isNotEmpty()) {
                    val id = UUID.randomUUID().toString()
                    offers[id] = Offer(prepared.files)
                    send(AirOffer(id, prepared.files.map { AirFile(it.name, it.size, it.mime) }))
                    scope.launch { delay(OFFER_TTL_MS); release(id) }
                }
            } catch (e: IOException) {
                prepared.close()
                status(app.getString(R.string.airsend_not_connected))
            }
        }
    }

    class Opened(val stream: InputStream, val name: String, val mime: String, val size: Long)

    /** Mac 来取清单里的第 [index] 个文件。 */
    fun open(offerId: String, index: Int): Opened? {
        val file = offers[offerId]?.files?.getOrNull(index) ?: return null
        val dup = ParcelFileDescriptor.dup(file.pfd.fileDescriptor)
        runCatching { Os.lseek(dup.fileDescriptor, 0, OsConstants.SEEK_SET) } // dup 共用读写位置，重复下载时要回到开头
        return Opened(ParcelFileDescriptor.AutoCloseInputStream(dup), file.name, file.mime, file.size)
    }

    /** Mac 取完了第 [index] 个文件。全部取完就释放并通知。 */
    fun served(offerId: String, index: Int) {
        val offer = offers[offerId] ?: return
        offer.files.getOrNull(index)?.served = true
        if (offer.files.all { it.served }) {
            release(offerId)
            val name = (app as LinkApp).pairingStore.paired.value?.name.orEmpty()
            status(app.resources.getQuantityString(R.plurals.airsend_sent, offer.files.size, offer.files.size, name))
        }
    }

    private fun release(id: String) {
        offers.remove(id)?.files?.forEach { runCatching { it.pfd.close() } }
    }

    // MARK: 接收（Mac → 手机）

    private class Incoming(val uri: Uri, val out: OutputStream, val name: String, val size: Long, val notificationId: Int) {
        var written = 0L
        var lastProgress = 0L
    }

    private val incoming = ConcurrentHashMap<Int, Incoming>()
    private var notificationSeq = 100

    fun onPush(push: AirPush) {
        try {
            val name = push.name.replace('/', '_').ifBlank { "file" }
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, push.mime.ifBlank { "application/octet-stream" })
                put(MediaStore.Downloads.RELATIVE_PATH, "Download/AirSend")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: throw IOException("insert failed")
            val out = resolver.openOutputStream(uri) ?: throw IOException("open failed")
            incoming[push.streamId] = Incoming(uri, out, name, push.size, notificationSeq++)
        } catch (e: Exception) {
            Log.w(TAG, "cannot receive ${push.name}: $e")
            status(app.getString(R.string.airsend_receive_failed, push.name))
        }
    }

    /** 返回 true 表示这个数据帧属于 AirSend。 */
    fun onData(chunk: DataChunk): Boolean {
        val file = incoming[chunk.streamId] ?: return false
        try {
            file.out.write(chunk.bytes, 0, chunk.length)
            file.written += chunk.length
            val now = System.currentTimeMillis()
            if (file.size > 0 && now - file.lastProgress > 400) {
                file.lastProgress = now
                notifications.notify(file.notificationId, progressNotification(file))
            }
        } catch (e: IOException) {
            fail(chunk.streamId)
        }
        return true
    }

    fun onEnd(end: StreamEnd): Boolean {
        val file = incoming.remove(end.streamId) ?: return false
        runCatching { file.out.close() }
        if (!end.ok) {
            runCatching { resolver.delete(file.uri, null, null) }
            notifications.cancel(file.notificationId)
            return true
        }
        resolver.update(file.uri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
        val mime = resolver.getType(file.uri) ?: "application/octet-stream"
        val open = PendingIntent.getActivity(
            app, file.notificationId,
            Intent(Intent.ACTION_VIEW).setDataAndType(file.uri, mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE,
        )
        notifications.notify(
            file.notificationId,
            NotificationCompat.Builder(app, LinkApp.CHANNEL_AIRSEND)
                .setSmallIcon(R.drawable.ic_launcher_monochrome)
                .setContentTitle(app.getString(R.string.airsend_received_title))
                .setContentText(file.name)
                .setContentIntent(open)
                .setAutoCancel(true)
                .build(),
        )
        return true
    }

    private fun fail(streamId: Int) {
        val file = incoming.remove(streamId) ?: return
        runCatching { file.out.close() }
        runCatching { resolver.delete(file.uri, null, null) }
        notifications.cancel(file.notificationId)
        status(app.getString(R.string.airsend_receive_failed, file.name))
    }

    private fun abortIncoming() {
        for (id in incoming.keys.toList()) fail(id)
    }

    private fun progressNotification(file: Incoming) = NotificationCompat.Builder(app, LinkApp.CHANNEL_AIRSEND_STATUS)
        .setSmallIcon(R.drawable.ic_launcher_monochrome)
        .setContentTitle(app.getString(R.string.airsend_receiving, file.name))
        .setProgress(100, (file.written * 100 / file.size).toInt().coerceIn(0, 100), false)
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .build()

    /** Mac 发来的文字：放进剪贴板，通知里显示。是链接的话，点通知打开。 */
    fun onText(message: AirText) {
        val text = message.text
        if (text.isBlank()) return
        runCatching { app.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("AirSend", text)) }
        val isLink = text.trim().let { (it.startsWith("http://") || it.startsWith("https://")) && !it.contains(' ') }
        val target = if (isLink) Intent(Intent.ACTION_VIEW, Uri.parse(text.trim())) else Intent(app, MainActivity::class.java)
        val builder = NotificationCompat.Builder(app, LinkApp.CHANNEL_AIRSEND)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(app.getString(R.string.airsend_text_title))
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(PendingIntent.getActivity(app, notificationSeq, target.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), PendingIntent.FLAG_IMMUTABLE))
            .setAutoCancel(true)
        notifications.notify(notificationSeq++, builder.build())
    }

    // MARK: 通知和分享目标

    /** 一条简短的状态通知（几秒后自动消失）。 */
    private fun status(text: String) {
        val id = notificationSeq++
        notifications.notify(
            id,
            NotificationCompat.Builder(app, LinkApp.CHANNEL_AIRSEND_STATUS)
                .setSmallIcon(R.drawable.ic_launcher_monochrome)
                .setContentTitle(text)
                .setTimeoutAfter(6_000)
                .setAutoCancel(true)
                .build(),
        )
    }

    /**
     * 在系统分享面板最上面一排（“直接分享”）放一个以 Mac 命名的目标；点它就是 AirSend 给这台 Mac。
     * 需要配合 res/xml/shortcuts.xml 里的 share-target；没配对时去掉。
     */
    fun publishShortcut(macName: String?) {
        if (macName == null) {
            ShortcutManagerCompat.removeDynamicShortcuts(app, listOf(SHORTCUT_ID))
            return
        }
        val icon = IconCompat.createWithAdaptiveBitmap(app.getDrawable(R.mipmap.ic_launcher)!!.toBitmap(432, 432))
        val shortcut = ShortcutInfoCompat.Builder(app, SHORTCUT_ID)
            .setShortLabel(macName)
            .setLongLabel(app.getString(R.string.airsend_shortcut_long, macName))
            .setIcon(icon)
            .setCategories(setOf(AIRSEND_SHORTCUT_CATEGORY))
            .setLongLived(true)
            .setRank(0)
            .setIntent(Intent(app, MainActivity::class.java).setAction(Intent.ACTION_VIEW))
            .build()
        ShortcutManagerCompat.pushDynamicShortcut(app, shortcut)
    }

    /** 用户通过“直接分享”目标发了东西，告诉系统这个目标有人用，排名会靠前。 */
    fun reportShortcutUsed() = ShortcutManagerCompat.reportShortcutUsed(app, SHORTCUT_ID)
}
