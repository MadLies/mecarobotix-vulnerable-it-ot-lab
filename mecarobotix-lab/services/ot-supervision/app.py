import os
from typing import Any

import requests
from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel


REQUEST_TIMEOUT_SECONDS = 4
CLIENT_TLS_CERT_FILE = os.getenv("CLIENT_TLS_CERT_FILE", "/etc/mecarobotix/client-tls/client-chain.crt")
CLIENT_TLS_KEY_FILE = os.getenv("CLIENT_TLS_KEY_FILE", "/etc/mecarobotix/client-tls/client.key")

ROBOTS = [
    {
        "id": "robot-a-01",
        "type": "A",
        "host": "robot-a-01",
        "api_url": "https://robot-a-01:8443",
        "network": "ot_net",
    },
    {
        "id": "robot-a-02",
        "type": "A",
        "host": "robot-a-02",
        "api_url": "https://robot-a-02:8443",
        "network": "ot_net",
    },
    {
        "id": "robot-b-01",
        "type": "B",
        "host": "robot-b-01",
        "api_url": "https://robot-b-01:8443",
        "network": "ot_net",
    },
]

app = FastAPI(title="MecaRobotix OT Supervision", version="0.2.0")


class DiagnosticServerUpdate(BaseModel):
    url: str


def robot_by_id(robot_id: str) -> dict[str, str]:
    for robot in ROBOTS:
        if robot["id"] == robot_id:
            return robot
    raise HTTPException(status_code=404, detail="unknown robot")


def robot_api_key(robot: dict[str, str]) -> str:
    if robot["type"] == "B":
        return os.getenv("ROBOT_B_API_KEY", "MRX-TYPE-B-SHARED-KEY")
    return os.getenv("ROBOT_A_API_KEY", "MRX-TYPE-A-SHARED-KEY")


def robot_headers(robot: dict[str, str]) -> dict[str, str]:
    return {"X-Robot-Api-Key": robot_api_key(robot)}


def client_tls_cert() -> tuple[str, str] | None:
    if os.path.exists(CLIENT_TLS_CERT_FILE) and os.path.exists(CLIENT_TLS_KEY_FILE):
        return (CLIENT_TLS_CERT_FILE, CLIENT_TLS_KEY_FILE)
    return None


def robot_request(
    robot_id: str,
    method: str,
    path: str,
    **kwargs: Any,
) -> dict[str, Any]:
    robot = robot_by_id(robot_id)
    url = f"{robot['api_url']}{path}"
    headers = dict(kwargs.pop("headers", {}) or {})
    headers.update(robot_headers(robot))

    try:
        response = requests.request(
            method,
            url,
            headers=headers,
            cert=client_tls_cert(),
            timeout=REQUEST_TIMEOUT_SECONDS,
            **kwargs,
        )
    except requests.RequestException as exc:
        return {
            "robot_id": robot_id,
            "reachable": False,
            "error": str(exc),
            "target": url,
        }

    try:
        payload: Any = response.json()
    except ValueError:
        payload = response.text

    return {
        "robot_id": robot_id,
        "reachable": response.ok,
        "http_status": response.status_code,
        "target": url,
        "response": payload,
    }


def robot_summary(robot: dict[str, str]) -> dict[str, Any]:
    status = robot_request(robot["id"], "GET", "/status")

    if status.get("reachable") and isinstance(status.get("response"), dict):
        payload = status["response"]
        return {
            **robot,
            "reachable": True,
            "state": payload.get("state", "unknown"),
            "firmware": payload.get("firmware", "unknown"),
            "registered": payload.get("registered", False),
            "temperature": payload.get("temperature"),
            "vibration": payload.get("vibration"),
            "diagnostic_server": payload.get("diagnostic_server"),
            "last_diagnostic_http_code": payload.get("last_diagnostic_http_code"),
            "last_firmware_check_at": payload.get("last_firmware_check_at"),
            "last_telemetry_sent_at": payload.get("last_telemetry_sent_at"),
        }

    return {
        **robot,
        "reachable": False,
        "state": "unreachable",
        "firmware": "unknown",
        "registered": False,
        "error": status.get("error") or status.get("response"),
    }


@app.get("/", response_class=HTMLResponse)
def dashboard() -> str:
    return HTML


@app.get("/health")
def health() -> dict[str, str]:
    return {
        "status": "ok",
        "service": os.getenv("APP_NAME", "ot-supervision"),
    }


@app.get("/robots")
def robots() -> list[dict[str, str]]:
    return ROBOTS


@app.get("/api/robots")
def api_robots() -> list[dict[str, str]]:
    return ROBOTS


@app.get("/api/robots/summary")
def robots_summary() -> dict[str, Any]:
    summaries = [robot_summary(robot) for robot in ROBOTS]
    return {
        "count": len(summaries),
        "reachable": sum(1 for robot in summaries if robot["reachable"]),
        "robots": summaries,
    }


