import SwiftUI
import Charts

struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    struct Reading {
        let timestamp: Date
        // Right side
        let temperatureR: Double
        let errorR: Double
        let integralR: Double
        let derivativeR: Double
        let heaterPowerR: Double
        // Left side
        let temperatureL: Double
        let errorL: Double
        let integralL: Double
        let derivativeL: Double
        let heaterPowerL: Double
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
                    
                    HStack(spacing: 30) {
                        // Right Side
                        VStack {
                            Text("Right Boot")
                                .font(.headline)
                            HStack(spacing: 20) {
                                VStack {
                                    Text("Target")
                                        .font(.subheadline)
                                    Text(String(format: "%.1f°F", bluetoothManager.targetTemperatureR))
                                        .font(.title)
                                }
                                
                                VStack {
                                    Text("Measured")
                                        .font(.subheadline)
                                    Text(String(format: "%.1f°F", bluetoothManager.measuredTemperatureR))
                                        .font(.title)
                                }
                            }
                        }
                        
                        // Left Side
                        VStack {
                            Text("Left Boot")
                                .font(.headline)
                            HStack(spacing: 20) {
                                VStack {
                                    Text("Target")
                                        .font(.subheadline)
                                    Text(String(format: "%.1f°F", bluetoothManager.targetTemperatureL))
                                        .font(.title)
                                }
                                
                                VStack {
                                    Text("Measured")
                                        .font(.subheadline)
                                    Text(String(format: "%.1f°F", bluetoothManager.measuredTemperatureL))
                                        .font(.title)
                                }
                            }
                        }
                    }
                    .onChange(of: bluetoothManager.measuredTemperatureR) { _ in
                        readings.append(Reading(
                            timestamp: Date(),
                            temperatureR: Double(bluetoothManager.measuredTemperatureR),
                            errorR: Double(bluetoothManager.pidErrorR),
                            integralR: Double(bluetoothManager.pidIntegralR),
                            derivativeR: Double(bluetoothManager.pidDerivativeR),
                            heaterPowerR: Double(bluetoothManager.heaterPowerR),
                            temperatureL: Double(bluetoothManager.measuredTemperatureL),
                            errorL: Double(bluetoothManager.pidErrorL),
                            integralL: Double(bluetoothManager.pidIntegralL),
                            derivativeL: Double(bluetoothManager.pidDerivativeL),
                            heaterPowerL: Double(bluetoothManager.heaterPowerL)
                        ))
                    }
                    
                    HStack(spacing: 20) {
                        // Right Side PID Debug
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Right PID Debug")
                                .font(.headline)
                                .padding(.bottom, 4)
                            
                            Group {
                                Text(String(format: "Error: %.2f°F", bluetoothManager.pidErrorR))
                                Text(String(format: "Integral: %.2f", bluetoothManager.pidIntegralR))
                                Text(String(format: "Derivative: %.2f", bluetoothManager.pidDerivativeR))
                                Text(String(format: "Heater Power: %d%%", Int(bluetoothManager.heaterPowerR)))
                            }
                            .font(.system(.body, design: .monospaced))
                        }
                        
                        // Left Side PID Debug
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Left PID Debug")
                                .font(.headline)
                                .padding(.bottom, 4)
                            
                            Group {
                                Text(String(format: "Error: %.2f°F", bluetoothManager.pidErrorL))
                                Text(String(format: "Integral: %.2f", bluetoothManager.pidIntegralL))
                                Text(String(format: "Derivative: %.2f", bluetoothManager.pidDerivativeL))
                                Text(String(format: "Heater Power: %d%%", Int(bluetoothManager.heaterPowerL)))
                            }
                            .font(.system(.body, design: .monospaced))
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(5)
                    
                    HStack(spacing: 20) {
                        // Right Side Temperature Control
                        VStack(spacing: 5) {
                            Text("Right Target")
                                .font(.subheadline)
                            Slider(value: Binding(
                                get: { bluetoothManager.targetTemperatureR },
                                set: { bluetoothManager.setTargetTemperatures(right: $0, left: bluetoothManager.targetTemperatureL) }
                            ), in: 50...100, step: 1)
                        }
                        
                        // Left Side Temperature Control
                        VStack(spacing: 5) {
                            Text("Left Target")
                                .font(.subheadline)
                            Slider(value: Binding(
                                get: { bluetoothManager.targetTemperatureL },
                                set: { bluetoothManager.setTargetTemperatures(right: bluetoothManager.targetTemperatureR, left: $0) }
                            ), in: 50...100, step: 1)
                        }
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
                    Chart {
                        ForEach(readings, id: \.timestamp) { reading in
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Right", reading.temperatureR)
                            )
                            .foregroundStyle(.blue)
                            
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Left", reading.temperatureL)
                            )
                            .foregroundStyle(.cyan)
                        }
                    }
                    .frame(height: 100)
                    .chartXAxis(.hidden)
                    .chartLegend(position: .top)
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
                    Chart {
                        ForEach(readings, id: \.timestamp) { reading in
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Right", reading.errorR)
                            )
                            .foregroundStyle(.red)
                            
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Left", reading.errorL)
                            )
                            .foregroundStyle(.pink)
                        }
                    }
                    .frame(height: 100)
                    .chartXAxis(.hidden)
                    .chartLegend(position: .top)
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
                    Chart {
                        ForEach(readings, id: \.timestamp) { reading in
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Right", reading.integralR)
                            )
                            .foregroundStyle(.green)
                            
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Left", reading.integralL)
                            )
                            .foregroundStyle(.mint)
                        }
                    }
                    .frame(height: 100)
                    .chartXAxis(.hidden)
                    .chartLegend(position: .top)
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
                    Chart {
                        ForEach(readings, id: \.timestamp) { reading in
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Right", reading.derivativeR)
                            )
                            .foregroundStyle(.orange)
                            
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Left", reading.derivativeL)
                            )
                            .foregroundStyle(.yellow)
                        }
                    }
                    .frame(height: 100)
                    .chartXAxis(.hidden)
                    .chartLegend(position: .top)
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
                    Chart {
                        ForEach(readings, id: \.timestamp) { reading in
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Right", reading.heaterPowerR)
                            )
                            .foregroundStyle(.purple)
                            
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Left", reading.heaterPowerL)
                            )
                            .foregroundStyle(.indigo)
                        }
                    }
                    .frame(height: 100)
                    .chartLegend(position: .top)
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
