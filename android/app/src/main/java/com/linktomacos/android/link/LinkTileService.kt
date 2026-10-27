package com.linktomacos.android.link

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.linktomacos.android.UiApp
import com.linktomacos.android.ipc.ServiceSnapshot
import com.linktomacos.android.MainActivity
import com.linktomacos.android.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

/**
 * 下拉面板（快速设置）里的磁贴：亮着表示已连接 Mac，副标题是 Mac 的名字；点一下打开应用。
 * 只在磁贴可见（面板展开）时监听连接状态，不常驻。
 */
class LinkTileService : TileService() {
    private var scope: CoroutineScope? = null
    private var job: Job? = null

    override fun onStartListening() {
        super.onStartListening()
        val scope = CoroutineScope(Dispatchers.Main).also { this.scope = it }
        val client = (application as UiApp).client
        client.connect()
        job = scope.launch { client.snapshot.collect { render(it) } }
    }

    override fun onStopListening() {
        job?.cancel()
        scope?.cancel()
        (application as UiApp).client.disconnect()
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), PendingIntent.FLAG_IMMUTABLE,
        )
        startActivityAndCollapse(open)
    }

    private fun render(snapshot: ServiceSnapshot?) {
        val tile = qsTile ?: return
        if (snapshot == null) return
        val state = snapshot.link
        val paired = snapshot.paired
        val (active, subtitle) = when {
            state is LinkState.Connected -> true to state.macName
            paired == null -> false to getString(R.string.state_not_paired_title)
            state is LinkState.Rejected -> false to getString(R.string.state_rejected_title)
            state is LinkState.Waiting -> false to getString(R.string.state_waiting_title)
            else -> false to getString(R.string.state_searching_title)
        }
        tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = getString(R.string.tile_label)
        tile.subtitle = subtitle
        tile.icon = Icon.createWithResource(this, R.drawable.ic_tile)
        tile.updateTile()
    }
}
