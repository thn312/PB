package com.usbrowser.pb

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.view.ViewGroup
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.NetworkCheck
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.DateFormat
import java.util.Date

private val Orange = Color(0xFFF26A1B)

@Composable
fun PBTheme(content: @Composable () -> Unit) {
    val scheme = if (isSystemInDarkTheme()) darkColorScheme(primary = Orange) else lightColorScheme(primary = Orange)
    MaterialTheme(colorScheme = scheme, content = content)
}

private enum class Sheet { Proxies, Tabs, History }

@Composable
fun BrowserApp(b: Browser) {
    var sheet by remember { mutableStateOf<Sheet?>(null) }
    Surface(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().safeDrawingPadding()) {
            val tab = b.current
            if (tab == null) ConnectScreen(b) { sheet = Sheet.Proxies }
            else key(tab.id) { BrowserScreen(b, tab) { sheet = it } } // key: fresh address-bar state per tab
        }
    }
    val close = { sheet = null }
    when (sheet) {
        Sheet.Proxies -> FullDialog(close) { ProxiesScreen(b, close) }
        Sheet.Tabs -> FullDialog(close) { TabsScreen(b, close) }
        Sheet.History -> FullDialog(close) { HistoryScreen(b, close) }
        null -> {}
    }
}

@Composable
private fun FullDialog(onDismiss: () -> Unit, content: @Composable () -> Unit) {
    Dialog(onDismiss, DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize().safeDrawingPadding()) { content() }
    }
}

@Composable
private fun ConnectScreen(b: Browser, openProxies: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Filled.Public, null, tint = Orange, modifier = Modifier.size(72.dp))
        Text("PB", fontSize = 34.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 12.dp))
        Text(b.status, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(vertical = 12.dp))
        if (b.connecting) CircularProgressIndicator()
        else {
            Button(onClick = { b.scope.launch { b.connect() } }) { Text("Reconnect") }
            TextButton(onClick = openProxies) { Text("Proxies") }
        }
    }
}

