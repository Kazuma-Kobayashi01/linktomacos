package com.linktomacos.android.data

import android.content.Context
import androidx.core.content.edit
import com.linktomacos.android.protocol.PairingPayload
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.UUID

/** 已配对的 Mac。[pendingToken] 非空表示尚未完成首次握手。 */
data class PairedMac(
    val name: String,
    val hosts: List<String>,
    val port: Int,
    val fingerprint: String,
    val pendingToken: String?,
)

/**
 * 两次配对状态是否属于同一次配对：同一台 Mac，且新状态不是“带着新令牌重新扫码”。
 * 握手成功后令牌被作废、地址被更新，这类变化不应让连接重启。
 */
fun isSamePairing(old: PairedMac?, new: PairedMac?): Boolean =
    old?.fingerprint == new?.fingerprint && (new?.pendingToken == null || old?.pendingToken == new.pendingToken)

class PairingStore(context: Context) {
    private val prefs = context.getSharedPreferences("pairing", Context.MODE_PRIVATE)
    private val _paired = MutableStateFlow(load())
    val paired: StateFlow<PairedMac?> = _paired.asStateFlow()

    /** 本机在协议中的稳定 ID，首次使用时生成。 */
    val deviceId: String = prefs.getString(KEY_DEVICE_ID, null)
        ?: UUID.randomUUID().toString().also { prefs.edit { putString(KEY_DEVICE_ID, it) } }

    fun pair(payload: PairingPayload) = save(
        PairedMac(payload.macName, payload.hosts, payload.port, payload.fingerprint, payload.token)
    )

    /** 握手成功：作废令牌，把成功的地址放到最前面。 */
    fun onConnected(host: String, port: Int, macName: String) {
        val current = _paired.value ?: return
        save(current.copy(
            name = macName,
            hosts = listOf(host) + current.hosts.filter { it != host },
            port = port,
            pendingToken = null,
        ))
    }

    fun unpair() {
        prefs.edit { remove(KEY_MAC) }
        _paired.value = null
    }

    private fun save(mac: PairedMac) {
        val raw = listOf(mac.name, mac.hosts.joinToString(","), mac.port.toString(), mac.fingerprint, mac.pendingToken.orEmpty())
            .joinToString(SEP)
        prefs.edit { putString(KEY_MAC, raw) }
        _paired.value = mac
    }

    private fun load(): PairedMac? {
        val parts = prefs.getString(KEY_MAC, null)?.split(SEP) ?: return null
        if (parts.size != 5) return null
        return PairedMac(parts[0], parts[1].split(',').filter { it.isNotBlank() }, parts[2].toInt(), parts[3],
            parts[4].ifEmpty { null })
    }

    private companion object {
        const val KEY_MAC = "mac"
        const val KEY_DEVICE_ID = "device_id"
        const val SEP = "\u001f"
    }
}
