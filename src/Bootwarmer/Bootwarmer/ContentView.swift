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
                Text("Boot warmer")
                    .font(.subheadline)
                
                if bluetoothManager.isConnected {
                    Text("Connected")
                        .foregroundColor(.green)
                    
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

                        // Left Side PID Debug
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Left")
                                .font(.headline)
                                .padding(.bottom, 4)
                            
                            Group {
                                VStack {
                                    Text("Target")
                                        .font(.subheadline)
                                    Text(String(format: "%.1f°F", bluetoothManager.targetTemperatureL))
                                        .font(.title2)
                                }
                                
                                VStack {
                                    Text("Measured")
                                        .font(.subheadline)
                                    Text(String(format: "%.1f°F", bluetoothManager.measuredTemperatureL))
                                        .font(.title2)
                                }
                            }
                            
                            Group {
                                Text(String(format: "Error: %.2f°F", bluetoothManager.pidErrorL))
                                Text(String(format: "Integral: %.2f", bluetoothManager.pidIntegralL))
                                Text(String(format: "Derivative: %.2f", bluetoothManager.pidDerivativeL))
                                Text(String(format: "Heater Power: %d%%", Int(bluetoothManager.heaterPowerL)))
                            }
                            .font(.system(size: UIFont.systemFontSize / 1.5, design: .monospaced))
                        }

                        // Right Side PID Debug
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Right")
                                .font(.headline)
                                .padding(.bottom, 4)
                                                            .font(.system(size: UIFont.systemFontSize / 1.5, design: .monospaced))

                            Group {
                                VStack {
                                    Text("Target")
                                        .font(.subheadline)
                                    Text(String(format: "%.1f°F", bluetoothManager.targetTemperatureR))
                                        .font(.title2)
                                }
                                
                                VStack {
                                    Text("Measured")
                                        .font(.subheadline)
                                    Text(String(format: "%.1f°F", bluetoothManager.measuredTemperatureR))
                                        .font(.title2)
                                }
                            }
                            
                            Group {
                                Text(String(format: "Error: %.2f°F", bluetoothManager.pidErrorR))
                                Text(String(format: "Integral: %.2f", bluetoothManager.pidIntegralR))
                                Text(String(format: "Derivative: %.2f", bluetoothManager.pidDerivativeR))
                                Text(String(format: "Heater Power: %d%%", Int(bluetoothManager.heaterPowerR)))
                            }
                            .font(.system(size: UIFont.systemFontSize / 1.5, design: .monospaced))
                        }
                        

                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(5)
                    
                    HStack(spacing: 20) {
         
                        // Left Side Temperature Control
                        VStack(spacing: 5) {
                            Text("Target")
                                .font(.subheadline)
                            Slider(value: Binding(
                                get: { bluetoothManager.targetTemperatureL },
                                set: { bluetoothManager.setTargetTemperatures(right: bluetoothManager.targetTemperatureR, left: $0) }
                            ), in: 50...100, step: 1)
                        }

                        // Right Side Temperature Control
                        VStack(spacing: 5) {
                            Text("Target")
                                .font(.subheadline)
                            Slider(value: Binding(
                                get: { bluetoothManager.targetTemperatureR },
                                set: { bluetoothManager.setTargetTemperatures(right: $0, left: bluetoothManager.targetTemperatureL) }
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
                                y: .value("Right", reading.temperatureL)
                            )
                            .foregroundStyle(by: .value("Temperature", "Left"))
                            
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Left", reading.temperatureR)
                            )
                            .foregroundStyle(by: .value("Temperature", "Right"))
                        }
                    }.chartForegroundStyleScale([
                        "Right": .blue,
                        "Left": .cyan
                    ])
                    .frame(height: 100)
                    .chartXAxis(.hidden)
                    .chartLegend(position: .top)
                    .chartYScale(domain: 40...110)
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
                    
                    Text("Heater Power (%)")
                        .font(.caption)
                    Chart {
                        ForEach(readings, id: \.timestamp) { reading in
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Right", reading.heaterPowerL)
                            )
                            .foregroundStyle(by: .value("Heater Power", "Left"))
                            
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Left", reading.heaterPowerR)
                            )
                            .foregroundStyle(by: .value("Heater Power", "Right"))
                        }
                    }.chartForegroundStyleScale([
                        "Right": .purple,
                        "Left": .indigo
                    ])
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
                    
                    Text("Error (°F)")
                        .font(.caption)
                    Chart {
                        ForEach(readings, id: \.timestamp) { reading in
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Right", reading.errorL)
                            )
                            .foregroundStyle(by: .value("Error", "Left"))
                            
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Left", reading.errorR)
                            )
                            .foregroundStyle(by: .value("Error", "Right"))
                        }
                    }.chartForegroundStyleScale([
                        "Right": .red,
                        "Left": .pink
                    ])
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
                                y: .value("Right", reading.integralL)
                            )
                            .foregroundStyle(by: .value("Integral", "Left"))
                            
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Left", reading.integralR)
                            )
                            .foregroundStyle(by: .value("Integral", "Right"))
                        }
                    }.chartForegroundStyleScale([
                        "Right": .green,
                        "Left": .mint
                    ])
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
                                y: .value("Right", reading.derivativeL)
                            )
                            .foregroundStyle(by: .value("Derivative", "Left"))
                            
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Left", reading.derivativeR)
                            )
                            .foregroundStyle(by: .value("Derivative", "Right"))
                        }
                    }.chartForegroundStyleScale([
                        "Right": .orange,
                        "Left": .yellow
                    ])
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
