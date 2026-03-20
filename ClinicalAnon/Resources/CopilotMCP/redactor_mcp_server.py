#!/usr/bin/env python3
"""
Redactor MCP Server — Exposes Redactor Lite's HTTP API as MCP tools.

Claude Cowork calls these tools to control the app and read session data
instead of using file-based triggers and polling.

Data tools (get/write chunks, notes, session info) can read directly from disk
when given client initials, so they work even without an active session.
Live recording tools (start/stop/pause/resume) always go through the HTTP API.

Dependencies: pip install mcp httpx
"""

import asyncio
import json
import os
import re
import subprocess
from pathlib import Path

import httpx
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("redactor")

BASE = "http://127.0.0.1:8787"


# ─── Token Discovery ───────────────────────────────────────────────


def _find_token() -> str:
    """Find the auth token from .server_token file. Always reads fresh from disk."""
    # Check environment variable first
    env_token = os.environ.get("REDACTOR_TOKEN")
    if env_token:
        return env_token

    # Check for app-wide persistent token at workspace root
    # REDACTOR_EXPORT_ROOT points to .../Workspace/Sessions, token is at .../Workspace/.server_token
    export_root = os.environ.get("REDACTOR_EXPORT_ROOT")
    if export_root:
        root = Path(export_root)
        # App-wide token: one level up from Sessions/
        workspace_token = root.parent / ".server_token"
        try:
            if workspace_token.exists():
                data = json.loads(workspace_token.read_text())
                return data.get("token", "")
        except Exception:
            pass

    return ""


def _headers() -> dict:
    token = _find_token()
    if token:
        return {"Authorization": f"Bearer {token}"}
    return {}


def _reset_token():
    """No-op — token is always read fresh from disk now."""
    pass


# ─── Session Resolution (Disk Access) ─────────────────────────────


def _sessions_root() -> Path | None:
    """Return the Sessions root directory from REDACTOR_EXPORT_ROOT."""
    export_root = os.environ.get("REDACTOR_EXPORT_ROOT")
    if export_root:
        return Path(export_root)
    return None


def _resolve_session(initials: str, date: str | None = None) -> Path | None:
    """Find a session folder on disk by client initials and optional date.

    Args:
        initials: Client initials (e.g. "JB")
        date: Session date folder name (e.g. "2026-03-20_0937"). If None, uses most recent.

    Returns:
        Path to session folder, or None if not found.
    """
    root = _sessions_root()
    if not root:
        return None

    client_dir = root / initials.upper()
    if not client_dir.is_dir():
        return None

    if date:
        session_dir = client_dir / date
        return session_dir if session_dir.is_dir() else None

    # Find most recent session (folder names sort chronologically)
    sessions = sorted(
        [d for d in client_dir.iterdir() if d.is_dir()],
        key=lambda d: d.name,
        reverse=True,
    )
    return sessions[0] if sessions else None


def _read_chunks_from_disk(folder: Path, since_index: int = 0) -> str:
    """Read chunk files directly from a session folder on disk."""
    chunks = []
    for f in folder.iterdir():
        if not (f.name.startswith("chunk_") and f.name.endswith(".json")):
            continue
        match = re.match(r"chunk_(\d+)\.json", f.name)
        if not match:
            continue
        idx = int(match.group(1))
        if idx <= since_index:
            continue
        try:
            chunks.append((idx, f.read_text()))
        except Exception:
            pass

    chunks.sort(key=lambda c: c[0])
    return "[" + ",".join(c[1] for c in chunks) + "]"


# ─── App Lifecycle ─────────────────────────────────────────────────


async def _is_app_running() -> bool:
    """Check if Redactor Lite is reachable on its HTTP port."""
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(f"{BASE}/health", timeout=2)
            return resp.status_code == 200
    except httpx.ConnectError:
        return False


async def _launch_app():
    """Launch Redactor Lite and wait for its HTTP server to become available."""
    subprocess.Popen(["open", "-a", "Redactor"])
    for _ in range(30):
        await asyncio.sleep(0.5)
        if await _is_app_running():
            return
    # If "Redactor" didn't work, try "Redactor Lite"
    subprocess.Popen(["open", "-a", "Redactor Lite"])
    for _ in range(20):
        await asyncio.sleep(0.5)
        if await _is_app_running():
            return


# ─── MCP Tools: Session Discovery ─────────────────────────────────


