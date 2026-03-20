#!/usr/bin/env python3
"""
Redactor MCP Server — Exposes Redactor Lite's HTTP API as MCP tools.

Claude Cowork calls these tools to control the app and read session data
instead of using file-based triggers and polling.

Dependencies: pip install mcp httpx
"""

import asyncio
import json
import os
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

    # Search for most recent .server_token in session folders
    export_root = os.environ.get("REDACTOR_EXPORT_ROOT")
    if export_root:
        root = Path(export_root)
        try:
            token_files = sorted(
                root.rglob(".server_token"),
                key=lambda f: f.stat().st_mtime,
                reverse=True,
            )
            if token_files:
                data = json.loads(token_files[0].read_text())
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


# ─── MCP Tools ─────────────────────────────────────────────────────


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
async def get_session_info() -> str:
    """Get session metadata (initials, type, goals, date, duration)."""
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(f"{BASE}/session-info", params={"token": _find_token()}, timeout=5)
            return resp.text
    except httpx.ConnectError:
        return json.dumps({"error": "Cannot connect to Redactor"})


@mcp.tool()
async def get_session_state() -> str:
    """Get current session state (metrics, agenda, themes, people, engagement scores)."""
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(f"{BASE}/state", params={"token": _find_token()}, timeout=5)
            return resp.text
    except httpx.ConnectError:
        return json.dumps({"error": "Cannot connect to Redactor"})


@mcp.tool()
async def get_new_chunks(since_index: int = 0) -> str:
    """Get transcript chunks since a given index.

    Args:
        since_index: Return chunks with index > this value. Use 0 to get all chunks.
                     Track the latest_index from the response to poll for new chunks.
    """
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
async def write_session_state(state_json: str) -> str:
    """Write updated session state (after AI analysis of chunks).

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
    """Check if recording has stopped. Returns {complete: true/false}."""
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(f"{BASE}/complete", params={"token": _find_token()}, timeout=5)
            return resp.text
    except httpx.ConnectError:
        return json.dumps({"error": "Cannot connect to Redactor"})


if __name__ == "__main__":
    mcp.run()
