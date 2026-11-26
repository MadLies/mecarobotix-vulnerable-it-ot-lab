import os
import random
import threading
import time
from datetime import datetime, timezone
from typing import Any
from urllib.parse import urlencode

import requests
from fastapi import Body, FastAPI, Header, HTTPException, Query
from pydantic import BaseModel


ROBOT_ID = os.getenv("ROBOT_ID", "robot-unknown")
ROBOT_TYPE = os.getenv("ROBOT_TYPE", "A")
ROBOT_API_KEY = os.getenv("ROBOT_API_KEY", "MRX-TYPE-A-SHARED-KEY")
ROBOT_MTLS_MANAGEMENT_CLIENTS = os.getenv(
    "ROBOT_MTLS_MANAGEMENT_CLIENTS",
    "ci-server ot-maintenance ot-supervision",
)

FIRMWARE_VERSION = "1.0.0-lab"
FIRMWARE_UPDATE_INTERVAL_SECONDS = 300
TELEMETRY_INTERVAL_SECONDS = 60
HTTP_TIMEOUT_SECONDS = 5
CLIENT_TLS_CERT_FILE = os.getenv("CLIENT_TLS_CERT_FILE", "/etc/mecarobotix/client-tls/client-chain.crt")
CLIENT_TLS_KEY_FILE = os.getenv("CLIENT_TLS_KEY_FILE", "/etc/mecarobotix/client-tls/client.key")


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def diagnostic_base_from_env() -> str:
    explicit_base = os.getenv("DIAGNOSTIC_BASE_URL")

    if explicit_base:
        return explicit_base.rstrip("/")

    configured_url = os.getenv(
        "DIAGNOSTIC_URL",
        "https://diagnostic-server/api/telemetry",
    ).rstrip("/")

    if configured_url.endswith("/api/telemetry"):
        return configured_url[: -len("/api/telemetry")]

    return configured_url


class RobotState:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.started_at = time.time()
        self.robot_id = ROBOT_ID
        self.robot_type = ROBOT_TYPE
        self.state = "idle"
        self.firmware = FIRMWARE_VERSION
        self.diagnostic_server = diagnostic_base_from_env()
        self.registered = False
        self.restart_requested = False
        self.temperature = 32.0
        self.vibration = 0.1
        self.last_diagnostic_http_code = 0
        self.last_diagnostic_error: str | None = None
        self.last_diagnostic_response: Any = None
        self.last_firmware_check_at: str | None = None
        self.last_telemetry_sent_at: str | None = None
        self.latest_artifact_url: str | None = None

    def snapshot(self) -> dict[str, Any]:
        with self.lock:
            return {
                "robot_id": self.robot_id,
                "robot_type": self.robot_type,
                "state": self.state,
                "firmware": self.firmware,
                "diagnostic_server": self.diagnostic_server,
                "registered": self.registered,
                "restart_requested": self.restart_requested,
                "temperature": self.temperature,
                "vibration": self.vibration,
                "uptime_ms": int((time.time() - self.started_at) * 1000),
                "last_diagnostic_http_code": self.last_diagnostic_http_code,
                "last_diagnostic_error": self.last_diagnostic_error,
                "last_diagnostic_response": self.last_diagnostic_response,
                "last_firmware_check_at": self.last_firmware_check_at,
                "last_telemetry_sent_at": self.last_telemetry_sent_at,
                "latest_artifact_url": self.latest_artifact_url,
            }

    def update_telemetry(self) -> dict[str, Any]:
        with self.lock:
            self.temperature = round(random.uniform(32.0, 55.0), 2)
            self.vibration = round(random.uniform(0.1, 1.5), 2)
            return {
                "robot_id": self.robot_id,
                "robot_type": self.robot_type,
                "firmware": self.firmware,
                "temperature": self.temperature,
                "vibration": self.vibration,
                "uptime_ms": int((time.time() - self.started_at) * 1000),
            }

    def diagnostic_url(self, path: str, params: dict[str, str] | None = None) -> str:
        query = dict(params or {})
        with self.lock:
            base_url = self.diagnostic_server
        if query:
            return f"{base_url}{path}?{urlencode(query)}"
        return f"{base_url}{path}"

    def remember_diagnostic_result(
        self,
        status_code: int,
        response: Any = None,
        error: str | None = None,
    ) -> None:
        with self.lock:
            self.last_diagnostic_http_code = status_code
            self.last_diagnostic_response = response
            self.last_diagnostic_error = error