@app.get("/robots/{robot_id}/status")
@app.get("/api/robots/{robot_id}/status")
def robot_status(robot_id: str) -> dict[str, Any]:
    return robot_request(robot_id, "GET", "/status")


@app.get("/api/robots/{robot_id}/telemetry")
def robot_telemetry(robot_id: str) -> dict[str, Any]:
    return robot_request(robot_id, "GET", "/telemetry")


@app.post("/robots/{robot_id}/restart")
@app.post("/api/robots/{robot_id}/restart")
def restart(robot_id: str) -> dict[str, Any]:
    return robot_request(robot_id, "POST", "/restart")


@app.post("/robots/{robot_id}/update")
@app.post("/api/robots/{robot_id}/update")
def update(robot_id: str) -> dict[str, Any]:
    return robot_request(
        robot_id,
        "GET",
        "/update-firmware",
    )


@app.post("/api/robots/{robot_id}/diagnostic-server")
def set_diagnostic_server(
    robot_id: str,
    update: DiagnosticServerUpdate,
) -> dict[str, Any]:
    return robot_request(
        robot_id,
        "POST",
        "/diagnostic-server",
        headers={
            "X-Ldap-Admin-Dn": os.getenv("LDAP_ADMIN_DN", "cn=admin,dc=mecarobotix,dc=local"),
            "X-Ldap-Password": os.getenv("LDAP_ADMIN_PASSWORD", "Admin123!"),
        },
        json=update.model_dump(),
    )


