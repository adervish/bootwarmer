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
        // IMU data
        let accelerationX: Double
        let accelerationY: Double
        let accelerationZ: Double
        let gyroX: Double
        let gyroY: Double
        let gyroZ: Double
        let imuTemperature: Double
    }
    
    @State private var readings: [Reading] = []
    
    // Helper functions for power level buttons
    private func powerLevelText(_ level: Int) -> String {
        switch level {
        case 0: return "Off"
        case 1: return "0%"
        case 2: return "25%"
        case 3: return "50%"
        case 4: return "100%"
        case 5: return "Trk Temp"
        default: return "Trk Temp"
        }
    }
    
    private func powerLevelColor(_ level: Int) -> Color {
        switch level {
        case 0: return Color.secondary
        case 1: return Color.gray
        case 2: return Color.blue
        case 3: return Color.orange
        case 4: return Color.red
        case 5: return Color.green
        default: return Color.green
        }
    }
    
    private var temperatureYAxisRange: ClosedRange<Double> {
        let temps = readings.flatMap { reading in 
            [reading.temperatureL, reading.temperatureR].filter { $0 > -20 }
        }
        guard let min = temps.min(), let max = temps.max() else { return 40...110 }
        let range = max - min
        let padding = range * 0.1
        return (min - padding)...(max + padding)
    }
    
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
                            heaterPowerL: Double(bluetoothManager.heaterPowerL),
                            accelerationX: Double(bluetoothManager.accelerationX),
                            accelerationY: Double(bluetoothManager.accelerationY),
                            accelerationZ: Double(bluetoothManager.accelerationZ),
                            gyroX: Double(bluetoothManager.gyroX),
                            gyroY: Double(bluetoothManager.gyroY),
                            gyroZ: Double(bluetoothManager.gyroZ),
                            imuTemperature: Double(bluetoothManager.imuTemperature)
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
                        VStack(spacing: 10) {
                            Text("Target")
                                .font(.subheadline)
                            Slider(value: Binding(
                                get: { bluetoothManager.targetTemperatureL },
                                set: { bluetoothManager.setTargetTemperatures(right: bluetoothManager.targetTemperatureR, left: $0) }
                            ), in: 50...100, step: 1)
                            
                            Button(action: {
                                bluetoothManager.cycleForcePowerLevelLeft()
                            }) {
                                Text("Force Pwr Lvl: \(powerLevelText(bluetoothManager.forcePowerLevelL))")
                                    .font(.system(size: 14))
                                    .padding(8)
                                    .background(powerLevelColor(bluetoothManager.forcePowerLevelL))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }

                        // Right Side Temperature Control
                        VStack(spacing: 10) {
                            Text("Target")
                                .font(.subheadline)
                            Slider(value: Binding(
                                get: { bluetoothManager.targetTemperatureR },
                                set: { bluetoothManager.setTargetTemperatures(right: $0, left: bluetoothManager.targetTemperatureL) }
                            ), in: 50...100, step: 1)
                            
                            Button(action: {
                                bluetoothManager.cycleForcePowerLevelRight()
                            }) {
                                Text("Force Pwr Lvl: \(powerLevelText(bluetoothManager.forcePowerLevelR))")
                                    .font(.system(size: 14))
                                    .padding(8)
                                    .background(powerLevelColor(bluetoothManager.forcePowerLevelR))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
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
                        ForEach(readings.indices, id: \.self) { index in
                            if readings[index].temperatureL > -20 {
                                LineMark(
                                    x: .value("Time", readings[index].timestamp),
                                    y: .value("Right", readings[index].temperatureL)
                                )
                                .foregroundStyle(by: .value("Temperature", "Left"))
                            }
                            
                            if readings[index].temperatureR > -20 {
                                LineMark(
                                    x: .value("Time", readings[index].timestamp),
                                    y: .value("Left", readings[index].temperatureR)
                                )
                                .foregroundStyle(by: .value("Temperature", "Right"))
                            }
                        }
                    }.chartForegroundStyleScale([
                        "Right": .blue,
                        "Left": .cyan
                    ])
                    .frame(height: 100)
                    .chartXAxis(.hidden)
                    .chartLegend(position: .top)
                    .chartYScale(domain: temperatureYAxisRange)
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
                    
                    Text("IMU Data")
                        .font(.caption)
                        .padding(.top)
                    
                    // IMU Temperature
                    Text("IMU Temperature (°F)")
                        .font(.caption)
                    Chart {
                        ForEach(readings, id: \.timestamp) { reading in
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Temperature", reading.imuTemperature)
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
                                if let temp = value.as(Double.self) {
                                    Text(String(format: "%.1f°F", temp))
                                }
                            }
                        }
                    }
                    
                    // Acceleration
                    Text("Acceleration (g)")
                        .font(.caption)
                    Chart {
                        ForEach(readings, id: \.timestamp) { reading in
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("X", reading.accelerationX)
                            )
                            .foregroundStyle(by: .value("Axis", "X"))
                            
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Y", reading.accelerationY)
                            )
                            .foregroundStyle(by: .value("Axis", "Y"))
                            
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Z", reading.accelerationZ)
                            )
                            .foregroundStyle(by: .value("Axis", "Z"))
                        }
                    }
                    .chartForegroundStyleScale([
                        "X": .red,
                        "Y": .green,
                        "Z": .blue
                    ])
                    .frame(height: 100)
                    .chartXAxis(.hidden)
                    .chartLegend(position: .top)
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let accel = value.as(Double.self) {
                                    Text(String(format: "%.2f", accel))
                                }
                            }
                        }
                    }
                    
                    // Gyroscope
                    Text("Gyroscope (°/s)")
                        .font(.caption)
                    Chart {
                        ForEach(readings, id: \.timestamp) { reading in
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("X", reading.gyroX)
                            )
                            .foregroundStyle(by: .value("Axis", "X"))
                            
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Y", reading.gyroY)
                            )
                            .foregroundStyle(by: .value("Axis", "Y"))
                            
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("Z", reading.gyroZ)
                            )
                            .foregroundStyle(by: .value("Axis", "Z"))
                        }
                    }
                    .chartForegroundStyleScale([
                        "X": .orange,
                        "Y": .purple,
                        "Z": .teal
                    ])
                    .frame(height: 100)
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel(format: .dateTime.hour().minute().second())
                        }
                    }
                    .chartLegend(position: .top)
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let gyro = value.as(Double.self) {
                                    Text(String(format: "%.1f", gyro))
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
