package com.usbrowser.pb

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

data class ProxyEntry(
    val id: String = UUID.randomUUID().toString(),
    val name: String = "",
    val host: String = "",
    val port: Int = 8080,
    val user: String = "",
    val pass: String = "",
) {
    val label get() = name.ifBlank { "$host:$port" }
    val valid get() = host.isNotBlank() && port in 1..65535
}

/**
 * Settings and saved proxies in app-private storage.
 * shortcut: proxy passwords are stored unencrypted in private prefs (other apps can't read them, backups are off);
 * move them to the Android Keystore if the threat model ever includes rooted devices.
 */
class Prefs(ctx: Context) {
    private val p = ctx.getSharedPreferences("pb", Context.MODE_PRIVATE)

    fun proxies(): List<ProxyEntry> = runCatching {
        val a = JSONArray(p.getString("proxies", "[]"))
        (0 until a.length()).map { i ->
            val o = a.getJSONObject(i)
            ProxyEntry(o.getString("id"), o.optString("name"), o.optString("host"), o.optInt("port", 8080),
                o.optString("user"), o.optString("pass"))
        }
    }.getOrDefault(emptyList())

    fun saveProxies(list: List<ProxyEntry>) {
        val a = JSONArray()
        list.forEach {
            a.put(JSONObject().put("id", it.id).put("name", it.name).put("host", it.host).put("port", it.port)
                .put("user", it.user).put("pass", it.pass))
        }
        p.edit().putString("proxies", a.toString()).apply()
    }

    var activeId: String?
        get() = p.getString("active", null)
        set(v) = p.edit().putString("active", v).apply()
    var direct: Boolean
        get() = p.getBoolean("direct", false)
        set(v) = p.edit().putBoolean("direct", v).apply()
    var adblock: Boolean
        get() = p.getBoolean("adblock", true)
        set(v) = p.edit().putBoolean("adblock", v).apply()
    var allowApps: Boolean
        get() = p.getBoolean("allowApps", false)
        set(v) = p.edit().putBoolean("allowApps", v).apply()
}

data class HistoryEntry(val url: String, val title: String, val date: Long, val id: String = UUID.randomUUID().toString())

/** Browsing history, newest first, only on this device (files/history.json). */
class HistoryStore(ctx: Context) {
    private val file = File(ctx.filesDir, "history.json")
    private val limit = 2000
    var entries by mutableStateOf(load())
        private set

    private fun load(): List<HistoryEntry> = runCatching {
        val a = JSONArray(file.readText())
        (0 until a.length()).map { i ->
            val o = a.getJSONObject(i)
            HistoryEntry(o.getString("url"), o.optString("title"), o.getLong("date"), o.getString("id"))
        }
    }.getOrDefault(emptyList())

    fun record(url: String?, title: String) {
        if (url == null || !(url.startsWith("http://") || url.startsWith("https://"))) return
        val first = entries.firstOrNull()
        entries = if (first?.url == url) { // reload/same page: refresh instead of duplicating
            listOf(first.copy(title = title.ifEmpty { first.title }, date = System.currentTimeMillis())) + entries.drop(1)
        } else {
            (listOf(HistoryEntry(url, title, System.currentTimeMillis())) + entries).take(limit)
        }
        save()
    }

    fun delete(e: HistoryEntry) { entries = entries.filter { it.id != e.id }; save() }

    fun clear() { entries = emptyList(); save() }

    fun matches(query: String, max: Int = 4): List<HistoryEntry> {
        val q = query.lowercase()
        return entries.filter { q in it.url.lowercase() || q in it.title.lowercase() }.distinctBy { it.url }.take(max)
    }

    private fun save() {
        // shortcut: rewrites the whole file per page load (≤2000 entries); batch writes if it ever feels slow.
        val a = JSONArray()
        entries.forEach { a.put(JSONObject().put("url", it.url).put("title", it.title).put("date", it.date).put("id", it.id)) }
        runCatching { file.writeText(a.toString()) }
    }
}
