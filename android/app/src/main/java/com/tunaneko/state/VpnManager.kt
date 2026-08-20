package com.tunaneko.state

import android.content.Context
import android.content.Intent
import android.net.TrafficStats
import android.os.Process
import com.tunaneko.TunanekoVpnService
import com.tunaneko.data.CertPinStore
import com.tunaneko.data.CredentialStore
import com.tunaneko.data.Profile
import com.tunaneko.data.ProfileStore
import com.tunaneko.net.LatencyTester
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

sealed interface Status {
    data object Disconnected : Status
    data object Measuring : Status
    data class Connecting(val profile: Profile) : Status
    data class Connected(val profile: Profile, val sinceMs: Long) : Status
    data class Failed(val profileName: String, val reason: String) : Status
}

/** Process-wide VPN orchestrator (drives TunanekoVpnService). */
object VpnManager {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    lateinit var appContext: Context
    lateinit var profileStore: ProfileStore
    lateinit var credentialStore: CredentialStore
    lateinit var certPinStore: CertPinStore

    fun init(context: Context) {
        if (::appContext.isInitialized) return
        appContext = context.applicationContext
        profileStore = ProfileStore(appContext)
        credentialStore = CredentialStore(appContext)
        certPinStore = CertPinStore(appContext)
        _profiles.value = profileStore.load()
        defaultUsername = prefsGet("defaultUsername", "")
    }

    // ---- observable state ----
    private val _status = MutableStateFlow<Status>(Status.Disconnected)
    val status: StateFlow<Status> = _status

    private val _profiles = MutableStateFlow<MutableList<Profile>>(mutableListOf())
    val profiles: StateFlow<MutableList<Profile>> = _profiles

    private val _selectedId = MutableStateFlow<String?>(null)  // null = Auto
    val selectedId: StateFlow<String?> = _selectedId

    private val _logs = MutableStateFlow<List<String>>(emptyList())
    val logs: StateFlow<List<String>> = _logs

    private val _isMeasuring = MutableStateFlow(false)
    val isMeasuring: StateFlow<Boolean> = _isMeasuring

    // traffic stats (per-connection)
    private val _upBps = MutableStateFlow(0.0)
    private val _downBps = MutableStateFlow(0.0)
    private val _totalUp = MutableStateFlow(0L)
    private val _totalDown = MutableStateFlow(0L)
    val upBps: StateFlow<Double> = _upBps
    val downBps: StateFlow<Double> = _downBps
    val totalUp: StateFlow<Long> = _totalUp
    val totalDown: StateFlow<Long> = _totalDown

    // ---- settings (SharedPreferences) ----
    var autoRetry: Boolean
        get() = prefsGet("autoRetry", "true").toBoolean()
        set(v) = prefsSet("autoRetry", v.toString())
    var defaultUsername: String
        get() = prefsGet("defaultUsername", "")
        set(v) = prefsSet("defaultUsername", v)
    var language: String
        get() = prefsGet("language", "auto")
        set(v) = prefsSet("language", v)

    private fun prefsGet(k: String, def: String) =
        appContext.getSharedPreferences("settings", Context.MODE_PRIVATE).getString(k, def) ?: def
    private fun prefsSet(k: String, v: String) =
        appContext.getSharedPreferences("settings", Context.MODE_PRIVATE).edit().putString(k, v).apply()

    // ---- internals ----
    private var retryQueue = mutableListOf<Profile>()
    private var retryCount = 0
    private val maxRetries = 5
    @Volatile private var userCancelled = false

    /** called by the service when disconnect came from the notification/tile */
    fun markUserCancelled() { userCancelled = true }
    private var statsJobRunning = false

    val currentProfile: Profile?
        get() = when (val s = _status.value) {
            is Status.Connecting -> s.profile
            is Status.Connected -> s.profile
            else -> null
        }

