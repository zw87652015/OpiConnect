package com.opiconnect.companion

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Binder
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.opiconnect.companion.core.Chunker
import com.opiconnect.companion.core.Crypto
import com.opiconnect.companion.core.Messages
import com.opiconnect.companion.core.Reassembler
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue

// BLE GATT server + advertiser (docs/PROTOCOL.md). The phone is the peripheral; the
// watch connects. Authentication is implicit: only messages that decrypt with encKey
// are accepted, and nothing is sent before a valid hello.
@SuppressLint("MissingPermission") // permissions are checked in onStartCommand
class LinkService : Service() {

    companion object {
        private const val TAG = "OpiLink"
        private const val NOTIF_ID = 1
        private const val CHANNEL = "link"

        val SERVICE_UUID: UUID = UUID.fromString("6f70690a-0001-4c6f-9e2b-6f7069636f6e")
        val TX_UUID: UUID = UUID.fromString("6f70690a-0002-4c6f-9e2b-6f7069636f6e") // notify, phone -> watch
        val RX_UUID: UUID = UUID.fromString("6f70690a-0003-4c6f-9e2b-6f7069636f6e") // write, watch -> phone
        val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        @Volatile var instance: LinkService? = null
            private set

        fun start(context: Context) {
            try {
                ContextCompat.startForegroundService(context, Intent(context, LinkService::class.java))
            } catch (e: Exception) {
                // ForegroundServiceStartNotAllowedException (background start) or
                // IllegalStateException — the listener must never crash here.
                Log.w(TAG, "couldn't start service: $e")
                AppState.setError("Couldn't start background service — open OpiConnect")
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LinkService::class.java))
        }
    }

    // Per-device connection state. Outbound messages are queued whole so chunks of
    // different messages can't interleave on the wire.
    class Conn(val device: BluetoothDevice) {
        var mtu = 23
        var cccdEnabled = false
        var authenticated = false
        var watchState = ""
        var lastCalHash: String? = null   // hash from hello.cal, then last sent
        val reassembler = Reassembler()
        val messages = ConcurrentLinkedQueue<List<ByteArray>>() // one entry per message (its chunks)
        @Volatile var chunkIndex = 0
        @Volatile var retries = 0
        @Volatile var sending = false
    }

    private val handler = Handler(Looper.getMainLooper())
    private var gattServer: BluetoothGattServer? = null
    private var tx: BluetoothGattCharacteristic? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var advertising = false
    private val conns = ConcurrentHashMap<String, Conn>()

    private val adapter: BluetoothAdapter? get() =
        (getSystemService(BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    override fun onBind(intent: Intent?) = Binder()

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel()
        registerReceiver(adapterReceiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED))
        PhoneStatus.register(this)
        MediaBridge.start(this)
        CalendarSync.start(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!hasBlePermissions()) {
            AppState.setError("Bluetooth permissions not granted")
            stopSelf()
            return START_NOT_STICKY
        }
        startForeground()
        openServerAndAdvertise()
        return START_STICKY
    }

    override fun onDestroy() {
        instance = null
        handler.removeCallbacksAndMessages(null)
        runCatching { unregisterReceiver(adapterReceiver) }
        PhoneStatus.unregister(this)
        MediaBridge.stop(this)
        CalendarSync.stop(this)
        stopAdvertising()
        gattServer?.close()
        gattServer = null
        conns.clear()
        AppState.setWatchLink(AppState.WatchLink.NONE)
        super.onDestroy()
    }

    private fun hasBlePermissions(): Boolean {
        val needed = arrayOf(
            android.Manifest.permission.BLUETOOTH_ADVERTISE,
            android.Manifest.permission.BLUETOOTH_CONNECT,
        )
        return needed.all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    // MARK: foreground notification

    private fun createChannel() {
        val channel = NotificationChannel(CHANNEL, getString(R.string.link_channel_name),
            NotificationManager.IMPORTANCE_LOW)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun startForeground() {
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentTitle("OpiConnect is running")
            .setContentText(linkStatusText())
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
        ServiceCompat.startForeground(
            this, NOTIF_ID, notification,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
        )
    }

    private fun updateNotification() {
        val notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentTitle("OpiConnect is running")
            .setContentText(linkStatusText())
            .setOngoing(true)
            .build()
        getSystemService(NotificationManager::class.java).notify(NOTIF_ID, notification)
    }

    private fun linkStatusText(): String = when {
        conns.values.any { it.authenticated && it.watchState == "active" } -> "Watch connected"
        conns.values.any { it.authenticated } -> "Watch connected in background"
        conns.isNotEmpty() -> "Watch connecting…"
        else -> "Waiting for watch"
    }

    private fun updateAppState() {
        AppState.setWatchLink(
            when {
                conns.values.any { it.authenticated && it.watchState == "active" } -> AppState.WatchLink.ACTIVE
                conns.values.any { it.authenticated } -> AppState.WatchLink.BACKGROUND
                conns.isNotEmpty() -> AppState.WatchLink.CONNECTED
                else -> AppState.WatchLink.NONE
            },
        )
        updateNotification()
    }

    // MARK: GATT server

    private fun openServerAndAdvertise() {
        if (adapter?.isEnabled != true) return
        if (gattServer == null) {
            val manager = getSystemService(BLUETOOTH_SERVICE) as BluetoothManager
            gattServer = manager.openGattServer(this, serverCallback)
            val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
            tx = BluetoothGattCharacteristic(
                TX_UUID,
                // Indications: each chunk is confirmed by the watch before the next one goes
                // out. Unacknowledged notifications got dropped on large (calendar) messages.
                BluetoothGattCharacteristic.PROPERTY_INDICATE,
                0,
            ).apply {
                addDescriptor(
                    BluetoothGattDescriptor(
                        CCCD_UUID,
                        BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
                    ),
                )
            }
            val rx = BluetoothGattCharacteristic(
                RX_UUID,
                BluetoothGattCharacteristic.PROPERTY_WRITE,
                BluetoothGattCharacteristic.PERMISSION_WRITE,
            )
            service.addCharacteristic(tx)
            service.addCharacteristic(rx)
            gattServer?.addService(service) // advertise starts in onServiceAdded
        } else {
            startAdvertising()
        }
    }

    private val serverCallback = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService) {
            if (status == BluetoothGatt.GATT_SUCCESS) startAdvertising()
            else Log.w(TAG, "addService failed: $status")
        }

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState == BluetoothGatt.STATE_CONNECTED) {
                conns[device.address] = Conn(device)
            } else {
                conns.remove(device.address)
            }
            updateAppState()
        }

        override fun onMtuChanged(device: BluetoothDevice, mtu: Int) {
            conns[device.address]?.mtu = mtu
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?,
        ) {
            if (descriptor.uuid != CCCD_UUID) {
                if (responseNeeded) gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, 0, null)
                return
            }
            val enable = value?.contentEquals(BluetoothGattDescriptor.ENABLE_INDICATION_VALUE) == true ||
                value?.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) == true
            val conn = conns[device.address]
            if (conn != null && value != null) {
                conn.cccdEnabled = enable
                descriptor.value = value
            }
            if (responseNeeded) {
                gattServer?.sendResponse(
                    device, requestId,
                    if (conn != null && value != null) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_FAILURE,
                    0, null,
                )
            }
            updateAppState()
        }

        override fun onDescriptorReadRequest(
            device: BluetoothDevice, requestId: Int, offset: Int, descriptor: BluetoothGattDescriptor,
        ) {
            val value = if (conns[device.address]?.cccdEnabled == true)
                BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
            else
                BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
            gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, value)
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?,
        ) {
            if (characteristic.uuid != RX_UUID || preparedWrite || value == null) {
                if (responseNeeded) gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, 0, null)
                return
            }
            if (responseNeeded) gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            val conn = conns[device.address] ?: return
            val sealed = conn.reassembler.push(value) ?: return
            val keys = PairingStore.keys(this@LinkService) ?: return
            val plaintext = runCatching { Crypto.open(sealed, keys.encKey) }.getOrNull() ?: return
            handle(conn, Messages.parse(plaintext))
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            val conn = conns[device.address] ?: return
            if (status == BluetoothGatt.GATT_SUCCESS) {
                synchronized(conn) {
                    conn.chunkIndex++
                    conn.retries = 0
                    conn.sending = false
                }
                pump(conn)
            } else {
                conn.sending = false
                onChunkFailed(conn)
            }
        }
    }

    // MARK: inbound messages

    private fun handle(conn: Conn, msg: Messages.In?) {
        if (!conn.authenticated) {
            // First valid message must be hello; nothing is sent before it.
            if (msg is Messages.Hello) {
                conn.authenticated = true
                conn.watchState = msg.state
                conn.lastCalHash = msg.cal
                send(conn, Messages.Welcome)
                send(conn, Messages.Sync(Router.activeIds()))
                // Per PROTOCOL: status, media_state, cal (if hash differs),
                // findphone_state (if ringing) — in this order.
                val snap = PhoneStatus.current()
                if (snap.bt >= 0) send(conn, Messages.Status(snap.bt, snap.bc))
                val ms = MediaBridge.state.value
                send(conn, Messages.MediaState(ms.on, ms.app, ms.title, ms.artist, ms.playing, ms.volume))
                sendCalTo(conn)
                if (FindPhone.ringing.value) send(conn, Messages.FindPhoneState(true))
                updateAppState()
            }
            return
        }
        when (msg) {
            is Messages.State -> { conn.watchState = msg.state; updateAppState() }
            is Messages.Ack -> Router.onAck(msg.id)
            is Messages.Dismiss -> ActionExecutor.dismiss(msg.id)
            is Messages.Action -> ActionExecutor.run(msg.id, msg.idx, msg.label, msg.text)
            is Messages.FindPhone -> FindPhone.set(this@LinkService, msg.on)
            is Messages.MediaCmd -> MediaBridge.command(msg.cmd, msg.v)
            else -> {}
        }
    }

    // MARK: outbound

    // Queue a message to one connection. Returns false if the connection can't take it.
    fun send(conn: Conn, msg: Messages.Out): Boolean {
        if (!conn.authenticated || !conn.cccdEnabled) return false
        val keys = PairingStore.keys(this) ?: return false
        tx ?: return false
        val sealed = runCatching { Crypto.seal(Messages.encode(msg), keys.encKey) }.getOrNull() ?: return false
        synchronized(conn) {
            conn.messages.add(Chunker.split(sealed, maxOf(2, conn.mtu - 3)))
        }
        pump(conn)
        return true
    }

    // Broadcast a message to every authenticated connection; true if at least one took it.
    fun sendAll(msg: Messages.Out): Boolean =
        conns.values.map { send(it, msg) }.any { it }

    fun anyAuthenticated(): Boolean = conns.values.any { it.authenticated }

    // Sends cal to every authenticated connection whose last-known hash differs.
    fun sendCal(msg: com.opiconnect.companion.core.CalMessage) {
        conns.values.forEach { conn ->
            if (conn.authenticated && conn.lastCalHash != msg.h) queueCal(conn, msg)
        }
    }

    private fun sendCalTo(conn: Conn) {
        if (!CalendarSync.hasPermission(this)) {
            AppState.setCalendarSent("Not sent: calendar permission not granted")
            return
        }
        // Rebuild on every hello: the 30-day window moves even when no event changes.
        val msg = CalendarSync.build(this) ?: return
        if (conn.lastCalHash != msg.h) queueCal(conn, msg)
        else AppState.setCalendarSent("Watch already up to date (${timeNow()})")
    }

    private fun queueCal(conn: Conn, msg: com.opiconnect.companion.core.CalMessage) {
        val ok = send(conn, Messages.Cal(msg))
        if (ok) conn.lastCalHash = msg.h
        val kb = (msg.evJson.length + 1023) / 1024
        AppState.setCalendarSent(
            if (ok) "Sent to watch: ~$kb KB (${timeNow()})"
            else "Send failed: watch not subscribed (${timeNow()})",
        )
    }

    private fun timeNow(): String =
        java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date())

    // First connection with an active watch (per Router's delivery rule).
    fun activeWatch(): Conn? =
        conns.values.firstOrNull { it.authenticated && it.cccdEnabled && it.watchState == "active" }

    // GATT callbacks and send() can arrive on different threads; serialize per connection
    // so a chunk can't be notified twice. Each chunk gets up to 3 attempts 50 ms apart;
    // on persistent failure only that message is dropped, the rest of the queue continues.
    private fun pump(conn: Conn): Unit = synchronized(conn) {
        val server = gattServer ?: return
        val tx = tx ?: return
        if (conn.sending) return
        val chunks = conn.messages.peek() ?: return
        if (conn.chunkIndex >= chunks.size) {
            conn.messages.poll()
            conn.chunkIndex = 0
            conn.retries = 0
            return pump(conn)
        }
        conn.sending = true
        notifyChunk(conn, server, tx, chunks[conn.chunkIndex])
    }

    // Must be called under synchronized(conn).
    private fun notifyChunk(
        conn: Conn, server: BluetoothGattServer,
        tx: BluetoothGattCharacteristic, chunk: ByteArray,
    ) {
        val status = server.notifyCharacteristicChanged(conn.device, tx, true, chunk)
        if (status != BluetoothStatusCodes.SUCCESS) {
            onChunkFailed(conn)
        }
    }

    // Retry the current chunk up to 3 times (50 ms apart), then drop the message.
    // Always leaves conn.sending in a consistent state. Safe to call from any thread.
    private fun onChunkFailed(conn: Conn) {
        conn.retries++
        if (conn.retries >= 3) {
            synchronized(conn) {
                conn.messages.poll()
                conn.chunkIndex = 0
                conn.retries = 0
                conn.sending = false
            }
            pump(conn)
            return
        }
        handler.postDelayed({
            synchronized(conn) {
                val server = gattServer
                val tx = tx
                val chunks = conn.messages.peek()
                if (server == null || tx == null || chunks == null || conn.chunkIndex >= chunks.size) {
                    conn.sending = false
                    conn.chunkIndex = 0
                    conn.retries = 0
                    return@synchronized
                }
                notifyChunk(conn, server, tx, chunks[conn.chunkIndex])
            }
        }, 50)
    }

    // MARK: advertising

    private fun startAdvertising() {
        if (advertising || adapter?.isEnabled != true) return
        val adv = adapter?.bluetoothLeAdvertiser ?: return
        advertiser = adv
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(true)
            .setTimeout(0)
            .build()
        val data = AdvertiseData.Builder()
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .setIncludeDeviceName(false)
            .build()
        adv.startAdvertising(settings, data, advertiseCallback)
    }

    private fun stopAdvertising() {
        advertising = false
        runCatching { advertiser?.stopAdvertising(advertiseCallback) }
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
            advertising = true
        }

        override fun onStartFailure(errorCode: Int) {
            advertising = false
            Log.w(TAG, "advertising failed: $errorCode, retrying in 10 s")
            handler.postDelayed({ startAdvertising() }, 10_000)
        }
    }

    // MARK: adapter state

    private val adapterReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)) {
                BluetoothAdapter.STATE_ON -> openServerAndAdvertise()
                // The stack tears down the GATT server with the adapter; drop our handle so
                // STATE_ON builds a fresh server instead of advertising a dead one.
                BluetoothAdapter.STATE_TURNING_OFF, BluetoothAdapter.STATE_OFF -> {
                    stopAdvertising()
                    runCatching { gattServer?.close() }
                    gattServer = null
                    tx = null
                    conns.clear()
                    updateAppState()
                }
            }
        }
    }
}