@Composable
private fun BrowserScreen(b: Browser, tab: Tab, open: (Sheet) -> Unit) {
    val focus = LocalFocusManager.current
    var editing by remember { mutableStateOf(false) }
    var field by remember { mutableStateOf(TextFieldValue(host(tab.url))) }
    var suggestions by remember { mutableStateOf(listOf<String>()) }
    val typing = editing && field.text.isNotEmpty() && field.text != tab.url

    LaunchedEffect(tab.url, editing) { if (!editing) field = TextFieldValue(host(tab.url)) }
    LaunchedEffect(editing) {
        // Like Chrome: focusing the bar shows the full URL, selected, so typing replaces it.
        if (editing) field = TextFieldValue(tab.url, TextRange(0, tab.url.length))
    }
    LaunchedEffect(field.text, typing) {
        if (!typing) { suggestions = emptyList(); return@LaunchedEffect }
        delay(200) // wait until the user pauses typing
        val c = b.client ?: return@LaunchedEffect
        suggestions = withContext(Dispatchers.IO) { Net.suggest(c, field.text) }
    }
    fun submit(input: String) { tab.go(input); focus.clearFocus() }

    Column(Modifier.fillMaxSize()) {
        // Address bar
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { b.setAdblock(!b.adblock) }) {
                Icon(Icons.Filled.Shield, if (b.adblock) "Ad blocking on" else "Ad blocking off",
                    tint = if (b.adblock) Orange else MaterialTheme.colorScheme.outline)
            }
            Row(Modifier.weight(1f).height(44.dp).background(MaterialTheme.colorScheme.surfaceVariant, CircleShape)
                .padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                if (!editing) {
                    Icon(if (tab.url.startsWith("https")) Icons.Filled.Lock else Icons.Filled.Public, null,
                        Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.width(6.dp))
                }
                BasicTextField(
                    value = field, onValueChange = { field = it }, singleLine = true,
                    textStyle = LocalTextStyle.current.copy(color = MaterialTheme.colorScheme.onSurface, fontSize = 16.sp),
                    cursorBrush = SolidColor(Orange),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Go, autoCorrectEnabled = false),
                    keyboardActions = KeyboardActions(onGo = { submit(field.text) }),
                    modifier = Modifier.weight(1f).onFocusChanged { editing = it.isFocused },
                    decorationBox = { inner ->
                        if (field.text.isEmpty()) Text("Search or enter address", color = MaterialTheme.colorScheme.onSurfaceVariant)
                        inner()
                    },
                )
                if (editing && field.text.isNotEmpty()) {
                    Icon(Icons.Filled.Cancel, "Clear", Modifier.size(20.dp).clickable { field = TextFieldValue("") },
                        tint = MaterialTheme.colorScheme.onSurfaceVariant)
                } else if (!editing) {
                    Icon(if (tab.loading) Icons.Filled.Close else Icons.Filled.Refresh, if (tab.loading) "Stop" else "Reload",
                        Modifier.size(20.dp).clickable { if (tab.loading) tab.webView.stopLoading() else tab.webView.reload() })
                }
            }
            if (editing) TextButton(onClick = { focus.clearFocus() }) { Text("Cancel") }
        }
        Text(b.status, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1,
            overflow = TextOverflow.Ellipsis, modifier = Modifier.align(Alignment.CenterHorizontally).padding(bottom = 4.dp))
        if (tab.loading) LinearProgressIndicator(progress = { tab.progress / 100f }, Modifier.fillMaxWidth().height(2.dp), color = Orange)
        else Spacer(Modifier.height(2.dp))

        Box(Modifier.weight(1f)) {
            AndroidView(factory = { tab.webView.apply { (parent as? ViewGroup)?.removeView(this) } }, modifier = Modifier.fillMaxSize())
            if (tab.error.isNotEmpty()) {
                Text(tab.error, color = Color.White, fontSize = 12.sp,
                    modifier = Modifier.fillMaxWidth().background(Color(0xE6D32F2F)).clickable { tab.error = "" }.padding(10.dp))
            }
            if (typing) {
                LazyColumn(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface)) {
                    val visited = b.history.matches(field.text)
                    if (visited.isNotEmpty()) item { SectionHeader("History") }
                    items(visited, key = { "h" + it.id }) { e ->
                        SuggestionRow(Icons.Filled.History, e.title.ifEmpty { e.url }, e.url) { submit(e.url) }
                    }
                    item { SectionHeader("Search") }
                    item { SuggestionRow(Icons.Filled.Search, field.text) { submit(field.text) } }
                    items(suggestions.filter { it != field.text }.distinct(), key = { "s$it" }) { s ->
                        SuggestionRow(Icons.Filled.Search, s) { submit(s) }
                    }
                }
            }
        }

        if (!editing) BottomBar(b, tab, open)
    }

    tab.longPressUrl?.let { link -> LinkMenu(b, tab, link) }
}

private fun host(url: String) = Uri.parse(url).host ?: url

@Composable
private fun SectionHeader(text: String) =
    Text(text, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = 16.dp, top = 12.dp, bottom = 4.dp))

@Composable
private fun SuggestionRow(icon: ImageVector, title: String, detail: String? = null, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(14.dp))
        Column {
            Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (detail != null) Text(detail, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun BottomBar(b: Browser, tab: Tab, open: (Sheet) -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainer).padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = { tab.webView.goBack() }, enabled = tab.canGoBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
        IconButton(onClick = { tab.webView.goForward() }, enabled = tab.canGoForward) { Icon(Icons.AutoMirrored.Filled.ArrowForward, "Forward") }
        IconButton(onClick = { b.activity.share(tab.url) }, enabled = tab.url.isNotEmpty()) { Icon(Icons.Filled.Share, "Share") }
        IconButton(onClick = { open(Sheet.Tabs) }) {
            Box(Modifier.size(24.dp).border(1.8.dp, MaterialTheme.colorScheme.onSurface, RoundedCornerShape(6.dp)),
                contentAlignment = Alignment.Center) {
                Text("${b.tabs.size}", fontSize = 12.sp, fontWeight = FontWeight.Bold)
            }
        }
        Box {
            IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, "Menu") }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text("New Tab") }, leadingIcon = { Icon(Icons.Filled.Add, null) },
                    onClick = { menu = false; b.newTab() })
                DropdownMenuItem(text = { Text("History") }, leadingIcon = { Icon(Icons.Filled.History, null) },
                    onClick = { menu = false; open(Sheet.History) })
                DropdownMenuItem(text = { Text("Check My IP") }, leadingIcon = { Icon(Icons.Filled.NetworkCheck, null) },
                    onClick = { menu = false; tab.go("https://browserleaks.com/ip") })
                HorizontalDivider()
                DropdownMenuItem(text = { Text("Block Ads & Trackers") }, leadingIcon = { Icon(Icons.Filled.Shield, null) },
                    trailingIcon = { Checkbox(b.adblock, null) }, onClick = { b.setAdblock(!b.adblock) })
                DropdownMenuItem(text = { Text("Allow Opening Apps") }, leadingIcon = { Icon(Icons.AutoMirrored.Filled.OpenInNew, null) },
                    trailingIcon = { Checkbox(b.allowApps, null) }, onClick = { b.setAllowApps(!b.allowApps) })
                HorizontalDivider()
                if (b.proxies.isNotEmpty()) {
                    b.proxies.forEach { p ->
                        val on = !b.direct && p.id == b.activeProxy?.id
                        DropdownMenuItem(text = { Text(p.label) }, leadingIcon = { Icon(Icons.Filled.SwapHoriz, null) },
                            trailingIcon = { if (on) Icon(Icons.Filled.CheckCircle, "In use", tint = Orange) },
                            onClick = { menu = false; b.use(p) })
                    }
                    DropdownMenuItem(text = { Text("No Proxy (real IP)") }, leadingIcon = { Icon(Icons.Filled.SwapHoriz, null) },
                        trailingIcon = { if (b.direct) Icon(Icons.Filled.CheckCircle, "In use", tint = Orange) },
                        onClick = { menu = false; b.useDirect() })
                }
                DropdownMenuItem(text = { Text("Proxies") }, leadingIcon = { Icon(Icons.Filled.Settings, null) },
                    onClick = { menu = false; open(Sheet.Proxies) })
            }
        }
    }
}

