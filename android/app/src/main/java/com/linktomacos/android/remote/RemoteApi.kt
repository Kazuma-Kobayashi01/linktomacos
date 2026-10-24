package com.linktomacos.android.remote

import android.Manifest
import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.util.Base64
import android.util.Size
import androidx.core.content.ContextCompat
import com.linktomacos.android.protocol.DataChunk
import com.linktomacos.android.protocol.LinkMessage
import com.linktomacos.android.protocol.Request
import com.linktomacos.android.protocol.Response
import com.linktomacos.android.protocol.StreamEnd
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.max
import kotlin.math.roundToInt

private const val CHUNK_SIZE = 256 * 1024
/** 单张缩略图的 JPEG 上限；base64 之后仍要小于一帧（1 MiB）。 */
private const val MAX_THUMBNAIL_BYTES = 650_000

/**
 * 处理 Mac 发来的请求：相册列表、缩略图、文件夹列表、下载。
 *
 * 每个请求在 [scope] 里独立执行，互不阻塞；[send] 把响应写回当前连接。
 */
class RemoteApi(
    private val context: Context,
    private val scope: CoroutineScope,
    private val send: (LinkMessage) -> Unit,
) {
    private val resolver: ContentResolver = context.contentResolver
    private val jobs = ConcurrentHashMap<Int, Job>()
    private val streamJobs = ConcurrentHashMap<Int, Job>()
    private val nextStream = AtomicInteger(1)

    fun handle(request: Request) {
        if (request.method == "cancel") {
            request.params.int("id")?.let { jobs[it]?.cancel() }
            request.params.int("streamId")?.let { streamJobs[it]?.cancel() }
            return
        }
        val job = scope.launch(Dispatchers.IO) {
            try {
                dispatch(request)?.let { send(Response(request.id, true, it)) }
            } catch (e: CancellationException) {
                throw e
            } catch (t: Throwable) {
                // 连接已断时发错误响应也会失败，忽略即可
                runCatching { send(Response(request.id, false, null, t.message ?: t.javaClass.simpleName)) }
            } finally {
                jobs.remove(request.id)
            }
        }
        jobs[request.id] = job
    }

    fun cancelAll() {
        jobs.values.forEach { it.cancel() }
        streamJobs.values.forEach { it.cancel() }
    }

    /** 返回 null 表示该请求已自行回复（下载）。 */
    private suspend fun dispatch(request: Request): JsonElement? = when (request.method) {
        "access" -> buildJsonObject {
            put("media", hasMediaAccess())
            put("allFiles", Environment.isExternalStorageManager())
        }
        "listAlbums" -> listAlbums()
        "listMedia" -> listMedia(request.params)
        "thumbnail" -> thumbnail(request.params)
        "listDir" -> listDir(request.params)
        "download" -> {
            download(request)
            null
        }
        else -> throw IllegalArgumentException("不支持的请求：${request.method}")
    }

    private fun hasMediaAccess(): Boolean =
        Environment.isExternalStorageManager() ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED

    private fun requireMediaAccess() {
        if (!hasMediaAccess()) throw SecurityException("手机未授予相册读取权限")
    }

    // MARK: 相册

    private val filesUri: Uri = MediaStore.Files.getContentUri("external")

    private fun query(projection: Array<String>, selection: String, args: Array<String>, limit: Int? = null, offset: Int = 0) =
        resolver.query(filesUri, projection, Bundle().apply {
            putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
            putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, args)
            putString(ContentResolver.QUERY_ARG_SQL_SORT_ORDER, "${MediaStore.MediaColumns.DATE_ADDED} DESC, ${MediaStore.MediaColumns._ID} DESC")
            if (limit != null) {
                putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
                putInt(ContentResolver.QUERY_ARG_OFFSET, offset)
            }
        }, null) ?: throw IOException("无法读取相册")

    private fun listAlbums(): JsonElement {
        requireMediaAccess()
        class Acc(val name: String, var count: Int, val coverId: Long, val coverIsVideo: Boolean)
        val albums = LinkedHashMap<Long, Acc>()
        var images = 0
        var videos = 0
        val projection = arrayOf(
            MediaStore.MediaColumns._ID, MediaStore.MediaColumns.BUCKET_ID,
            MediaStore.MediaColumns.BUCKET_DISPLAY_NAME, MediaStore.Files.FileColumns.MEDIA_TYPE,
        )
        query(projection, MEDIA_SELECTION, arrayOf(IMAGE, VIDEO)).use { c ->
            val idCol = c.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val bucketCol = c.getColumnIndexOrThrow(MediaStore.MediaColumns.BUCKET_ID)
            val nameCol = c.getColumnIndexOrThrow(MediaStore.MediaColumns.BUCKET_DISPLAY_NAME)
            val typeCol = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MEDIA_TYPE)
            while (c.moveToNext()) {
                val isVideo = c.getInt(typeCol) == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO
                if (isVideo) videos++ else images++
                val bucket = c.getLong(bucketCol)
                val acc = albums.getOrPut(bucket) {
                    // 结果按时间倒序，所以每个相簿第一次出现的就是最新一张，用作封面
                    Acc(c.getString(nameCol) ?: "其他", 0, c.getLong(idCol), isVideo)
                }
                acc.count++
            }
        }
        return buildJsonObject {
            put("imageCount", images)
            put("videoCount", videos)
            put("albums", buildJsonArray {
                albums.entries.sortedByDescending { it.value.count }.forEach { (id, a) ->
                    add(buildJsonObject {
                        put("id", id)
                        put("name", a.name)
                        put("count", a.count)
                        put("coverId", a.coverId)
                        put("coverIsVideo", a.coverIsVideo)
                    })
                }
            })
        }
    }

    private fun listMedia(params: JsonObject): JsonElement {
        requireMediaAccess()
        val kind = params.string("kind") ?: "all"
        val album = params.long("album")
        val offset = (params.int("offset") ?: 0).coerceAtLeast(0)
        val limit = (params.int("limit") ?: 300).coerceIn(1, 1000)

        val types = when (kind) {
            "image" -> listOf(IMAGE)
            "video" -> listOf(VIDEO)
            else -> listOf(IMAGE, VIDEO)
        }
        val selection = StringBuilder("${MediaStore.Files.FileColumns.MEDIA_TYPE} IN (${types.joinToString(",") { "?" }})")
        val args = types.toMutableList()
        if (album != null) {
            selection.append(" AND ${MediaStore.MediaColumns.BUCKET_ID} = ?")
            args.add(album.toString())
        }

        val total = query(arrayOf(MediaStore.MediaColumns._ID), selection.toString(), args.toTypedArray()).use { it.count }
        val projection = arrayOf(
            MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.SIZE, MediaStore.MediaColumns.WIDTH, MediaStore.MediaColumns.HEIGHT,
            MediaStore.MediaColumns.DURATION, MediaStore.MediaColumns.DATE_TAKEN, MediaStore.MediaColumns.DATE_ADDED,
            MediaStore.Files.FileColumns.MEDIA_TYPE, MediaStore.MediaColumns.BUCKET_DISPLAY_NAME,
        )
        return buildJsonObject {
            put("total", total)
            put("items", buildJsonArray {
                query(projection, selection.toString(), args.toTypedArray(), limit, offset).use { c ->
                    while (c.moveToNext()) {
                        val taken = c.getLong(7)
                        add(buildJsonObject {
                            put("id", c.getLong(0))
                            put("name", c.getString(1) ?: "")
                            put("mime", c.getString(2) ?: "")
                            put("size", c.getLong(3))
                            put("width", c.getInt(4))
                            put("height", c.getInt(5))
                            put("duration", c.getLong(6))
                            put("date", if (taken > 0) taken else c.getLong(8) * 1000)
                            put("isVideo", c.getInt(9) == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO)
                            put("album", c.getString(10) ?: "")
                        })
                    }
                }
            })
        }
    }

    private fun mediaUri(id: Long, video: Boolean): Uri = ContentUris.withAppendedId(
        if (video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id,
    )

    private fun thumbnail(params: JsonObject): JsonElement {
        requireMediaAccess()
        val id = params.long("id") ?: throw IllegalArgumentException("缺少 id")
        val video = params.bool("video") ?: false
        val size = (params.int("size") ?: 360).coerceIn(64, 3000)
        val quality = (params.int("quality") ?: 80).coerceIn(30, 95)
        val uri = mediaUri(id, video)

        val bitmap = if (video || size <= 512) resolver.loadThumbnail(uri, Size(size, size), null) else decodePreview(uri, size)
        try {
            val out = ByteArrayOutputStream()
            var q = quality
            do {
                out.reset()
                bitmap.compress(Bitmap.CompressFormat.JPEG, q, out)
                q -= 10
            } while (out.size() > MAX_THUMBNAIL_BYTES && q >= 30)
            return buildJsonObject {
                put("data", Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP))
                put("width", bitmap.width)
                put("height", bitmap.height)
            }
        } finally {
            bitmap.recycle()
        }
    }

    /** 大图预览：按长边缩放解码，EXIF 方向由 ImageDecoder 处理。 */
    private fun decodePreview(uri: Uri, longEdge: Int): Bitmap =
        ImageDecoder.decodeBitmap(ImageDecoder.createSource(resolver, uri)) { decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            val edge = max(info.size.width, info.size.height)
            if (edge > longEdge) {
                val scale = longEdge.toFloat() / edge
                decoder.setTargetSize(
                    (info.size.width * scale).roundToInt().coerceAtLeast(1),
                    (info.size.height * scale).roundToInt().coerceAtLeast(1),
                )
            }
        }

    // MARK: 文件

    private val root: File get() = Environment.getExternalStorageDirectory().canonicalFile

    /** 把相对路径解析到内部存储内，拒绝跳出根目录的路径（如 `..`）。 */
    private fun resolve(relative: String): File {
        if (!Environment.isExternalStorageManager()) throw SecurityException("手机未授予“所有文件访问权限”")
        val base = root
        val file = File(base, relative).canonicalFile
        if (file != base && !file.path.startsWith(base.path + File.separator)) throw SecurityException("路径无效")
        return file
    }

    private fun listDir(params: JsonObject): JsonElement {
        val dir = resolve(params.string("path") ?: "")
        val children = dir.listFiles() ?: throw IOException("无法读取该文件夹")
        val entries = children.filter { !it.name.startsWith(".") }
            .sortedWith(compareBy<File>({ !it.isDirectory }, { it.name.lowercase() }))
        return buildJsonObject {
            put("path", if (dir == root) "" else dir.relativeTo(root).path)
            put("entries", buildJsonArray {
                entries.forEach { f ->
                    add(buildJsonObject {
                        put("name", f.name)
                        put("isDir", f.isDirectory)
                        put("size", if (f.isDirectory) 0L else f.length())
                        put("modified", f.lastModified())
                    })
                }
            })
        }
    }

    // MARK: 下载

    private class Source(val stream: InputStream, val name: String, val mime: String, val size: Long, val modified: Long)

    private fun openSource(params: JsonObject): Source = when (params.string("source")) {
        "media" -> {
            requireMediaAccess()
            val id = params.long("id") ?: throw IllegalArgumentException("缺少 id")
            val uri = ContentUris.withAppendedId(filesUri, id)
            var name = "$id"
            var mime = "application/octet-stream"
            var modified = 0L
            resolver.query(uri, arrayOf(
                MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.MIME_TYPE, MediaStore.MediaColumns.DATE_MODIFIED,
            ), null, null, null)?.use { c ->
                if (!c.moveToFirst()) throw FileNotFoundException("文件已不存在")
                name = c.getString(0) ?: name
                mime = c.getString(1) ?: mime
                modified = c.getLong(2) * 1000
            }
            // 默认会抹掉照片里的位置信息；有权限时取原始文件
            val source = if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_MEDIA_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
            ) MediaStore.setRequireOriginal(uri) else uri
            val pfd = resolver.openFileDescriptor(source, "r") ?: throw FileNotFoundException("无法打开文件")
            Source(ParcelFileDescriptor.AutoCloseInputStream(pfd), name, mime, pfd.statSize, modified)
        }
        "file" -> {
            val file = resolve(params.string("path") ?: throw IllegalArgumentException("缺少 path"))
            if (!file.isFile) throw FileNotFoundException("不是文件")
            Source(FileInputStream(file), file.name, "application/octet-stream", file.length(), file.lastModified())
        }
        else -> throw IllegalArgumentException("未知的下载来源")
    }

    /** 先回复文件信息和 streamId，再流式发送数据帧，最后发 streamEnd。 */
    private suspend fun download(request: Request) {
        val source = openSource(request.params)
        val streamId = nextStream.getAndIncrement()
        currentCoroutineContext()[Job]?.let { streamJobs[streamId] = it }
        try {
            send(Response(request.id, true, buildJsonObject {
                put("streamId", streamId)
                put("size", source.size)
                put("name", source.name)
                put("mime", source.mime)
                put("modified", source.modified)
            }))
            val buffer = ByteArray(CHUNK_SIZE)
            while (true) {
                currentCoroutineContext().ensureActive()
                val n = source.stream.read(buffer)
                if (n < 0) break
                send(DataChunk(streamId, buffer, n))
            }
            send(StreamEnd(streamId, true))
        } catch (e: CancellationException) {
            runCatching { send(StreamEnd(streamId, false, "已取消")) }
            throw e
        } catch (e: IOException) {
            runCatching { send(StreamEnd(streamId, false, e.message ?: "读取失败")) }
        } finally {
            streamJobs.remove(streamId)
            runCatching { source.stream.close() }
        }
    }

    private companion object {
        val IMAGE = MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE.toString()
        val VIDEO = MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO.toString()
        val MEDIA_SELECTION = "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN (?,?)"
    }
}

private fun JsonObject.string(key: String): String? = (this[key] as? JsonPrimitive)?.contentOrNull
private fun JsonObject.int(key: String): Int? = (this[key] as? JsonPrimitive)?.intOrNull
private fun JsonObject.long(key: String): Long? = (this[key] as? JsonPrimitive)?.longOrNull
private fun JsonObject.bool(key: String): Boolean? = (this[key] as? JsonPrimitive)?.booleanOrNull
