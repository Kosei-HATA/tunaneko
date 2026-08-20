package com.tunaneko.data

import android.content.Context

/** TOFU certificate pins: host → libopenconnect hash string. */
class CertPinStore(context: Context) {
    private val prefs = context.getSharedPreferences("cert_pins", Context.MODE_PRIVATE)

    fun pin(host: String): String? = prefs.getString(host, null)
    fun setPin(host: String, pin: String) = prefs.edit().putString(host, pin).apply()
    fun delete(host: String) = prefs.edit().remove(host).apply()
}