@mcp.tool()
async def list_sessions(initials: str = "") -> str:
    """List available sessions from disk. Works without an active session.

    Args:
        initials: Client initials to filter by (e.g. "JB"). If empty, lists all clients.
    """
    root = _sessions_root()
    if not root or not root.is_dir():
        return json.dumps({"error": "REDACTOR_EXPORT_ROOT not set or Sessions folder not found"})

    if initials:
        # List sessions for a specific client
        client_dir = root / initials.upper()
        if not client_dir.is_dir():
            return json.dumps({"error": f"No sessions found for {initials.upper()}"})

        sessions = []
        for d in sorted(client_dir.iterdir(), key=lambda x: x.name, reverse=True):
            if not d.is_dir():
                continue
            sessions.append({
                "initials": initials.upper(),
                "date": d.name,
                "has_notes": (d / "clinical_notes.json").exists(),
                "has_complete": (d / "session_complete.json").exists(),
                "chunk_count": len([f for f in d.iterdir() if f.name.startswith("chunk_")]),
            })
        return json.dumps(sessions, indent=2)
    else:
        # List all clients with session counts
        clients = []
        for d in sorted(root.iterdir()):
            if not d.is_dir() or d.name.startswith("."):
                continue
            session_count = len([s for s in d.iterdir() if s.is_dir()])
            if session_count > 0:
                clients.append({
                    "initials": d.name,
                    "session_count": session_count,
                })
        return json.dumps(clients, indent=2)


# ─── MCP Tools: Live Recording Control (HTTP only) ────────────────


@mcp.tool()
async def health_check() -> str:
    """Check if Redactor app is running and the HTTP server is up."""
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(f"{BASE}/health", timeout=3)
            return resp.text
    except httpx.ConnectError:
        return json.dumps({"status": "unreachable", "error": "Cannot connect to Redactor on port 8787"})


@mcp.tool()
async def start_recording(
    initials: str,
    session_type: str = "Therapy",
    length: int = 50,
    goals: str = "",
    multi_speaker: bool = False,
) -> str:
    """Start a recording session in Redactor. Launches the app automatically if not running.

    Args:
        initials: Client initials (e.g. "JB")
        session_type: Session type — Therapy, Assessment, Supervision, Other
        length: Session length in minutes (default 50)
        goals: Newline-separated therapist goals for the session
        multi_speaker: Enable enhanced speaker diarization for group sessions
    """
    _reset_token()

    # Launch Redactor Lite if not already running
    if not await _is_app_running():
        await _launch_app()

    body = {
        "initials": initials,
        "type": session_type,
        "length": length,
        "goals": goals,
        "multiSpeaker": multi_speaker,
    }
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(f"{BASE}/start", json=body, headers=_headers(), timeout=10)
            if resp.status_code == 200:
                _reset_token()  # New session = new token
            return resp.text
    except httpx.ConnectError:
        return json.dumps({"error": "Failed to connect to Redactor after launch attempt."})


@mcp.tool()
async def stop_recording() -> str:
    """Stop the current recording session."""
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(f"{BASE}/stop", headers=_headers(), timeout=5)
            return resp.text
    except httpx.ConnectError:
        return json.dumps({"error": "Cannot connect to Redactor"})


@mcp.tool()
async def pause_recording() -> str:
    """Pause the current recording session."""
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(f"{BASE}/pause", headers=_headers(), timeout=5)
            return resp.text
    except httpx.ConnectError:
        return json.dumps({"error": "Cannot connect to Redactor"})


@mcp.tool()
async def resume_recording() -> str:
    """Resume a paused recording session."""
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(f"{BASE}/resume", headers=_headers(), timeout=5)
            return resp.text
    except httpx.ConnectError:
        return json.dumps({"error": "Cannot connect to Redactor"})


@mcp.tool()
async def write_session_state(state_json: str) -> str:
    """Write updated session state (after AI analysis of chunks). Requires active session.

    Args:
        state_json: Full session_state.json content as a JSON string.
                    Should include metrics, agenda, themes, people, etc.
    """
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"{BASE}/state",
                content=state_json,
                headers={**_headers(), "Content-Type": "application/json"},
                timeout=5,
            )
            return resp.text
    except httpx.ConnectError:
        return json.dumps({"error": "Cannot connect to Redactor"})


@mcp.tool()
async def is_session_complete() -> str:
    """Check if recording has stopped. Returns {complete: true/false}. Requires active session."""
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(f"{BASE}/complete", params={"token": _find_token()}, timeout=5)
            return resp.text
    except httpx.ConnectError:
        return json.dumps({"error": "Cannot connect to Redactor"})


# ─── MCP Tools: Data Access (Disk + HTTP fallback) ────────────────


