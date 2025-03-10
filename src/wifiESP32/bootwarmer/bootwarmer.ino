#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <Wire.h>

Adafruit_MPU6050 mpu;

// BLE service and characteristic UUIDs
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define HEATER_CHAR_UUID   "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define TEMP_CHAR_UUID     "beb5483e-36e1-4688-b7f5-ea07361b26a9"

// Pin definitions
const int HEATER_PIN_R = 33;  // PWM output for right heater control
const int TEMP_PIN_R = 35;    // ADC input for right temperature sensor
const int HEATER_PIN_L = 18;  // PWM output for left heater control
const int TEMP_PIN_L = 34;    // ADC input for left temperature sensor

// PWM configuration
const int PWM_FREQ = 100;      // 100 Hz
const int PWM_RESOLUTION = 8;   // 8-bit resolution (0-255)

// Temperature calculation constants
const float THERMISTOR_R25 = 10000.0;  // 10k thermistor
const float THERMISTOR_BETA = 3950.0;  // Beta coefficient
const float SERIES_R = 10000.0;        // 10k series resistor

// PID constants
const float KP = 5.0;    // Increased proportional gain for faster response
const float KI = 0.5;    // Keep integral gain the same to avoid oscillation
const float KD = 1.0;    // Increased derivative gain to help with quick changes

// Structure to hold all the data we want to send
struct DebugData {
    float temperatureR;
    float errorR;
    float integralR;
    float derivativeR;
    uint32_t heaterPowerR;
    float temperatureL;
    float errorL;
    float integralL;
    float derivativeL;
    uint32_t heaterPowerL;
    float accelerationX;
    float accelerationY;
    float accelerationZ;
    float gyroX;
    float gyroY;
    float gyroZ;
    float temperature;
} __attribute__((packed));

// Global variables
BLEServer* pServer = NULL;
BLECharacteristic* pHeaterCharacteristic = NULL;
BLECharacteristic* pTempCharacteristic = NULL;
bool deviceConnected = false;
float setpointTempR = 70.0;  // Target temperature for right side in Fahrenheit
float setpointTempL = 70.0;  // Target temperature for left side in Fahrenheit
float lastErrorR = 0.0;      // Last error for right derivative term
float lastErrorL = 0.0;      // Last error for left derivative term
float integralR = 0.0;       // Right integral accumulator
float integralL = 0.0;       // Left integral accumulator
uint8_t heaterPowerR = 33;    // Right heater 0-100%
uint8_t heaterPowerL = 33;    // Left heater 0-100%
uint8_t forcePowerLevelR = 5;  // 0=Off, 1=0%, 2=25%, 3=50%, 4=100%, 5=Track Temp (default)
uint8_t forcePowerLevelL = 5;  // 0=Off, 1=0%, 2=25%, 3=50%, 4=100%, 5=Track Temp (default)
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
        Serial.print("Length: ");
        Serial.println(pCharacteristic->getLength());
        if (data != nullptr && pCharacteristic->getLength() > 0) {
            // Log the raw data received
            Serial.print("Raw data received [");
            for (int i = 0; i < pCharacteristic->getLength(); i++) {
                Serial.print(data[i]);
                if (i < pCharacteristic->getLength() - 1) {
                    Serial.print(", ");
                }
            }
            Serial.println("]");
            
            // Check if we received at least 4 bytes (2 temps + 2 force power levels)
            if (pCharacteristic->getLength() >= 4) {
                setpointTempR = data[0];  // Right temperature setpoint in Fahrenheit
                setpointTempL = data[1];  // Left temperature setpoint in Fahrenheit
                forcePowerLevelR = data[2];  // Right force power level
                forcePowerLevelL = data[3];  // Left force power level
                
                Serial.printf("New settings - Right: %.1f°F (Force: %d), Left: %.1f°F (Force: %d)\n", 
                            setpointTempR, forcePowerLevelR, setpointTempL, forcePowerLevelL);
                
                // Log the meaning of the force power levels
                Serial.println("Force power levels: 0=Off, 1=0%, 2=25%, 3=50%, 4=100%, 5=Track Temp");
            }
            else if (pCharacteristic->getLength() >= 2) {
                // Backward compatibility for older app versions
                setpointTempR = data[0];  // Right temperature setpoint in Fahrenheit
                setpointTempL = data[1];  // Left temperature setpoint in Fahrenheit
                Serial.printf("New temperature setpoints - Right: %.1f°F, Left: %.1f°F\n", 
                            setpointTempR, setpointTempL);
            }
        }
    }
};