    fun log(msg: String) {
        val ts = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US)
            .format(java.util.Date())
        _logs.value = (_logs.value + "[$ts] $msg").takeLast(500)
    }

    // ---- profiles ----

    fun saveProfiles() = profileStore.save(_profiles.value)

    fun addOrUpdate(p: Profile) {
        val list = _profiles.value
        val idx = list.indexOfFirst { it.id == p.id }
        if (idx >= 0) list[idx] = p else list.add(p)
        _profiles.value = list.toMutableList()
        saveProfiles()
    }

    fun delete(p: Profile) {
        credentialStore.delete(p.id)
        certPinStore.delete(p.host)
        _profiles.value = _profiles.value.filter { it.id != p.id }.toMutableList()
        if (_selectedId.value == p.id) _selectedId.value = null
        saveProfiles()
    }

    fun select(id: String?) { _selectedId.value = id }

    // ---- latency ----

    fun measureAll(onDone: (() -> Unit)? = null) {
        if (_isMeasuring.value) { onDone?.invoke(); return }
        _isMeasuring.value = true
        val targets = _profiles.value.map { it.id to it.bareHost }
        scope.launch {
            withContext(Dispatchers.Default) {
                LatencyTester.measureAll(targets) { id, ms ->
                    scope.launch {
                        val list = _profiles.value
                        list.find { it.id == id }?.latencyMs = ms
                        _profiles.value = list.toMutableList()
                    }
                }
            }
            _isMeasuring.value = false
            onDone?.invoke()
        }
    }

    // ---- connect / disconnect ----

    fun connect(context: Context) {
        if (_status.value is Status.Connecting || _status.value is Status.Connected || _isMeasuring.value) return

        // preflight: credentials
        val hasDefault = credentialStore.password("default") != null
        val hasAny = hasDefault || _profiles.value.any { it.hasOwnPassword }
        if (!hasAny) {
            _status.value = Status.Failed("-", "no credentials stored")
            log("preflight: no password stored")
            return
        }

        // auto: measure first if no latency data
        if (_selectedId.value == null && _profiles.value.any { it.latencyMs == null }) {
            log("auto: measuring latency…")
            measureAll { doConnect(context) }
            return
        }
        doConnect(context)
    }

    private fun doConnect(context: Context) {
        retryQueue.clear()
        retryCount = 0
        userCancelled = false

        val target = _profiles.value.find { it.id == _selectedId.value }
            ?: _profiles.value.filter { it.latencyMs != null }.minByOrNull { it.latencyMs!! }
            ?: _profiles.value.firstOrNull()
        if (target == null) {
            log("no profiles")
            return
        }
        if (autoRetry) {
            retryQueue = _profiles.value.filter { it.id != target.id }
                .sortedBy { it.latencyMs ?: Int.MAX_VALUE }.toMutableList()
        }
        startService(context, target)
    }

    private fun startService(context: Context, profile: Profile) {
        val (user, pass) = credentialsFor(profile) ?: run {
            if (retryQueue.isNotEmpty() && retryCount < maxRetries) {
                log("no credentials for ${profile.name}; skipping")
                tryNext(context)
            } else {
                _status.value = Status.Failed(profile.name, "no credentials")
            }
            return
        }
        _status.value = Status.Connecting(profile)
        log("connecting to ${profile.name} (${profile.host}) as $user")
        val intent = Intent(context, TunanekoVpnService::class.java).apply {
            action = TunanekoVpnService.ACTION_CONNECT
            putExtra(TunanekoVpnService.EXTRA_HOST, profile.host)
            putExtra(TunanekoVpnService.EXTRA_USER, user)
            putExtra(TunanekoVpnService.EXTRA_PASS, pass)
            putExtra(TunanekoVpnService.EXTRA_PIN, certPinStore.pin(profile.host))
        }
        context.startForegroundService(intent)
    }

    private fun credentialsFor(profile: Profile): Pair<String, String>? {
        val user = profile.username ?: defaultUsername
        val account = if (profile.hasOwnPassword) profile.id else "default"
        val pass = credentialStore.password(account)
        return if (pass.isNullOrEmpty()) null else user to pass
    }

    fun disconnect(context: Context) {
        userCancelled = true
        context.startService(Intent(context, TunanekoVpnService::class.java)
            .setAction(TunanekoVpnService.ACTION_DISCONNECT))
    }

    /** Underlying network changed (SIM ⇔ Wi-Fi): reconnect the SAME profile. */
    fun handleNetworkChange(context: Context) {
        val s = _status.value
        val profile = when (s) {
            is Status.Connected -> s.profile
            is Status.Connecting -> s.profile
            else -> null
        } ?: return
        log("network changed — reconnecting ${profile.name}")
        userCancelled = true          // suppress failure-retry for this teardown
        retryQueue.clear()
        retryCount = 0
        context.startService(Intent(context, TunanekoVpnService::class.java)
            .setAction(TunanekoVpnService.ACTION_DISCONNECT))
        scope.launch {
            delay(1500)               // let the tunnel come down
            userCancelled = false
            startService(context, profile)
        }
    }

    // ---- events from the service ----

    fun onConnected() {
        val s = _status.value
        if (s is Status.Connecting) {
            _status.value = Status.Connected(s.profile, System.currentTimeMillis())
            log("connected: ${s.profile.name}")
            startStats()
        }
    }

    fun onAuthFailed() {
        val s = _status.value
        if (s is Status.Connecting) {
            log("auth failed on ${s.profile.name}")
            // never retry auth failures: same wrong password would just fail
            // (and burn lockout attempts) on every other server
            retryQueue.clear()
            _status.value = Status.Failed(s.profile.name, "authentication failed")
        }
    }

    fun onCertMismatch(host: String) {
        val s = _status.value
        if (s is Status.Connecting) {
            retryQueue.clear()  // never retry a cert mismatch
            _status.value = Status.Failed(s.profile.name, "certificate changed: $host")
            log("cert mismatch on $host — refusing to re-pin")
        }
    }

    fun onExited(code: Int) {
        stopStats()
        val s = _status.value
        when {
            s is Status.Connected -> {
                _status.value = Status.Disconnected
                log("disconnected (${s.profile.name})")
            }
            s is Status.Connecting && !userCancelled -> {
                log("connection to ${s.profile.name} failed (exit $code)")
                scheduleRetry(s.profile.name, "exit $code")
            }
            else -> _status.value = Status.Disconnected
        }
    }

    private fun scheduleRetry(name: String, reason: String) {
        _status.value = Status.Failed(name, reason)
        val ctx = if (::appContext.isInitialized) appContext else return
        if (autoRetry && retryCount < maxRetries && retryQueue.isNotEmpty() && !userCancelled) {
            tryNext(ctx)
        }
    }

    private fun tryNext(context: Context) {
        if (retryQueue.isEmpty()) return
        retryCount++
        val next = retryQueue.removeAt(0)
        log("retrying with ${next.name} ($retryCount/$maxRetries)")
        scope.launch {
            delay(500)
            if (userCancelled || _status.value is Status.Disconnected) return@launch
            startService(context, next)
        }
    }

    // ---- stats ----

    private fun startStats() {
        if (statsJobRunning) return
        statsJobRunning = true
        _totalUp.value = 0
        _totalDown.value = 0
        val uid = Process.myUid()
        val baseRx = TrafficStats.getUidRxBytes(uid)
        val baseTx = TrafficStats.getUidTxBytes(uid)
        if (baseRx < 0 || baseTx < 0) { statsJobRunning = false; return } // unsupported device
        var lastRx = baseRx
        var lastTx = baseTx
        var lastAt = System.currentTimeMillis()
        scope.launch {
            while (_status.value is Status.Connected) {
                delay(1000)
                val rx = TrafficStats.getUidRxBytes(uid)
                val tx = TrafficStats.getUidTxBytes(uid)
                val now = System.currentTimeMillis()
                val dt = (now - lastAt) / 1000.0
                if (dt > 0) {
                    _downBps.value = ((rx - lastRx) / dt).coerceAtLeast(0.0)
                    _upBps.value = ((tx - lastTx) / dt).coerceAtLeast(0.0)
                }
                _totalDown.value = (rx - baseRx).coerceAtLeast(0)
                _totalUp.value = (tx - baseTx).coerceAtLeast(0)
                lastRx = rx; lastTx = tx; lastAt = now
            }
            _upBps.value = 0.0
            _downBps.value = 0.0
            statsJobRunning = false
        }
    }

    private fun stopStats() { /* loop exits on status change */ }
}