@mcp.tool()
async def get_session_info(initials: str = "", session_date: str = "") -> str:
    """Get session metadata (initials, type, goals, date, duration).

    Args:
        initials: Client initials to read from disk (e.g. "JB"). If empty, reads from active session via HTTP.
        session_date: Session date folder (e.g. "2026-03-20_0937"). If empty, uses most recent.
    """
    if initials:
        folder = _resolve_session(initials, session_date or None)
        if not folder:
            return json.dumps({"error": f"No session found for {initials}"})
        path = folder / "session_info.json"
        if path.exists():
            return path.read_text()
        return json.dumps({"error": "session_info.json not found"})

    # Fall back to HTTP (active session)
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(f"{BASE}/session-info", params={"token": _find_token()}, timeout=5)
            return resp.text
    except httpx.ConnectError:
        return json.dumps({"error": "Cannot connect to Redactor"})


@mcp.tool()
async def get_session_state(initials: str = "", session_date: str = "") -> str:
    """Get session state (metrics, agenda, themes, people, engagement scores).

    Args:
        initials: Client initials to read from disk. If empty, reads from active session via HTTP.
        session_date: Session date folder. If empty, uses most recent.
    """
    if initials:
        folder = _resolve_session(initials, session_date or None)
        if not folder:
            return json.dumps({"error": f"No session found for {initials}"})
        path = folder / "session_state.json"
        if path.exists():
            return path.read_text()
        return json.dumps({"error": "session_state.json not found"})

    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(f"{BASE}/state", params={"token": _find_token()}, timeout=5)
            return resp.text
    except httpx.ConnectError:
        return json.dumps({"error": "Cannot connect to Redactor"})


@mcp.tool()
async def get_new_chunks(since_index: int = 0, initials: str = "", session_date: str = "") -> str:
    """Get transcript chunks since a given index.

    Args:
        since_index: Return chunks with index > this value. Use 0 to get all chunks.
        initials: Client initials to read from disk. If empty, reads from active session via HTTP.
        session_date: Session date folder. If empty, uses most recent.
    """
    if initials:
        folder = _resolve_session(initials, session_date or None)
        if not folder:
            return json.dumps({"error": f"No session found for {initials}"})
        return _read_chunks_from_disk(folder, since_index)

    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(
                f"{BASE}/chunks",
                params={"token": _find_token(), "since": since_index},
                timeout=5,
            )
            return resp.text
    except httpx.ConnectError:
        return json.dumps({"error": "Cannot connect to Redactor"})


@mcp.tool()
async def get_clinical_notes(initials: str = "", session_date: str = "") -> str:
    """Get existing clinical notes for a session.

    Args:
        initials: Client initials to read from disk. If empty, reads from active session via HTTP.
        session_date: Session date folder. If empty, uses most recent.
    """
    if initials:
        folder = _resolve_session(initials, session_date or None)
        if not folder:
            return json.dumps({"error": f"No session found for {initials}"})
        path = folder / "clinical_notes.json"
        if path.exists():
            return path.read_text()
        return json.dumps({"error": "No clinical notes found for this session"})

    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(
                f"{BASE}/notes", params={"token": _find_token()}, timeout=5
            )
            return resp.text
    except httpx.ConnectError:
        return json.dumps({"error": "Cannot connect to Redactor"})


@mcp.tool()
async def write_clinical_notes(notes_json: str, initials: str = "", session_date: str = "") -> str:
    """Write clinical notes for a session.

    Args:
        notes_json: Full clinical_notes.json content as a JSON string.
                    Should include session_id, generated_at, and sections
                    (clinical_notes, client_summary, clinical_review).
        initials: Client initials to write to disk. If empty, writes via active session HTTP.
        session_date: Session date folder. If empty, uses most recent.
    """
    if initials:
        folder = _resolve_session(initials, session_date or None)
        if not folder:
            return json.dumps({"error": f"No session found for {initials}"})
        path = folder / "clinical_notes.json"
        try:
            # Pretty-print if valid JSON
            parsed = json.loads(notes_json)
            path.write_text(json.dumps(parsed, indent=2, sort_keys=True))
        except (json.JSONDecodeError, TypeError):
            path.write_text(notes_json)
        return json.dumps({"status": "ok", "path": str(path)})

    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"{BASE}/notes",
                content=notes_json,
                headers={**_headers(), "Content-Type": "application/json"},
                timeout=10,
            )
            return resp.text
    except httpx.ConnectError:
        return json.dumps({"error": "Cannot connect to Redactor"})


if __name__ == "__main__":
    mcp.run()
