package com.linktomacos.android.link

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

sealed interface LinkState {
    data object NotPaired : LinkState
    data class Searching(val macName: String) : LinkState
    data class Connected(val macName: String, val host: String) : LinkState
    data class Waiting(val macName: String, val reason: String, val retryInSeconds: Int) : LinkState
    /** Mac 拒绝了本机（被取消配对或证书不符），需重新扫码。 */
    data class Rejected(val macName: String, val reason: String) : LinkState
}

/** 服务与界面共享的连接状态。 */
object LinkStatus {
    private val _state = MutableStateFlow<LinkState>(LinkState.NotPaired)
    val state: StateFlow<LinkState> = _state.asStateFlow()

    internal fun set(state: LinkState) {
        _state.value = state
    }
}
