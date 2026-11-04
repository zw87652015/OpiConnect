package com.opiconnect.companion

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.opiconnect.companion.core.Crypto
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    SetupScreen()
                }
            }
        }
    }
}

private val BLE_PERMISSIONS = arrayOf(
    Manifest.permission.BLUETOOTH_ADVERTISE,
    Manifest.permission.BLUETOOTH_CONNECT,
    Manifest.permission.POST_NOTIFICATIONS,
)

@Composable
fun SetupScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }

    var permissionsGranted by remember { mutableStateOf(false) }
    var listenerEnabled by remember { mutableStateOf(false) }
    var listenerBound by remember { mutableStateOf(false) }
    var batteryExempt by remember { mutableStateOf(false) }
    var calendarGranted by remember { mutableStateOf(false) }
    var calendarApps by remember { mutableStateOf(emptyList<String>()) }
    var ringing by remember { mutableStateOf(false) }
    var paired by remember { mutableStateOf(PairingStore.isPaired(context)) }
    var showOppoTips by remember { mutableStateOf(false) }
    var confirmUnpair by remember { mutableStateOf(false) }
    var cards by remember { mutableStateOf(CardStore.all(context)) }
    var editingCard by remember { mutableStateOf<OpiCard?>(null) }
    var showCardEditor by remember { mutableStateOf(false) }
    var language by remember { mutableStateOf(AppLanguage.current(context)) }
    var showLanguagePicker by remember { mutableStateOf(false) }

    val watchLink by AppState.watchLink.collectAsState()
    val lastRelay by AppState.lastRelay.collectAsState()
    val lastError by AppState.lastError.collectAsState()
    val calendarFound by AppState.calendarFound.collectAsState()
    val calendarSent by AppState.calendarSent.collectAsState()

    fun refresh() {
        permissionsGranted = BLE_PERMISSIONS.all {
            ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
        }
        listenerEnabled = NotificationManagerCompat
            .getEnabledListenerPackages(context).contains(context.packageName)
        if (listenerEnabled) OpiListenerService.ensureBound(context)
        listenerBound = OpiListenerService.instance != null
        batteryExempt = context.getSystemService(PowerManager::class.java)
            ?.isIgnoringBatteryOptimizations(context.packageName) == true
        paired = PairingStore.isPaired(context)
        calendarGranted = CalendarSync.hasPermission(context)
        calendarApps = if (calendarGranted) CalendarApps.labels(context) else emptyList()
        // Permission may have been granted after the service started: register the change
        // observer now and push the calendar to a connected watch.
        if (calendarGranted) {
            CalendarSync.start(context)
            CalendarSync.schedule()
        }
        ringing = FindPhone.ringing.value
        cards = CardStore.all(context)
        // Recover the link service if it wasn't allowed to start in the background.
        if (paired && permissionsGranted) LinkService.start(context)
    }

    // Re-check everything whenever the app comes back to the foreground.
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) refresh()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        refresh()
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    LaunchedEffect(lastError) {
        lastError?.let { snackbar.showSnackbar(it) }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { refresh() }

    val calendarLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) {
        refresh()
        if (it) CalendarSync.sendUpdates()
    }

    // Opening the app while the phone rings stops it.
    LaunchedEffect(Unit) {
        if (FindPhone.ringing.value) FindPhone.stop(context)
        FindPhone.ringing.collect { ringing = it }
    }

    Scaffold(snackbarHost = { SnackbarHost(snackbar) }) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("OpiLink", style = MaterialTheme.typography.headlineMedium)

            TextButton(onClick = { showLanguagePicker = true }) {
                Text(
                    stringResource(R.string.language) + ": " +
                        AppLanguage.options.firstOrNull { it.tag == language }
                            ?.let { stringResource(it.nameRes) } ?: language,
                )
            }

            StepCard(
                title = stringResource(R.string.step_permissions),
                done = permissionsGranted,
                doneText = stringResource(R.string.permissions_done),
                actionText = stringResource(R.string.grant_permissions),
            ) {
                permissionLauncher.launch(BLE_PERMISSIONS)
            }

            StepCard(
                title = stringResource(R.string.step_notif_access),
                done = listenerEnabled,
                doneText = stringResource(
                    if (listenerBound) R.string.notif_access_ok
                    else R.string.notif_access_not_running,
                ),
                actionText = stringResource(R.string.open_settings),
            ) {
                context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
            }

            StepCard(
                title = stringResource(R.string.step_battery),
                done = batteryExempt,
                doneText = stringResource(R.string.battery_done),
                actionText = stringResource(R.string.allow_background),
            ) {
                context.startActivity(
                    Intent(
                        Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                        Uri.parse("package:${context.packageName}"),
                    ),
                )
            }
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    TextButton(onClick = { showOppoTips = !showOppoTips }) {
                        Text(
                            stringResource(R.string.oppo_tips) +
                                if (showOppoTips) " ▲" else " ▼",
                        )
                    }
                    if (showOppoTips) {
                        Text(
                            stringResource(R.string.oppo_tips_body),
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
            }

            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.step_pairing), fontWeight = FontWeight.Bold)
                        Spacer(modifier = Modifier.weight(1f))
                        Text(if (paired) "✓" else "…")
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                    if (paired) {
                        Text(
                            stringResource(
                                R.string.pair_id,
                                PairingStore.keys(context)?.pairId?.take(8) ?: "",
                            ),
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        OutlinedButton(onClick = { confirmUnpair = true }) {
                            Text(stringResource(R.string.unpair))
                        }
                    } else {
                        Button(onClick = {
                            val options = GmsBarcodeScannerOptions.Builder()
                                .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                                .build()
                            GmsBarcodeScanning.getClient(context, options)
                                .startScan()
                                .addOnSuccessListener { barcode ->
                                    val k = Crypto.parseQr(barcode.rawValue)
                                    if (k != null && PairingStore.pair(context, k)) {
                                        paired = true
                                        LinkService.start(context)
                                    } else {
                                        scope.launch {
                                            snackbar.showSnackbar(
                                                context.getString(R.string.not_opi_qr),
                                            )
                                        }
                                    }
                                }
                        }) {
                            Text(stringResource(R.string.scan_watch_qr))
                        }
                    }
                }
            }

            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    var screenOffOnly by remember {
                        mutableStateOf(ForwardPrefs.screenOffOnly(context))
                    }
                    var mode by remember { mutableStateOf(ForwardPrefs.mode(context)) }
                    var selectedApps by remember { mutableStateOf(ForwardPrefs.apps(context)) }
                    var showPicker by remember { mutableStateOf(false) }
                    Text(stringResource(R.string.step_forwarding), fontWeight = FontWeight.Bold)
                    Spacer(modifier = Modifier.height(8.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.screen_off_only))
                        Spacer(modifier = Modifier.weight(1f))
                        Switch(
                            checked = screenOffOnly,
                            onCheckedChange = {
                                screenOffOnly = it
                                ForwardPrefs.setScreenOffOnly(context, it)
                            },
                        )
                    }
                    Text(
                        stringResource(R.string.screen_off_desc),
                        style = MaterialTheme.typography.bodySmall,
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(stringResource(R.string.apps))
                    listOf(
                        ForwardPrefs.Mode.ALL to R.string.fwd_all,
                        ForwardPrefs.Mode.ALLOW to R.string.fwd_allow,
                        ForwardPrefs.Mode.BLOCK to R.string.fwd_block,
                    ).forEach { (m, labelRes) ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .selectable(
                                    selected = mode == m,
                                    onClick = {
                                        mode = m
                                        ForwardPrefs.setMode(context, m)
                                    },
                                    role = Role.RadioButton,
                                ),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(selected = mode == m, onClick = null)
                            Text(stringResource(labelRes))
                        }
                    }
                    if (mode != ForwardPrefs.Mode.ALL) {
                        Spacer(modifier = Modifier.height(8.dp))
                        OutlinedButton(onClick = { showPicker = true }) {
                            Text(
                                stringResource(R.string.choose_apps_selected, selectedApps.size),
                            )
                        }
                    }
                    if (showPicker) {
                        AppPickerDialog(onDismiss = {
                            showPicker = false
                            selectedApps = ForwardPrefs.apps(context)
                        })
                    }
                }
            }

            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.step_calendar), fontWeight = FontWeight.Bold)
                        Spacer(modifier = Modifier.weight(1f))
                        Text(if (calendarGranted) "✓" else "")
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                    if (calendarGranted) {
                        Text(
                            stringResource(R.string.calendar_desc) +
                                if (calendarApps.isNotEmpty()) {
                                    " " + stringResource(
                                        R.string.calendar_detected,
                                        calendarApps.joinToString(),
                                    )
                                } else "",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            calendarFound ?: stringResource(R.string.calendar_not_read),
                            style = MaterialTheme.typography.bodySmall,
                        )
                        calendarSent?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                        Spacer(modifier = Modifier.height(8.dp))
                        OutlinedButton(onClick = {
                            val link = LinkService.instance
                            if (link == null) AppState.setCalendarSent(
                                context.getString(R.string.cal_not_sent_service),
                            )
                            else Thread { link.resendCal() }.start()
                        }) {
                            Text(stringResource(R.string.calendar_sync_now))
                        }
                    } else {
                        Text(
                            stringResource(R.string.calendar_denied_desc),
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        OutlinedButton(onClick = {
                            calendarLauncher.launch(Manifest.permission.READ_CALENDAR)
                        }) {
                            Text(stringResource(R.string.grant_calendar))
                        }
                    }
                }
            }

            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(stringResource(R.string.step_cards), fontWeight = FontWeight.Bold)
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        stringResource(R.string.cards_desc),
                        style = MaterialTheme.typography.bodySmall,
                    )
                    cards.forEach { card ->
                        Spacer(modifier = Modifier.height(8.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(modifier = Modifier.weight(1f)) {
                                if (card.label.isNotEmpty()) {
                                    Text(card.label, style = MaterialTheme.typography.bodySmall)
                                }
                                Text(card.code, fontWeight = FontWeight.Bold)
                                if (card.onWatch) {
                                    Text(
                                        stringResource(R.string.on_watch),
                                        style = MaterialTheme.typography.bodySmall,
                                    )
                                }
                            }
                            TextButton(
                                onClick = {
                                    Router.sendCard(context, card)
                                    cards = CardStore.all(context)
                                },
                                enabled = paired,
                            ) { Text(stringResource(R.string.send)) }
                            TextButton(onClick = {
                                editingCard = card
                                showCardEditor = true
                            }) { Text(stringResource(R.string.edit)) }
                            TextButton(onClick = {
                                if (card.onWatch) Router.removeCard(context, card.id)
                                CardStore.delete(context, card.id)
                                cards = CardStore.all(context)
                            }) { Text(stringResource(R.string.delete)) }
                        }
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                    OutlinedButton(onClick = {
                        editingCard = null
                        showCardEditor = true
                    }) {
                        Text(stringResource(R.string.new_card))
                    }
                }
            }

            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(stringResource(R.string.step_status), fontWeight = FontWeight.Bold)
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        stringResource(
                            R.string.watch_link,
                            when (watchLink) {
                                AppState.WatchLink.NONE -> stringResource(R.string.watch_link_none)
                                AppState.WatchLink.CONNECTED ->
                                    stringResource(R.string.watch_link_connecting)
                                AppState.WatchLink.ACTIVE -> stringResource(R.string.watch_link_active)
                                AppState.WatchLink.BACKGROUND ->
                                    stringResource(R.string.watch_link_background)
                            },
                        ),
                    )
                    lastRelay?.let {
                        Text(
                            stringResource(R.string.relay_line, it.text),
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    if (ringing) {
                        Spacer(modifier = Modifier.height(8.dp))
                        Button(onClick = { FindPhone.stop(context) }) {
                            Text(stringResource(R.string.stop_ringing))
                        }
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                    OutlinedButton(
                        onClick = { Router.test() },
                        enabled = paired,
                    ) {
                        Text(stringResource(R.string.send_test))
                    }
                }
            }

            HorizontalDivider()
            Text(
                stringResource(R.string.app_version, BuildConfig.VERSION_NAME),
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }

    if (confirmUnpair) {
        AlertDialog(
            onDismissRequest = { confirmUnpair = false },
            title = { Text(stringResource(R.string.unpair_title)) },
            text = { Text(stringResource(R.string.unpair_body)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmUnpair = false
                    LinkService.stop(context)
                    PairingStore.unpair(context)
                    paired = false
                }) { Text(stringResource(R.string.unpair)) }
            },
            dismissButton = {
                TextButton(onClick = { confirmUnpair = false }) {
                    Text(stringResource(R.string.cancel))
                }
            },
        )
    }

    if (showLanguagePicker) {
        AlertDialog(
            onDismissRequest = { showLanguagePicker = false },
            title = { Text(stringResource(R.string.language)) },
            text = {
                Column {
                    AppLanguage.options.forEach { option ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .selectable(
                                    selected = language == option.tag,
                                    onClick = {
                                        language = option.tag
                                        AppLanguage.set(context, option.tag)
                                    },
                                    role = Role.RadioButton,
                                ),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(selected = language == option.tag, onClick = null)
                            Text(stringResource(option.nameRes))
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showLanguagePicker = false }) {
                    Text(stringResource(R.string.done))
                }
            },
        )
    }

    if (showCardEditor) {
        CardEditorDialog(
            card = editingCard,
            onSave = { label, code, note ->
                val card = OpiCard(
                    id = editingCard?.id ?: OpiCard.newId(),
                    label = label,
                    code = code,
                    note = note,
                    onWatch = editingCard?.onWatch == true,
                )
                CardStore.upsert(context, card)
                if (card.onWatch) Router.sendCard(context, card)
                cards = CardStore.all(context)
                showCardEditor = false
            },
            onDismiss = { showCardEditor = false },
        )
    }
}

