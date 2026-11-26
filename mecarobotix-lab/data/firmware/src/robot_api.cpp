#include "robot_api.h"
#include "config.h"
#include "device_state.h"
#include "diagnostic_client.h"
#include "pki_material.h"

#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <WiFiServer.h>
#include <ctype.h>
#include <string.h>

#include "mbedtls/ctr_drbg.h"
#include "mbedtls/entropy.h"
#include "mbedtls/error.h"
#include "mbedtls/net_sockets.h"
#include "mbedtls/pk.h"
#include "mbedtls/ssl.h"
#include "mbedtls/x509_crt.h"

static WebServer httpServer(ROBOT_HTTP_PORT);
static WiFiServer tlsServer(ROBOT_HTTPS_PORT);
static bool tlsReady = false;

static mbedtls_entropy_context entropy;
static mbedtls_ctr_drbg_context ctrDrbg;
static mbedtls_ssl_config sslConfig;
static mbedtls_x509_crt caCert;
static mbedtls_x509_crt serverCert;
static mbedtls_pk_context serverKey;

struct TlsHttpRequest {
    String method;
    String path;
    String query;
    String body;
    String clientCn;
};

static void sendHttpJson(int statusCode, const String &body) {
    httpServer.sendHeader("Access-Control-Allow-Origin", "*");
    httpServer.send(statusCode, "application/json", body);
}

static bool isValidDiagnosticUrl(const String &url) {
    return url.startsWith("http://") || url.startsWith("https://");
}

static String jsonRoot() {
    DeviceState state;
    getDeviceStateSnapshot(&state);

    String body = "{";
    body += "\"robot_id\":\"" + String(state.robotId) + "\",";
    body += "\"robot_type\":\"" + String(state.robotType) + "\",";
    body += "\"service\":\"robot-api\"";
    body += "}";

    return body;
}

static String jsonHealth() {
    DeviceState state;
    getDeviceStateSnapshot(&state);

    String body = "{";
    body += "\"status\":\"ok\",";
    body += "\"robot_id\":\"" + String(state.robotId) + "\",";
    body += "\"ip\":\"" + WiFi.localIP().toString() + "\"";
    body += "}";

    return body;
}

static String jsonStatus() {
    DeviceState state;
    getDeviceStateSnapshot(&state);

    String body = "{";
    body += "\"robot_id\":\"" + String(state.robotId) + "\",";
    body += "\"robot_type\":\"" + String(state.robotType) + "\",";
    body += "\"state\":\"" + String(state.state) + "\",";
    body += "\"firmware\":\"" + String(state.firmwareVersion) + "\",";
    body += "\"diagnostic_server\":\"" + String(state.diagnosticServerBaseUrl) + "\",";
    body += "\"registered\":" + String(state.registered ? "true" : "false") + ",";
    body += "\"last_diagnostic_http_code\":" + String(state.lastDiagnosticHttpCode) + ",";
    body += "\"uptime_ms\":" + String(state.uptimeMs);
    body += "}";

    return body;
}

static String jsonTelemetry() {
    updateSimulatedTelemetry();

    DeviceState state;
    getDeviceStateSnapshot(&state);

    String body = "{";
    body += "\"robot_id\":\"" + String(state.robotId) + "\",";
    body += "\"robot_type\":\"" + String(state.robotType) + "\",";
    body += "\"temperature\":" + String(state.temperature, 2) + ",";
    body += "\"vibration\":" + String(state.vibration, 2) + ",";
    body += "\"diagnostic_url\":\"" + String(state.diagnosticServerBaseUrl) + "/api/telemetry\"";
    body += "}";

    return body;
}

static String jsonUpdateFirmware(const String &authorizedClient = "") {
    digitalWrite(BUILTIN_LED_PIN, HIGH);

    String diagnosticResponse;
    int diagnosticHttpCode = requestLatestFirmwareFromDiagnosticServer(&diagnosticResponse);

    digitalWrite(BUILTIN_LED_PIN, LOW);

    DeviceState state;
    getDeviceStateSnapshot(&state);

    String body = "{";
    body += "\"robot_id\":\"" + String(state.robotId) + "\",";
    body += "\"robot_type\":\"" + String(state.robotType) + "\",";
    body += "\"update_check_requested\":true,";
    body += "\"led_triggered\":true,";
    body += "\"diagnostic_auth\":\"mTLS_client_certificate\",";
    body += "\"diagnostic_http_code\":" + String(diagnosticHttpCode) + ",";
    body += "\"diagnostic_server\":\"" + String(state.diagnosticServerBaseUrl) + "\",";
    body += "\"diagnostic_response\":";

    if (diagnosticResponse.length() > 0) {
        body += diagnosticResponse;
    } else {
        body += "null";
    }

    if (authorizedClient.length() > 0) {
        body += ",\"authorized_client\":\"" + authorizedClient + "\"";
    }

    body += "}";
    return body;
}

