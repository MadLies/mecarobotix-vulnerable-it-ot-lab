#include "device_state.h"
#include "config.h"

#include <string.h>

static DeviceState g_state;
static SemaphoreHandle_t g_stateMutex = nullptr;

void initDeviceState() {
    g_stateMutex = xSemaphoreCreateMutex();

    xSemaphoreTake(g_stateMutex, portMAX_DELAY);

    snprintf(g_state.robotId, sizeof(g_state.robotId), "%s", ROBOT_ID);
    snprintf(g_state.robotType, sizeof(g_state.robotType), "%s", ROBOT_TYPE);
    snprintf(g_state.firmwareVersion, sizeof(g_state.firmwareVersion), "%s", FIRMWARE_VERSION);
    snprintf(g_state.state, sizeof(g_state.state), "idle");

    snprintf(
        g_state.diagnosticServerBaseUrl,
        sizeof(g_state.diagnosticServerBaseUrl),
        "%s",
        DIAGNOSTIC_SERVER_DEFAULT_URL
    );

    g_state.temperature = 32.0f;
    g_state.vibration = 0.1f;

    g_state.registered = false;
    g_state.restartRequested = false;

    g_state.uptimeMs = 0;
    g_state.lastTelemetryMs = 0;
    g_state.lastFirmwareCheckMs = 0;
    g_state.lastDiagnosticHttpCode = 0;

    xSemaphoreGive(g_stateMutex);
}

void updateSimulatedTelemetry() {
    if (!g_stateMutex) {
        return;
    }

    xSemaphoreTake(g_stateMutex, portMAX_DELAY);

    g_state.temperature = random(3200, 5500) / 100.0f;
    g_state.vibration = random(10, 150) / 100.0f;
    g_state.uptimeMs = millis();

    xSemaphoreGive(g_stateMutex);
}

void getDeviceStateSnapshot(DeviceState *out) {
    if (!out || !g_stateMutex) {
        return;
    }

    xSemaphoreTake(g_stateMutex, portMAX_DELAY);
    memcpy(out, &g_state, sizeof(DeviceState));
    xSemaphoreGive(g_stateMutex);
}

void setRegistered(bool value) {
    if (!g_stateMutex) {
        return;
    }

    xSemaphoreTake(g_stateMutex, portMAX_DELAY);
    g_state.registered = value;
    xSemaphoreGive(g_stateMutex);
}

void setLastDiagnosticHttpCode(int code) {
    if (!g_stateMutex) {
        return;
    }

    xSemaphoreTake(g_stateMutex, portMAX_DELAY);
    g_state.lastDiagnosticHttpCode = code;
    xSemaphoreGive(g_stateMutex);
}

void setFirmwareVersion(const char *version) {
    if (!version || !g_stateMutex) {
        return;
    }

    xSemaphoreTake(g_stateMutex, portMAX_DELAY);
    snprintf(g_state.firmwareVersion, sizeof(g_state.firmwareVersion), "%s", version);
    xSemaphoreGive(g_stateMutex);
}

void setDiagnosticServerBaseUrl(const char *url) {
    if (!url || !g_stateMutex) {
        return;
    }

    xSemaphoreTake(g_stateMutex, portMAX_DELAY);
    snprintf(g_state.diagnosticServerBaseUrl, sizeof(g_state.diagnosticServerBaseUrl), "%s", url);
    xSemaphoreGive(g_stateMutex);
}

void requestRestart() {
    if (!g_stateMutex) {
        return;
    }

    xSemaphoreTake(g_stateMutex, portMAX_DELAY);
    g_state.restartRequested = true;
    snprintf(g_state.state, sizeof(g_state.state), "restart_requested");
    xSemaphoreGive(g_stateMutex);
}