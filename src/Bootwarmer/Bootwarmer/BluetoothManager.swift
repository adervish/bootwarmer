import CoreBluetooth
import Foundation

/// Talks to the per-boot controllers (one ESP32-C6 board per boot).
///
/// Each boot is its own BLE peripheral advertising the Bootwarmer service. The
/// manager connects to every one it finds and files each under left or right
/// using the `side` byte in its status packet, so the rest of the app keeps
/// using the same left/right properties as before.
class BluetoothManager: NSObject, ObservableObject {
    private var centralManager: CBCentralManager!

    /// One connected (or connecting) boot controller.
    private final class Boot {
        let peripheral: CBPeripheral
        var controlCharacteristic: CBCharacteristic?
        var side: Side?
        var hasReported = false
        init(peripheral: CBPeripheral) { self.peripheral = peripheral }
    }

    enum Side: UInt8 {
        case left = 0
        case right = 1
    }

    private var boots: [UUID: Boot] = [:]

    @Published var isScanning = false
    @Published var isConnected = false
    @Published var isLeftConnected = false
    @Published var isRightConnected = false

    // Right side
    @Published var measuredTemperatureR: Float = 0.0
    @Published var targetTemperatureR: Float = 70.0  // Default target temp of 70°F
    @Published var heaterPowerR: Float = 0.0
    @Published var pidErrorR: Float = 0.0
    @Published var pidIntegralR: Float = 0.0
    @Published var pidDerivativeR: Float = 0.0
    @Published var forcePowerLevelR: Int = 5  // 0 = Off, 1 = 0%, 2 = 25%, 3 = 50%, 4 = 100%, 5 = Trk Temp
    @Published var batteryVoltsR: Float = 0.0
    @Published var batteryPercentR: Float = 0.0
    @Published var faultsR: UInt8 = 0

    // Left side
    @Published var measuredTemperatureL: Float = 0.0
    @Published var targetTemperatureL: Float = 70.0  // Default target temp of 70°F
    @Published var heaterPowerL: Float = 0.0
    @Published var pidErrorL: Float = 0.0
    @Published var pidIntegralL: Float = 0.0
    @Published var pidDerivativeL: Float = 0.0
    @Published var forcePowerLevelL: Int = 5  // 0 = Off, 1 = 0%, 2 = 25%, 3 = 50%, 4 = 100%, 5 = Trk Temp
    @Published var batteryVoltsL: Float = 0.0
    @Published var batteryPercentL: Float = 0.0
    @Published var faultsL: UInt8 = 0

    // IMU data (from whichever boot reported most recently)
    @Published var accelerationX: Float = 0.0
    @Published var accelerationY: Float = 0.0
    @Published var accelerationZ: Float = 0.0
    @Published var gyroX: Float = 0.0
    @Published var gyroY: Float = 0.0
    @Published var gyroZ: Float = 0.0
    @Published var imuTemperature: Float = 0.0

    @Published var connectionStatus: ConnectionStatus = .disconnected

    enum ConnectionStatus {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    /// Bits of the `faults` byte in the status packet.
    struct Fault {
        static let sensorOpen: UInt8 = 1 << 0
        static let sensorShort: UInt8 = 1 << 1
        static let overTemp: UInt8 = 1 << 2
        static let lowBattery: UInt8 = 1 << 3
        static let charging: UInt8 = 1 << 4
    }

    private let serviceUUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
    private let controlCharUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")
    private let statusCharUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a9")

    /// Status packet v2 is 64 bytes, little-endian, packed (see src/esp32c6/bootwarmer/bootwarmer.ino).
    private let statusPacketSize = 64

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            connectionStatus = .error("Bluetooth is not powered on")
            return
        }
        isScanning = true
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    func stopScanning() {
        isScanning = false
        centralManager.stopScan()
    }

    func setTargetTemperatures(right: Float, left: Float) {
        targetTemperatureR = right
        targetTemperatureL = left
        sendControlPackets()
    }

    func cycleForcePowerLevelRight() {
        forcePowerLevelR = (forcePowerLevelR + 1) % 6
        sendControlPackets()
    }

    func cycleForcePowerLevelLeft() {
        forcePowerLevelL = (forcePowerLevelL + 1) % 6
        sendControlPackets()
    }

    /// Tell a connected boot which side it is. It keeps the setting and
    /// advertises under the new name after its next power cycle.
    func assign(side: Side, toBootCurrentlyOn current: Side) {
        guard let boot = boots.values.first(where: { $0.side == current }),
              let characteristic = boot.controlCharacteristic else { return }
        let packet = controlPacket(for: current) + Data([side.rawValue])
        boot.peripheral.writeValue(packet, for: characteristic, type: .withResponse)
    }