static String jsonSetDiagnosticServer(const String &newUrl) {
    if (newUrl.length() == 0) {
        return "{\"error\":\"missing url parameter\"}";
    }

    if (!isValidDiagnosticUrl(newUrl)) {
        return "{\"error\":\"invalid url. Use http:// or https://\"}";
    }

    setDiagnosticServerBaseUrl(newUrl.c_str());

    DeviceState state;
    getDeviceStateSnapshot(&state);

    String body = "{";
    body += "\"updated\":true,";
    body += "\"diagnostic_server\":\"" + String(state.diagnosticServerBaseUrl) + "\"";
    body += "}";

    return body;
}

static String jsonRestart() {
    requestRestart();

    DeviceState state;
    getDeviceStateSnapshot(&state);

    String body = "{";
    body += "\"robot_id\":\"" + String(state.robotId) + "\",";
    body += "\"restart\":\"accepted\"";
    body += "}";

    return body;
}

static void handleRoot() {
    sendHttpJson(200, jsonRoot());
}

static void handleHealth() {
    sendHttpJson(200, jsonHealth());
}

static void handleStatus() {
    sendHttpJson(200, jsonStatus());
}

static void handleTelemetry() {
    sendHttpJson(200, jsonTelemetry());
}

static void handleUpdateFirmware() {
    sendHttpJson(200, jsonUpdateFirmware());
}

static void handleSetDiagnosticServer() {
    String newUrl;

    if (httpServer.hasArg("url")) {
        newUrl = httpServer.arg("url");
    }

    String body = jsonSetDiagnosticServer(newUrl);
    sendHttpJson(body.startsWith("{\"error\"") ? 400 : 200, body);
}

static void handleRestart() {
    sendHttpJson(200, jsonRestart());
}

static void handleNotFound() {
    sendHttpJson(404, "{\"error\":\"not found\"}");
}

static int tlsSend(void *ctx, const unsigned char *buf, size_t len) {
    WiFiClient *client = static_cast<WiFiClient *>(ctx);
    size_t written = client->write(buf, len);

    if (written == 0) {
        return MBEDTLS_ERR_SSL_WANT_WRITE;
    }

    return (int)written;
}

static int tlsRecv(void *ctx, unsigned char *buf, size_t len) {
    WiFiClient *client = static_cast<WiFiClient *>(ctx);
    unsigned long deadline = millis() + 5000;

    while (client->connected() && !client->available()) {
        if ((long)(millis() - deadline) > 0) {
            return MBEDTLS_ERR_SSL_TIMEOUT;
        }
        delay(1);
    }

    if (!client->connected() && !client->available()) {
        return MBEDTLS_ERR_NET_CONN_RESET;
    }

    int received = client->read(buf, len);

    if (received <= 0) {
        return MBEDTLS_ERR_SSL_WANT_READ;
    }

    return received;
}

static bool tlsWriteAll(mbedtls_ssl_context &ssl, const String &data) {
    const unsigned char *buf = reinterpret_cast<const unsigned char *>(data.c_str());
    size_t remaining = data.length();

    while (remaining > 0) {
        int written = mbedtls_ssl_write(&ssl, buf, remaining);

        if (written == MBEDTLS_ERR_SSL_WANT_READ || written == MBEDTLS_ERR_SSL_WANT_WRITE) {
            delay(1);
            continue;
        }

        if (written <= 0) {
            return false;
        }

        buf += written;
        remaining -= (size_t)written;
    }

    return true;
}

static void tlsSendJson(mbedtls_ssl_context &ssl, int statusCode, const char *statusText, const String &body) {
    String response = "HTTP/1.1 ";
    response += String(statusCode);
    response += " ";
    response += statusText;
    response += "\r\nContent-Type: application/json\r\nContent-Length: ";
    response += String(body.length());
    response += "\r\nConnection: close\r\n\r\n";
    response += body;

    tlsWriteAll(ssl, response);
}

static String getHeaderValue(const String &raw, const String &headerName) {
    String lower = raw;
    lower.toLowerCase();

    String needle = "\r\n" + headerName;
    needle.toLowerCase();
    needle += ":";

    int start = lower.indexOf(needle);
    if (start < 0) {
        return "";
    }

    start += needle.length();
    int end = raw.indexOf("\r\n", start);
    if (end < 0) {
        return "";
    }

    String value = raw.substring(start, end);
    value.trim();
    return value;
}

