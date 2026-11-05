import Foundation
import CoreBluetooth
import UserNotifications

// BLE central side of the link (docs/PROTOCOL.md): scans for the phone's GATT service,
// authenticates via encKey (first message must be a valid hello; nothing before it).
@MainActor
final class PhoneLink: NSObject, ObservableObject {
    static let shared = PhoneLink()

    enum Status: String {
        case off, unauthorized, searching, connecting, connected, authenticated

        // Short user-facing label (rawValue stays for diagnostics).
        var label: String {
            switch self {
            case .off: "Bluetooth off"
            case .unauthorized: "Bluetooth not allowed"
            case .searching: "Searching…"
            case .connecting, .connected: "Connecting…"
            case .authenticated: "Connected"
            }
        }
    }

    @Published private(set) var status: Status = .off
    // Diagnostics (Settings): messages that failed to open/decode vs. handled, since launch.
    @Published private(set) var droppedMessages = 0
    @Published private(set) var receivedMessages = 0

    private static let serviceUUID = CBUUID(string: "6f70690a-0001-4c6f-9e2b-6f7069636f6e")
    private static let txUUID = CBUUID(string: "6f70690a-0002-4c6f-9e2b-6f7069636f6e")
    private static let rxUUID = CBUUID(string: "6f70690a-0003-4c6f-9e2b-6f7069636f6e")

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rx: CBCharacteristic?
    // Peripherals that failed auth/discovery, skipped for a short while so a phone that
    // recovers (e.g. after a Bluetooth toggle) is retried instead of ignored all session.
    private var rejected: [CBPeripheralIdentifierBox: Date] = [:]
    private static let rejectFor: TimeInterval = 30
    private var appState = "active"
    private var running = false
    private var workItems: [DispatchWorkItem] = []

    private var lastInboundAt = Date.distantPast

    // True when no message has been received for `seconds` (used by background refresh).
    func inboundIdle(_ seconds: TimeInterval) -> Bool {
        Date().timeIntervalSince(lastInboundAt) >= seconds
    }

    private let reassembler = Reassembler()
    private var chunkQueue: [Data] = []       // chunks of the message being written
    private var messageQueue: [Data] = []     // sealed messages waiting / in flight
    private var writingQueueMessage = false   // current message came from PendingQueue

    override init() {
        super.init()
        // Demo mode never touches Bluetooth (avoids the permission alert).
        if !DemoMode.isActive {
            central = CBCentralManager(delegate: self, queue: .main)
        }
    }

    func start(state: String) {
        guard !DemoMode.isActive else {
            status = AppModel.shared.paired ? .authenticated : .searching
            running = true
            return
        }
        let previousState = appState
        appState = state
        running = true
        if status == .authenticated, previousState != state { send(.state(state)) }
        switch central.state {
        case .poweredOn:
            if let peripheral, peripheral.state != .connected, peripheral.state != .connecting {
                cleanupConnection()
                beginScan()
            } else if peripheral == nil {
                beginScan()
            }
        case .unauthorized: status = .unauthorized
        case .poweredOff: status = .off
        default: break
        }
        flush()
    }

    func disconnect() {
        guard !DemoMode.isActive else { return }
        running = false
        cancelTimers()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        cleanupConnection()
        status = central.state == .poweredOn ? .searching : .off
    }

    // If authenticated, send state{background}; then drop once inbound data has been quiet
    // for 2 s (so a calendar transfer in progress can finish), or after 30 s at the latest.
    // If not authenticated just drop the link.
    func goBackground() {
        guard !DemoMode.isActive else { return }
        appState = "background"
        guard status == .authenticated else {
            if PendingQueue.shared.count == 0 {
                disconnect()
            } else {
                dropWhenQuiet(deadline: Date().addingTimeInterval(30))
            }
            return
        }
        send(.state("background"))
        dropWhenQuiet(deadline: Date().addingTimeInterval(30))
    }

    private func dropWhenQuiet(deadline: Date) {
        after(2) { [weak self] in
            guard let self, self.appState == "background", self.running else { return }
            if (self.inboundIdle(2) && PendingQueue.shared.count == 0) || Date() >= deadline { self.disconnect() }
            else { self.dropWhenQuiet(deadline: deadline) }
        }
    }

