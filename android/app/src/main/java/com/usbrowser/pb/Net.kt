package com.usbrowser.pb

import android.content.Context
import okhttp3.Credentials
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Proxy
import java.util.TimeZone
import java.util.concurrent.TimeUnit

data class Geo(val ip: String, val city: String, val region: String, val country: String,
               val lat: Double, val lon: Double, val tz: String)

/** App-side requests (proxy check, suggestions, youtube.js). Blocking calls: run them on Dispatchers.IO. */
object Net {
    private const val YOUTUBE_JS = "https://raw.githubusercontent.com/thn312/PB/main/Sources/youtube.js"

    /** Same route as the tabs: through the HTTP proxy, or direct (never the system proxy) when proxy is null. */
    fun client(proxy: ProxyEntry?): OkHttpClient {
        val b = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS).readTimeout(15, TimeUnit.SECONDS)
        if (proxy == null) return b.proxy(Proxy.NO_PROXY).build()
        b.proxy(Proxy(Proxy.Type.HTTP, InetSocketAddress.createUnresolved(proxy.host, proxy.port)))
        if (proxy.user.isNotEmpty()) {
            b.proxyAuthenticator { _, response ->
                if (response.request.header("Proxy-Authorization") != null) null // wrong credentials: give up
                else response.request.newBuilder()
                    .header("Proxy-Authorization", Credentials.basic(proxy.user, proxy.pass)).build()
            }
        }
        return b.build()
    }

    private fun get(client: OkHttpClient, url: String, timeoutSec: Long = 15): String {
        val c = client.newBuilder().callTimeout(timeoutSec, TimeUnit.SECONDS).build()
        c.newCall(Request.Builder().url(url).build()).execute().use { r ->
            if (!r.isSuccessful) throw IOException("HTTP ${r.code}")
            return r.body?.string() ?: ""
        }
    }

    /** Where the proxy's exit IP is, looked up through the proxy. Throws if anything is missing (fail closed). */
    fun geo(client: OkHttpClient): Geo {
        val o = JSONObject(get(client, "https://ipinfo.io/json"))
        val loc = o.getString("loc").split(",").map { it.trim().toDouble() }
        val tz = o.getString("timezone")
        if (loc.size != 2 || tz !in TimeZone.getAvailableIDs()) throw IOException("Could not read the proxy location")
        return Geo(o.getString("ip"), o.optString("city"), o.optString("region"), o.getString("country"), loc[0], loc[1], tz)
    }

    fun suggest(client: OkHttpClient, query: String): List<String> = runCatching {
        val url = "https://suggestqueries.google.com/complete/search".toHttpUrl().newBuilder()
            .addQueryParameter("client", "firefox").addQueryParameter("hl", "en-US")
            .addQueryParameter("ie", "utf-8").addQueryParameter("oe", "utf-8")
            .addQueryParameter("q", query).build().toString()
        val list = JSONArray(get(client, url, 5)).getJSONArray(1)
        (0 until minOf(list.length(), 6)).map { list.getString(it) }
    }.getOrDefault(emptyList())

    /** Newest youtube.js from GitHub (fixes ship without reinstalling), else the bundled copy. */
    fun youtubeScript(client: OkHttpClient, ctx: Context): String =
        runCatching { get(client, YOUTUBE_JS, 6) }.getOrNull()?.takeIf { it.startsWith("// PB youtube.js") }
            ?: asset(ctx, "youtube.js")

    fun asset(ctx: Context, name: String) = ctx.assets.open(name).bufferedReader().use { it.readText() }
}
