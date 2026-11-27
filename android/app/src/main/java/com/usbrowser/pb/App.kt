package com.usbrowser.pb

import android.app.Application
import android.os.LocaleList
import java.util.Locale

class App : Application() {
    override fun onCreate() {
        super.onCreate()
        // WebView takes Accept-Language from the default locales when it starts: en-US, like the iOS build.
        Locale.setDefault(Locale.US)
        LocaleList.setDefault(LocaleList(Locale.US))
    }
}
