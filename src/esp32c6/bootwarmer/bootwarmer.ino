// Bootwarmer per-boot controller: ESP32-C6-MINI-1 on the rev C integrated board.
//
// One board per boot. Each board drives one heater pad from one thermistor,
// runs its own PID loop, and talks to the iPhone app over Bluetooth LE.
// Arduino board: "ESP32C6 Dev Module", with "USB CDC On Boot" enabled.
//
// Board wiring (see hardware/README.md):
//   IO14  heater MOSFET gate (high = heat)     IO1  thermistor divider
//   IO0   battery voltage / 2                  IO6  USB-present sense (VBUS / 2)
//   IO7 / IO18  I2C SDA / SCL: LSM6DS3TR-C IMU (0x6A)
//   IO19  IMU INT1                             IO8  status LED (low = on)
//   IO9   BOOT button

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Preferences.h>
#include <Wire.h>
#include <esp_task_wdt.h>

// Same service as the original two-boot controller; the packets are new (v2).
#define SERVICE_UUID       "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CONTROL_CHAR_UUID  "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define STATUS_CHAR_UUID   "beb5483e-36e1-4688-b7f5-ea07361b26a9"

const int PIN_HEATER = 14;
const int PIN_NTC = 1;
const int PIN_VBAT_SENSE = 0;
const int PIN_VBUS_SENSE = 6;
const int PIN_SDA = 7;
const int PIN_SCL = 18;
const int PIN_IMU_INT = 19;
const int PIN_LED = 8;            // active low

const int PWM_FREQ = 100;
const int PWM_RESOLUTION = 8;

// Thermistor: 10k NTC (B = 3950) from 3V3 to the pin, 5.1k from the pin to ground.
const float THERMISTOR_R25 = 10000.0;
const float THERMISTOR_BETA = 3950.0;
const float DIVIDER_R = 5100.0;
const float RAIL_MV = 3300.0;

const float KP = 5.0;
const float KI = 0.5;
const float KD = 1.0;
const unsigned long CONTROL_PERIOD_MS = 500;

// Safety limits. Any fault forces the heater off until the condition clears.
const float MAX_PAD_TEMP_F = 130.0;       // hard cutoff at the thermistor
const float MIN_VALID_TEMP_F = -40.0;     // colder than this reads as an open thermistor
const float MAX_VALID_TEMP_F = 200.0;     // hotter than this reads as a shorted thermistor
const float LOW_BATTERY_V = 3.30;         // stop heating; cell protection trips much lower
const float LOW_BATTERY_RESUME_V = 3.50;
const uint8_t MAX_SETPOINT_F = 110;

enum Fault : uint8_t {
  FAULT_SENSOR_OPEN  = 1 << 0,
  FAULT_SENSOR_SHORT = 1 << 1,
  FAULT_OVER_TEMP    = 1 << 2,
  FAULT_LOW_BATTERY  = 1 << 3,
  FAULT_CHARGING     = 1 << 4,   // heater is held off while USB power is present
};

// Mode byte, unchanged from the original app:
// 0 = off, 1 = 0 %, 2 = 25 %, 3 = 50 %, 4 = 100 %, 5 = track temperature (PID)
const uint8_t MODE_TRACK = 5;

// Status notification, v2. Little-endian, packed; mirrored in the iOS app.
struct StatusPacket {
  uint8_t  version;        // 2
  uint8_t  side;           // 0 = left, 1 = right
  uint8_t  mode;
  uint8_t  faults;
  float    temperature;    // deg F
  float    setpoint;       // deg F
  float    error;
  float    integral;
  float    derivative;
  uint32_t heaterPower;    // 0-100 %
  float    batteryVolts;
  float    batteryPercent;
  float    accel[3];       // m/s^2
  float    gyro[3];        // rad/s
  float    imuTemperature; // deg C
} __attribute__((packed));

Preferences prefs;
BLEServer *server = nullptr;
BLECharacteristic *statusChar = nullptr;
bool deviceConnected = false;

uint8_t side = 0;
float setpointF = 70.0;
uint8_t mode = MODE_TRACK;
float integral = 0.0;
float lastError = 0.0;
uint8_t heaterPower = 0;
uint8_t faults = 0;
bool lowBatteryLatched = false;
bool imuPresent = false;

float tempSum = 0.0;
int tempCount = 0;
unsigned long lastControl = 0;

// ---------------------------------------------------------------- I2C helpers
bool i2cRead(uint8_t addr, uint8_t reg, uint8_t *buf, size_t len) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom(addr, (uint8_t)len) != len) return false;
  for (size_t i = 0; i < len; i++) buf[i] = Wire.read();
  return true;
}

