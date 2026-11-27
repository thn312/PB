package com.usbrowser.pb

import org.json.JSONArray
import java.net.URLEncoder

/** Pure helpers (no Android APIs) so they run in plain unit tests. */
object Urls {
    const val HOME = "https://www.google.com"

    /** Address bar input -> URL: full URLs as-is, "x.com" gets https://, anything else is a Google search. */
    fun resolve(input: String): String? {
        val t = input.trim()
        if (t.isEmpty()) return null
        return when {
            "://" in t -> t
            '.' in t && ' ' !in t -> "https://$t"
            else -> "https://www.google.com/search?q=" + URLEncoder.encode(t, "UTF-8")
        }
    }

    /** Only these stay in the browser; anything else (tel:, intent:, twitter://…) would open another app. */
    fun isWeb(scheme: String?) = scheme?.lowercase() in setOf("http", "https", "about", "data", "blob", "javascript")

    /** "US" -> 🇺🇸 */
    fun flag(country: String) = country.uppercase().filter { it in 'A'..'Z' }
        .map { String(Character.toChars(0x1F1E6 + (it - 'A'))) }.joinToString("")
}

/** Reads the iOS content-blocker list (Sources/blocklist.json) so both apps block the same domains. */
object Blocklist {
    private const val PREFIX = "^[^:]+://+([^:/]+\\.)?"
    private const val SUFFIX = "[:/]"

    class Rules(val domains: Set<String>, val hideSelector: String)

    fun parse(json: String): Rules {
        val arr = JSONArray(json)
        val domains = HashSet<String>()
        var hide = ""
        for (i in 0 until arr.length()) {
            val rule = arr.getJSONObject(i)
            val action = rule.getJSONObject("action")
            when (action.getString("type")) {
                "block" -> {
                    val f = rule.getJSONObject("trigger").getString("url-filter")
                    if (f.startsWith(PREFIX) && f.endsWith(SUFFIX)) {
                        domains += f.removePrefix(PREFIX).removeSuffix(SUFFIX).replace("\\.", ".")
                    }
                }
                "css-display-none" -> hide = action.getString("selector")
            }
        }
        return Rules(domains, hide)
    }

    /** True if host is a listed domain or a subdomain of one. */
    fun blocked(host: String?, domains: Set<String>): Boolean {
        var h = host?.lowercase() ?: return false
        while (true) {
            if (h in domains) return true
            val dot = h.indexOf('.')
            if (dot < 0) return false
            h = h.substring(dot + 1)
        }
    }
}
