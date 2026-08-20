package com.tunaneko.data

import android.content.Context

/** profiles.json in app-private storage. */
class ProfileStore(private val context: Context) {
    private val file get() = java.io.File(context.filesDir, "profiles.json")

    fun load(): MutableList<Profile> {
        if (!file.exists()) return mutableListOf()
        return try {
            Profile.listFromJson(file.readText()).toMutableList()
        } catch (e: Exception) {
            // corrupt: back up instead of overwriting
            file.renameTo(java.io.File(context.filesDir, "profiles.json.corrupt-${System.currentTimeMillis()}"))
            mutableListOf()
        }
    }

    fun save(profiles: List<Profile>) {
        try {
            val tmp = java.io.File(context.filesDir, "profiles.json.tmp")
            tmp.writeText(Profile.listToJson(profiles))
            tmp.renameTo(file)
        } catch (e: Exception) {
            android.util.Log.e("tunaneko", "profile save failed", e)
        }
    }
}