HTML = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MecaRobotix OT Supervision</title>
  <style>
    :root {
      --bg: #f5f7fa;
      --panel: #ffffff;
      --line: #d8dee8;
      --text: #18212f;
      --muted: #607084;
      --good: #157f55;
      --bad: #b3261e;
      --warn: #9a6700;
      --accent: #1f6feb;
      --accent-dark: #174ea6;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: var(--text);
      background: var(--bg);
    }
    header {
      border-bottom: 1px solid var(--line);
      background: var(--panel);
    }
    .bar {
      max-width: 1180px;
      margin: 0 auto;
      padding: 18px 22px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
    }
    h1 {
      margin: 0;
      font-size: 22px;
      font-weight: 700;
      letter-spacing: 0;
    }
    .meta {
      color: var(--muted);
      font-size: 13px;
      white-space: nowrap;
    }
    main {
      max-width: 1180px;
      margin: 0 auto;
      padding: 22px;
    }
    .toolbar {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      align-items: center;
      margin-bottom: 16px;
    }
    button {
      border: 1px solid var(--line);
      border-radius: 6px;
      background: var(--panel);
      color: var(--text);
      min-height: 36px;
      padding: 0 12px;
      font: inherit;
      cursor: pointer;
    }
    button.primary {
      color: white;
      border-color: var(--accent);
      background: var(--accent);
    }
    button.primary:hover { background: var(--accent-dark); }
    button:hover { border-color: #9fb1c6; }
    input {
      border: 1px solid var(--line);
      border-radius: 6px;
      min-height: 36px;
      padding: 0 10px;
      font: inherit;
      min-width: 170px;
      background: white;
    }
    .summary {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 12px;
      margin-bottom: 16px;
    }
    .metric {
      border: 1px solid var(--line);
      background: var(--panel);
      border-radius: 8px;
      padding: 14px;
    }
    .metric span {
      display: block;
      color: var(--muted);
      font-size: 12px;
      text-transform: uppercase;
    }
    .metric strong {
      display: block;
      margin-top: 4px;
      font-size: 24px;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(310px, 1fr));
      gap: 14px;
    }
    .robot {
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      padding: 14px;
      display: flex;
      flex-direction: column;
      gap: 12px;
    }
    .robot-head {
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: flex-start;
    }
    .robot h2 {
      margin: 0;
      font-size: 18px;
      letter-spacing: 0;
    }
    .tag {
      display: inline-flex;
      align-items: center;
      min-height: 24px;
      border-radius: 999px;
      padding: 0 9px;
      font-size: 12px;
      border: 1px solid var(--line);
      color: var(--muted);
      background: #fafbfc;
      white-space: nowrap;
    }
    .tag.good { color: var(--good); border-color: #a6d8c0; background: #eefaf4; }
    .tag.bad { color: var(--bad); border-color: #f0b8b5; background: #fff1f0; }
    dl {
      display: grid;
      grid-template-columns: 120px minmax(0, 1fr);
      gap: 7px 12px;
      margin: 0;
      font-size: 13px;
    }
    dt { color: var(--muted); }
    dd {
      margin: 0;
      min-width: 0;
      overflow-wrap: anywhere;
    }
    .actions {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 8px;
    }
    .actions .wide { grid-column: 1 / -1; }
    .log {
      margin-top: 16px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: #111827;
      color: #dce6f2;
      min-height: 160px;
      max-height: 280px;
      overflow: auto;
      padding: 12px;
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-size: 12px;
      white-space: pre-wrap;
    }
    @media (max-width: 700px) {
      .bar { align-items: flex-start; flex-direction: column; }
      .summary { grid-template-columns: 1fr; }
      .actions { grid-template-columns: 1fr; }
      dl { grid-template-columns: 96px minmax(0, 1fr); }
    }
  </style>
</head>
<body>
  <header>
    <div class="bar">
      <h1>MecaRobotix OT Supervision</h1>
      <div class="meta" id="lastRefresh">No data</div>
    </div>
  </header>
  <main>
    <section class="toolbar">
      <button class="primary" onclick="refreshFleet()">Refresh</button>
      <input id="diagnosticUrl" value="https://diagnostic-server" aria-label="Diagnostic server">
    </section>
    <section class="summary">
      <div class="metric"><span>Robots</span><strong id="robotCount">0</strong></div>
      <div class="metric"><span>Reachable</span><strong id="reachableCount">0</strong></div>
      <div class="metric"><span>Firmware Checks</span><strong id="firmwareChecks">0</strong></div>
    </section>
    <section class="grid" id="robots"></section>
    <section class="log" id="log"></section>
  </main>
  <script>
    const robotsEl = document.getElementById('robots');
    const logEl = document.getElementById('log');
    const diagnosticInput = document.getElementById('diagnosticUrl');

    function writeLog(label, payload) {
      const stamp = new Date().toISOString();
      logEl.textContent = `[${stamp}] ${label}\\n${JSON.stringify(payload, null, 2)}\\n\\n` + logEl.textContent;
    }

    function valueOrDash(value) {
      return value === null || value === undefined || value === '' ? '-' : value;
    }

    function robotCard(robot) {
      const statusClass = robot.reachable ? 'good' : 'bad';
      const statusText = robot.reachable ? 'reachable' : 'offline';
      return `
        <article class="robot">
          <div class="robot-head">
            <div>
              <h2>${robot.id}</h2>
              <span class="tag">Type ${robot.type}</span>
            </div>
            <span class="tag ${statusClass}">${statusText}</span>
          </div>
          <dl>
            <dt>Host</dt><dd>${robot.host}</dd>
            <dt>Network</dt><dd>${robot.network}</dd>
            <dt>State</dt><dd>${valueOrDash(robot.state)}</dd>
            <dt>Firmware</dt><dd>${valueOrDash(robot.firmware)}</dd>
            <dt>Registered</dt><dd>${robot.registered ? 'yes' : 'no'}</dd>
            <dt>Temperature</dt><dd>${valueOrDash(robot.temperature)}</dd>
            <dt>Vibration</dt><dd>${valueOrDash(robot.vibration)}</dd>
            <dt>Diagnostic</dt><dd>${valueOrDash(robot.diagnostic_server)}</dd>
            <dt>Last HTTP</dt><dd>${valueOrDash(robot.last_diagnostic_http_code)}</dd>
          </dl>
          <div class="actions">
            <button onclick="robotAction('${robot.id}', 'status')">Status</button>
            <button onclick="robotAction('${robot.id}', 'telemetry')">Telemetry</button>
            <button onclick="robotAction('${robot.id}', 'restart')">Restart</button>
            <button class="primary wide" onclick="robotAction('${robot.id}', 'update')">Update Firmware</button>
            <button class="wide" onclick="robotAction('${robot.id}', 'diagnostic')">Set Diagnostic</button>
          </div>
        </article>
      `;
    }

    async function requestJson(url, options = {}) {
      const response = await fetch(url, options);
      const payload = await response.json();
      return payload;
    }

    async function refreshFleet() {
      const payload = await requestJson('/api/robots/summary');
      document.getElementById('robotCount').textContent = payload.count;
      document.getElementById('reachableCount').textContent = payload.reachable;
      document.getElementById('firmwareChecks').textContent =
        payload.robots.filter(robot => robot.last_firmware_check_at).length;
      robotsEl.innerHTML = payload.robots.map(robotCard).join('');
      document.getElementById('lastRefresh').textContent = new Date().toLocaleString();
    }

    async function robotAction(robotId, action) {
      let url = '';
      let options = {};
      const diagnostic = diagnosticInput.value || '';

      if (action === 'status') url = `/api/robots/${robotId}/status`;
      if (action === 'telemetry') url = `/api/robots/${robotId}/telemetry`;
      if (action === 'restart') {
        url = `/api/robots/${robotId}/restart`;
        options.method = 'POST';
      }
      if (action === 'update') {
        url = `/api/robots/${robotId}/update`;
        options.method = 'POST';
      }
      if (action === 'diagnostic') {
        url = `/api/robots/${robotId}/diagnostic-server`;
        options = {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({url: diagnostic})
        };
      }

      const payload = await requestJson(url, options);
      writeLog(`${robotId} ${action}`, payload);
      await refreshFleet();
    }

    refreshFleet();
    setInterval(refreshFleet, 10000);
  </script>
</body>
</html>
"""
