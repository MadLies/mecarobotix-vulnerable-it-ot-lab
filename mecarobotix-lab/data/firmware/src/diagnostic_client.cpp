#include "diagnostic_client.h"
#include "config.h"
#include "device_state.h"
#include "pki_material.h"

#include <Arduino.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>

static String diagnosticUrl(const String &pathAndQuery) {
    DeviceState state;
    getDeviceStateSnapshot(&state);

    return String(state.diagnosticServerBaseUrl) + pathAndQuery;
}

static void configureTls(WiFiClientSecure &client) {
    client.setCACert(MECAROBOTIX_CA_CERT);
    client.setCertificate(ROBOT_CLIENT_CERT);
    client.setPrivateKey(ROBOT_CLIENT_KEY);
}

static int httpGet(const String &url, String *responseOut = nullptr) {
    WiFiClientSecure client;
    configureTls(client);

    HTTPClient http;
    http.begin(client, url);

    int code = http.GET();

    if (responseOut) {
        *responseOut = http.getString();
    }

    Serial.printf("[diagnostic-client] GET %s -> HTTP %d\n", url.c_str(), code);

    if (responseOut && responseOut->length() > 0) {
        Serial.printf("[diagnostic-client] response: %s\n", responseOut->c_str());
    }

    http.end();

    setLastDiagnosticHttpCode(code);
    return code;
}

static int httpPostJson(const String &url, const String &jsonBody, String *responseOut = nullptr) {
    WiFiClientSecure client;
    configureTls(client);

    HTTPClient http;
    http.begin(client, url);
    http.addHeader("Content-Type", "application/json");

    int code = http.POST(jsonBody);

    if (responseOut) {
        *responseOut = http.getString();
    }

    Serial.printf("[diagnostic-client] POST %s -> HTTP %d\n", url.c_str(), code);
    Serial.printf("[diagnostic-client] body: %s\n", jsonBody.c_str());

    if (responseOut && responseOut->length() > 0) {
        Serial.printf("[diagnostic-client] response: %s\n", responseOut->c_str());
    }

    http.end();

    setLastDiagnosticHttpCode(code);
    return code;
}

int requestLatestFirmwareFromDiagnosticServer(String *responseOut) {
    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("[diagnostic-client] cannot request firmware: Wi-Fi not connected");

        if (responseOut) {
            *responseOut = "{\"error\":\"wifi_not_connected\"}";
        }

        setLastDiagnosticHttpCode(-1);
        return -1;
    }

    String url = diagnosticUrl(
        String("/api/firmware/latest?robot_type=") + ROBOT_TYPE
    );

    return httpGet(url, responseOut);
}

static void registerRobot() {
    String url = diagnosticUrl(
        String("/api/robots/register?robot_id=") + ROBOT_ID +
        "&robot_type=" + ROBOT_TYPE
    );

    String response;
    int code = httpPostJson(url, "{}", &response);

    if (code == 200) {
        setRegistered(true);
        Serial.println("[diagnostic-client] robot registered successfully");
    } else {
        Serial.println("[diagnostic-client] robot registration failed");
    }
}

static void checkLatestFirmware() {
    String response;
    requestLatestFirmwareFromDiagnosticServer(&response);
}

static void sendTelemetry() {
    DeviceState state;
    getDeviceStateSnapshot(&state);

    String url = diagnosticUrl("/api/telemetry");

    String body = "{";
    body += "\"robot_id\":\"" + String(state.robotId) + "\",";
    body += "\"robot_type\":\"" + String(state.robotType) + "\",";
    body += "\"firmware\":\"" + String(state.firmwareVersion) + "\",";
    body += "\"temperature\":" + String(state.temperature, 2) + ",";
    body += "\"vibration\":" + String(state.vibration, 2) + ",";
    body += "\"uptime_ms\":" + String(state.uptimeMs);
    body += "}";

    String response;
    httpPostJson(url, body, &response);
}

static void fetchLabConfigOnce() {
    String url = diagnosticUrl("/api/lab/config");

    String response;
    httpGet(url, &response);
}

void diagnosticClientTask(void *parameter) {
    Serial.println("[diagnostic-client] task started");

    bool labConfigFetched = false;
    unsigned long lastTelemetry = 0;
    unsigned long lastFirmwareCheck = 0;

    while (true) {
        if (WiFi.status() != WL_CONNECTED) {
            Serial.println("[diagnostic-client] Wi-Fi not connected, waiting...");
            vTaskDelay(pdMS_TO_TICKS(1000));
            continue;
        }

        DeviceState state;
        getDeviceStateSnapshot(&state);

        if (!state.registered) {
            registerRobot();
        }

        if (!labConfigFetched) {
            fetchLabConfigOnce();
            labConfigFetched = true;
        }

        unsigned long now = millis();

        if (now - lastFirmwareCheck >= FIRMWARE_CHECK_INTERVAL_MS) {
            checkLatestFirmware();
            lastFirmwareCheck = now;
        }

        if (now - lastTelemetry >= TELEMETRY_INTERVAL_MS) {
            updateSimulatedTelemetry();
            sendTelemetry();
            lastTelemetry = now;
        }

        vTaskDelay(pdMS_TO_TICKS(500));
    }
}
