package com.tunaneko

import android.content.Intent
import android.net.VpnService
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.tunaneko.state.Status
import com.tunaneko.state.VpnManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach

/** Quick Settings tile: connect / disconnect toggle. */
class TunanekoTileService : TileService() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var listenJob: kotlinx.coroutines.Job? = null

    override fun onCreate() {
        super.onCreate()
        VpnManager.init(this)
    }

    override fun onStartListening() {
        super.onStartListening()
        listenJob?.cancel()
        listenJob = VpnManager.status.onEach { updateTileState() }.launchIn(scope)
        updateTileState()
    }

    override fun onStopListening() {
        listenJob?.cancel()
        listenJob = null
        super.onStopListening()
    }

    private fun updateTileState() {
        qsTile?.let { tile ->
            val s = VpnManager.status.value
            tile.state = when (s) {
                is Status.Connected -> Tile.STATE_ACTIVE
                is Status.Connecting, Status.Measuring -> Tile.STATE_UNAVAILABLE
                else -> Tile.STATE_INACTIVE
            }
            tile.label = "tunaneko"
            // subtitle (Android 10+): show the server when busy/connected
            tile.subtitle = when (s) {
                is Status.Connected -> s.profile.name
                is Status.Connecting -> "…"
                else -> null
            }
            tile.updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        VpnManager.init(this)
        when (VpnManager.status.value) {
            is Status.Connected, is Status.Connecting ->
                VpnManager.disconnect(this)
            else -> {
                // VPN consent is required the first time; open the app for it
                if (VpnService.prepare(this) != null) {
                    startActivityAndCollapse(
                        Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                } else {
                    VpnManager.connect(this)
                }
            }
        }
    }
}