bool i2cWrite(uint8_t addr, uint8_t reg, uint8_t value) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  Wire.write(value);
  return Wire.endTransmission() == 0;
}

// LSM6DS3TR-C
const uint8_t IMU_ADDR = 0x6A;

bool imuBegin() {
  uint8_t who = 0;
  if (!i2cRead(IMU_ADDR, 0x0F, &who, 1) || who != 0x6A) return false;
  i2cWrite(IMU_ADDR, 0x12, 0x44);   // CTRL3_C: block data update, register auto-increment
  i2cWrite(IMU_ADDR, 0x10, 0x2C);   // CTRL1_XL: 26 Hz, +-8 g
  i2cWrite(IMU_ADDR, 0x11, 0x24);   // CTRL2_G: 26 Hz, 500 dps
  return true;
}

void imuRead(StatusPacket &p) {
  uint8_t b[14];
  if (!imuPresent || !i2cRead(IMU_ADDR, 0x20, b, 14)) return;
  int16_t t  = (int16_t)(b[1] << 8 | b[0]);
  int16_t g[3], a[3];
  for (int i = 0; i < 3; i++) {
    g[i] = (int16_t)(b[3 + 2 * i] << 8 | b[2 + 2 * i]);
    a[i] = (int16_t)(b[9 + 2 * i] << 8 | b[8 + 2 * i]);
  }
  p.imuTemperature = 25.0 + t / 256.0;
  for (int i = 0; i < 3; i++) {
    p.accel[i] = a[i] * 0.244e-3 * 9.80665;            // +-8 g: 0.244 mg / LSB
    p.gyro[i]  = g[i] * 17.5e-3 * (PI / 180.0);        // 500 dps: 17.5 mdps / LSB
  }
}

// Battery voltage through the on-board 1:2 divider. The percentage is a
// rough straight-line estimate between empty (3.3 V) and full (4.2 V).
void batteryRead(float &volts, float &percent) {
  uint32_t mv = 0;
  for (int i = 0; i < 8; i++) mv += analogReadMilliVolts(PIN_VBAT_SENSE);
  volts = (mv / 8) * 2 / 1000.0;
  percent = constrain((volts - 3.3f) / (4.2f - 3.3f) * 100.0f, 0.0f, 100.0f);
}

// ---------------------------------------------------------------- sensing
float readTemperatureF() {
  float mv = analogReadMilliVolts(PIN_NTC);
  if (mv < 20.0) return -999.0;                          // open thermistor or unplugged
  if (mv > RAIL_MV - 20.0) return 999.0;                 // shorted thermistor
  float resistance = DIVIDER_R * (RAIL_MV - mv) / mv;
  float invT = log(resistance / THERMISTOR_R25) / THERMISTOR_BETA + 1.0 / 298.15;
  return (1.0 / invT - 273.15) * 9.0 / 5.0 + 32.0;
}

bool usbPresent() {
  return analogReadMilliVolts(PIN_VBUS_SENSE) * 2 > 4000;
}

void setHeater(uint8_t percent) {
  heaterPower = percent;
  ledcWrite(PIN_HEATER, (uint32_t)percent * 255 / 100);
}

// ---------------------------------------------------------------- BLE
String deviceName() {
  return side == 0 ? "BootHeater-L" : "BootHeater-R";
}

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *s) override { deviceConnected = true; }
  void onDisconnect(BLEServer *s) override {
    deviceConnected = false;
    s->startAdvertising();
  }
};

// Control write, v2: [setpoint deg F, mode] and optionally [.., side] to assign left/right.
class ControlCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    uint8_t *data = c->getData();
    size_t len = c->getLength();
    if (data == nullptr || len < 2) return;
    setpointF = min(data[0], MAX_SETPOINT_F);
    mode = data[1] <= MODE_TRACK ? data[1] : 0;
    prefs.putUChar("setpoint", (uint8_t)setpointF);
    prefs.putUChar("mode", mode);
    if (len >= 3 && data[2] <= 1 && data[2] != side) {
      side = data[2];
      prefs.putUChar("side", side);        // new name is advertised after the next power cycle
    }
  }
};

