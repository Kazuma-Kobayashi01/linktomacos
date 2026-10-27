package com.linktomacos.android.protocol

import java.net.URI
import java.net.URLDecoder

/** 二维码内容：`linktomacos://pair?v=1&n=..&h=ip1,ip2&p=..&fp=..&t=..` */
data class PairingPayload(
    val macName: String,
    val hosts: List<String>,
    val port: Int,
    val fingerprint: String,
    val token: String,
) {
    companion object {
        fun parse(text: String): PairingPayload? {
            val uri = runCatching { URI(text.trim()) }.getOrNull() ?: return null
            if (uri.scheme != "linktomacos" || uri.host != "pair") return null
            val query = uri.rawQuery?.split('&').orEmpty().mapNotNull { part ->
                val i = part.indexOf('=')
                if (i <= 0) null
                else part.substring(0, i) to URLDecoder.decode(part.substring(i + 1), Charsets.UTF_8)
            }.toMap()
            return PairingPayload(
                macName = query["n"] ?: return null,
                hosts = query["h"]?.split(',')?.filter { it.isNotBlank() } ?: return null,
                port = query["p"]?.toIntOrNull() ?: return null,
                fingerprint = query["fp"]?.lowercase() ?: return null,
                token = query["t"] ?: return null,
            )
        }
    }
}
