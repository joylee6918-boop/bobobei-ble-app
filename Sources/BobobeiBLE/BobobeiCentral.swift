import Combine
import CoreBluetooth
import Foundation

public struct BobobeiDevice: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let rssi: Int?
}

public enum BobobeiPhase: Equatable, Sendable {
    case idle, scanning, connecting, discovering, ready, reconnecting
}

public enum BobobeiError: LocalizedError {
    case bluetoothUnavailable(String)
    case deviceNotFound
    case controlChannelUnavailable
    case disconnected
    case writeInProgress
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable(let reason): return reason
        case .deviceNotFound: return "The selected device is no longer available."
        case .controlChannelUnavailable: return "The EE03 write characteristic is unavailable."
        case .disconnected: return "The BLE device is not ready."
        case .writeInProgress: return "A previous GATT write is still in progress."
        case .writeFailed(let reason): return reason
        }
    }
}

/// Minimal native iOS/macOS central for SOSEXY/啵啵贝.
///
/// Call `scan()` from an explicit user action, show `devices`, then call
/// `connect(_:)` for the device chosen by the user. Keep this object alive for
/// as long as the app owns the connection.
@MainActor
public final class BobobeiCentral: NSObject, ObservableObject,
    @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {

    @Published public private(set) var phase: BobobeiPhase = .idle
    @Published public private(set) var devices: [BobobeiDevice] = []
    @Published public private(set) var levels: BobobeiProtocol.Levels = .stopped
    @Published public private(set) var status = "Not connected"

    public var isReady: Bool { phase == .ready && writeCharacteristic != nil }

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var selected: CBPeripheral?
    private var wantsConnection = false
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var reconnectTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var writeTimeout: Task<Void, Never>?

    private let serviceUUID = CBUUID(string: BobobeiProtocol.serviceUUID)
    private let writeUUID = CBUUID(string: BobobeiProtocol.writeUUID)
    private let notifyUUID = CBUUID(string: BobobeiProtocol.notifyUUID)

    private struct PendingWrite {
        let id: UUID
        let packets: [Data]
        var index: Int
        let continuation: CheckedContinuation<Void, Error>
    }
    private var pendingWrite: PendingWrite?

    public override init() {
        super.init()
    }

    public func scan() {
        guard selected == nil else { return }
        devices = []
        peripherals = [:]
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main,
                                       options: [CBCentralManagerOptionShowPowerAlertKey: false])
        } else if central?.state == .poweredOn {
            beginScan()
        }
    }

    public func stopScan() {
        central?.stopScan()
        if phase == .scanning { phase = .idle }
    }

    public func connect(_ id: UUID) {
        stopScan()
        guard let central, central.state == .poweredOn, let peripheral = peripherals[id] else {
            status = BobobeiError.deviceNotFound.localizedDescription
            return
        }
        selected = peripheral
        wantsConnection = true
        writeCharacteristic = nil
        notifyCharacteristic = nil
        phase = .connecting
        status = "Connecting…"
        central.connect(peripheral, options: nil)
    }

    public func disconnect() {
        wantsConnection = false
        reconnectTask?.cancel()
        keepAliveTask?.cancel()
        failPending(BobobeiError.disconnected)
        guard let selected else {
            phase = .idle
            status = "Disconnected"
            return
        }
        central?.cancelPeripheralConnection(selected)
    }

    public func setLevels(_ requested: BobobeiProtocol.Levels) async throws {
        keepAliveTask?.cancel()
        try await writeWithReconnect(BobobeiProtocol.packets(for: requested))
        levels = requested
        status = "Connected"
        startKeepAlive()
    }

    public func stop() async throws {
        keepAliveTask?.cancel()
        try await writeWithReconnect(BobobeiProtocol.stopPackets)
        levels = .stopped
        status = "Stopped"
        startKeepAlive()
    }

    private func beginScan() {
        phase = .scanning
        status = "Scanning for SOSEXY…"
        // Some units omit their service UUID from advertisements, so scan
        // broadly and filter by the advertised/local name.
        central?.scanForPeripherals(withServices: nil,
                                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func writeWithReconnect(_ packets: [Data]) async throws {
        while wantsConnection {
            if !isReady || pendingWrite != nil {
                try await Task.sleep(nanoseconds: 100_000_000)
                continue
            }
            do {
                try await write(packets)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard wantsConnection else { throw error }
                reconnect(reason: error.localizedDescription)
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        throw BobobeiError.disconnected
    }

    private func write(_ packets: [Data]) async throws {
        guard isReady, let peripheral = selected, peripheral.state == .connected,
              let characteristic = writeCharacteristic,
              characteristic.properties.contains(.write) else {
            throw BobobeiError.controlChannelUnavailable
        }
        guard pendingWrite == nil, !packets.isEmpty else { throw BobobeiError.writeInProgress }

        try await withCheckedThrowingContinuation { continuation in
            let id = UUID()
            pendingWrite = PendingWrite(id: id, packets: packets, index: 0,
                                        continuation: continuation)
            peripheral.writeValue(packets[0], for: characteristic, type: .withResponse)
            armWriteTimeout(id)
        }
    }

    private func armWriteTimeout(_ id: UUID) {
        writeTimeout?.cancel()
        writeTimeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            guard let self, self.pendingWrite?.id == id else { return }
            self.failPending(BobobeiError.writeFailed("GATT write timed out."))
            self.reconnect(reason: "GATT write timed out")
        }
    }

    private func advanceWrite(error: Error?) {
        guard var pending = pendingWrite else { return }
        if let error {
            failPending(BobobeiError.writeFailed(error.localizedDescription))
            reconnect(reason: error.localizedDescription)
            return
        }
        pending.index += 1
        guard pending.index < pending.packets.count else {
            writeTimeout?.cancel()
            pendingWrite = nil
            pending.continuation.resume()
            return
        }
        pendingWrite = pending
        guard let selected, let writeCharacteristic else {
            failPending(BobobeiError.controlChannelUnavailable)
            return
        }
        selected.writeValue(pending.packets[pending.index], for: writeCharacteristic,
                            type: .withResponse)
        armWriteTimeout(pending.id)
    }

    private func failPending(_ error: Error) {
        guard let pending = pendingWrite else { return }
        writeTimeout?.cancel()
        pendingWrite = nil
        pending.continuation.resume(throwing: error)
    }

    private func startKeepAlive() {
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 400_000_000) } catch { return }
                guard let self, self.wantsConnection else { return }
                if !self.isReady || self.pendingWrite != nil { continue }
                do {
                    try await self.write([BobobeiProtocol.keepAlivePacket(for: self.levels)])
                } catch {
                    guard self.wantsConnection else { return }
                    self.reconnect(reason: error.localizedDescription)
                }
            }
        }
    }

    private func reconnect(reason: String?) {
        guard wantsConnection, let selected else { return }
        keepAliveTask?.cancel()
        writeCharacteristic = nil
        notifyCharacteristic = nil
        phase = .reconnecting
        status = reason.map { "Reconnecting: \($0)" } ?? "Reconnecting…"
        if selected.state == .disconnected { scheduleReconnect(selected) }
        else { central?.cancelPeripheralConnection(selected) }
    }

    private func scheduleReconnect(_ peripheral: CBPeripheral) {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self, weak peripheral] in
            do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            guard let self, let peripheral, self.wantsConnection,
                  self.selected?.identifier == peripheral.identifier,
                  self.central?.state == .poweredOn else { return }
            self.central?.connect(peripheral, options: nil)
        }
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if phase == .idle || phase == .scanning { beginScan() }
            else if wantsConnection, let selected, selected.state == .disconnected {
                scheduleReconnect(selected)
            }
        case .unknown:
            break
        default:
            keepAliveTask?.cancel()
            failPending(BobobeiError.disconnected)
            let reason: String
            switch central.state {
            case .unauthorized: reason = "Bluetooth permission is denied."
            case .poweredOff: reason = "Bluetooth is off."
            case .unsupported: reason = "BLE is unsupported on this device."
            case .resetting: reason = "Bluetooth is resetting."
            default: reason = "Bluetooth is unavailable."
            }
            phase = .idle
            status = reason
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        guard let name, name.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased().hasPrefix("SOSEXY") else { return }
        peripherals[peripheral.identifier] = peripheral
        let device = BobobeiDevice(id: peripheral.identifier, name: name,
                                   rssi: RSSI.intValue == 127 ? nil : RSSI.intValue)
        if let index = devices.firstIndex(where: { $0.id == device.id }) { devices[index] = device }
        else { devices.append(device) }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard wantsConnection, selected?.identifier == peripheral.identifier else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        reconnectTask?.cancel()
        phase = .discovering
        status = "Discovering GATT service…"
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                               error: Error?) {
        connectionEnded(peripheral, error: error)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                               error: Error?) {
        connectionEnded(peripheral, error: error)
    }

    private func connectionEnded(_ peripheral: CBPeripheral, error: Error?) {
        guard selected?.identifier == peripheral.identifier else { return }
        writeCharacteristic = nil
        notifyCharacteristic = nil
        failPending(BobobeiError.writeFailed(error?.localizedDescription ?? "Disconnected"))
        if wantsConnection {
            phase = .reconnecting
            status = "Reconnecting…"
            scheduleReconnect(peripheral)
        } else {
            selected = nil
            phase = .idle
            status = "Disconnected"
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard selected?.identifier == peripheral.identifier else { return }
        if let error { reconnect(reason: error.localizedDescription); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            status = "SOSEXY service EE01 was not found."
            return
        }
        peripheral.discoverCharacteristics([writeUUID, notifyUUID], for: service)
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard selected?.identifier == peripheral.identifier else { return }
        if let error { reconnect(reason: error.localizedDescription); return }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == writeUUID { writeCharacteristic = characteristic }
            if characteristic.uuid == notifyUUID { notifyCharacteristic = characteristic }
        }
        guard let writeCharacteristic, writeCharacteristic.properties.contains(.write) else {
            status = BobobeiError.controlChannelUnavailable.localizedDescription
            return
        }
        if let notifyCharacteristic, notifyCharacteristic.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: notifyCharacteristic)
        }
        phase = .ready
        status = "Connected"
        startKeepAlive()
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        guard selected?.identifier == peripheral.identifier,
              characteristic.uuid == writeUUID else { return }
        advanceWrite(error: error)
    }
}
