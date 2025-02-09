import SwiftUI
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
    
    private let serviceUUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
    private let heaterCharUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")
    private let tempCharUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a9")
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        isScanning = true
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
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

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
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

struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Boot Warmer")
                .font(.largeTitle)
                .padding()
            
            if bluetoothManager.isConnected {
                Text("Connected")
                    .foregroundColor(.green)
                
                Text(String(format: "Temperature: %.1f°C", bluetoothManager.temperature))
                    .font(.title2)
                    .padding()
                
                VStack {
                    Text("Heater Power: \(Int(bluetoothManager.heaterPower))%")
                    Slider(value: Binding(
                        get: { bluetoothManager.heaterPower },
                        set: { bluetoothManager.setHeaterPower($0) }
                    ), in: 0...100, step: 1)
                }
                .padding()
            } else {
                Text(bluetoothManager.isScanning ? "Scanning..." : "Disconnected")
                    .foregroundColor(bluetoothManager.isScanning ? .blue : .red)
                
                Button(action: {
                    bluetoothManager.startScanning()
                }) {
                    Text("Start Scanning")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
        }
        .padding()
    }
}

@main
struct BootWarmerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
