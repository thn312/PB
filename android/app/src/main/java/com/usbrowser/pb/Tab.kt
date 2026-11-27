package com.usbrowser.pb

import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Message
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.GeolocationPermissions
import android.webkit.HttpAuthHandler
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.webkit.ScriptHandler
import androidx.webkit.WebViewCompat
import java.io.ByteArrayInputStream
import java.util.UUID

/** WebView that keeps playing audio/video when the app goes to the background or the screen turns off. */
class PBWebView(ctx: Context) : WebView(ctx) {
    override fun onWindowVisibilityChanged(visibility: Int) {
        if (visibility == View.VISIBLE) super.onWindowVisibilityChanged(visibility) // never report "hidden"
    }
}

@SuppressLint("SetJavaScriptEnabled")
class Tab(private val browser: Browser, private val activity: MainActivity) {
    val id: String = UUID.randomUUID().toString()
    val webView = PBWebView(activity)
    var title by mutableStateOf("")
    var url by mutableStateOf("")
    var progress by mutableIntStateOf(0)
    var loading by mutableStateOf(false)
    var canGoBack by mutableStateOf(false)
    var canGoForward by mutableStateOf(false)
    var error by mutableStateOf("")
    /** Link the user long-pressed; the UI shows a menu for it. */
    var longPressUrl by mutableStateOf<String?>(null)

    private var scripts = listOf<ScriptHandler>()
    @Volatile private var pageHost: String? = null // read on WebView's network thread
    private var authTries = 0

    init {
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            setSupportMultipleWindows(true) // target=_blank / window.open -> new tab
            builtInZoomControls = true
            displayZoomControls = false
            loadWithOverviewMode = true
            useWideViewPort = true
            // Look like Chrome: the stock WebView UA ("; wv", "Version/4.0") tells sites it's an in-app browser.
            userAgentString = WebSettings.getDefaultUserAgent(activity)
                .replace("; wv", "").replace(Regex("""Version/[\d.]+ """), "")
        }
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true) // needed by some logins
        webView.webViewClient = Client()
        webView.webChromeClient = Chrome()
        webView.setOnLongClickListener {
            val hit = webView.hitTestResult
            if (hit.type == WebView.HitTestResult.SRC_ANCHOR_TYPE && hit.extra != null) {
                longPressUrl = hit.extra
                true
            } else false
        }
    }

    fun go(input: String) {
        val u = Urls.resolve(input) ?: return
        error = ""
        webView.loadUrl(u)
    }

    /** Replaces this tab's document-start scripts (they apply from the next page load). */
    fun installScripts(sources: List<String>) {
        scripts.forEach { it.remove() }
        scripts = sources.map { WebViewCompat.addDocumentStartJavaScript(webView, it, setOf("*")) }
    }

    fun destroy() {
        scripts.forEach { it.remove() }
        webView.stopLoading()
        (webView.parent as? ViewGroup)?.removeView(webView)
        webView.destroy()
    }

    /** Opens a link in another app, only for a user tap and only when "Allow Opening Apps" is on. */
    fun openExternally(url: String) {
        val intent = if (url.startsWith("intent:")) {
            runCatching { Intent.parseUri(url, Intent.URI_INTENT_SCHEME) }.getOrNull() ?: return
        } else Intent(Intent.ACTION_VIEW, Uri.parse(url))
        // Only let it reach apps that accept browser links, never this app's or other apps' internal screens.
        intent.addCategory(Intent.CATEGORY_BROWSABLE)
        intent.component = null
        intent.selector = null
        try { activity.startActivity(intent) } catch (_: ActivityNotFoundException) { }
    }

    private fun syncNav() {
        canGoBack = webView.canGoBack()
        canGoForward = webView.canGoForward()
        webView.url?.let { url = it }
    }

    private inner class Client : WebViewClient() {
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            if (Urls.isWeb(request.url.scheme)) return false // stays in PB (Android doesn't hand web links to apps here)
            // tel:, mailto:, intent:, twitter://… would open another app, outside the proxy.
            if (browser.allowApps && request.hasGesture()) openExternally(request.url.toString())
            return true
        }

        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
            if (!browser.adblock || request.isForMainFrame) return null
            val domains = browser.blockDomains
            // Third-party only, like the iOS rules: visiting a listed site directly still works.
            if (Blocklist.blocked(request.url.host, domains) && !Blocklist.blocked(pageHost, domains)) {
                return WebResourceResponse("text/plain", "utf-8", ByteArrayInputStream(ByteArray(0)))
            }
            return null
        }

        override fun onReceivedHttpAuthRequest(view: WebView, handler: HttpAuthHandler, host: String, realm: String?) {
            // Only ever hand the proxy's password to the proxy itself, never to a website asking for a login.
            val p = browser.connectedProxy
            if (p != null && p.user.isNotEmpty() && authTries < 3 &&
                (host.equals(p.host, true) || host.equals("${p.host}:${p.port}", true))) {
                authTries++
                handler.proceed(p.user, p.pass)
            } else super.onReceivedHttpAuthRequest(view, handler, host, realm)
        }

        override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
            pageHost = Uri.parse(url).host
            this@Tab.url = url
            error = ""
            loading = true
            syncNav()
        }

        override fun onPageFinished(view: WebView, url: String) {
            loading = false
            authTries = 0
            syncNav()
            browser.history.record(view.url, view.title ?: "")
        }

        override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) = syncNav()

        override fun onReceivedError(view: WebView, request: WebResourceRequest, err: WebResourceError) {
            if (request.isForMainFrame) error = "⚠️ ${err.description} (${err.errorCode}) ${request.url}"
        }
    }

    private inner class Chrome : WebChromeClient() {
        override fun onProgressChanged(view: WebView, newProgress: Int) { progress = newProgress }

        override fun onReceivedTitle(view: WebView, t: String?) { title = t ?: "" }

        override fun onCreateWindow(view: WebView, isDialog: Boolean, isUserGesture: Boolean, resultMsg: Message): Boolean {
            if (!isUserGesture) return false // no pop-ups the user didn't ask for
            val tab = browser.newTab("")
            (resultMsg.obj as WebView.WebViewTransport).webView = tab.webView
            resultMsg.sendToTarget()
            return true
        }

        override fun onCloseWindow(window: WebView) = browser.close(this@Tab)

        override fun onShowCustomView(view: View, callback: CustomViewCallback) = activity.showFullscreen(view, callback)

        override fun onHideCustomView() = activity.hideFullscreen()

        // shortcut: real GPS is never shared. With a proxy, spoof.js answers instead; in No Proxy mode sites get "denied".
        override fun onGeolocationPermissionsShowPrompt(origin: String, callback: GeolocationPermissions.Callback) =
            callback.invoke(origin, false, false)

        override fun onShowFileChooser(view: WebView, callback: ValueCallback<Array<Uri>>, params: FileChooserParams): Boolean {
            activity.pickFiles(callback)
            return true
        }
    }
}
