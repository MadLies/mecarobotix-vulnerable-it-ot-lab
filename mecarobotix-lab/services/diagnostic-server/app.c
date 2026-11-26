#define _GNU_SOURCE

#include <arpa/inet.h>
#include <ctype.h>
#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define REQ_BUF_SIZE 8192
#define SMALL_BUF 256

static char robot_type_global[64];

static const char *env_or_default(const char *name, const char *fallback) {
    const char *value = getenv(name);
    return value && value[0] ? value : fallback;
}

static void send_response(int client, int status, const char *status_text, const char *body) {
    char header[1024];
    size_t body_len = strlen(body);

    int n = snprintf(
        header,
        sizeof(header),
        "HTTP/1.1 %d %s\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: %zu\r\n"
        "Connection: close\r\n"
        "\r\n",
        status,
        status_text,
        body_len
    );

    if (n > 0) {
        send(client, header, (size_t)n, 0);
        send(client, body, body_len, 0);
    }
}

static int hex_value(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static size_t url_decode_bytes(char *dst, size_t dst_size, const char *src, size_t src_len) {
    size_t di = 0;

    for (size_t si = 0; si < src_len && di + 1 < dst_size; si++) {
        if (
            src[si] == '%' &&
            si + 2 < src_len &&
            isxdigit((unsigned char)src[si + 1]) &&
            isxdigit((unsigned char)src[si + 2])
        ) {
            int hi = hex_value(src[si + 1]);
            int lo = hex_value(src[si + 2]);
            dst[di++] = (char)((hi << 4) | lo);
            si += 2;
        } else if (src[si] == '+') {
            dst[di++] = ' ';
        } else {
            dst[di++] = src[si];
        }
    }

    dst[di] = '\0';
    return di;
}

static int contains_percent_escape(const char *buf, size_t len) {
    for (size_t i = 0; i + 2 < len; i++) {
        if (
            buf[i] == '%' &&
            isxdigit((unsigned char)buf[i + 1]) &&
            isxdigit((unsigned char)buf[i + 2])
        ) {
            return 1;
        }
    }

    return 0;
}

static void url_decode(char *dst, size_t dst_size, const char *src, size_t src_len) {
    char once[500];
    size_t once_len = url_decode_bytes(once, sizeof(once), src, src_len);

    if (contains_percent_escape(once, once_len)) {
        url_decode_bytes(dst, dst_size, once, once_len);
        return;
    }

    size_t copy_len = once_len;

    if (copy_len >= dst_size) {
        copy_len = dst_size - 1;
    }

    memcpy(dst, once, copy_len);
    dst[copy_len] = '\0';
}

static void get_query_param(
    const char *query,
    const char *key,
    char *out,
    size_t out_size,
    const char *fallback
) {
    if (!out || out_size == 0) return;

    snprintf(out, out_size, "%s", fallback);

    if (!query || !key) return;

    size_t key_len = strlen(key);
    const char *p = query;

    while (*p) {
        if (strncmp(p, key, key_len) == 0 && p[key_len] == '=') {
            const char *value_start = p + key_len + 1;
            const char *value_end = strchr(value_start, '&');

            char encoded[500];
            size_t len = value_end ? (size_t)(value_end - value_start) : strlen(value_start);

            if (len >= sizeof(encoded)) {
                len = sizeof(encoded) - 1;
            }

            memcpy(encoded, value_start, len);
            encoded[len] = '\0';

            url_decode(out, out_size, encoded, len);
            return;
        }

        p = strchr(p, '&');
        if (!p) break;
        p++;
    }
}

static void get_header_value(
    const char *request,
    const char *header_name,
    char *out,
    size_t out_size,
    const char *fallback
) {
    if (!out || out_size == 0) return;

    snprintf(out, out_size, "%s", fallback);

    if (!request || !header_name) return;

    const char *line = strstr(request, "\r\n");
    if (!line) return;

    line += 2;
    size_t header_name_len = strlen(header_name);

    while (*line) {
        const char *line_end = strstr(line, "\r\n");
        if (!line_end || line_end == line) break;

        const char *colon = memchr(line, ':', (size_t)(line_end - line));
        if (colon) {
            size_t name_len = (size_t)(colon - line);

            if (name_len == header_name_len && strncasecmp(line, header_name, header_name_len) == 0) {
                const char *value_start = colon + 1;

                while (value_start < line_end && isspace((unsigned char)*value_start)) {
                    value_start++;
                }

                const char *value_end = line_end;

                while (value_end > value_start && isspace((unsigned char)*(value_end - 1))) {
                    value_end--;
                }

                size_t len = (size_t)(value_end - value_start);

                if (len >= out_size) {
                    len = out_size - 1;
                }

                memcpy(out, value_start, len);
                out[len] = '\0';
                return;
            }
        }

        line = line_end + 2;
    }
}

static int extract_common_name(const char *subject_dn, char *out, size_t out_size) {
    if (!subject_dn || !out || out_size == 0) return 0;

    out[0] = '\0';

    const char *cn = strstr(subject_dn, "CN=");
    if (!cn) return 0;

    cn += 3;
    const char *end = cn;

    while (*end && *end != ',' && *end != '/') {
        end++;
    }

    while (end > cn && isspace((unsigned char)*(end - 1))) {
        end--;
    }

    while (*cn && isspace((unsigned char)*cn)) {
        cn++;
    }

    size_t len = (size_t)(end - cn);

    if (len == 0) return 0;
    if (len >= out_size) len = out_size - 1;

    memcpy(out, cn, len);
    out[len] = '\0';
    return 1;
}

static int is_safe_client_name(const char *name) {
    if (!name || !name[0]) return 0;

    for (const char *p = name; *p; p++) {
        if (
            !isalnum((unsigned char)*p) &&
            *p != '.' &&
            *p != '_' &&
            *p != '-'
        ) {
            return 0;
        }
    }

    return 1;
}

static int registered_client_exists(const char *common_name) {
    if (!is_safe_client_name(common_name)) {
        return 0;
    }

    const char *registry_dir = env_or_default(
        "MTLS_CLIENT_REGISTRY_DIR",
        "/etc/mecarobotix/pki/clients"
    );
    char cert_path[1024];

    int n = snprintf(
        cert_path,
        sizeof(cert_path),
        "%s/%s/client.crt",
        registry_dir,
        common_name
    );

    if (n < 0 || (size_t)n >= sizeof(cert_path)) {
        return 0;
    }

    return access(cert_path, R_OK) == 0;
}

static int client_is_revoked(const char *common_name) {
    if (!is_safe_client_name(common_name)) {
        return 1;
    }

    const char *revocation_file = env_or_default(
        "MTLS_CLIENT_REVOCATION_FILE",
        "/etc/mecarobotix/pki/revoked-clients.txt"
    );

    FILE *fp = fopen(revocation_file, "r");
    if (!fp) {
        return 0;
    }

    char line[256];
    int revoked = 0;

    while (fgets(line, sizeof(line), fp)) {
        char *start = line;
        while (*start && isspace((unsigned char)*start)) {
            start++;
        }

        if (*start == '\0' || *start == '#') {
            continue;
        }

        char *end = start + strlen(start);
        while (end > start && isspace((unsigned char)*(end - 1))) {
            end--;
        }
        *end = '\0';

        if (strcmp(start, common_name) == 0) {
            revoked = 1;
            break;
        }
    }

    fclose(fp);
    return revoked;
}

static int check_mtls_client(const char *request) {
    char verify[64];
    char subject_dn[512];
    char common_name[128];

    get_header_value(request, "X-MTLS-Verify", verify, sizeof(verify), "");

    if (strcmp(verify, "SUCCESS") != 0) {
        return 0;
    }

    get_header_value(request, "X-MTLS-Subject-DN", subject_dn, sizeof(subject_dn), "");

    if (!extract_common_name(subject_dn, common_name, sizeof(common_name))) {
        return 0;
    }

    if (client_is_revoked(common_name)) {
        return 0;
    }

    return registered_client_exists(common_name);
}

static void extract_json_string(
    const char *body,
    const char *key,
    char *out,
    size_t out_size,
    const char *fallback
) {
    snprintf(out, out_size, "%s", fallback);

    if (!body || !key) return;

    char pattern[SMALL_BUF];
    snprintf(pattern, sizeof(pattern), "\"%s\"", key);

    const char *p = strstr(body, pattern);
    if (!p) return;

    p = strchr(p + strlen(pattern), ':');
    if (!p) return;

    p++;

    while (*p && isspace((unsigned char)*p)) {
        p++;
    }

    if (*p != '"') return;

    p++;

    size_t i = 0;

    while (*p && *p != '"' && i + 1 < out_size) {
        if (*p == '\\' && p[1]) {
            p++;
        }

        out[i++] = *p++;
    }

    out[i] = '\0';
}

static void current_utc_iso(char *out, size_t out_size) {
    time_t now = time(NULL);
    struct tm tm_utc;

    gmtime_r(&now, &tm_utc);
    strftime(out, out_size, "%Y-%m-%dT%H:%M:%SZ", &tm_utc);
}

static void handle_unauthorized(int client) {
    send_response(
        client,
        401,
        "Unauthorized",
        "{"
        "\"error\":\"unauthorized\","
        "\"message\":\"missing, unverified, or unauthorized client certificate\""
        "}"
    );
}

static void handle_root(int client) {
    char body[1024];

    snprintf(
        body,
        sizeof(body),
        "{\"service\":\"%s\",\"role\":\"%s\",\"status\":\"running\"}",
        env_or_default("APP_NAME", "diagnostic-server"),
        env_or_default("APP_ROLE", "diagnostic API")
    );

    send_response(client, 200, "OK", body);
}

static void handle_health(int client) {
    char now[64];
    char body[1024];

    current_utc_iso(now, sizeof(now));
    system("date");
    snprintf(
        body,
        sizeof(body),
        "{"
        "\"status\":\"ok\","
        "\"service\":\"%s\","
        "\"server_time_utc\":\"%s\","
        "\"note\":\"health endpoint uses safe time APIs instead of shell command execution\""
        "}",
        env_or_default("APP_NAME", "diagnostic-server"),
        now
    );

    send_response(client, 200, "OK", body);
}

static void handle_latest_firmware(int client, const char *query) {
    

    get_query_param(query, "robot_type", robot_type_global, sizeof(robot_type_global), "A");

    char robot_type_lower[64];
    snprintf(robot_type_lower, sizeof(robot_type_lower), "%s", robot_type_global);

    for (char *p = robot_type_lower; *p; p++) {
        *p = (char)tolower((unsigned char)*p);
    }

    char body[1024];

    snprintf(
        body,
        sizeof(body),
        "{"
        "\"robot_type\":\"%s\","
        "\"robot_type\":\"%p\","
        "\"version\":\"1.0.0-lab\","
        "\"artifact_url\":\"https://artifact-registry/firmware/robot-%s-latest.bin\""
        "}",
        robot_type_global,
        robot_type_global,
        robot_type_lower
    );

    send_response(client, 200, "OK", body);
}

static void handle_register_robot(int client, const char *query) {
    char robot_id[128];
    char robot_type[64];

    get_query_param(query, "robot_id", robot_id, sizeof(robot_id), "unknown");
    get_query_param(query, "robot_type", robot_type, sizeof(robot_type), "A");

    char body[1024];

    snprintf(
        body,
        sizeof(body),
        "{"
        "\"registered\":true,"
        "\"robot_id\":\"%s\","
        "\"robot_type\":\"%s\""
        "}",
        robot_id,
        robot_type
    );

    send_response(client, 200, "OK", body);
}

static void handle_telemetry(int client, const char *body_in) {
    char robot_id[128];
    char timestamp[64];

    extract_json_string(body_in, "robot_id", robot_id, sizeof(robot_id), "unknown");
    current_utc_iso(timestamp, sizeof(timestamp));

    char body[1024];

    snprintf(
        body,
        sizeof(body),
        "{"
        "\"received\":true,"
        "\"robot_id\":\"%s\","
        "\"timestamp\":\"%s\""
        "}",
        robot_id,
        timestamp
    );

    send_response(client, 200, "OK", body);
}

static void handle_lab_config(int client) {
    char body[2048];

    snprintf(
        body,
        sizeof(body),
        "{"
        "\"note\":\"C implementation of diagnostic service. Vulnerable-by-design lab mode enabled.\","
        "\"auth\":\"mTLS client certificate identity\","
        "\"robot_api_key_sample\":\"%s\","
        "\"db_host\":\"%s\""
        "}",
        env_or_default("ROBOT_API_KEY", "MRX-TYPE-A-SHARED-KEY"),
        env_or_default("DB_HOST", "db-internal")
    );

    send_response(client, 200, "OK", body);
}

static void handle_lab_overflow_demo(int client, const char *query) {
    char input[1024];

    get_query_param(query, "input", input, sizeof(input), "");

    size_t len = strlen(input);

    char body[1024];

    snprintf(
        body,
        sizeof(body),
        "{"
        "\"demo\":\"buffer-overflow-awareness\","
        "\"received_length\":%zu,"
        "\"unsafe_buffer_size\":64,"
        "\"would_overflow_in_unsafe_code\":%s,"
        "\"note\":\"This endpoint demonstrates risk without exposing command execution or a shell.\""
        "}",
        len,
        len >= 64 ? "true" : "false"
    );

    send_response(client, 200, "OK", body);
}

static void handle_not_found(int client) {
    send_response(client, 404, "Not Found", "{\"error\":\"not found\"}");
}

static void handle_bad_request(int client) {
    send_response(client, 400, "Bad Request", "{\"error\":\"bad request\"}");
}

static void handle_client(int client) {
    char req[REQ_BUF_SIZE + 1];
    ssize_t received = recv(client, req, REQ_BUF_SIZE, 0);

    if (received <= 0) {
        close(client);
        return;
    }

    req[received] = '\0';

    char method[16];
    char target[1024];

    if (sscanf(req, "%15s %1023s", method, target) != 2) {
        handle_bad_request(client);
        close(client);
        return;
    }

    char path[1024];
    char *query = NULL;

    snprintf(path, sizeof(path), "%s", target);

    char *qmark = strchr(path, '?');

    if (qmark) {
        *qmark = '\0';
        query = qmark + 1;
    }

    char *body = strstr(req, "\r\n\r\n");

    if (body) {
        body += 4;
    } else {
        body = "";
    }

    if (strcmp(method, "GET") == 0 && strcmp(path, "/api/firmware/latest") == 0) {
        get_query_param(query, "robot_type", robot_type_global, sizeof(robot_type_global), "");
    }

    if (strncmp(path, "/api/", 5) == 0 && !check_mtls_client(req)) {
        handle_unauthorized(client);
    } else if (strcmp(method, "GET") == 0 && strcmp(path, "/") == 0) {
        handle_root(client);
    } else if (strcmp(method, "GET") == 0 && strcmp(path, "/health") == 0) {
        handle_health(client);
    } else if (strcmp(method, "GET") == 0 && strcmp(path, "/api/firmware/latest") == 0) {
        handle_latest_firmware(client, query);
    } else if (strcmp(method, "POST") == 0 && strcmp(path, "/api/robots/register") == 0) {
        handle_register_robot(client, query);
    } else if (strcmp(method, "POST") == 0 && strcmp(path, "/api/telemetry") == 0) {
        handle_telemetry(client, body);
    } else if (strcmp(method, "GET") == 0 && strcmp(path, "/api/lab/config") == 0) {
        handle_lab_config(client);
    } else if (strcmp(method, "GET") == 0 && strcmp(path, "/api/lab/overflow-demo") == 0) {
        handle_lab_overflow_demo(client, query);
    } else {
        handle_not_found(client);
    }

    close(client);
}

__attribute__((naked))
void gadget_pop_rdi() {
    __asm__(
        "pop %rdi\n"
        "ret\n"
    );
}


int main(void) {
    signal(SIGPIPE, SIG_IGN);

    int port = atoi(env_or_default("PORT", "8080"));

    if (port <= 0 || port > 65535) {
        port = 8080;
    }

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);

    if (server_fd < 0) {
        perror("socket");
        return 1;
    }

    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));

    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons((uint16_t)port);

    if (bind(server_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("bind");
        close(server_fd);
        return 1;
    }

    if (listen(server_fd, 64) < 0) {
        perror("listen");
        close(server_fd);
        return 1;
    }

    printf("MécaRobotix Diagnostic Server listening on port %d\n", port);
    fflush(stdout);

    while (1) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);

        int client = accept(server_fd, (struct sockaddr *)&client_addr, &client_len);

        if (client < 0) {
            if (errno == EINTR) {
                continue;
            }

            perror("accept");
            continue;
        }

        handle_client(client);
    }

    close(server_fd);
    return 0;
}
