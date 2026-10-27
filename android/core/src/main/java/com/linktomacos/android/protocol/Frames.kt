package com.linktomacos.android.protocol

import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException

/** 单帧上限，与 Mac 端一致。 */
const val MAX_FRAME_LENGTH = 1 shl 20

/** 二进制数据帧的标记字节。JSON 对象以 `{` 开头，不会与之冲突。 */
const val BINARY_FRAME_MARKER = 0x01

/**
 * 帧格式：
 *  - JSON：`[4 字节大端长度][UTF-8 JSON]`
 *  - 数据：`[4 字节大端长度][0x01][4 字节 streamId][数据]`
 */
object Frames {
    fun write(output: DataOutputStream, message: LinkMessage) {
        if (message is DataChunk) {
            val total = message.length + 5
            if (total > MAX_FRAME_LENGTH) throw IOException("frame too large: $total")
            output.writeInt(total)
            output.writeByte(BINARY_FRAME_MARKER)
            output.writeInt(message.streamId)
            output.write(message.bytes, 0, message.length)
            return
        }
        val body = MessageCodec.encode(message).toByteArray(Charsets.UTF_8)
        if (body.size > MAX_FRAME_LENGTH) throw IOException("frame too large: ${body.size}")
        output.writeInt(body.size)
        output.write(body)
    }

    fun read(input: DataInputStream): LinkMessage {
        val length = input.readInt()
        if (length < 1 || length > MAX_FRAME_LENGTH) throw IOException("bad frame length: $length")
        val body = ByteArray(length)
        input.readFully(body)
        if (body[0].toInt() == BINARY_FRAME_MARKER) {
            if (length < 5) throw IOException("bad data frame length: $length")
            val streamId = ((body[1].toInt() and 0xFF) shl 24) or ((body[2].toInt() and 0xFF) shl 16) or
                ((body[3].toInt() and 0xFF) shl 8) or (body[4].toInt() and 0xFF)
            return DataChunk(streamId, body.copyOfRange(5, length))
        }
        return MessageCodec.decode(String(body, Charsets.UTF_8))
    }
}
