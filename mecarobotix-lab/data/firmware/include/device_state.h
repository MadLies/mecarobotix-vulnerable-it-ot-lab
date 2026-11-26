#pragma once

#include <Arduino.h>
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

struct DeviceState {
    char robotId[32];
    char robotType[32];
    char firmwareVersion[32];
    char state[32];

    char diagnosticServerBaseUrl[128];

    float temperature;
    float vibration;

    bool registered;
    bool restartRequested;

    unsigned long uptimeMs;
    unsigned long lastTelemetryMs;
    unsigned long lastFirmwareCheckMs;

    int lastDiagnosticHttpCode;
};

void initDeviceState();
void updateSimulatedTelemetry();
void getDeviceStateSnapshot(DeviceState *out);

void setRegistered(bool value);
void setLastDiagnosticHttpCode(int code);
void setFirmwareVersion(const char *version);
void setDiagnosticServerBaseUrl(const char *url);
void requestRestart();