state = RobotState()
stop_worker = threading.Event()
worker_thread: threading.Thread | None = None

app = FastAPI(title=f"MecaRobotix Robot API - {ROBOT_ID}", version="0.2.0")


class DiagnosticServerUpdate(BaseModel):
    url: str


def diagnostic_auth_headers() -> dict[str, str]:
    return {}


def client_tls_cert() -> tuple[str, str] | None:
    if os.path.exists(CLIENT_TLS_CERT_FILE) and os.path.exists(CLIENT_TLS_KEY_FILE):
        return (CLIENT_TLS_CERT_FILE, CLIENT_TLS_KEY_FILE)
    return None


def extract_common_name(subject_dn: str | None) -> str | None:
    if not subject_dn:
        return None

    marker = "CN="
    start = subject_dn.find(marker)

    if start < 0:
        return None

    start += len(marker)
    end = len(subject_dn)

    for separator in (",", "/"):
        separator_index = subject_dn.find(separator, start)
        if separator_index >= 0:
            end = min(end, separator_index)

    common_name = subject_dn[start:end].strip()
    return common_name or None


def require_mtls_client(
    x_mtls_verify: str | None,
    x_mtls_subject_dn: str | None,
    allowed_clients: str = ROBOT_MTLS_MANAGEMENT_CLIENTS,
) -> str:
    common_name = extract_common_name(x_mtls_subject_dn)
    allowed = {client.strip() for client in allowed_clients.replace(",", " ").split() if client.strip()}

    if x_mtls_verify != "SUCCESS" or not common_name or common_name not in allowed:
        raise HTTPException(status_code=401, detail="missing, unverified, or unauthorized client certificate")

    return common_name


def require_mtls_identity(
    x_mtls_verify: str | None,
    x_mtls_subject_dn: str | None,
) -> str:
    common_name = extract_common_name(x_mtls_subject_dn)

    if x_mtls_verify != "SUCCESS" or not common_name:
        raise HTTPException(status_code=401, detail="missing or unverified client certificate")

    return common_name


def require_robot_api_key(
    x_robot_api_key: str | None = Header(default=None, alias="X-Robot-Api-Key"),
) -> None:
    if x_robot_api_key != ROBOT_API_KEY:
        raise HTTPException(status_code=401, detail="missing or invalid robot API key")


def require_robot_read_access(
    x_robot_api_key: str | None,
    x_mtls_verify: str | None,
    x_mtls_subject_dn: str | None,
) -> str:
    if x_robot_api_key == ROBOT_API_KEY:
        return "robot-api-key"

    return require_mtls_identity(x_mtls_verify, x_mtls_subject_dn)


def http_json(method: str, url: str, **kwargs: Any) -> tuple[int, Any, str | None]:
    try:
        kwargs.setdefault("cert", client_tls_cert())
        response = requests.request(method, url, timeout=HTTP_TIMEOUT_SECONDS, **kwargs)
        try:
            payload: Any = response.json()
        except ValueError:
            payload = response.text
        return response.status_code, payload, None
    except requests.RequestException as exc:
        return -1, None, str(exc)


def register_robot() -> dict[str, Any]:
    url = state.diagnostic_url(
        "/api/robots/register",
        {"robot_id": ROBOT_ID, "robot_type": ROBOT_TYPE},
    )
    code, payload, error = http_json("POST", url, headers=diagnostic_auth_headers(), json={})
    state.remember_diagnostic_result(code, payload, error)

    with state.lock:
        state.registered = code == 200

    return {
        "registered": code == 200,
        "diagnostic_http_code": code,
        "diagnostic_response": payload,
        "error": error,
    }


