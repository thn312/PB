package com.usbrowser.pb

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class LogicTest {
    @Test fun resolvesAddressBarInput() {
        assertEquals("https://x.com", Urls.resolve(" x.com "))
        assertEquals("http://a.b/c", Urls.resolve("http://a.b/c"))
        assertEquals("https://www.google.com/search?q=cat+videos", Urls.resolve("cat videos"))
        assertEquals("https://www.google.com/search?q=hello", Urls.resolve("hello"))
        assertNull(Urls.resolve("   "))
    }

    @Test fun onlyWebSchemesStayInBrowser() {
        assertTrue(Urls.isWeb("HTTPS"))
        assertFalse(Urls.isWeb("intent"))
        assertFalse(Urls.isWeb("tel"))
        assertFalse(Urls.isWeb(null))
    }

    @Test fun flags() = assertEquals("🇺🇸", Urls.flag("us"))

    @Test fun readsSharedBlocklist() {
        // The real list the iOS app ships.
        val rules = Blocklist.parse(File("../../Sources/blocklist.json").readText())
        assertTrue(rules.domains.size > 1000)
        assertTrue("doubleclick.net" in rules.domains)
        assertTrue(rules.hideSelector.contains(".adsbygoogle"))

        assertTrue(Blocklist.blocked("ad.doubleclick.net", rules.domains))
        assertTrue(Blocklist.blocked("DOUBLECLICK.NET", rules.domains))
        assertFalse(Blocklist.blocked("notdoubleclick.net", rules.domains))
        assertFalse(Blocklist.blocked("www.youtube.com", rules.domains))
        assertFalse(Blocklist.blocked(null, rules.domains))
    }
}
