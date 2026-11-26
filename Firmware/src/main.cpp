#include <Arduino.h>
#include <WiFi.h>
#include "esp_system.h"

#include "config.h"
#include "device_state.h"
#include "diagnostic_client.h"
#include "robot_api.h"

static void connectWiFi() {
    Serial.printf("[wifi] connecting to SSID: %s\n", WIFI_SSID);

    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

    while (WiFi.status() != WL_CONNECTED) {
        Serial.print(".");
        delay(WIFI_RETRY_DELAY_MS);
    }

    Serial.println();
    Serial.println("[wifi] connected");
    Serial.print("[wifi] IP address: ");
    Serial.println(WiFi.localIP());
}

void setup() {
    Serial.begin(115200);
    delay(1000);

    pinMode(BUILTIN_LED_PIN, OUTPUT);
    digitalWrite(BUILTIN_LED_PIN, LOW);

    Serial.println();
    Serial.println("==========================================");
    Serial.println("MecaRobotix ESP32 Firmware");
    Serial.println("Version: 1.0.0-lab");
    Serial.println("Mode: dual-task diagnostic + robot API");
    Serial.println("==========================================");

    randomSeed(esp_random());

    initDeviceState();
    connectWiFi();

    startRobotApi();

    xTaskCreatePinnedToCore(
        diagnosticClientTask,
        "diagnostic_client",
        8192,
        nullptr,
        1,
        nullptr,
        0
    );

    xTaskCreatePinnedToCore(
        robotApiTask,
        "robot_api",
        4096,
        nullptr,
        1,
        nullptr,
        1
    );
}

void loop() {
    DeviceState state;
    getDeviceStateSnapshot(&state);

    if (state.restartRequested) {
        Serial.println("[main] restart requested, rebooting in 2 seconds...");
        delay(2000);
        ESP.restart();
    }

    delay(1000);
}