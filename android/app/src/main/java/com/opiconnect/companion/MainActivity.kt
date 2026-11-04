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

            StepCard(
                title = "1. Permissions",
                done = permissionsGranted,
                doneText = "Bluetooth + notifications granted",
                actionText = "Grant permissions",
            ) {
                permissionLauncher.launch(BLE_PERMISSIONS)
            }

            StepCard(
                title = "2. Notification access",
                done = listenerEnabled,
                doneText = if (listenerBound) "OpiLink can read notifications"
                    else "Access granted, but the listener isn't running — reopen OpiLink",
                actionText = "Open settings",
            ) {
                context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
            }

            StepCard(
                title = "3. Battery exemption",
                done = batteryExempt,
                doneText = "Unrestricted background activity",
                actionText = "Allow background",
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
                        Text(if (showOppoTips) "OPPO / ColorOS tips ▲" else "OPPO / ColorOS tips ▼")
                    }
                    if (showOppoTips) {
                        Text(
                            "Settings > Battery > App battery management > OpiLink > " +
                                "allow background activity and auto launch. Also lock OpiLink " +
                                "in Recents so ColorOS doesn't kill it.",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
            }

            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("4. Pairing", fontWeight = FontWeight.Bold)
                        Spacer(modifier = Modifier.weight(1f))
                        Text(if (paired) "✓" else "…")
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                    if (paired) {
                        Text(
                            "Pair ID: ${PairingStore.keys(context)?.pairId?.take(8) ?: ""}…",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        OutlinedButton(onClick = { confirmUnpair = true }) {
                            Text("Unpair")
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
                                            snackbar.showSnackbar("Not an OpiLink QR code")
                                        }
                                    }
                                }
                        }) {
                            Text("Scan watch QR")
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
                    Text("5. Forwarding", fontWeight = FontWeight.Bold)
                    Spacer(modifier = Modifier.height(8.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Only when screen is off")
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
                        "Skip notifications while you're using the phone.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text("Apps")
                    listOf(
                        ForwardPrefs.Mode.ALL to "All apps",
                        ForwardPrefs.Mode.ALLOW to "Only selected apps",
                        ForwardPrefs.Mode.BLOCK to "All except selected apps",
                    ).forEach { (m, label) ->
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
                            Text(label)
                        }
                    }
                    if (mode != ForwardPrefs.Mode.ALL) {
                        Spacer(modifier = Modifier.height(8.dp))
                        OutlinedButton(onClick = { showPicker = true }) {
                            Text("Choose apps (${selectedApps.size} selected)")
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
                        Text("6. Calendar (optional)", fontWeight = FontWeight.Bold)
                        Spacer(modifier = Modifier.weight(1f))
                        Text(if (calendarGranted) "✓" else "")
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                    if (calendarGranted) {
                        Text(
                            "Watch shows the next 30 days and reminds you. " +
                                "Calendar app notifications aren't forwarded — the watch reminds you itself." +
                                if (calendarApps.isNotEmpty()) " Detected: ${calendarApps.joinToString()}" else "",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            calendarFound ?: "Calendar not read yet — open the watch app",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        calendarSent?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                        Spacer(modifier = Modifier.height(8.dp))
                        OutlinedButton(onClick = {
                            val link = LinkService.instance
                            if (link == null) AppState.setCalendarSent("Not sent: background service not running")
                            else Thread { link.resendCal() }.start()
                        }) {
                            Text("Sync calendar to watch now")
                        }
                    } else {
                        Text(
                            "Powers the watch calendar and on-wrist reminders.",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        OutlinedButton(onClick = {
                            calendarLauncher.launch(Manifest.permission.READ_CALENDAR)
                        }) {
                            Text("Grant calendar access")
                        }
                    }
                }
            }

            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("7. Status", fontWeight = FontWeight.Bold)
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        "Watch link: " + when (watchLink) {
                            AppState.WatchLink.NONE -> "not connected"
                            AppState.WatchLink.CONNECTED -> "connecting…"
                            AppState.WatchLink.ACTIVE -> "active"
                            AppState.WatchLink.BACKGROUND -> "background"
                        },
                    )
                    lastRelay?.let {
                        Text(
                            "Relay: ${it.text}",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    if (ringing) {
                        Spacer(modifier = Modifier.height(8.dp))
                        Button(onClick = { FindPhone.stop(context) }) {
                            Text("Stop ringing")
                        }
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                    OutlinedButton(
                        onClick = { Router.test() },
                        enabled = paired,
                    ) {
                        Text("Send test notification")
                    }
                }
            }

            HorizontalDivider()
            Text(
                "OpiLink ${BuildConfig.VERSION_NAME}",
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }

    if (confirmUnpair) {
        AlertDialog(
            onDismissRequest = { confirmUnpair = false },
            title = { Text("Unpair watch?") },
            text = { Text("Notifications will stop and a new QR pairing will be needed.") },
            confirmButton = {
                TextButton(onClick = {
                    confirmUnpair = false
                    LinkService.stop(context)
                    PairingStore.unpair(context)
                    paired = false
                }) { Text("Unpair") }
            },
            dismissButton = {
                TextButton(onClick = { confirmUnpair = false }) { Text("Cancel") }
            },
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
                    if (done) "✓ $doneText" else "Not set up",
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
        title = { Text("Choose apps") },
        text = {
            Column {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    placeholder = { Text("Search") },
                )
                if (loading) {
                    Text("Loading…", modifier = Modifier.padding(16.dp))
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
            TextButton(onClick = onDismiss) { Text("Done") }
        },
    )
}
