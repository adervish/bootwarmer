import SwiftUI
import Charts

struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    @State private var temperatureReadings: [(timestamp: Date, value: Double)] = []
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Current Temperature")
                .font(.headline)
            
            if bluetoothManager.isConnected {
                Text("Connected")
                    .foregroundColor(.green)
                
                Text(String(format: "%.1f°C", bluetoothManager.temperature))
                    .font(.largeTitle)
                    .onChange(of: bluetoothManager.temperature) { newTemp in
                        temperatureReadings.append((timestamp: Date(), value: Double(newTemp)))
                    }
                
                VStack {
                    Text("Left target temp: \(Int(bluetoothManager.heaterPower)) ℉")
                    Slider(value: Binding(
                        get: { bluetoothManager.heaterPower },
                        set: { bluetoothManager.setHeaterPower($0) }
                    ), in: 0...255, step: 5)
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
            
            if !temperatureReadings.isEmpty {
                Chart(temperatureReadings, id: \.timestamp) { reading in
                    PointMark(
                        x: .value("Time", reading.timestamp),
                        y: .value("Temperature", reading.value)
                    )
                    .foregroundStyle(.blue)
                }
                .frame(height: 200)
                .padding()
                .chartXAxis {
                    AxisMarks(position: .bottom) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.hour().minute().second())
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel()
                    }
                }
            }
            
            Button(action: {
                temperatureReadings.removeAll()
            }) {
                Text("reset chart")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
