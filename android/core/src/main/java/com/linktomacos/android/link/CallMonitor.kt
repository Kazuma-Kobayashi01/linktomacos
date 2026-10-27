package com.linktomacos.android.link

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Log
import com.linktomacos.android.protocol.CallState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private const val TAG = "CallMonitor"

/**
 * 监听手机的通话状态，来电、接通、挂断时通过 [NotificationBridge] 告诉 Mac，Mac 据此弹出来电提示并播放提示音。
 *
 * 只需要 READ_PHONE_STATE。联系人名取自系统的来电通知（需要通知访问权限，已经有了），不读通话记录和联系人。
 */
class CallMonitor(private val context: Context, private val scope: CoroutineScope) {
    private val telephony = context.getSystemService(TelephonyManager::class.java)
    private var callback: TelephonyCallback? = null
    private var lastState = TelephonyManager.CALL_STATE_IDLE
    private var identityJob: Job? = null

    /** 可以重复调用：已经在监听就什么也不做；没有权限时不监听，授权后再次调用即可。 */
    @Synchronized
    fun start() {
        if (callback != null) return
        if (context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
            Log.d(TAG, "no READ_PHONE_STATE, call alerts are off")
            return
        }
        val listener = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
            override fun onCallStateChanged(state: Int) = this@CallMonitor.onState(state)
        }
        telephony.registerTelephonyCallback(context.mainExecutor, listener)
        callback = listener
        Log.d(TAG, "listening for call state")
    }

    @Synchronized
    fun stop() {
        callback?.let { runCatching { telephony.unregisterTelephonyCallback(it) } }
        callback = null
        identityJob?.cancel()
        lastState = TelephonyManager.CALL_STATE_IDLE
    }

    private fun onState(state: Int) {
        if (state == lastState) return
        lastState = state
        identityJob?.cancel()
        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                emit("ringing", null)
                // 来电通知比状态回调稍晚才出现，几百毫秒内取到名字就补发一次
                identityJob = scope.launch {
                    repeat(15) {
                        delay(200)
                        PhoneNotificationListener.activeCallIdentity()?.let { name ->
                            emit("ringing", name)
                            return@launch
                        }
                    }
                }
            }
            TelephonyManager.CALL_STATE_OFFHOOK -> emit("offhook", null)
            else -> emit("idle", null)
        }
    }

    private fun emit(state: String, name: String?) {
        Log.d(TAG, "call state $state")
        NotificationBridge.emit(CallState(state, name, System.currentTimeMillis()))
    }
}