def request_latest_firmware() -> dict[str, Any]:
    url = state.diagnostic_url(
        "/api/firmware/latest",
        {"robot_type": ROBOT_TYPE},
    )
    code, payload, error = http_json("GET", url, headers=diagnostic_auth_headers())
    now = utc_now()
    state.remember_diagnostic_result(code, payload, error)

    applied = False
    version = None
    artifact_url = None

    if isinstance(payload, dict):
        version = payload.get("version")
        artifact_url = payload.get("artifact_url")

    with state.lock:
        previous_firmware = state.firmware
        state.last_firmware_check_at = now
        state.latest_artifact_url = artifact_url

        if code == 200 and version:
            state.firmware = str(version)
            state.state = "idle"
            applied = previous_firmware != state.firmware
        elif error:
            state.state = "diagnostic_unreachable"

    return {
        "robot_id": ROBOT_ID,
        "robot_type": ROBOT_TYPE,
        "update_check_requested": True,
        "diagnostic_auth": "mTLS_client_certificate",
        "diagnostic_http_code": code,
        "diagnostic_server": state.snapshot()["diagnostic_server"],
        "diagnostic_response": payload,
        "error": error,
        "firmware_applied": applied,
        "firmware": state.snapshot()["firmware"],
        "artifact_url": artifact_url,
        "checked_at": now,
    }


def send_telemetry_to_diagnostic() -> dict[str, Any]:
    telemetry = state.update_telemetry()
    url = state.diagnostic_url("/api/telemetry")
    code, payload, error = http_json("POST", url, headers=diagnostic_auth_headers(), json=telemetry)
    state.remember_diagnostic_result(code, payload, error)

    with state.lock:
        if code == 200:
            state.last_telemetry_sent_at = utc_now()

    return {
        "sent": code == 200,
        "diagnostic_http_code": code,
        "diagnostic_response": payload,
        "error": error,
        "telemetry": telemetry,
    }


def fetch_lab_config_once() -> None:
    url = state.diagnostic_url("/api/lab/config")
    code, payload, error = http_json("GET", url, headers=diagnostic_auth_headers())
    state.remember_diagnostic_result(code, payload, error)


def diagnostic_worker() -> None:
    register_robot()
    fetch_lab_config_once()

    last_firmware_update = 0.0
    last_telemetry = 0.0

    while not stop_worker.is_set():
        now = time.monotonic()

        if now - last_firmware_update >= FIRMWARE_UPDATE_INTERVAL_SECONDS:
            request_latest_firmware()
            last_firmware_update = now

        if now - last_telemetry >= TELEMETRY_INTERVAL_SECONDS:
            send_telemetry_to_diagnostic()
            last_telemetry = now

        stop_worker.wait(1)


@app.on_event("startup")
def startup() -> None:
    global worker_thread
    stop_worker.clear()
    worker_thread = threading.Thread(target=diagnostic_worker, daemon=True)
    worker_thread.start()


@app.on_event("shutdown")
def shutdown() -> None:
    stop_worker.set()
    if worker_thread:
        worker_thread.join(timeout=2)


@app.get("/")
def root() -> dict[str, Any]:
    return {
        "robot_id": ROBOT_ID,
        "robot_type": ROBOT_TYPE,
        "service": "robot-api",
        "vulnerable_by_design": True,
        "vulnerability": "legacy diagnostic token removed; mTLS client identity is used",
    }


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "robot_id": ROBOT_ID,
        "server_time_utc": utc_now(),
    }


@app.get("/status")
def status(
    x_robot_api_key: str | None = Header(default=None, alias="X-Robot-Api-Key"),
    x_mtls_verify: str | None = Header(default=None, alias="X-MTLS-Verify"),
    x_mtls_subject_dn: str | None = Header(default=None, alias="X-MTLS-Subject-DN"),
) -> dict[str, Any]:
    authorized_client = require_robot_read_access(x_robot_api_key, x_mtls_verify, x_mtls_subject_dn)
    payload = state.snapshot()
    payload["authorized_client"] = authorized_client
    return payload