    // MARK: outbound

    func send(_ message: BLEMessage) {
        guard let plaintext = try? message.encode(),
              let sealed = try? OpiCrypto.seal(plaintext, using: PairingKeys.shared.encKey) else { return }
        messageQueue.append(sealed)
        pumpWrites()
    }

    // Flush persisted queue (dismiss/action). Items are removed once their final
    // chunk write is acknowledged without error.
    func flush() {
        pumpWrites()
    }

    var canWrite: Bool {
        if DemoMode.isActive { return true }
        return status == .authenticated && rx != nil
    }

    // Live messages (hello, state, ack) go out as soon as the RX channel exists, since hello
    // is what earns the welcome; the persisted queue waits for authentication.
    private func pumpWrites() {
        guard rx != nil, chunkQueue.isEmpty else { return }
        // .withoutResponse returns ATT MTU - 3; .withResponse would return 512 and make
        // CoreBluetooth issue prepared writes, which our GATT server rejects.
        let maxLen = peripheral?.maximumWriteValueLength(for: .withoutResponse) ?? 182
        if let sealed = messageQueue.first {
            messageQueue.removeFirst()
            chunkQueue = Chunker.split(sealed, maxLen: max(2, maxLen))
            writingQueueMessage = false
        } else if canWrite, let plaintext = PendingQueue.shared.items.first,
                  let sealed = try? OpiCrypto.seal(plaintext, using: PairingKeys.shared.encKey) {
            chunkQueue = Chunker.split(sealed, maxLen: max(2, maxLen))
            writingQueueMessage = true
        } else {
            return
        }
        writeNextChunk()
    }

    private func writeNextChunk() {
        guard let chunk = chunkQueue.first, let rx, let peripheral else { return }
        peripheral.writeValue(chunk, for: rx, type: .withResponse)
    }

    // MARK: inbound

    private func handle(_ message: BLEMessage) {
        switch message {
        case .welcome:
            cancelTimers()
            status = .authenticated
            AppModel.shared.markPaired()
            if AppModel.shared.sendState == .sending, PendingQueue.shared.count == 0 {
                AppModel.shared.sendState = .sent
            }
            if appState == "background" { dropWhenQuiet(deadline: Date().addingTimeInterval(30)) }
            flush()
        case .notif(let payload):
            Task {
                await Categories.ensureRegistered(for: payload)
                let request = UNNotificationRequest(identifier: payload.i,
                                                    content: NotificationContent.make(for: payload),
                                                    trigger: nil)
                try? await UNUserNotificationCenter.current().add(request)
                AppModel.shared.insert(payload)
                self.send(.ack(id: payload.i))
            }
        case .remove(let id):
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
            AppModel.shared.remove(id: id)
        case .sync(let ids):
            Task { await Self.syncDelivered(ids: Set(ids)) }
            AppModel.shared.sync(ids: Set(ids))
        case .status(let bt, let bc):
            AppModel.shared.updateStatus(bt: bt, bc: bc)
        case .mediaState(let snapshot):
            AppModel.shared.media = snapshot
            AppModel.shared.store.saveMedia(snapshot)
        case .findphoneState(let on):
            AppModel.shared.ringing = on
        case .cal(let cache):
            AppModel.shared.calendar = cache
            AppModel.shared.store.saveCalendar(cache)
            Task { await CalendarReminders.reschedule(events: cache.events) }
        case .hello, .state, .ack, .dismiss, .action, .findphone, .media, .calSync:
            break
        }
    }

