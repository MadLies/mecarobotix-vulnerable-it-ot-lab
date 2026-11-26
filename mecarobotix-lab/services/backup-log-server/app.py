import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import FastAPI
from pydantic import BaseModel


BACKUPS = Path("/srv/backups")
LOGS = Path("/srv/logs")
LOG_RETENTION_SECONDS = int(os.getenv("LOG_RETENTION_SECONDS", "60"))

app = FastAPI(title="MecaRobotix Backup/Log Server", version="0.2.0")


class LogEntry(BaseModel):
    source: str = "unknown"
    message: str


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def ensure_dirs() -> None:
    BACKUPS.mkdir(parents=True, exist_ok=True)
    LOGS.mkdir(parents=True, exist_ok=True)


def file_summary(path: Path) -> dict[str, Any]:
    stat = path.stat()
    return {
        "file_name": path.name,
        "size_bytes": stat.st_size,
        "complete": stat.st_size > 0,
        "last_modified_utc": datetime.fromtimestamp(
            stat.st_mtime,
            timezone.utc,
        ).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


@app.get("/")
def root() -> dict[str, Any]:
    return {
        "service": "backup-log-server",
        "status": "running",
        "role": "central backup and log collector",
        "warning": "lab mode: service is intentionally misconfigured",
    }


@app.get("/health")
def health() -> dict[str, Any]:
    ensure_dirs()
    return {
        "status": "ok",
        "reported_healthy": True,
        "usable_backups": any(p.stat().st_size > 0 for p in BACKUPS.iterdir() if p.is_file()),
        "note": "Health check reports ok even when backups are empty or logs are short-lived.",
    }


@app.get("/backups")
def backups() -> dict[str, Any]:
    ensure_dirs()
    files = [file_summary(p) for p in sorted(BACKUPS.iterdir()) if p.is_file()]
    return {
        "backup_directory": str(BACKUPS),
        "count": len(files),
        "files": files,
        "problem": "Backups exist by name, but zero-byte files are incomplete and not restorable.",
    }


@app.get("/logs")
def logs() -> dict[str, Any]:
    ensure_dirs()
    files = [file_summary(p) for p in sorted(LOGS.iterdir()) if p.is_file()]
    return {
        "log_directory": str(LOGS),
        "retention_seconds": LOG_RETENTION_SECONDS,
        "count": len(files),
        "files": files,
        "problem": "Logs are aggressively deleted, so incidents may leave no useful evidence.",
    }


@app.post("/logs")
def ingest_log(entry: LogEntry) -> dict[str, Any]:
    ensure_dirs()
    filename = f"{utc_now()}-{entry.source}.log".replace(":", "")
    path = LOGS / filename
    path.write_text(f"{utc_now()} {entry.source}: {entry.message}\n")
    path.chmod(0o666)
    return {
        "stored": True,
        "file_name": filename,
        "retention_seconds": LOG_RETENTION_SECONDS,
        "warning": "Log accepted, but retention policy will delete it quickly.",
    }


@app.get("/audit")
def audit() -> dict[str, Any]:
    ensure_dirs()
    backup_files = [p for p in BACKUPS.iterdir() if p.is_file()]
    log_files = [p for p in LOGS.iterdir() if p.is_file()]
    return {
        "misconfigured": True,
        "findings": [
            {
                "id": "insecure_permissions",
                "description": "Backup and log directories are world-writable.",
                "paths": [str(BACKUPS), str(LOGS)],
                "mode": "0777 directories, 0666 seeded backup files",
                "impact": "Any local user can tamper with or delete backups and logs.",
            },
            {
                "id": "empty_backups",
                "description": "Seeded backup files are zero bytes.",
                "zero_byte_backups": [p.name for p in backup_files if p.stat().st_size == 0],
                "impact": "The organization believes backups exist, but they cannot restore from them.",
            },
            {
                "id": "short_log_retention",
                "description": "Logs are deleted after roughly one minute.",
                "current_log_count": len(log_files),
                "retention_seconds": LOG_RETENTION_SECONDS,
                "impact": "Incident investigation can fail because evidence disappears too quickly.",
            },
            {
                "id": "false_health_status",
                "description": "The health endpoint reports ok despite unusable backups.",
                "impact": "Monitoring may miss a business-critical backup failure.",
            },
        ],
    }