static bool tlsReadRawRequest(mbedtls_ssl_context &ssl, String &raw) {
    unsigned char buf[512];
    int headerEnd = -1;
    int contentLength = 0;

    while (raw.length() < 4096) {
        int received = mbedtls_ssl_read(&ssl, buf, sizeof(buf));

        if (received == MBEDTLS_ERR_SSL_WANT_READ || received == MBEDTLS_ERR_SSL_WANT_WRITE) {
            delay(1);
            continue;
        }

        if (received <= 0) {
            return false;
        }

        char chunk[513];
        memcpy(chunk, buf, received);
        chunk[received] = '\0';
        raw += chunk;
        headerEnd = raw.indexOf("\r\n\r\n");

        if (headerEnd >= 0) {
            String contentLengthHeader = getHeaderValue(raw, "Content-Length");
            contentLength = contentLengthHeader.length() ? contentLengthHeader.toInt() : 0;

            if (raw.length() >= headerEnd + 4 + contentLength) {
                return true;
            }
        }
    }

    return false;
}

static bool parseTlsRequest(const String &raw, TlsHttpRequest &request) {
    int firstLineEnd = raw.indexOf("\r\n");
    if (firstLineEnd < 0) {
        return false;
    }

    String firstLine = raw.substring(0, firstLineEnd);
    int firstSpace = firstLine.indexOf(' ');
    int secondSpace = firstLine.indexOf(' ', firstSpace + 1);

    if (firstSpace < 0 || secondSpace < 0) {
        return false;
    }

    request.method = firstLine.substring(0, firstSpace);
    String target = firstLine.substring(firstSpace + 1, secondSpace);
    int qmark = target.indexOf('?');

    if (qmark >= 0) {
        request.path = target.substring(0, qmark);
        request.query = target.substring(qmark + 1);
    } else {
        request.path = target;
        request.query = "";
    }

    int headerEnd = raw.indexOf("\r\n\r\n");
    request.body = headerEnd >= 0 ? raw.substring(headerEnd + 4) : "";
    return true;
}