@Composable
private fun LinkMenu(b: Browser, tab: Tab, link: String) {
    val ctx = b.activity
    val dismiss = { tab.longPressUrl = null }
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text(link, maxLines = 3, overflow = TextOverflow.Ellipsis, fontSize = 14.sp) },
        text = {
            Column {
                SuggestionRow(Icons.Filled.Add, "Open in New Tab") { dismiss(); b.newTab(link) }
                SuggestionRow(Icons.Filled.ContentCopy, "Copy Link") {
                    dismiss()
                    (ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("link", link))
                }
                if (b.allowApps) SuggestionRow(Icons.AutoMirrored.Filled.OpenInNew, "Open in App") { dismiss(); tab.openExternally(link) }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = dismiss) { Text("Cancel") } },
    )
}

@Composable
private fun TopBar(title: String, left: @Composable () -> Unit = {}, right: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.width(96.dp)) { left() }
        Text(title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, modifier = Modifier.weight(1f),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        Box(Modifier.width(96.dp), contentAlignment = Alignment.CenterEnd) { right() }
    }
    HorizontalDivider()
}

@Composable
private fun TabsScreen(b: Browser, close: () -> Unit) {
    Column {
        TopBar("${b.tabs.size} Tabs",
            left = { IconButton(onClick = { b.newTab(); close() }) { Icon(Icons.Filled.Add, "New tab") } },
            right = { TextButton(onClick = close) { Text("Done") } })
        LazyColumn {
            items(b.tabs, key = { it.id }) { t ->
                val selected = t == b.current
                Row(Modifier.fillMaxWidth().clickable { b.current = t; close() }.padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Icon(if (selected) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null,
                        tint = if (selected) Orange else MaterialTheme.colorScheme.outline)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(t.title.ifEmpty { "New Tab" }, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(host(t.url), fontSize = 12.sp, maxLines = 1, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    IconButton(onClick = { b.close(t) }) { Icon(Icons.Filled.Close, "Close tab") }
                }
            }
        }
    }
}

@Composable
private fun HistoryScreen(b: Browser, close: () -> Unit) {
    var query by remember { mutableStateOf("") }
    var confirmClear by remember { mutableStateOf(false) }
    val q = query.lowercase()
    val list = b.history.entries.filter { q.isEmpty() || q in it.url.lowercase() || q in it.title.lowercase() }
    val days = list.groupBy { DateFormat.getDateInstance(DateFormat.FULL).format(Date(it.date)) }

    Column {
        TopBar("History",
            left = { TextButton(onClick = { confirmClear = true }, enabled = b.history.entries.isNotEmpty()) { Text("Clear") } },
            right = { TextButton(onClick = close) { Text("Done") } })
        OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth().padding(12.dp), singleLine = true,
            placeholder = { Text("Search history") }, leadingIcon = { Icon(Icons.Filled.Search, null) })
        LazyColumn {
            if (b.history.entries.isEmpty()) item { Text("No history yet.", Modifier.padding(16.dp), color = MaterialTheme.colorScheme.onSurfaceVariant) }
            days.forEach { (day, entries) ->
                item(key = "d$day") { SectionHeader(day) }
                items(entries, key = { it.id }) { e ->
                    Row(Modifier.fillMaxWidth().clickable { b.current?.go(e.url); close() }.padding(start = 16.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f).padding(vertical = 8.dp)) {
                            Text(e.title.ifEmpty { e.url }, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(e.url, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        IconButton(onClick = { b.history.delete(e) }) { Icon(Icons.Filled.Delete, "Delete") }
                    }
                }
            }
        }
    }
    if (confirmClear) {
        AlertDialog(onDismissRequest = { confirmClear = false }, title = { Text("Clear all history?") },
            confirmButton = { TextButton(onClick = { b.history.clear(); confirmClear = false }) { Text("Clear History") } },
            dismissButton = { TextButton(onClick = { confirmClear = false }) { Text("Cancel") } })
    }
}

@Composable
private fun ProxiesScreen(b: Browser, close: () -> Unit) {
    var editing by remember { mutableStateOf<ProxyEntry?>(null) }
    Column {
        TopBar("Proxies",
            left = { TextButton(onClick = close) { Text("Done") } },
            right = { IconButton(onClick = { editing = ProxyEntry() }) { Icon(Icons.Filled.Add, "Add proxy") } })
        LazyColumn {
            item {
                ProxyRow("No Proxy", "Real IP and location · ad blocking still on", b.direct,
                    onUse = { b.useDirect(); close() }, onEdit = null, onDelete = null)
                HorizontalDivider()
            }
            items(b.proxies, key = { it.id }) { p ->
                ProxyRow(p.label, "HTTP · ${p.host}:${p.port}", !b.direct && p.id == b.activeProxy?.id,
                    onUse = { b.use(p); close() }, onEdit = { editing = p }, onDelete = { b.deleteProxy(p) })
            }
            if (b.proxies.isEmpty()) item { Text("Tap + to add a proxy.", Modifier.padding(16.dp), color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
    editing?.let { p ->
        ProxyEditor(p, isNew = b.proxies.none { it.id == p.id }, onDismiss = { editing = null }) { b.saveProxy(it); editing = null }
    }
}

@Composable
private fun ProxyRow(title: String, detail: String, active: Boolean, onUse: () -> Unit,
                     onEdit: (() -> Unit)?, onDelete: (() -> Unit)?) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onUse).padding(start = 16.dp, end = 4.dp, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Icon(if (active) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null,
            tint = if (active) Orange else MaterialTheme.colorScheme.outline)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title)
            Text(detail, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (onEdit != null) IconButton(onClick = onEdit) { Icon(Icons.Filled.Edit, "Edit $title") }
        if (onDelete != null) IconButton(onClick = onDelete) { Icon(Icons.Filled.Delete, "Delete $title") }
    }
}

@Composable
private fun ProxyEditor(start: ProxyEntry, isNew: Boolean, onDismiss: () -> Unit, onSave: (ProxyEntry) -> Unit) {
    var p by remember { mutableStateOf(start) }
    var port by remember { mutableStateOf(start.port.toString()) }
    val candidate = p.copy(host = p.host.trim(), port = port.toIntOrNull() ?: 0)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (isNew) "New Proxy" else "Edit Proxy") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(p.name, { p = p.copy(name = it) }, label = { Text("Name (e.g. Dallas residential)") }, singleLine = true)
                OutlinedTextField(p.host, { p = p.copy(host = it) }, label = { Text("Host") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, autoCorrectEnabled = false))
                OutlinedTextField(port, { port = it.filter(Char::isDigit).take(5) }, label = { Text("Port") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                OutlinedTextField(p.user, { p = p.copy(user = it) }, label = { Text("Username (optional)") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(autoCorrectEnabled = false))
                OutlinedTextField(p.pass, { p = p.copy(pass = it) }, label = { Text("Password (optional)") }, singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
                Text("HTTP proxies only. Location and timezone come from the proxy IP automatically.",
                    fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        confirmButton = { TextButton(onClick = { onSave(candidate) }, enabled = candidate.valid) { Text("Save") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
