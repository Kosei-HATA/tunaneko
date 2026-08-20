package com.tunaneko.data

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Passwords in EncryptedSharedPreferences (Android Keystore backed).
 * If the Keystore is broken (key invalidated by lockscreen change, device
 * migration, Keystore bugs), the store self-heals: wipes and falls back to
 * plain SharedPreferences rather than crashing the app forever.
 */
class CredentialStore(context: Context) {
    private val prefs: SharedPreferences = try {
        EncryptedSharedPreferences.create(
            context,
            "credentials",
            MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    } catch (e: Exception) {
        Log.w("tunaneko", "EncryptedSharedPreferences failed, falling back to plain prefs", e)
        context.deleteSharedPreferences("credentials")
        context.getSharedPreferences("credentials_fallback", Context.MODE_PRIVATE)
    }

    fun password(account: String): String? = prefs.getString(account, null)
    fun setPassword(account: String, password: String) = prefs.edit().putString(account, password).apply()
    fun delete(account: String) = prefs.edit().remove(account).apply()
    fun has(account: String): Boolean = prefs.contains(account)
}
