#pragma once

// ==========================
// Wi-Fi configuration
// ==========================

#define WIFI_SSID "YOUR_WIFI_SSID"
#define WIFI_PASSWORD "YOUR_WIFI_PASSWORD"

// ==========================
// Hardware
// ==========================

#define BUILTIN_LED_PIN 2

// ==========================
// Diagnostic server
// ==========================

#define DIAGNOSTIC_SERVER_DEFAULT_URL "https://10.93.22.136:8443"
#define ROBOT_HTTP_PORT 80
#define ROBOT_HTTPS_PORT 8443
#define ROBOT_MTLS_MANAGEMENT_CLIENTS "ci-server ot-maintenance ot-supervision"

// ==========================
// Robot identity
// ==========================

#define ROBOT_ID "mrx-esp32-001"
#define ROBOT_TYPE "madliesChiquito"
#define FIRMWARE_VERSION "1.0.0-lab"

// ==========================
// Task intervals
// ==========================

#define TELEMETRY_INTERVAL_MS 10000
#define FIRMWARE_CHECK_INTERVAL_MS 30000
#define WIFI_RETRY_DELAY_MS 1000
