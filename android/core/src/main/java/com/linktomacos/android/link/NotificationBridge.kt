package com.linktomacos.android.link

import com.linktomacos.android.protocol.LinkMessage
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * 通知监听服务（由系统绑定）与连接服务之间的桥。
 *
 * 用没有回放的 SharedFlow：未连接 Mac 时没有订阅者，通知直接丢弃，
 * 不会在重连时把积压的旧通知一次性刷给 Mac。
 */
object NotificationBridge {
    private val _events = MutableSharedFlow<LinkMessage>(extraBufferCapacity = 64, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    val events: SharedFlow<LinkMessage> = _events.asSharedFlow()

    fun emit(message: LinkMessage) {
        _events.tryEmit(message)
    }
}