@app.get("/telemetry")
def telemetry(
    x_robot_api_key: str | None = Header(default=None, alias="X-Robot-Api-Key"),
    x_mtls_verify: str | None = Header(default=None, alias="X-MTLS-Verify"),
    x_mtls_subject_dn: str | None = Header(default=None, alias="X-MTLS-Subject-DN"),
) -> dict[str, Any]:
    authorized_client = require_robot_read_access(x_robot_api_key, x_mtls_verify, x_mtls_subject_dn)
    payload = state.update_telemetry()
    payload["authorized_client"] = authorized_client
    payload["diagnostic_url"] = f"{state.snapshot()['diagnostic_server']}/api/telemetry"
    return payload


@app.get("/update-firmware")
def update_firmware(
    version: str | None = Query(default=None),
    x_mtls_verify: str | None = Header(default=None, alias="X-MTLS-Verify"),
    x_mtls_subject_dn: str | None = Header(default=None, alias="X-MTLS-Subject-DN"),
) -> dict[str, Any]:
    client_name = require_mtls_client(x_mtls_verify, x_mtls_subject_dn)
    result = request_latest_firmware()
    result["authorized_client"] = client_name

    if version:
        result["requested_version"] = version
        result["mode"] = "server_lookup_version_parameter_ignored"
    else:
        result["mode"] = "server_lookup"

    return result


@app.post("/diagnostic/register")
def diagnostic_register() -> dict[str, Any]:
    return register_robot()


@app.post("/diagnostic-server")
def set_diagnostic_server(
    update: DiagnosticServerUpdate | None = Body(default=None),
    url: str | None = Query(default=None),
    x_ldap_admin_dn: str | None = Header(default=None, alias="X-Ldap-Admin-Dn"),
    x_ldap_password: str | None = Header(default=None, alias="X-Ldap-Password"),
) -> dict[str, Any]:
    if not x_ldap_admin_dn or not x_ldap_password:
        raise HTTPException(status_code=401, detail="missing LDAP maintenance headers")

    new_url = url or (update.url if update else None)

    if not new_url:
        return {"updated": False, "error": "missing url parameter"}

    if not new_url.startswith(("http://", "https://")):
        return {"updated": False, "error": "invalid url. Use http:// or https://"}

    with state.lock:
        state.diagnostic_server = new_url.rstrip("/")

    return {
        "updated": True,
        "diagnostic_server": state.snapshot()["diagnostic_server"],
    }


@app.get("/debug/config")
def debug_config(
    x_mtls_verify: str | None = Header(default=None, alias="X-MTLS-Verify"),
    x_mtls_subject_dn: str | None = Header(default=None, alias="X-MTLS-Subject-DN"),
    x_postgres_password: str | None = Header(default=None, alias="X-Postgres-Password"),
) -> dict[str, Any]:
    client_name = require_mtls_client(x_mtls_verify, x_mtls_subject_dn)
    if not x_postgres_password:
        raise HTTPException(status_code=401, detail="missing PostgreSQL maintenance header")

    return {
        "robot_id": ROBOT_ID,
        "robot_type": ROBOT_TYPE,
        "robot_api_key": ROBOT_API_KEY,
        "authorized_client": client_name,
        "firmware_update_interval_seconds": FIRMWARE_UPDATE_INTERVAL_SECONDS,
        "telemetry_interval_seconds": TELEMETRY_INTERVAL_SECONDS,
        "diagnostic_server": state.snapshot()["diagnostic_server"],
        "warning": "lab intentionally exposes firmware secrets for vulnerability demonstration",
    }


@app.post("/restart")
def restart(x_robot_api_key: str | None = Header(default=None, alias="X-Robot-Api-Key")) -> dict[str, Any]:
    require_robot_api_key(x_robot_api_key)
    with state.lock:
        state.restart_requested = True
        state.state = "restart_requested"
    return {"robot_id": ROBOT_ID, "restart": "accepted"}
