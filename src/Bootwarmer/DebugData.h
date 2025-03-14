#ifndef DebugData_h
#define DebugData_h

#include <stdint.h>

// Packed struct to match embedded controller's debug data layout
typedef struct __attribute__((packed)) {
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
} DebugData;

#endif /* DebugData_h */