void setup() {
  // Heater off before anything else; the carrier also pulls the gate low.
  pinMode(PIN_HEATER, OUTPUT);
  digitalWrite(PIN_HEATER, LOW);

  Serial.begin(115200);

  prefs.begin("bootwarmer", false);
  side = prefs.getUChar("side", 0);
  setpointF = prefs.getUChar("setpoint", 70);
  mode = prefs.getUChar("mode", MODE_TRACK);

  ledcAttach(PIN_HEATER, PWM_FREQ, PWM_RESOLUTION);
  setHeater(0);

  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);
  pinMode(PIN_IMU_INT, INPUT);

  pinMode(PIN_LED, OUTPUT);
  digitalWrite(PIN_LED, HIGH);
  Wire.begin(PIN_SDA, PIN_SCL);
  imuPresent = imuBegin();
  Serial.printf("IMU %s\n", imuPresent ? "ok" : "missing");

  // Reset (and so switch the heater off) if the control loop ever stalls.
  esp_task_wdt_config_t wdt = {.timeout_ms = 5000, .idle_core_mask = 0, .trigger_panic = true};
  esp_task_wdt_reconfigure(&wdt);
  esp_task_wdt_add(NULL);

  BLEDevice::init(deviceName().c_str());
  BLEDevice::setMTU(185);            // the 64-byte status packet needs more than the 23-byte default
  server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  BLEService *service = server->createService(SERVICE_UUID);
  BLECharacteristic *control = service->createCharacteristic(
      CONTROL_CHAR_UUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE);
  control->setCallbacks(new ControlCallbacks());
  statusChar = service->createCharacteristic(
      STATUS_CHAR_UUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  statusChar->addDescriptor(new BLE2902());
  service->start();
  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();

  Serial.printf("%s ready\n", deviceName().c_str());
}

void loop() {
  esp_task_wdt_reset();

  float sample = readTemperatureF();
  tempSum += sample;
  tempCount++;

  unsigned long now = millis();
  if (now - lastControl >= CONTROL_PERIOD_MS) {
    lastControl = now;
    float temperature = tempSum / tempCount;
    tempSum = 0.0;
    tempCount = 0;

    StatusPacket p = {};
    p.version = 2;
    p.side = side;

    float volts = 0.0, percent = 0.0;
    batteryRead(volts, percent);
    bool haveBattery = volts > 1.0;       // below this the divider is not connected to a cell

    faults = 0;
    if (temperature < MIN_VALID_TEMP_F) faults |= FAULT_SENSOR_OPEN;
    else if (temperature > MAX_VALID_TEMP_F) faults |= FAULT_SENSOR_SHORT;
    else if (temperature > MAX_PAD_TEMP_F) faults |= FAULT_OVER_TEMP;
    if (haveBattery) {
      if (volts < LOW_BATTERY_V) lowBatteryLatched = true;
      else if (volts > LOW_BATTERY_RESUME_V) lowBatteryLatched = false;
    }
    if (lowBatteryLatched) faults |= FAULT_LOW_BATTERY;
    if (usbPresent()) faults |= FAULT_CHARGING;

    float error = setpointF - temperature;
    float derivative = error - lastError;
    lastError = error;

    uint8_t power = 0;
    if (faults != 0) {
      integral = 0.0;
    } else if (mode == MODE_TRACK) {
      integral = constrain(integral + error, -255.0f, 255.0f);
      power = (uint8_t)constrain((int)(KP * error + KI * integral + KD * derivative), 0, 100);
    } else {
      const uint8_t forced[] = {0, 0, 25, 50, 100};
      power = forced[mode];
    }
    setHeater(power);

    p.mode = mode;
    p.faults = faults;
    p.temperature = temperature;
    p.setpoint = setpointF;
    p.error = error;
    p.integral = integral;
    p.derivative = derivative;
    p.heaterPower = heaterPower;
    p.batteryVolts = volts;
    p.batteryPercent = percent;
    imuRead(p);

    statusChar->setValue((uint8_t *)&p, sizeof(p));
    if (deviceConnected) statusChar->notify();

    // Bench log over USB serial, every 2 s.
    static uint8_t logTick = 0;
    if (++logTick >= 4) {
      logTick = 0;
      Serial.printf("T=%.1fF set=%.0fF mode=%u power=%u%% bat=%.2fV usb=%d faults=0x%02X imu=%d ble=%d\n",
                    temperature, setpointF, mode, heaterPower, volts, usbPresent() ? 1 : 0, faults,
                    imuPresent ? 1 : 0, deviceConnected ? 1 : 0);
    }

    // Status LED: solid when a phone is connected, a short blink otherwise, fast blink on a fault.
    static uint8_t tick = 0;
    tick++;
    bool on = (faults & ~FAULT_CHARGING) ? (tick & 1) : deviceConnected ? true : (tick % 6 == 0);
    digitalWrite(PIN_LED, on ? LOW : HIGH);
  }

  delay(50);
}