// Calculate temperature from ADC reading
float calculateTemperature(int adcValue) {
    float voltage = (float)adcValue * (3.3 / 4095.0);  // ESP32 ADC is 12-bit
    float resistance = SERIES_R * voltage / (3.3 - voltage);
    resistance = (3.3 * SERIES_R) / voltage - SERIES_R;
    float steinhart = log(resistance / THERMISTOR_R25);

    steinhart /= THERMISTOR_BETA;
    steinhart += 1.0 / (25.0 + 273.15);
    steinhart = 1.0 / steinhart;
    return (steinhart - 273.15) * 9/5 + 32;  // Convert Kelvin to Fahrenheit
}

void setup() {
    // Initialize Serial for debugging
    Serial.begin(115200);
    while (!Serial)
      delay(10);

    // Try to initialize!
    if (!mpu.begin()) {
      Serial.println("Failed to find MPU6050 chip");
        delay(10);
    } else {
        Serial.println("MPU6050 Found!");
    }
  mpu.setAccelerometerRange(MPU6050_RANGE_8_G);
  Serial.print("Accelerometer range set to: ");
  switch (mpu.getAccelerometerRange()) {
  case MPU6050_RANGE_2_G:
    Serial.println("+-2G");
    break;
  case MPU6050_RANGE_4_G:
    Serial.println("+-4G");
    break;
  case MPU6050_RANGE_8_G:
    Serial.println("+-8G");
    break;
  case MPU6050_RANGE_16_G:
    Serial.println("+-16G");
    break;
  }
  mpu.setGyroRange(MPU6050_RANGE_500_DEG);
  Serial.print("Gyro range set to: ");
  switch (mpu.getGyroRange()) {
  case MPU6050_RANGE_250_DEG:
    Serial.println("+- 250 deg/s");
    break;
  case MPU6050_RANGE_500_DEG:
    Serial.println("+- 500 deg/s");
    break;
  case MPU6050_RANGE_1000_DEG:
    Serial.println("+- 1000 deg/s");
    break;
  case MPU6050_RANGE_2000_DEG:
    Serial.println("+- 2000 deg/s");
    break;
  }

  mpu.setFilterBandwidth(MPU6050_BAND_5_HZ);
  Serial.print("Filter bandwidth set to: ");
  switch (mpu.getFilterBandwidth()) {
  case MPU6050_BAND_260_HZ:
    Serial.println("260 Hz");
    break;
  case MPU6050_BAND_184_HZ:
    Serial.println("184 Hz");
    break;
  case MPU6050_BAND_94_HZ:
    Serial.println("94 Hz");
    break;
  case MPU6050_BAND_44_HZ:
    Serial.println("44 Hz");
    break;
  case MPU6050_BAND_21_HZ:
    Serial.println("21 Hz");
    break;
  case MPU6050_BAND_10_HZ:
    Serial.println("10 Hz");
    break;
  case MPU6050_BAND_5_HZ:
    Serial.println("5 Hz");
    break;
  }

  Serial.println("");
  delay(100);

    ledcAttach(HEATER_PIN_R, PWM_FREQ, PWM_RESOLUTION);  // Channel 0 for right heater
    //ledcSetup(0, PWM_FREQ, PWM_RESOLUTION);
    ledcAttach(HEATER_PIN_L, PWM_FREQ, PWM_RESOLUTION);  // Channel 1 for left heater
    // ledcSetup(1, PWM_FREQ, PWM_RESOLUTION);
    
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

    int counterR = 0;
    int counterL = 0;
    float tempAccumR = 0;
    float tempAccumL = 0;

    if (true) {
        unsigned long currentTime = millis();
        
        // Read temperatures
        int adcValueR = analogRead(TEMP_PIN_R);
        int adcValueL = analogRead(TEMP_PIN_L);
        float temperatureR = calculateTemperature(adcValueR);
        float temperatureL = calculateTemperature(adcValueL);
        
        counterR++;
        counterL++;
        tempAccumR += temperatureR;
        tempAccumL += temperatureL;

        // Calculate PID control every 250ms for faster response
        if (currentTime - lastPidTime >= 500) {

            sensors_event_t a, g, temp;
            mpu.getEvent(&a, &g, &temp);

            debugData.accelerationX = a.acceleration.x;
            debugData.accelerationY = a.acceleration.y;
            debugData.accelerationZ = a.acceleration.z;
            debugData.gyroX = g.gyro.x;
            debugData.gyroY = g.gyro.y;
            debugData.gyroZ = g.gyro.z;
            debugData.temperature = temp.temperature;

            float avgTempR = tempAccumR / (float) counterR;
            float avgTempL = tempAccumL / (float) counterL;
            counterR = 0;
            counterL = 0;
            tempAccumR = 0.0;
            tempAccumL = 0.0;

            // Update initial debug data
            debugData.temperatureR = avgTempR;
            debugData.temperatureL = avgTempL;
            
            // Initialize PID variables
            float errorR = 0, errorL = 0;
            float derivativeR = 0, derivativeL = 0;

            // Always calculate error for debug display purposes
            errorR = setpointTempR - avgTempR;
            derivativeR = (errorR - lastErrorR);
            
            // Right side - Check if using forced power or PID control
            if (forcePowerLevelR == 5) {
                // Track Temperature mode - use PID control
                integralR = constrain(integralR + errorR, -255, 255);
                float outputR = (KP * errorR) + (KI * integralR) + (KD * derivativeR);
                heaterPowerR = constrain((int)outputR, 0, 100);
                if (temperatureR < 0)
                    heaterPowerR = 33;
            } else {
                // Force power mode
                switch (forcePowerLevelR) {
                    case 0: // Off
                        heaterPowerR = 0;
                        break;
                    case 1: // 0%
                        heaterPowerR = 0;
                        break;
                    case 2: // 25%
                        heaterPowerR = 25;
                        break;
                    case 3: // 50%
                        heaterPowerR = 50;
                        break;
                    case 4: // 100%
                        heaterPowerR = 100;
                        break;
                    default:
                        heaterPowerR = 0;
                        break;
                }
                Serial.printf("Right using forced power level: %d%% (mode %d)\n", heaterPowerR, forcePowerLevelR);
            }
            
            uint8_t pwmLevelR = (int)((float)heaterPowerR / 100.0 * 255.0);
            ledcWrite(HEATER_PIN_R, pwmLevelR);  // Channel 0 for right heater
            
            // Always calculate error for debug display purposes
            errorL = setpointTempL - avgTempL;
            derivativeL = (errorL - lastErrorL);
            
            // Left side - Check if using forced power or PID control
            if (forcePowerLevelL == 5) {
                // Track Temperature mode - use PID control
                integralL = constrain(integralL + errorL, -255, 255);
                float outputL = (KP * errorL) + (KI * integralL) + (KD * derivativeL);
                heaterPowerL = constrain((int)outputL, 0, 100);
                if (temperatureL < 0)
                    heaterPowerL = 33;
            } else {
                // Force power mode
                switch (forcePowerLevelL) {
                    case 0: // Off
                        heaterPowerL = 0;
                        break;
                    case 1: // 0%
                        heaterPowerL = 0;
                        break;
                    case 2: // 25%
                        heaterPowerL = 25;
                        break;
                    case 3: // 50%
                        heaterPowerL = 50;
                        break;
                    case 4: // 100%
                        heaterPowerL = 100;
                        break;
                    default:
                        heaterPowerL = 0;
                        break;
                }
                Serial.printf("Left using forced power level: %d%% (mode %d)\n", heaterPowerL, forcePowerLevelL);
            }
            
            uint8_t pwmLevelL = (int)((float)heaterPowerL / 100.0 * 255.0);
            ledcWrite(HEATER_PIN_L, pwmLevelL);  // Channel 1 for left heater
            
            // Update debug data - Always send current values regardless of mode
            debugData.errorR = errorR;
            debugData.integralR = integralR;
            debugData.derivativeR = derivativeR;
            debugData.heaterPowerR = heaterPowerR;
            debugData.errorL = errorL;
            debugData.integralL = integralL;
            debugData.derivativeL = derivativeL;
            debugData.heaterPowerL = heaterPowerL;
            
            // Send updated debug data over BLE
            pTempCharacteristic->setValue((uint8_t*)&debugData, sizeof(DebugData));
            pTempCharacteristic->notify();
            
            // Always update tracking variables for smooth transition
            // if returning to Track Temperature mode
            lastErrorR = errorR;
            lastErrorL = errorL;
            
            lastPidTime = currentTime;
            
            // Print debug info
            //Serial.printf("Right - Temp: %.1f°F, Set: %.1f°F, Error: %.1f, Power: %d%%\n", 
            //             temperatureR, setpointTempR, errorR, heaterPowerR);
            //Serial.printf("Left  - Temp: %.1f°F, Set: %.1f°F, Error: %.1f, Power: %d%%\n", 
            //             temperatureL, setpointTempL, errorL, heaterPowerL);
        }
    }
    
    // Small delay for system stability
    delay(100);
}
