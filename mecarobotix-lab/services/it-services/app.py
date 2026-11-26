import os
from pathlib import Path
from html import escape
from urllib.parse import quote

from fastapi import FastAPI
from fastapi import HTTPException
from fastapi.responses import FileResponse, HTMLResponse

SHARE = Path("/srv/share")
app = FastAPI(title="MécaRobotix IT Services", version="0.1.0")

@app.get("/")
def root():
    return {"service": os.getenv("APP_NAME", "it-services"), "role": os.getenv("APP_ROLE", "file share/admin panel")}

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/files")
def list_files():
    SHARE.mkdir(parents=True, exist_ok=True)
    files = sorted(p.relative_to(SHARE) for p in SHARE.rglob("*") if p.is_file())

    if files:
        rows = "\n".join(
            f'<li><a href="/files/download/{quote(str(path))}">{escape(str(path))}</a></li>'
            for path in files
        )
    else:
        rows = "<li>No files available</li>"

    html = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MecaRobotix File Share</title>
  <style>
    body {{
      margin: 2rem;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: #17202a;
      background: #f7f9fb;
    }}
    main {{
      max-width: 760px;
    }}
    h1 {{
      margin-bottom: 0.25rem;
      font-size: 1.8rem;
    }}
    p {{
      margin-top: 0;
      color: #52616f;
    }}
    ul {{
      padding: 0;
      list-style: none;
    }}
    li {{
      margin: 0.5rem 0;
      border: 1px solid #d8e0e8;
      background: white;
    }}
    a {{
      display: block;
      padding: 0.75rem 1rem;
      color: #0b5cad;
      text-decoration: none;
      overflow-wrap: anywhere;
    }}
    a:hover {{
      background: #eef5fc;
      text-decoration: underline;
    }}
  </style>
</head>
<body>
  <main>
    <h1>MecaRobotix File Share</h1>
    <p>Click a file to download it.</p>
    <ul>
      {rows}
    </ul>
  </main>
</body>
</html>"""

    return HTMLResponse(html)

@app.get("/files/download/{file_path:path}")
def download_file(file_path: str):
    share_root = SHARE.resolve()
    path = (share_root / file_path).resolve()

    if not path.is_relative_to(share_root) or not path.is_file():
        raise HTTPException(status_code=404, detail="File not found")

    return FileResponse(
        path,
        media_type="application/octet-stream",
        filename=path.name,
    )

@app.get("/admin")
def admin_panel():
    return {"panel": "internal admin panel", "status": "running"}
