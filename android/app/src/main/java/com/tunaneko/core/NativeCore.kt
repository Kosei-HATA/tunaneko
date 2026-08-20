package com.tunaneko.core

object NativeCore {
    init {
        System.loadLibrary("tunaneko")
    }

    interface Callbacks {
        fun onLog(level: Int, msg: String)
        /** TOFU / pin check. fingerprint = hash string from libopenconnect. */
        fun onCertCheck(fingerprint: String, reason: String): Boolean
        /** must call VpnService.protect(fd) so tunnel traffic bypasses the VPN */
        fun onProtect(fd: Int): Boolean
        fun onAuthError(error: String)
        /** called when the server assigned IP config; must establish the TUN
         *  via VpnService.Builder and return its fd (or -1 on failure) */
        fun onSetupTun(
            addr: String,
            netmask: String,
            dns: Array<String>,
            mtu: Int,
            domain: String
        ): Int
    }

    external fun nativeRun(
        host: String,
        username: String,
        password: String,
        certPin: String?,
        callbacks: Callbacks
    ): Int

    external fun nativeCancel()
}
