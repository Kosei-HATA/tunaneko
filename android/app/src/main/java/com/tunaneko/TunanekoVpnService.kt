package com.tunaneko

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.ParcelFileDescriptor
import com.tunaneko.core.NativeCore
import com.tunaneko.state.Status
import com.tunaneko.state.VpnManager
import java.util.concurrent.atomic.AtomicBoolean

class TunanekoVpnService : VpnService(), NativeCore.Callbacks {

    companion object {
        const val ACTION_CONNECT = "com.tunaneko.CONNECT"
        const val ACTION_DISCONNECT = "com.tunaneko.DISCONNECT"
        const val EXTRA_HOST = "host"
        const val EXTRA_USER = "user"
        const val EXTRA_PASS = "pass"
        const val EXTRA_PIN = "pin"
        private const val CHANNEL_ID = "vpn"
        private const val NOTIF_ID = 1
    }

    /** prevents parallel nativeRun sessions (tun/global ctx are shared) */
    private val running = AtomicBoolean(false)

    @Volatile private var tun: ParcelFileDescriptor? = null
    @Volatile private var currentHost: String = ""

    // underlying network watcher (SIM ⇔ Wi-Fi handover → reconnect)
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private val physicalNetworks = mutableSetOf<Network>()
    @Volatile private var activePhysical: Network? = null
    @Volatile private var lastReconnectAt = 0L

    override fun onCreate() {
        super.onCreate()
        VpnManager.init(this)
        registerNetworkWatcher()
    }

