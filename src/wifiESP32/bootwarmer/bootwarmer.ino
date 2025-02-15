#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// BLE service and characteristic UUIDs
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define HEATER_CHAR_UUID   "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define TEMP_CHAR_UUID     "beb5483e-36e1-4688-b7f5-ea07361b26a9"

// Pin definitions
const int HEATER_PIN = 18;  // PWM output for heater control
const int TEMP_PIN = 35;    // ADC input for temperature sensor

// PWM configuration
const int PWM_FREQ = 10;      // 100 Hz
const int PWM_RESOLUTION = 8;   // 8-bit resolution (0-255)

// Temperature calculation constants
const float THERMISTOR_R25 = 10000.0;  // 10k thermistor
const float THERMISTOR_BETA = 3950.0;  // Beta coefficient
const float SERIES_R = 10000.0;        // 10k series resistor

// PID constants
const float KP = 7.0;    // Increased proportional gain for faster response
const float KI = 0.7;    // Keep integral gain the same to avoid oscillation
const float KD = 0.7;    // Increased derivative gain to help with quick changes

// Structure to hold all the data we want to send
struct DebugData {
    float temperature;
    float error;
    float integral;
    float derivative;
    uint8_t heaterPower;
} __attribute__((packed));

// Global variables
BLEServer* pServer = NULL;
BLECharacteristic* pHeaterCharacteristic = NULL;
BLECharacteristic* pTempCharacteristic = NULL;
bool deviceConnected = false;
float setpointTemp = 70.0;  // Target temperature in Fahrenheit
float lastError = 0.0;      // Last error for derivative term
float integral = 0.0;       // Integral accumulator
uint8_t heaterPower = 0;    // 0-100%
unsigned long lastPidTime = 0; // Last PID calculation time
DebugData debugData;        // Data structure for BLE transmission

// BLE server callbacks
class ServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
        deviceConnected = true;
    }

    void onDisconnect(BLEServer* pServer) {
        deviceConnected = false;
        // Start advertising again
        pServer->startAdvertising();
    }
};

// Heater control characteristic callbacks
class HeaterCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        uint8_t* data = pCharacteristic->getData();
        if (data != nullptr && pCharacteristic->getLength() > 0) {
            setpointTemp = data[0];  // Temperature setpoint in Fahrenheit
            Serial.printf("New temperature setpoint: %.1f°F\n", setpointTemp);

            //analogWrite(HEATER_PIN, pwmValue);  // Using analogWrite instead of ledcWrite
        }
    }
};

// Calculate temperature from ADC reading
float calculateTemperature(int adcValue) {
    float voltage = (float)adcValue * (3.3 / 4095.0);  // ESP32 ADC is 12-bit
    float resistance = SERIES_R * voltage / (3.3 - voltage);
    resistance = (3.3 * SERIES_R) / voltage - SERIES_R;
    float steinhart = log(resistance / THERMISTOR_R25);
    Serial.printf( "ADC=%d Voltage=%f R=%f S=%f", adcValue, voltage, resistance, steinhart );

    steinhart /= THERMISTOR_BETA;
    steinhart += 1.0 / (25.0 + 273.15);
    steinhart = 1.0 / steinhart;
    return (steinhart - 273.15) * 9/5 + 32;  // Convert Kelvin to Fahrenheit
}

void setup() {
    // Initialize Serial for debugging
    Serial.begin(115200);
    ledcAttach(HEATER_PIN, PWM_FREQ, PWM_RESOLUTION);
    
    // Configure ADC
    analogReadResolution(12);
    analogSetAttenuation(ADC_11db);  // Full range: 0-3.3V
    
    // Initialize BLE
    BLEDevice::init("BootHeater");
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new ServerCallbacks());
    
    // Create BLE Service
    BLEService *pService = pServer->createService(SERVICE_UUID);
    
    // Create BLE Characteristics
    pHeaterCharacteristic = pService->createCharacteristic(
        HEATER_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ |
        BLECharacteristic::PROPERTY_WRITE
    );
    pHeaterCharacteristic->setCallbacks(new HeaterCallbacks());
    
    pTempCharacteristic = pService->createCharacteristic(
        TEMP_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ |
        BLECharacteristic::PROPERTY_NOTIFY
    );
    pTempCharacteristic->addDescriptor(new BLE2902());
    
    // Start the service
    pService->start();
    
    // Start advertising
    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(false);
    pAdvertising->setMinPreferred(0x0);
    BLEDevice::startAdvertising();
    
    Serial.println("Boot heater ready! Waiting for connection...");
}

void loop() {
    if (deviceConnected) {
        unsigned long currentTime = millis();
        
        // Read temperature
        int adcValue = analogRead(TEMP_PIN);
        float temperature = calculateTemperature(adcValue);
        
        // Update initial debug data
        debugData.temperature = temperature;
        
        // Calculate PID control every 250ms for faster response
        if (currentTime - lastPidTime >= 250) {
            // Calculate error
            float error = setpointTemp - temperature;
            
            // Calculate integral term with anti-windup
            integral = constrain(integral + error, -255, 255);
            
            // Calculate derivative term
            float derivative = (error - lastError);
            
            // Update all debug data
            debugData.error = error;
            debugData.integral = integral;
            debugData.derivative = derivative;
            debugData.heaterPower = heaterPower;
            
            // Send updated debug data over BLE
            pTempCharacteristic->setValue((uint8_t*)&debugData, sizeof(DebugData));
            pTempCharacteristic->notify();
            
            // Calculate PID output
            float output = (KP * error) + (KI * integral) + (KD * derivative);
            
            // Convert output to PWM value (0-100%)
            heaterPower = constrain((int)output, 0, 100);
            
            // Convert percentage to PWM value (0-255)
            uint8_t pwmLevel = (int)((float)heaterPower / 100.0 * 255.0);
            ledcWrite(HEATER_PIN, pwmLevel);
            
            // Update tracking variables
            lastError = error;
            lastPidTime = currentTime;
            
            // Print debug info
            Serial.printf("Temp: %.1f°F, Setpoint: %.1f°F, Error: %.1f, Output: %d%%, PWM: %d\n", 
                         temperature, setpointTemp, error, heaterPower, pwmLevel);
        }
    }
    
    // Small delay for system stability
    delay(50);
}