    /// Control packet v2: [target °F, mode].
    private func controlPacket(for side: Side) -> Data {
        let target = side == .left ? targetTemperatureL : targetTemperatureR
        let mode = side == .left ? forcePowerLevelL : forcePowerLevelR
        return Data([UInt8(max(0, min(110, target))), UInt8(mode)])
    }

    private func sendControlPackets() {
        for boot in boots.values {
            guard let side = boot.side, let characteristic = boot.controlCharacteristic else { continue }
            boot.peripheral.writeValue(controlPacket(for: side), for: characteristic, type: .withResponse)
        }
    }

    private func updateConnectionState() {
        let connected = boots.values.filter { $0.peripheral.state == .connected }
        isLeftConnected = connected.contains { $0.side == .left }
        isRightConnected = connected.contains { $0.side == .right }
        isConnected = !connected.isEmpty
        if isConnected {
            connectionStatus = .connected
        } else if boots.isEmpty {
            connectionStatus = .disconnected
        } else {
            connectionStatus = .connecting
        }
        // Keep looking until both boots are found.
        if connected.count < 2 && centralManager.state == .poweredOn && !centralManager.isScanning {
            startScanning()
        } else if connected.count >= 2 && centralManager.isScanning {
            stopScanning()
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on")
        case .poweredOff:
            connectionStatus = .error("Bluetooth is powered off")
        case .unsupported:
            connectionStatus = .error("Bluetooth is not supported")
        case .unauthorized:
            connectionStatus = .error("Bluetooth permission denied")
        case .resetting:
            connectionStatus = .error("Bluetooth is resetting")
        case .unknown:
            connectionStatus = .error("Bluetooth state unknown")
        @unknown default:
            connectionStatus = .error("Unknown Bluetooth state")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard boots[peripheral.identifier] == nil else { return }
        let boot = Boot(peripheral: peripheral)
        // The advertised name is only a first guess; the status packet is authoritative.
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        if name.hasSuffix("-L") { boot.side = .left }
        if name.hasSuffix("-R") { boot.side = .right }
        boots[peripheral.identifier] = boot
        peripheral.delegate = self
        connectionStatus = .connecting
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([serviceUUID])
        updateConnectionState()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        boots[peripheral.identifier] = nil
        updateConnectionState()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        boots[peripheral.identifier] = nil
        updateConnectionState()
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else { return }
        peripheral.discoverCharacteristics([controlCharUUID, statusCharUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics, let boot = boots[peripheral.identifier] else { return }
        for characteristic in characteristics {
            if characteristic.uuid == statusCharUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == controlCharUUID {
                boot.controlCharacteristic = characteristic
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == statusCharUUID,
              let data = characteristic.value,
              data.count >= statusPacketSize,
              let boot = boots[peripheral.identifier] else { return }

        func byte(_ offset: Int) -> UInt8 { data[data.startIndex + offset] }
        func float(_ offset: Int) -> Float {
            data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Float.self) }
        }
        func uint32(_ offset: Int) -> UInt32 {
            data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        }

        guard byte(0) == 2, let side = Side(rawValue: byte(1)) else { return }
        let firstReport = !boot.hasReported || boot.side != side
        boot.hasReported = true
        boot.side = side

        let mode = Int(byte(2))
        let faults = byte(3)
        let temperature = float(4)
        let setpoint = float(8)
        let error = float(12)
        let integral = float(16)
        let derivative = float(20)
        let power = Float(uint32(24))
        let volts = float(28)
        let percent = float(32)

        DispatchQueue.main.async {
            switch side {
            case .left:
                self.measuredTemperatureL = temperature
                self.heaterPowerL = power
                self.pidErrorL = error
                self.pidIntegralL = integral
                self.pidDerivativeL = derivative
                self.batteryVoltsL = volts
                self.batteryPercentL = percent
                self.faultsL = faults
                if firstReport {
                    // Adopt what the boot is already doing rather than overwriting it.
                    self.targetTemperatureL = setpoint
                    self.forcePowerLevelL = mode
                }
            case .right:
                self.measuredTemperatureR = temperature
                self.heaterPowerR = power
                self.pidErrorR = error
                self.pidIntegralR = integral
                self.pidDerivativeR = derivative
                self.batteryVoltsR = volts
                self.batteryPercentR = percent
                self.faultsR = faults
                if firstReport {
                    self.targetTemperatureR = setpoint
                    self.forcePowerLevelR = mode
                }
            }
            self.accelerationX = float(36)
            self.accelerationY = float(40)
            self.accelerationZ = float(44)
            self.gyroX = float(48)
            self.gyroY = float(52)
            self.gyroZ = float(56)
            self.imuTemperature = float(60)
            if firstReport { self.updateConnectionState() }
        }
    }
}