    /**
     * Watches ALL physical networks (Wi-Fi/cellular). The default-network
     * callback stops reporting physical networks once the VPN is the default,
     * so we track them explicitly and react when the best one changes.
     */
    private fun registerNetworkWatcher() {
        val cm = getSystemService(ConnectivityManager::class.java) ?: return
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                if (isVpn(cm, network)) return
                synchronized(physicalNetworks) { physicalNetworks.add(network) }
                evaluate(cm)
            }
            override fun onLost(network: Network) {
                synchronized(physicalNetworks) { physicalNetworks.remove(network) }
                evaluate(cm)
            }
        }
        cm.registerNetworkCallback(request, cb)
        networkCallback = cb
    }

    private fun isVpn(cm: ConnectivityManager, network: Network): Boolean =
        cm.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true

    /** system preference: Wi-Fi over cellular */
    private fun bestPhysical(cm: ConnectivityManager): Network? {
        synchronized(physicalNetworks) {
            return physicalNetworks.firstOrNull {
                cm.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
            } ?: physicalNetworks.firstOrNull()
        }
    }

    private fun evaluate(cm: ConnectivityManager) {
        val best = bestPhysical(cm) ?: return
        val prev = activePhysical ?: run {
            activePhysical = best   // first sighting: just record
            return
        }
        if (best != prev) {
            val now = System.currentTimeMillis()
            if (now - lastReconnectAt > 3000 &&
                VpnManager.status.value is Status.Connected) {
                lastReconnectAt = now
                activePhysical = best
                VpnManager.handleNetworkChange(this)
            }
        }
    }

    /** called when the tunnel comes up: remember the underlay we connected on */
    private fun noteConnectedUnderlay() {
        val cm = getSystemService(ConnectivityManager::class.java) ?: return
        activePhysical = bestPhysical(cm)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_DISCONNECT -> {
                VpnManager.markUserCancelled()
                NativeCore.nativeCancel()
                return START_NOT_STICKY
            }
            ACTION_CONNECT -> {
                if (!running.compareAndSet(false, true)) {
                    VpnManager.log("connection already running; ignoring")
                    return START_NOT_STICKY
                }
                startForeground(NOTIF_ID, buildNotification("connecting…"))
                currentHost = intent.getStringExtra(EXTRA_HOST) ?: return START_NOT_STICKY
                val user = intent.getStringExtra(EXTRA_USER) ?: ""
                val pass = intent.getStringExtra(EXTRA_PASS) ?: ""
                val pin = intent.getStringExtra(EXTRA_PIN)
                Thread {
                    val ret = NativeCore.nativeRun(currentHost, user, pass, pin, this)
                    VpnManager.log("nativeRun exited: $ret")
                    running.set(false)
                    // tun fd was detached; native side closed it. Just drop the ref.
                    tun = null
                    VpnManager.onExited(ret)
                    stopSelf()
                }.also { it.start() }
                return START_NOT_STICKY
            }
            else -> {
                // START_STICKY restart with null intent: the tunnel is already
                // dead (fd closed with the process) — don't linger as a zombie
                stopSelf()
                return START_NOT_STICKY
            }
        }
    }

    override fun onDestroy() {
        networkCallback?.let {
            getSystemService(ConnectivityManager::class.java)?.unregisterNetworkCallback(it)
        }
        networkCallback = null
        NativeCore.nativeCancel()
        tun = null   // fd is detached & closed natively
        super.onDestroy()
    }

    // ---- NativeCore.Callbacks ----

    override fun onLog(level: Int, msg: String) = VpnManager.log(msg.trim())

    override fun onCertCheck(fingerprint: String, reason: String): Boolean {
        val stored = VpnManager.certPinStore.pin(currentHost)
        return if (stored == null) {
            VpnManager.certPinStore.setPin(currentHost, fingerprint)
            VpnManager.log("pinned cert for $currentHost")
            true
        } else {
            VpnManager.onCertMismatch(currentHost)
            false
        }
    }

    override fun onProtect(fd: Int): Boolean = protect(fd)

    override fun onAuthError(error: String) {
        VpnManager.log("auth error: $error")
        VpnManager.onAuthFailed()
    }

    override fun onSetupTun(
        addr: String, netmask: String, dns: Array<String>, mtu: Int, domain: String
    ): Int {
        return try {
            val b = Builder()
                .setSession("tunaneko")
                .setMtu(if (mtu > 0) mtu else 1280)
                .addAddress(addr, netmaskToPrefix(netmask))
                .addRoute("0.0.0.0", 0)
            dns.filter { it.isNotEmpty() }.forEach { b.addDnsServer(it) }
            if (domain.isNotEmpty()) b.addSearchDomain(domain)
            val pfd = b.establish() ?: return -1
            tun = pfd
            // transfer fd ownership to the native side; lib closes it at teardown.
            // (closing a PFD-owned fd natively aborts via fdsan)
            val fd = pfd.detachFd()
            noteConnectedUnderlay()
            VpnManager.onConnected()
            updateNotification("connected: $addr")
            fd
        } catch (e: Exception) {
            VpnManager.log("tun establish failed: ${e.message}")
            -1
        }
    }

    // ---- helpers ----

    private fun netmaskToPrefix(mask: String): Int = try {
        mask.split(".").sumOf { Integer.bitCount(it.toInt()) }
    } catch (e: Exception) { 32 }

    private fun buildNotification(text: String): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "VPN", NotificationManager.IMPORTANCE_LOW)
        )
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        val stopPi = PendingIntent.getService(
            this, 1, Intent(this, TunanekoVpnService::class.java).setAction(ACTION_DISCONNECT),
            PendingIntent.FLAG_IMMUTABLE
        )
        val profileName = (VpnManager.status.value as? Status.Connected)?.profile?.name
            ?: (VpnManager.status.value as? Status.Connecting)?.profile?.name ?: ""
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("tunaneko")
            .setContentText(if (profileName.isEmpty()) text else "$text — $profileName")
            .setSmallIcon(R.drawable.ic_tile_fish)
            .setContentIntent(pi)
            .addAction(Notification.Action.Builder(null, getString(R.string.disconnect), stopPi).build())
            .build()
    }

    private fun updateNotification(text: String) {
        getSystemService(NotificationManager::class.java).notify(NOTIF_ID, buildNotification(text))
    }
}
