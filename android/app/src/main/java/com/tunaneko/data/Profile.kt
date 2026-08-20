package com.tunaneko.data

import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

enum class IpType(val label: String) {
    IPV4("IPv4"), IPV6("IPv6");

    companion object {
        fun of(host: String) = if (host.startsWith("[") || host.contains(":")) IPV6 else IPV4
    }
}

data class Profile(
    val id: String = UUID.randomUUID().toString(),
    var name: String,
    var host: String,
    var protocol: String = "anyconnect",
    var ipType: IpType = IpType.of(host),
    var username: String? = null,     // null = use default credentials
    var hasOwnPassword: Boolean = false,
    @Transient var latencyMs: Int? = null
) {
    val bareHost: String get() = host.trim('[', ']')

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id); put("name", name); put("host", host)
        put("protocol", protocol); put("ipType", ipType.label)
        put("username", username ?: JSONObject.NULL)
        put("hasOwnPassword", hasOwnPassword)
    }

    companion object {
        fun fromJson(o: JSONObject) = Profile(
            id = o.optString("id", UUID.randomUUID().toString()),
            name = o.getString("name"),
            host = o.getString("host"),
            protocol = o.optString("protocol", "anyconnect"),
            ipType = if (o.optString("ipType") == "IPv6") IpType.IPV6 else IpType.of(o.getString("host")),
            username = if (o.isNull("username")) null else o.optString("username").ifEmpty { null },
            hasOwnPassword = o.optBoolean("hasOwnPassword", false)
        )

        fun listToJson(list: List<Profile>) = JSONArray().apply { list.forEach { put(it.toJson()) } }.toString()

        fun listFromJson(text: String): List<Profile> {
            val arr = JSONArray(text)
            return (0 until arr.length()).map { fromJson(arr.getJSONObject(it)) }
        }

        /** plain-text format: "name host [protocol]" per line */
        fun listFromText(text: String): List<Profile> =
            text.lines().map { it.trim() }
                .filter { it.isNotEmpty() && !it.startsWith("#") }
                .mapNotNull { line ->
                    val p = line.split(Regex("\\s+"))
                    if (p.size >= 2) Profile(name = p[0], host = p[1], protocol = p.getOrElse(2) { "anyconnect" }) else null
                }
    }
}
