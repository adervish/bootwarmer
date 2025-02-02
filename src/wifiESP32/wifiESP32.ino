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
const int HEATER_PIN = 25;  // PWM output for heater control
const int TEMP_PIN = 34;    // ADC input for temperature sensor

// PWM configuration
const int PWM_FREQ = 5000;      // 5 KHz
const int PWM_CHANNEL = 0;
const int PWM_RESOLUTION = 8;   // 8-bit resolution (0-255)

// Temperature calculation constants
const float THERMISTOR_R25 = 10000.0;  // 10k thermistor
const float THERMISTOR_BETA = 3950.0;  // Beta coefficient
const float SERIES_R = 10000.0;        // 10k series resistor

// Global variables
BLEServer* pServer = NULL;
BLECharacteristic* pHeaterCharacteristic = NULL;
BLECharacteristic* pTempCharacteristic = NULL;
bool deviceConnected = false;
uint8_t heaterPower = 0;  // 0-100%

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
            heaterPower = data[0];  // 0-100%
            // Convert percentage to PWM value (0-255)
            uint32_t pwmValue = (heaterPower * 255) / 100;
            analogWrite(HEATER_PIN, pwmValue);  // Using analogWrite instead of ledcWrite
        }
    }
};

// Calculate temperature from ADC reading
float calculateTemperature(int adcValue) {
    float voltage = (float)adcValue * (3.3 / 4095.0);  // ESP32 ADC is 12-bit
    float resistance = SERIES_R * voltage / (3.3 - voltage);
    float steinhart = log(resistance / THERMISTOR_R25);
    steinhart /= THERMISTOR_BETA;
    steinhart += 1.0 / (25.0 + 273.15);
    steinhart = 1.0 / steinhart;
    return steinhart - 273.15;  // Convert Kelvin to Celsius
}

void setup() {
    // Initialize Serial for debugging
    Serial.begin(115200);
    
    // Configure PWM output pin
    pinMode(HEATER_PIN, OUTPUT);
    analogWrite(HEATER_PIN, 0);  // Start with heater off
    
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
        // Read temperature
        int adcValue = analogRead(TEMP_PIN);
        float temperature = calculateTemperature(adcValue);
        
        // Update temperature characteristic
        uint8_t tempData[4];
        memcpy(tempData, &temperature, 4);
        pTempCharacteristic->setValue(tempData, 4);
        pTempCharacteristic->notify();
        
        // Print debug info
        Serial.printf("Temperature: %.1f°C, Heater: %d%%\n", temperature, heaterPower);
    }
    
    // Update temperature every second
    delay(1000);
}