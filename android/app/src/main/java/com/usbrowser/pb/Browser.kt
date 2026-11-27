package com.usbrowser.pb

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewFeature
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import org.json.JSONObject
import java.util.concurrent.Executor
import kotlin.coroutines.resume

/** App state: proxies, tabs, scripts. Everything here runs on the main thread unless noted. */
class Browser(val activity: MainActivity) {
    val prefs = Prefs(activity)
    val history = HistoryStore(activity)
    val scope = MainScope()

    var tabs by mutableStateOf(listOf<Tab>())
        private set
    var current by mutableStateOf<Tab?>(null)
    var status by mutableStateOf("Not connected")
        private set
    var connecting by mutableStateOf(false)
        private set
    var proxies by mutableStateOf(prefs.proxies())
        private set
    var activeId by mutableStateOf(prefs.activeId)
        private set
    /** No proxy: real IP and real location. Only on because the user picked it; a dead proxy never falls back to it. */
    var direct by mutableStateOf(prefs.direct)
        private set
    var adblock by mutableStateOf(prefs.adblock)
        private set
    /** Off by default: links stay in PB instead of opening other apps, which would bypass the proxy. */
    var allowApps by mutableStateOf(prefs.allowApps)
        private set

    /** Proxy the tabs are using right now (null = direct or not connected). Read by Tab for proxy auth. */
    @Volatile var connectedProxy: ProxyEntry? = null
        private set
    /** For suggestions: same route as the tabs. */
    var client: OkHttpClient? = null
        private set
    /** Read from WebView's network thread. */
    @Volatile var blockDomains: Set<String> = emptySet()
        private set
    private var hideSelector = ""
    private var spoofJs = ""
    private var youtubeJs = ""
    private var attempt = 0

    val activeProxy get() = proxies.firstOrNull { it.id == activeId } ?: proxies.firstOrNull()

    fun use(p: ProxyEntry) {
        activeId = p.id; prefs.activeId = p.id
        switchDirect(false)
    }

    fun useDirect() = switchDirect(true)

    private fun switchDirect(on: Boolean) {
        direct = on; prefs.direct = on
        scope.launch { connect() }
    }

    fun saveProxy(p: ProxyEntry) {
        val i = proxies.indexOfFirst { it.id == p.id }
        proxies = if (i >= 0) proxies.toMutableList().also { it[i] = p } else proxies + p
        prefs.saveProxies(proxies)
        if (!direct && p.id == activeProxy?.id) use(p) // edited the one in use (or the first one): reconnect
    }

    fun deleteProxy(p: ProxyEntry) {
        val wasActive = p.id == activeProxy?.id
        proxies = proxies.filter { it.id != p.id }
        prefs.saveProxies(proxies)
        if (!direct && wasActive) {
            activeId = proxies.firstOrNull()?.id; prefs.activeId = activeId
            scope.launch { connect() }
        }
    }

    fun changeAdblock(on: Boolean) {
        adblock = on; prefs.adblock = on
        tabs.forEach { it.installScripts(scripts()) }
        current?.webView?.reload()
    }

    fun changeAllowApps(on: Boolean) { allowApps = on; prefs.allowApps = on }

    /** Fail closed: no tab exists until the proxy is verified, so the real IP is never used by accident. */
    suspend fun connect() {
        val mine = ++attempt // a newer switch wins; an older check that finishes late is dropped
        tabs.forEach { it.destroy() }
        tabs = emptyList(); current = null; client = null; connectedProxy = null
        val p = if (direct) null else activeProxy
        if (!direct && (p == null || !p.valid)) { status = "No proxy set"; return }
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE) ||
            !WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            status = "Please update \"Android System WebView\" from the Play Store"
            return
        }
        connecting = true
        status = if (p == null) "Connecting…" else "Checking ${p.label}…"
        try {
            val c = Net.client(p)
            val (geo, yt) = withContext(Dispatchers.IO) {
                (if (p != null) Net.geo(c) else null) to Net.youtubeScript(c, activity)
            }
            if (blockDomains.isEmpty()) loadBlocklist()
            if (mine != attempt) return
            setWebViewProxy(p) // before any tab exists
            if (mine != attempt) return
            spoofJs = geo?.let { spoof(it) } ?: "" // direct: real IP, so keep the real location/timezone too
            youtubeJs = yt
            client = c
            connectedProxy = p
            status = if (geo != null && p != null) "${Urls.flag(geo.country)} ${geo.city}, ${geo.region} · ${geo.ip} · ${p.label}"
                     else "⚠️ Direct · real IP (no proxy)"
            newTab(if (p != null) "https://browserleaks.com/ip" else Urls.HOME)
        } catch (e: Exception) {
            if (mine == attempt) status = "Proxy error${p?.let { " (${it.label})" } ?: ""}: ${e.message ?: e.javaClass.simpleName}"
        } finally {
            if (mine == attempt) connecting = false
        }
    }

    private suspend fun loadBlocklist() {
        val rules = withContext(Dispatchers.IO) {
            runCatching { Blocklist.parse(Net.asset(activity, "blocklist.json")) }.getOrNull()
        } ?: return // a broken blocklist must not stop browsing
        blockDomains = rules.domains
        hideSelector = rules.hideSelector
    }

    /** WebView's proxy is app-wide. HTTP only: Android WebView can't do SOCKS5 with a password. */
    private suspend fun setWebViewProxy(p: ProxyEntry?) = suspendCancellableCoroutine { cont ->
        val run = Executor { it.run() }
        val done = Runnable { if (cont.isActive) cont.resume(Unit) }
        if (p == null) ProxyController.getInstance().clearProxyOverride(run, done)
        else ProxyController.getInstance().setProxyOverride(
            ProxyConfig.Builder().addProxyRule("http://${p.host}:${p.port}").build(), run, done)
    }

    private fun spoof(g: Geo): String {
        // JSON-encode values from the network so they can't inject JS; wrapped so `C` never collides with page globals.
        val cfg = JSONObject().put("lat", g.lat).put("lon", g.lon).put("tz", g.tz)
        return "(C => {\n${Net.asset(activity, "spoof.js")}\n})($cfg);"
    }

    /** Scripts every page gets at document start, in order. */
    fun scripts(): List<String> = buildList {
        if (spoofJs.isNotEmpty()) add(spoofJs)
        add("(P => {\n$youtubeJs\n})({\"adblock\": $adblock});")
        if (adblock && hideSelector.isNotEmpty()) {
            val css = JSONObject.quote("$hideSelector{display:none!important}")
            add("(() => { const s = document.createElement('style'); s.textContent = $css; document.documentElement.appendChild(s); })();")
        }
    }

    fun newTab(url: String = Urls.HOME): Tab {
        val t = Tab(this, activity)
        t.installScripts(scripts())
        tabs = tabs + t
        current = t
        if (url.isNotEmpty()) t.go(url)
        return t
    }

    fun close(t: Tab) {
        t.destroy()
        tabs = tabs - t
        if (current == t) current = tabs.lastOrNull()
        if (tabs.isEmpty()) newTab()
    }

    /** The OS pauses page video when the app leaves the screen; youtube.js undoes that for YouTube. */
    fun setBackground(on: Boolean) = tabs.forEach { it.webView.evaluateJavascript("window.__pbBg && __pbBg($on)", null) }

    fun destroy() {
        tabs.forEach { it.destroy() }
        scope.cancel()
    }
}
