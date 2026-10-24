package com.linktomacos.android.protocol

import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException

/** 单帧上限，与 Mac 端一致。 */
const val MAX_FRAME_LENGTH = 1 shl 20

/** `[4 字节大端长度][UTF-8 JSON]` */
object Frames {
    fun write(output: DataOutputStream, message: LinkMessage) {
        val body = MessageCodec.encode(message).toByteArray(Charsets.UTF_8)
        if (body.size > MAX_FRAME_LENGTH) throw IOException("frame too large: ${body.size}")
        output.writeInt(body.size)
        output.write(body)
    }

    fun read(input: DataInputStream): LinkMessage {
        val length = input.readInt()
        if (length < 0 || length > MAX_FRAME_LENGTH) throw IOException("bad frame length: $length")
        val body = ByteArray(length)
        input.readFully(body)
        return MessageCodec.decode(String(body, Charsets.UTF_8))
    }
}
