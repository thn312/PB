package com.usbrowser.pb

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import androidx.activity.ComponentActivity
import androidx.activity.addCallback
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    lateinit var browser: Browser
        private set
    private var fullscreenView: View? = null
    private var fullscreenCallback: WebChromeClient.CustomViewCallback? = null
    private var fileCallback: ValueCallback<Array<Uri>>? = null

    private val filePicker = registerForActivityResult(ActivityResultContracts.GetMultipleContents()) { uris ->
        fileCallback?.onReceiveValue(uris.toTypedArray())
        fileCallback = null
    }
    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        browser = Browser(this)
        setContent { PBTheme { BrowserApp(browser) } }
        browser.scope.launch { browser.connect() }
        // The background-playback notification needs this on Android 13+.
        if (Build.VERSION.SDK_INT >= 33) notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)

        onBackPressedDispatcher.addCallback(this) {
            val tab = browser.current
            when {
                fullscreenView != null -> hideFullscreen()
                tab?.webView?.canGoBack() == true -> tab.webView.goBack()
                else -> moveTaskToBack(true) // keep tabs (and music) alive instead of closing
            }
        }
    }

    override fun onPause() {
        super.onPause()
        browser.setBackground(true)
        // Started here, while still visible: Android 12+ refuses to start it once the app is in the background.
        if (browser.tabs.any { "youtube.com" in it.url }) {
            runCatching { startForegroundService(Intent(this, PlaybackService::class.java)) }
        }
    }

    override fun onResume() {
        super.onResume()
        browser.setBackground(false)
        stopService(Intent(this, PlaybackService::class.java))
    }

    override fun onDestroy() {
        stopService(Intent(this, PlaybackService::class.java))
        browser.destroy()
        super.onDestroy()
    }

    fun pickFiles(callback: ValueCallback<Array<Uri>>) {
        fileCallback?.onReceiveValue(null) // a page may only have one chooser open
        fileCallback = callback
        filePicker.launch("*/*")
    }

    /** Fullscreen video. */
    fun showFullscreen(view: View, callback: WebChromeClient.CustomViewCallback) {
        hideFullscreen()
        fullscreenView = view
        fullscreenCallback = callback
        (window.decorView as ViewGroup).addView(view, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
    }

    fun hideFullscreen() {
        fullscreenView?.let { (window.decorView as ViewGroup).removeView(it) }
        fullscreenCallback?.onCustomViewHidden()
        fullscreenView = null
        fullscreenCallback = null
    }

    fun share(url: String) {
        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, url)
        startActivity(Intent.createChooser(send, null))
    }
}
