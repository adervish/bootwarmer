import CoreBluetooth
import Foundation



class BluetoothManager: NSObject, ObservableObject {
    private var centralManager: CBCentralManager!
    private var bootwarmerPeripheral: CBPeripheral?
    private var heaterCharacteristic: CBCharacteristic?
    private var temperatureCharacteristic: CBCharacteristic?
    
    @Published var isScanning = false
    @Published var isConnected = false
    // Right side
    @Published var measuredTemperatureR: Float = 0.0
    @Published var targetTemperatureR: Float = 70.0  // Default target temp of 70°F
    @Published var heaterPowerR: Float = 0.0
    @Published var pidErrorR: Float = 0.0
    @Published var pidIntegralR: Float = 0.0
    @Published var pidDerivativeR: Float = 0.0
    @Published var forcePowerLevelR: Int = 4  // 0 = Off, 1 = 0%, 2 = 25%, 3 = 50%, 4 = 100%, 5 = Trk Temp
    
    // Left side
    @Published var measuredTemperatureL: Float = 0.0
    @Published var targetTemperatureL: Float = 70.0  // Default target temp of 70°F
    @Published var heaterPowerL: Float = 0.0
    @Published var pidErrorL: Float = 0.0
    @Published var pidIntegralL: Float = 0.0
    @Published var pidDerivativeL: Float = 0.0
    @Published var forcePowerLevelL: Int = 5  // 0 = Off, 1 = 0%, 2 = 25%, 3 = 50%, 4 = 100%, 5 = Trk Temp
    
    // IMU Data
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
    
    private let serviceUUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
    private let heaterCharUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")
    private let tempCharUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a9")
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            connectionStatus = .error("Bluetooth is not powered on")
            return }
        isScanning = true
        centralManager.scanForPeripherals(withServices:  nil, options: nil)
    }
    
    func stopScanning() {
        isScanning = false
        centralManager.stopScan()
    }
    
    func setTargetTemperatures(right: Float, left: Float) {
        targetTemperatureR = right
        targetTemperatureL = left
        sendControlPacket()
    }
    
    func cycleForcePowerLevelRight() {
        forcePowerLevelR = (forcePowerLevelR + 1) % 6
        updateForcePowerLevel()
    }
    
    func cycleForcePowerLevelLeft() {
        forcePowerLevelL = (forcePowerLevelL + 1) % 6
        updateForcePowerLevel()
    }
    
    private func updateForcePowerLevel() {
        // Send updated control packet with force power levels
        sendControlPacket()
    }
    
    private func sendControlPacket() {
        guard let characteristic = heaterCharacteristic else { return }
        
        // Format packet: [targetTempR, targetTempL, forcePowerLevelR, forcePowerLevelL]
        let targetTempR = UInt8(max(0, min(100, targetTemperatureR)))
        let targetTempL = UInt8(max(0, min(100, targetTemperatureL)))
        let powerLevelR = UInt8(forcePowerLevelR)
        let powerLevelL = UInt8(forcePowerLevelL)
        
        let packet = Data([targetTempR, targetTempL, powerLevelR, powerLevelL])
        bootwarmerPeripheral?.writeValue(packet, for: characteristic, type: .withResponse)
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
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print(peripheral.name ?? "no name conversion")
        if peripheral.name == "BootHeater" {
            bootwarmerPeripheral = peripheral
            stopScanning()
            central.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        startScanning()
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first else { return }
        peripheral.discoverCharacteristics([heaterCharUUID, tempCharUUID], for: service)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.uuid == tempCharUUID {
                temperatureCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == heaterCharUUID {
                heaterCharacteristic = characteristic
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {

        //print("MemoryLayoutSize=", MemoryLayout<DebugData>.size );
        if characteristic.uuid == tempCharUUID,
           let data = characteristic.value,
           data.count >= 40 { // Minimum size for PID data (10 values * 4 bytes)
            var debugData = data.withUnsafeBytes { ptr -> DebugData in
                return DebugData(
                    temperatureR: ptr.load(as: Float.self),
                    errorR: ptr.load(fromByteOffset: 4, as: Float.self),
                    integralR: ptr.load(fromByteOffset: 8, as: Float.self),
                    derivativeR: ptr.load(fromByteOffset: 12, as: Float.self),
                    heaterPowerR: ptr.load(fromByteOffset: 16, as: UInt32.self),
                    temperatureL: ptr.load(fromByteOffset: 20, as: Float.self),
                    errorL: ptr.load(fromByteOffset: 24, as: Float.self),
                    integralL: ptr.load(fromByteOffset: 28, as: Float.self),
                    derivativeL: ptr.load(fromByteOffset: 32, as: Float.self),
                    heaterPowerL: ptr.load(fromByteOffset: 36, as: UInt32.self),
                    accelerationX: 0,
                    accelerationY: 0,
                    accelerationZ: 0,
                    gyroX: 0,
                    gyroY: 0,
                    gyroZ: 0,
                    temperature: 0
                )
            }
            
            // Load IMU data if available (additional 28 bytes: 7 float values * 4 bytes)
            if data.count >= 68 {
                debugData = data.withUnsafeBytes { ptr -> DebugData in
                    var updated = debugData
                    updated.accelerationX = ptr.load(fromByteOffset: 40, as: Float.self)
                    updated.accelerationY = ptr.load(fromByteOffset: 44, as: Float.self)
                    updated.accelerationZ = ptr.load(fromByteOffset: 48, as: Float.self)
                    updated.gyroX = ptr.load(fromByteOffset: 52, as: Float.self)
                    updated.gyroY = ptr.load(fromByteOffset: 56, as: Float.self)
                    updated.gyroZ = ptr.load(fromByteOffset: 60, as: Float.self)
                    updated.temperature = ptr.load(fromByteOffset: 64, as: Float.self)
                    return updated
                }
            }
            
            DispatchQueue.main.async {
                // Update PID data
                self.measuredTemperatureR = debugData.temperatureR
                self.heaterPowerR = Float(debugData.heaterPowerR)
                self.pidErrorR = debugData.errorR
                self.pidIntegralR = debugData.integralR
                self.pidDerivativeR = debugData.derivativeR
                
                self.measuredTemperatureL = debugData.temperatureL
                self.heaterPowerL = Float(debugData.heaterPowerL)
                self.pidErrorL = debugData.errorL
                self.pidIntegralL = debugData.integralL
                self.pidDerivativeL = debugData.derivativeL
                
                // Update IMU data (will be 0 if not available in packet)
                self.accelerationX = debugData.accelerationX
                self.accelerationY = debugData.accelerationY
                self.accelerationZ = debugData.accelerationZ
                self.gyroX = debugData.gyroX
                self.gyroY = debugData.gyroY
                self.gyroZ = debugData.gyroZ
                self.imuTemperature = debugData.temperature
            }
        }
    }
}
