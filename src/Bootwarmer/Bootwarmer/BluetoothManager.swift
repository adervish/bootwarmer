import CoreBluetooth

class BluetoothManager: NSObject, ObservableObject {
    private var centralManager: CBCentralManager!
    private var bootwarmerPeripheral: CBPeripheral?
    private var heaterCharacteristic: CBCharacteristic?
    private var temperatureCharacteristic: CBCharacteristic?
    
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var temperature: Float = 0.0
    @Published var heaterPower: Float = 0.0
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
    
    func setHeaterPower(_ power: Float) {
        guard let characteristic = heaterCharacteristic else { return }
        let value = UInt8(max(0, min(100, power)))
        bootwarmerPeripheral?.writeValue(Data([value]), for: characteristic, type: .withResponse)
        heaterPower = Float(value)
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
        if characteristic.uuid == tempCharUUID,
           let data = characteristic.value,
           data.count >= 4 {
            let temp = data.withUnsafeBytes { $0.load(as: Float.self) }
            DispatchQueue.main.async {
                self.temperature = temp
            }
        }
    }
}
