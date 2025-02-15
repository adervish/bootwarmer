import SwiftUI
import Charts

struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    struct Reading {
        let timestamp: Date
        let temperature: Double
        let error: Double
        let integral: Double
        let derivative: Double
        let heaterPower: Double
    }
    
    @State private var readings: [Reading] = []
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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
                                .onChange(of: bluetoothManager.measuredTemperature) { _ in
                                    readings.append(Reading(
                                        timestamp: Date(),
                                        temperature: Double(bluetoothManager.measuredTemperature),
                                        error: Double(bluetoothManager.pidError),
                                        integral: Double(bluetoothManager.pidIntegral),
                                        derivative: Double(bluetoothManager.pidDerivative),
                                        heaterPower: Double(bluetoothManager.heaterPower)
                                    ))
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
                
            if !readings.isEmpty {
                VStack(spacing: 0) {
                    Text("Temperature (°F)")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Chart {
                        ForEach(readings, id: \.timestamp) { reading in
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Temperature", reading.temperature)
                            )
                            .foregroundStyle(.blue)
                        }
                    }
                    .frame(height: 100)
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let temp = value.as(Double.self) {
                                    Text("\(Int(temp))°F")
                                }
                            }
                        }
                    }
                    
                    Text("Error (°F)")
                        .font(.caption)
                        .foregroundColor(.red)
                    Chart {
                        ForEach(readings, id: \.timestamp) { reading in
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Error", reading.error)
                            )
                            .foregroundStyle(.red)
                        }
                    }
                    .frame(height: 100)
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let error = value.as(Double.self) {
                                    Text(String(format: "%.1f", error))
                                }
                            }
                        }
                    }
                    
                    Text("Integral")
                        .font(.caption)
                        .foregroundColor(.green)
                    Chart {
                        ForEach(readings, id: \.timestamp) { reading in
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Integral", reading.integral)
                            )
                            .foregroundStyle(.green)
                        }
                    }
                    .frame(height: 100)
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let integral = value.as(Double.self) {
                                    Text(String(format: "%.1f", integral))
                                }
                            }
                        }
                    }
                    
                    Text("Derivative")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Chart {
                        ForEach(readings, id: \.timestamp) { reading in
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Derivative", reading.derivative)
                            )
                            .foregroundStyle(.orange)
                        }
                    }
                    .frame(height: 100)
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let derivative = value.as(Double.self) {
                                    Text(String(format: "%.1f", derivative))
                                }
                            }
                        }
                    }
                    
                    Text("Heater Power (%)")
                        .font(.caption)
                        .foregroundColor(.purple)
                    Chart {
                        ForEach(readings, id: \.timestamp) { reading in
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Power", reading.heaterPower)
                            )
                            .foregroundStyle(.purple)
                        }
                    }
                    .frame(height: 100)
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel(format: .dateTime.hour().minute().second())
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let power = value.as(Double.self) {
                                    Text("\(Int(power))%")
                                }
                            }
                        }
                    }
                }
                .padding()
                }
                
                Button(action: {
                    readings.removeAll()
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
