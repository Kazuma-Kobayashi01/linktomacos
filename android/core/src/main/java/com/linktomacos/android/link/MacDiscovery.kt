package com.linktomacos.android.link

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.withTimeoutOrNull
import java.net.Inet4Address

private const val TAG = "MacDiscovery"
private const val SERVICE_TYPE = "_linktomacos._tcp"

/** 通过 Bonjour（NSD）按证书指纹前缀找到已配对的 Mac，返回其当前地址。 */
class MacDiscovery(context: Context) {
    private val nsd = context.getSystemService(NsdManager::class.java)

    data class Endpoint(val host: String, val port: Int)

    suspend fun find(fingerprint: String, timeoutMs: Long): Endpoint? = withTimeoutOrNull(timeoutMs) {
        resolvedServices().firstOrNull { (info, endpoint) ->
            val fp = info.attributes["fp"]?.toString(Charsets.UTF_8)
            endpoint != null && fp != null && fingerprint.startsWith(fp)
        }?.second
    }

    private fun resolvedServices() = callbackFlow {
        val infoCallbacks = mutableListOf<NsdManager.ServiceInfoCallback>()
        val discovery = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(service: NsdServiceInfo) {
                val callback = object : NsdManager.ServiceInfoCallback {
                    override fun onServiceUpdated(info: NsdServiceInfo) {
                        val host = info.hostAddresses.firstOrNull { it is Inet4Address } ?: info.hostAddresses.firstOrNull()
                        trySend(info to host?.let { Endpoint(it.hostAddress!!, info.port) })
                    }
                    override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) {
                        Log.w(TAG, "resolve failed: $errorCode")
                    }
                    override fun onServiceLost() = Unit
                    override fun onServiceInfoCallbackUnregistered() = Unit
                }
                synchronized(infoCallbacks) { infoCallbacks += callback }
                nsd.registerServiceInfoCallback(service, Runnable::run, callback)
            }
            override fun onServiceLost(service: NsdServiceInfo) = Unit
            override fun onDiscoveryStarted(serviceType: String) = Unit
            override fun onDiscoveryStopped(serviceType: String) = Unit
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.w(TAG, "discovery failed: $errorCode")
                close()
            }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) = Unit
        }
        nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discovery)
        awaitClose {
            runCatching { nsd.stopServiceDiscovery(discovery) }
            synchronized(infoCallbacks) {
                infoCallbacks.forEach { runCatching { nsd.unregisterServiceInfoCallback(it) } }
            }
        }
    }
}