@Composable
private fun StepCard(
    title: String,
    done: Boolean,
    doneText: String,
    actionText: String,
    onAction: () -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(title, fontWeight = FontWeight.Bold)
                Text(
                    if (done) "✓ $doneText" else stringResource(R.string.step_not_done),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            if (!done) {
                Button(onClick = onAction) { Text(actionText) }
            }
        }
    }
}

@Composable
private fun AppPickerDialog(onDismiss: () -> Unit) {
    val context = LocalContext.current
    var loading by remember { mutableStateOf(true) }
    var entries by remember { mutableStateOf(emptyList<Pair<String, String>>()) }
    var query by remember { mutableStateOf("") }
    val initial = remember { ForwardPrefs.apps(context) }
    var selected by remember { mutableStateOf(initial) }

    LaunchedEffect(Unit) {
        entries = withContext(Dispatchers.IO) {
            val pm = context.packageManager
            val launchable = pm.queryIntentActivities(
                Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER),
                PackageManager.ResolveInfoFlags.of(0),
            ).map { it.loadLabel(pm).toString() to it.activityInfo.packageName }
            val extra = ForwardPrefs.apps(context).map { pkg ->
                runCatching {
                    pm.getApplicationLabel(
                        pm.getApplicationInfo(pkg, PackageManager.ApplicationInfoFlags.of(0)),
                    ).toString()
                }.getOrDefault(pkg) to pkg
            }
            (launchable + extra)
                .distinctBy { it.second }
                .filter { it.second != context.packageName }
        }
        loading = false
    }

    val filtered = entries
        .filter {
            query.isEmpty() ||
                it.first.contains(query, ignoreCase = true) ||
                it.second.contains(query, ignoreCase = true)
        }
        .sortedWith(
            compareByDescending<Pair<String, String>> { it.second in initial }
                .thenBy { it.first.lowercase() },
        )

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.choose_apps)) },
        text = {
            Column {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    placeholder = { Text(stringResource(R.string.search)) },
                )
                if (loading) {
                    Text(
                        stringResource(R.string.loading),
                        modifier = Modifier.padding(16.dp),
                    )
                } else {
                    LazyColumn(modifier = Modifier.height(400.dp)) {
                        items(filtered, key = { it.second }) { (label, pkg) ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        selected = if (pkg in selected) {
                                            selected - pkg
                                        } else {
                                            selected + pkg
                                        }
                                        ForwardPrefs.setApps(context, selected)
                                    },
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Checkbox(checked = pkg in selected, onCheckedChange = null)
                                Column {
                                    Text(label, style = MaterialTheme.typography.bodyLarge)
                                    Text(pkg, style = MaterialTheme.typography.bodySmall)
                                }
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.done)) }
        },
    )
}

@Composable
private fun CardEditorDialog(
    card: OpiCard?,
    onSave: (label: String, code: String, note: String) -> Unit,
    onDismiss: () -> Unit,
) {
    var label by remember { mutableStateOf(card?.label ?: "") }
    var code by remember { mutableStateOf(card?.code ?: "") }
    var note by remember { mutableStateOf(card?.note ?: "") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                stringResource(if (card == null) R.string.new_card else R.string.edit_card),
            )
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = label,
                    onValueChange = { label = it },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    label = { Text(stringResource(R.string.card_label)) },
                    placeholder = { Text(stringResource(R.string.card_label_placeholder)) },
                )
                OutlinedTextField(
                    value = code,
                    onValueChange = { code = it },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    label = { Text(stringResource(R.string.card_code)) },
                )
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.card_note)) },
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onSave(label.trim(), code.trim(), note.trim()) },
                enabled = code.isNotBlank(),
            ) { Text(stringResource(R.string.save)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
        },
    )
}