static int hexValue(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static String urlDecode(const String &value) {
    String decoded;

    for (size_t i = 0; i < value.length(); i++) {
        char c = value[i];

        if (c == '+' ) {
            decoded += ' ';
        } else if (c == '%' && i + 2 < value.length()) {
            int hi = hexValue(value[i + 1]);
            int lo = hexValue(value[i + 2]);

            if (hi >= 0 && lo >= 0) {
                decoded += char((hi << 4) | lo);
                i += 2;
            } else {
                decoded += c;
            }
        } else {
            decoded += c;
        }
    }

    return decoded;
}

static String getParamFromPairs(const String &pairs, const String &key) {
    int start = 0;

    while (start < (int)pairs.length()) {
        int end = pairs.indexOf('&', start);
        if (end < 0) {
            end = pairs.length();
        }

        String pair = pairs.substring(start, end);
        int equals = pair.indexOf('=');

        if (equals >= 0 && urlDecode(pair.substring(0, equals)) == key) {
            return urlDecode(pair.substring(equals + 1));
        }

        start = end + 1;
    }

    return "";
}

static String getRequestParam(const TlsHttpRequest &request, const String &key) {
    String value = getParamFromPairs(request.query, key);

    if (value.length() > 0) {
        return value;
    }

    return getParamFromPairs(request.body, key);
}

static bool extractCommonName(const char *subject, String &commonName) {
    if (!subject) {
        return false;
    }

    String dn(subject);
    int start = dn.indexOf("CN=");

    if (start < 0) {
        return false;
    }

    start += 3;
    int comma = dn.indexOf(',', start);
    int slash = dn.indexOf('/', start);
    int end = dn.length();

    if (comma >= 0) end = min(end, comma);
    if (slash >= 0) end = min(end, slash);

    commonName = dn.substring(start, end);
    commonName.trim();
    return commonName.length() > 0;
}

static bool getPeerCommonName(mbedtls_ssl_context &ssl, String &commonName) {
    const mbedtls_x509_crt *peer = mbedtls_ssl_get_peer_cert(&ssl);

    if (!peer) {
        return false;
    }

    char subject[512];
    int n = mbedtls_x509_dn_gets(subject, sizeof(subject), &peer->subject);

    if (n <= 0) {
        return false;
    }

    return extractCommonName(subject, commonName);
}

static bool isAllowedManagementClient(const String &clientCn) {
    String allowed = ROBOT_MTLS_MANAGEMENT_CLIENTS;
    allowed.replace(",", " ");

    int start = 0;

    while (start < (int)allowed.length()) {
        while (start < (int)allowed.length() && isspace((unsigned char)allowed[start])) {
            start++;
        }

        int end = start;
        while (end < (int)allowed.length() && !isspace((unsigned char)allowed[end])) {
            end++;
        }

        if (allowed.substring(start, end) == clientCn) {
            return true;
        }

        start = end + 1;
    }

    return false;
}

static void handleTlsRequest(mbedtls_ssl_context &ssl, const TlsHttpRequest &request) {
    bool managementClient = isAllowedManagementClient(request.clientCn);

    if (request.method == "GET" && request.path == "/") {
        tlsSendJson(ssl, 200, "OK", jsonRoot());
    } else if (request.method == "GET" && request.path == "/health") {
        tlsSendJson(ssl, 200, "OK", jsonHealth());
    } else if (request.method == "GET" && request.path == "/status") {
        tlsSendJson(ssl, 200, "OK", jsonStatus());
    } else if (request.method == "GET" && request.path == "/telemetry") {
        tlsSendJson(ssl, 200, "OK", jsonTelemetry());
    } else if (request.method == "GET" && request.path == "/update-firmware") {
        if (!managementClient) {
            tlsSendJson(ssl, 401, "Unauthorized", "{\"error\":\"unauthorized client certificate\"}");
            return;
        }
        tlsSendJson(ssl, 200, "OK", jsonUpdateFirmware(request.clientCn));
    } else if (request.method == "POST" && request.path == "/diagnostic-server") {
        if (!managementClient) {
            tlsSendJson(ssl, 401, "Unauthorized", "{\"error\":\"unauthorized client certificate\"}");
            return;
        }

        String body = jsonSetDiagnosticServer(getRequestParam(request, "url"));
        tlsSendJson(ssl, body.startsWith("{\"error\"") ? 400 : 200, body.startsWith("{\"error\"") ? "Bad Request" : "OK", body);
    } else if (request.method == "POST" && request.path == "/restart") {
        if (!managementClient) {
            tlsSendJson(ssl, 401, "Unauthorized", "{\"error\":\"unauthorized client certificate\"}");
            return;
        }
        tlsSendJson(ssl, 200, "OK", jsonRestart());
    } else {
        tlsSendJson(ssl, 404, "Not Found", "{\"error\":\"not found\"}");
    }
}

static bool initTlsServer() {
    mbedtls_entropy_init(&entropy);
    mbedtls_ctr_drbg_init(&ctrDrbg);
    mbedtls_ssl_config_init(&sslConfig);
    mbedtls_x509_crt_init(&caCert);
    mbedtls_x509_crt_init(&serverCert);
    mbedtls_pk_init(&serverKey);

    const char *personalization = "mecarobotix-esp32-server";
    int ret = mbedtls_ctr_drbg_seed(
        &ctrDrbg,
        mbedtls_entropy_func,
        &entropy,
        reinterpret_cast<const unsigned char *>(personalization),
        strlen(personalization)
    );

    if (ret != 0) {
        Serial.printf("[robot-api] ctr_drbg_seed failed: -0x%04x\n", -ret);
        return false;
    }

    ret = mbedtls_x509_crt_parse(
        &caCert,
        reinterpret_cast<const unsigned char *>(MECAROBOTIX_CA_CERT),
        strlen(MECAROBOTIX_CA_CERT) + 1
    );
    if (ret != 0) {
        Serial.printf("[robot-api] CA parse failed: -0x%04x\n", -ret);
        return false;
    }

    ret = mbedtls_x509_crt_parse(
        &serverCert,
        reinterpret_cast<const unsigned char *>(ROBOT_SERVER_CERT),
        strlen(ROBOT_SERVER_CERT) + 1
    );
    if (ret != 0) {
        Serial.printf("[robot-api] server cert parse failed: -0x%04x\n", -ret);
        return false;
    }

    ret = mbedtls_pk_parse_key(
        &serverKey,
        reinterpret_cast<const unsigned char *>(ROBOT_SERVER_KEY),
        strlen(ROBOT_SERVER_KEY) + 1,
        nullptr,
        0
    );
    if (ret != 0) {
        Serial.printf("[robot-api] server key parse failed: -0x%04x\n", -ret);
        return false;
    }

    ret = mbedtls_ssl_config_defaults(
        &sslConfig,
        MBEDTLS_SSL_IS_SERVER,
        MBEDTLS_SSL_TRANSPORT_STREAM,
        MBEDTLS_SSL_PRESET_DEFAULT
    );
    if (ret != 0) {
        Serial.printf("[robot-api] ssl config defaults failed: -0x%04x\n", -ret);
        return false;
    }

    mbedtls_ssl_conf_rng(&sslConfig, mbedtls_ctr_drbg_random, &ctrDrbg);
    mbedtls_ssl_conf_authmode(&sslConfig, MBEDTLS_SSL_VERIFY_REQUIRED);
    mbedtls_ssl_conf_ca_chain(&sslConfig, &caCert, nullptr);

    ret = mbedtls_ssl_conf_own_cert(&sslConfig, &serverCert, &serverKey);
    if (ret != 0) {
        Serial.printf("[robot-api] own cert config failed: -0x%04x\n", -ret);
        return false;
    }

    tlsServer.begin();
    return true;
}

static void handleSecureClient(WiFiClient client) {
    mbedtls_ssl_context ssl;
    mbedtls_ssl_init(&ssl);

    int ret = mbedtls_ssl_setup(&ssl, &sslConfig);
    if (ret != 0) {
        Serial.printf("[robot-api] ssl setup failed: -0x%04x\n", -ret);
        mbedtls_ssl_free(&ssl);
        client.stop();
        return;
    }

    mbedtls_ssl_set_bio(&ssl, &client, tlsSend, tlsRecv, nullptr);

    while ((ret = mbedtls_ssl_handshake(&ssl)) != 0) {
        if (ret != MBEDTLS_ERR_SSL_WANT_READ && ret != MBEDTLS_ERR_SSL_WANT_WRITE) {
            Serial.printf("[robot-api] TLS handshake failed: -0x%04x\n", -ret);
            mbedtls_ssl_free(&ssl);
            client.stop();
            return;
        }
        delay(1);
    }

    uint32_t verifyResult = mbedtls_ssl_get_verify_result(&ssl);
    if (verifyResult != 0) {
        Serial.printf("[robot-api] client certificate verification failed: 0x%08lx\n", (unsigned long)verifyResult);
        tlsSendJson(ssl, 401, "Unauthorized", "{\"error\":\"invalid client certificate\"}");
        mbedtls_ssl_close_notify(&ssl);
        mbedtls_ssl_free(&ssl);
        client.stop();
        return;
    }

    TlsHttpRequest request;
    if (!getPeerCommonName(ssl, request.clientCn)) {
        tlsSendJson(ssl, 401, "Unauthorized", "{\"error\":\"missing client certificate identity\"}");
        mbedtls_ssl_close_notify(&ssl);
        mbedtls_ssl_free(&ssl);
        client.stop();
        return;
    }

    String raw;
    if (!tlsReadRawRequest(ssl, raw) || !parseTlsRequest(raw, request)) {
        tlsSendJson(ssl, 400, "Bad Request", "{\"error\":\"bad request\"}");
    } else {
        handleTlsRequest(ssl, request);
    }

    mbedtls_ssl_close_notify(&ssl);
    mbedtls_ssl_free(&ssl);
    client.stop();
}

void startRobotApi() {
    httpServer.on("/", HTTP_GET, handleRoot);
    httpServer.on("/health", HTTP_GET, handleHealth);
    httpServer.on("/status", HTTP_GET, handleStatus);
    httpServer.on("/telemetry", HTTP_GET, handleTelemetry);
    httpServer.on("/update-firmware", HTTP_GET, handleUpdateFirmware);
    httpServer.on("/diagnostic-server", HTTP_POST, handleSetDiagnosticServer);
    httpServer.on("/restart", HTTP_POST, handleRestart);
    httpServer.onNotFound(handleNotFound);

    httpServer.begin();
    tlsReady = initTlsServer();

    Serial.printf("[robot-api] HTTP server started on port %d\n", ROBOT_HTTP_PORT);
    Serial.print("[robot-api] Local HTTP API: http://");
    Serial.println(WiFi.localIP());

    if (tlsReady) {
        Serial.printf("[robot-api] HTTPS+mTLS server started on port %d\n", ROBOT_HTTPS_PORT);
        Serial.print("[robot-api] Local HTTPS API: https://");
        Serial.print(WiFi.localIP());
        Serial.printf(":%d\n", ROBOT_HTTPS_PORT);
    } else {
        Serial.println("[robot-api] HTTPS+mTLS server failed to start");
    }
}

void robotApiTask(void *parameter) {
    Serial.println("[robot-api] task started");

    while (true) {
        httpServer.handleClient();

        if (tlsReady) {
            WiFiClient client = tlsServer.available();
            if (client) {
                handleSecureClient(client);
            }
        }

        vTaskDelay(pdMS_TO_TICKS(10));
    }
}
