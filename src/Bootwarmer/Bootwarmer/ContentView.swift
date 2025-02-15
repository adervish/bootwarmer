import SwiftUI
import Charts

struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    @State private var temperatureReadings: [(timestamp: Date, value: Double)] = []
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Text("Temperature")
                    .font(.headline)
                
                if bluetoothManager.isConnected {
                    Text("Connected")
                        .foregroundColor(.green)
                    
                    HStack(spacing: 20) {
                        VStack {
                            Text("Target")
                                .font(.subheadline)
                            Text(String(format: "%.1f°F", bluetoothManager.targetTemperature))
                                .font(.title)
                        }
                        
                        VStack {
                            Text("Measured")
                                .font(.subheadline)
                            Text(String(format: "%.1f°F", bluetoothManager.measuredTemperature))
                                .font(.title)
                                .onChange(of: bluetoothManager.measuredTemperature) { newTemp in
                                    temperatureReadings.append((timestamp: Date(), value: Double(newTemp)))
                                }
                        }
                    }
                    
                    // PID Debug Information
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PID Debug Info")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        Group {
                            Text(String(format: "Error: %.2f°F", bluetoothManager.pidError))
                            Text(String(format: "Integral: %.2f", bluetoothManager.pidIntegral))
                            Text(String(format: "Derivative: %.2f", bluetoothManager.pidDerivative))
                            Text(String(format: "Heater Power: %d%%", Int(bluetoothManager.heaterPower)))
                        }
                        .font(.system(.body, design: .monospaced))
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(5)
                    
                    VStack(spacing: 5) {
                        Text("Set Target Temperature")
                            .font(.subheadline)
                        Slider(value: Binding(
                            get: { bluetoothManager.targetTemperature },
                            set: { bluetoothManager.setTargetTemperature($0) }
                        ), in: 50...100, step: 1)
                    }
                    .padding()
                }
                else {
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
                        .symbol(.circle)
                        .symbolSize(10)
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
}

#Preview {
    ContentView()
}
