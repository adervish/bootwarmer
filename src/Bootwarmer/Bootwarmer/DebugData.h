#ifndef DebugData_h
#define DebugData_h

#include <stdint.h>

// Packed struct to match embedded controller's debug data layout
typedef struct __attribute__((packed)) {
    float temperatureR;
    float errorR;
    float integralR;
    float derivativeR;
    uint8_t heaterPowerR;
    float temperatureL;
    float errorL;
    float integralL;
    float derivativeL;
    uint8_t heaterPowerL;
} DebugData;

#endif /* DebugData_h */