    private static func syncDelivered(ids: Set<String>) async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let stale = delivered
            .filter { $0.request.content.userInfo["opi"] != nil && !ids.contains($0.request.identifier) }
            .map { $0.request.identifier }
        if !stale.isEmpty { center.removeDeliveredNotifications(withIdentifiers: stale) }
    }

    // MARK: scan / connect

    private func beginScan() {
        status = .searching
        central.scanForPeripherals(withServices: [Self.serviceUUID],
                                 options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func cleanupConnection() {
        peripheral = nil
        rx = nil
        chunkQueue.removeAll()
        messageQueue.removeAll()
        writingQueueMessage = false
        reassembler.reset()
    }

    private func after(_ seconds: TimeInterval, _ block: @escaping () -> Void) {
        let item = DispatchWorkItem(block: block)
        workItems.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func cancelTimers() {
        workItems.forEach { $0.cancel() }
        workItems.removeAll()
    }

    private func dropPeripheral(reject: Bool) {
        guard let peripheral else { return }
        if reject { rejected[CBPeripheralIdentifierBox(peripheral.identifier)] = Date() }
        central.cancelPeripheralConnection(peripheral)
        cleanupConnection()
        if running { beginScan() }
    }
}

private struct CBPeripheralIdentifierBox: Hashable {
    let id: UUID
    init(_ id: UUID) { self.id = id }
}

extension PhoneLink: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard running else {
            status = central.state == .poweredOff ? .off : status
            return
        }
        switch central.state {
        case .poweredOn: if peripheral == nil { beginScan() }
        case .unauthorized: status = .unauthorized
        case .poweredOff: status = .off
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if let at = rejected[CBPeripheralIdentifierBox(peripheral.identifier)],
           Date().timeIntervalSince(at) < Self.rejectFor { return }
        guard self.peripheral == nil else { return }
        self.peripheral = peripheral
        status = .connecting
        central.stopScan()
        central.connect(peripheral, options: nil)
        after(10) { [weak self] in
            guard let self, self.status == .connecting else { return }
            self.dropPeripheral(reject: true)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = .connected
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        dropPeripheral(reject: true)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        cleanupConnection()
        guard running else { status = .searching; return }
        status = .searching
        if appState == "active" || PendingQueue.shared.count > 0 {
            after(2) { [weak self] in
                guard let self, self.running, self.peripheral == nil else { return }
                self.beginScan()
            }
        }
    }
}

extension PhoneLink: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            dropPeripheral(reject: true)
            return
        }
        peripheral.discoverCharacteristics([Self.txUUID, Self.rxUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let tx = service.characteristics?.first(where: { $0.uuid == Self.txUUID }),
              let rx = service.characteristics?.first(where: { $0.uuid == Self.rxUUID }) else {
            dropPeripheral(reject: true)
            return
        }
        self.rx = rx
        peripheral.setNotifyValue(true, for: tx)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.isNotifying else {
            if error != nil { dropPeripheral(reject: true) }
            return
        }
        // Channel is up: authenticate (echo cached calendar hash so the phone only
        // resends the calendar when it changed).
        send(.hello(state: appState, cal: AppModel.shared.calendar.flatMap { $0.events.isEmpty ? nil : $0.h }))
        after(5) { [weak self] in
            guard let self, self.status != .authenticated else { return }
            self.dropPeripheral(reject: true)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        // A failed write stalls the chunk queue; drop the link and let the rescan retry
        // (PendingQueue items persist and are retried on the next connect).
        guard error == nil else { dropPeripheral(reject: false); return }
        if !chunkQueue.isEmpty { chunkQueue.removeFirst() }
        if chunkQueue.isEmpty {
            if writingQueueMessage {
                PendingQueue.shared.removeFirst()
                writingQueueMessage = false
                if PendingQueue.shared.count == 0, AppModel.shared.sendState == .sending {
                    AppModel.shared.sendState = .sent
                }
                if appState == "background", PendingQueue.shared.count == 0, inboundIdle(2) {
                    disconnect(); return
                }
            }
            pumpWrites()
        } else {
            writeNextChunk()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        lastInboundAt = Date() // per chunk, so a long transfer counts as activity
        guard let sealed = reassembler.push(data) else { return }
        guard let plaintext = try? OpiCrypto.open(sealed, using: PairingKeys.shared.encKey),
              let message = BLEMessage.decode(plaintext) else {
            droppedMessages += 1
            reassembler.reset()
            return
        }
        receivedMessages += 1
        handle(message)
    }
}
