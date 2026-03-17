#!/usr/bin/env python3
"""
Live Session Pipeline — Cowork Integration (One-Shot Mode)

Processes all available chunks and AI deltas in a single pass, then exits.
Designed to be called repeatedly by Cowork's orchestration loop.

Each invocation:
  1. Finds the most recent session folder
  2. Loads or creates session state
  3. Processes any new chunk files (local calculations)
  4. Merges any new ai_delta_NNN.json files
  5. Writes updated session_state.json
  6. Prints status to stdout (which chunks were processed, session complete, etc.)

Cowork calls this between AI analysis steps. The AI analysis itself is done
by Claude, not by this script.

Usage:
    python3 session_pipeline.py <root_export_folder>

Output (JSON to stdout):
    {
      "session_path": "/path/to/session",
      "new_chunks": [1, 2],
      "new_deltas": ["ai_delta_001.json"],
      "total_chunks": 5,
      "complete": false
    }
"""

import json
import os
import sys
import re
from pathlib import Path

# ═══════════════════════════════════════════════════
# LOCAL CALCULATIONS
# ═══════════════════════════════════════════════════

def ts_to_sec(ts):
    p = ts.split(":")
    return int(p[0])*3600 + int(p[1])*60 + int(p[2]) if len(p)==3 else 0

def wc(text):
    cleaned = re.sub(r'\([^)]*\)', '', text).strip()
    return len(cleaned.split()) if cleaned else 0

class SessionState:
    def __init__(self, info):
        self.info = info
        self.chunks_processed = 0
        self.last_ts = "00:00:00"
        self.second_speaker_at = None
        self.ther_sec = 0.0
        self.cli_sec = 0.0
        self.ther_q = 0; self.ther_sr = 0; self.ther_cr = 0
        self.cli_turns = 0; self.cli_words = 0; self.elab_turns = 0
        self.all_segs = []
        goals = info.get("therapist_goals", [])
        self.ther_agenda = [{"id":f"ta{i+1}","text":g,"status":"not_discussed","evidence":[]} for i,g in enumerate(goals)]
        self.cli_agenda = []
        self.people = []
        self.themes = []
        self.rupture = {"detected":False,"type":None,"chunk_index":None,"timestamp":None}
        self.risk = {"flagged":False,"chunk_index":None,"timestamp":None}

    def process_chunk(self, chunk):
        for seg in chunk.get("segments",[]):
            sp = seg["speaker"]; text = seg["text"]; ts = seg.get("timestamp","00:00:00")
            words = wc(text); dur = words * 0.4
            self.all_segs.append({"speaker":sp,"ts_sec":ts_to_sec(ts),"words":words,"dur":dur,"chunk":chunk["chunk_index"]})
            if sp == "therapist":
                self.ther_sec += dur
            elif sp.startswith("client"):
                self.cli_sec += dur; self.cli_turns += 1; self.cli_words += words
                if self.second_speaker_at is None: self.second_speaker_at = ts
                sents = len(re.split(r'[.!?]+', text.strip()))
                if sents >= 3 or words >= 40: self.elab_turns += 1
        self.chunks_processed = chunk["chunk_index"]
        self.last_ts = chunk.get("timestamp_end","00:00:00")

    def apply_delta(self, delta):
        for uc in delta.get("utterance_classifications",[]):
            t = uc.get("type","O")
            if t=="Q": self.ther_q+=1
            elif t=="SR": self.ther_sr+=1
            elif t=="CR": self.ther_cr+=1
        for au in delta.get("agenda_updates",[]):
            for item in self.ther_agenda:
                if item["id"]==au.get("id"):
                    ns = au.get("new_status")
                    order = ["not_discussed","partially_discussed","fully_discussed"]
                    if ns and order.index(ns) > order.index(item["status"]): item["status"]=ns
                    action = au.get("evidence_action","append"); items = au.get("evidence_items",[])
                    if action=="append": item["evidence"].extend(items)
                    elif action=="synthesise" and items: item["evidence"]=items
        for ca in delta.get("new_client_agenda_items",[]):
            if ca.get("confidence")=="high":
                self.cli_agenda.append({"id":ca.get("id",f"ca{len(self.cli_agenda)+1}"),"text":ca.get("text",""),"status":"partially_discussed","evidence":[]})
        for pu in delta.get("people_updates",[]):
            tok = pu.get("token","")
            ex = next((p for p in self.people if p["token"]==tok), None)
            if ex:
                if pu.get("new_details"): ex.setdefault("details",{}).update(pu["new_details"])
                if pu.get("new_events"): ex.setdefault("events",[]).extend(pu["new_events"])
            else:
                self.people.append({"token":tok,"role":pu.get("role","unknown"),"details":pu.get("new_details",{}),"events":pu.get("new_events",[])})
        for tu in delta.get("theme_updates",[]):
            a = tu.get("action","")
            if a=="add_phrase":
                for th in self.themes:
                    if th["id"]==tu.get("theme_id"): th["phrases"].append(tu.get("phrase","")); break
            elif a=="new_theme":
                nt = tu.get("theme",{}); rep = tu.get("replaces")
                if rep: self.themes = [t for t in self.themes if t["id"]!=rep]
                self.themes.append({"id":nt.get("id",f"th{len(self.themes)+1}"),"text":nt.get("text",""),"phrases":nt.get("phrases",[])})
            elif a=="rename":
                for th in self.themes:
                    if th["id"]==tu.get("theme_id"): th["text"]=tu.get("new_text",th["text"]); break
            elif a=="merge":
                drop = next((t for t in self.themes if t["id"]==tu.get("drop_id")),None)
                if drop:
                    for th in self.themes:
                        if th["id"]==tu.get("keep_id"): th["phrases"].extend(drop.get("phrases",[])); break
                    self.themes = [t for t in self.themes if t["id"]!=tu.get("drop_id")]
        if delta.get("rupture_signal"):
            rs = delta["rupture_signal"]
            self.rupture = {"detected":True,"type":rs.get("type"),"chunk_index":self.chunks_processed,"timestamp":self.last_ts}
        if delta.get("risk_signal") and not self.risk["flagged"]:
            self.risk = {"flagged":True,"chunk_index":self.chunks_processed,"timestamp":self.last_ts}

    def to_json(self):
        total = self.ther_sec + self.cli_sec
        cpct = (self.cli_sec/total*100) if total>0 else 0
        rq = ((self.ther_sr+self.ther_cr)/self.ther_q) if self.ther_q>0 else 0
        mw = (self.cli_words/self.cli_turns) if self.cli_turns>0 else 0
        tc = cpct; tlc = min(mw/40*100,100)
        ec = (self.elab_turns/self.cli_turns*100) if self.cli_turns>0 else 0
        eng = tc*0.5 + tlc*0.3 + ec*0.2
        now = ts_to_sec(self.last_ts); ws = max(0,now-600)
        wseg = [s for s in self.all_segs if s["ts_sec"]>=ws]
        wt = sum(s["dur"] for s in wseg if s["speaker"]=="therapist")
        wc_ = sum(s["dur"] for s in wseg if s["speaker"].startswith("client"))
        wtot = wt+wc_; wpct = (wc_/wtot*100) if wtot>0 else 0
        return {
            "session_id": self.info.get("session_id",""),
            "session_type": self.info.get("session_type",""),
            "session_date": self.info.get("session_date",""),
            "session_start": "00:00:00",
            "session_duration_seconds": self.info.get("session_duration_minutes",50)*60,
            "chunks_processed": self.chunks_processed,
            "last_chunk_timestamp": self.last_ts,
            "second_speaker_at": self.second_speaker_at,
            "speaker_totals": {"therapist_seconds":round(self.ther_sec,1),"client_seconds":round(self.cli_sec,1),"client_talk_pct":round(cpct,1)},
            "utterance_counts": {"therapist_questions":self.ther_q,"therapist_sr":self.ther_sr,"therapist_cr":self.ther_cr,"rq_ratio":round(rq,2)},
            "rolling_10m": {"window_start_timestamp":f"{int(ws//3600):02d}:{int((ws%3600)//60):02d}:{int(ws%60):02d}","therapist_seconds":round(wt,1),"client_seconds":round(wc_,1),"client_talk_pct":round(wpct,1),"engagement_score":round(eng,1)},
            "engagement": {"session_score":round(eng,1),"mean_client_words_per_turn":round(mw,1),"elaborated_turns":self.elab_turns,"total_client_turns":self.cli_turns},
            "therapist_agenda": self.ther_agenda, "client_agenda": self.cli_agenda,
            "people": self.people, "themes": self.themes,
            "rupture": self.rupture, "risk": self.risk,
        }

    def save(self, folder):
        with open(Path(folder)/"session_state.json","w") as f: json.dump(self.to_json(), f, indent=2)

# ═══════════════════════════════════════════════════
# STATE PERSISTENCE (between one-shot invocations)
# ═══════════════════════════════════════════════════

PIPELINE_STATE_FILE = ".pipeline_state.json"

def load_pipeline_state(session_path):
    """Load tracking state (which chunks/deltas have been processed)."""
    p = Path(session_path) / PIPELINE_STATE_FILE
    if p.exists():
        with open(p) as f:
            return json.load(f)
    return {"processed_chunks": [], "processed_deltas": []}

def save_pipeline_state(session_path, pstate):
    """Save tracking state for next invocation."""
    with open(Path(session_path) / PIPELINE_STATE_FILE, "w") as f:
        json.dump(pstate, f)

# ═══════════════════════════════════════════════════
# ONE-SHOT PROCESSOR
# ═══════════════════════════════════════════════════

def find_session(root):
    """Find the most recent session folder with session_info.json."""
    folders = sorted([d for d in Path(root).iterdir() if d.is_dir() and (d/"session_info.json").exists()],
                     key=lambda d: d.stat().st_mtime, reverse=True)
    return folders[0] if folders else None

def run_once(root_folder):
    """Single-pass: process all new chunks and deltas, save state, exit."""
    session_path = find_session(root_folder)
    if not session_path:
        print(json.dumps({"error": "no_session", "message": "No session folder found"}))
        return

    # Load session info
    with open(session_path / "session_info.json") as f:
        info = json.load(f)

    # Load pipeline tracking state
    pstate = load_pipeline_state(session_path)
    processed_chunks = set(pstate["processed_chunks"])
    processed_deltas = set(pstate["processed_deltas"])

    # Init SessionState and replay all previously processed chunks + deltas
    state = SessionState(info)
    files = set(os.listdir(session_path))

    # Replay processed chunks in order
    for idx in sorted(processed_chunks):
        cf = f"chunk_{idx:03d}.json"
        if cf in files:
            with open(session_path / cf) as f:
                state.process_chunk(json.load(f))

    # Replay processed deltas
    for df in sorted(processed_deltas):
        if df in files:
            with open(session_path / df) as f:
                state.apply_delta(json.load(f))

    # Process NEW chunks
    new_chunks = []
    chunk_files = sorted([f for f in files if f.startswith("chunk_") and f.endswith(".json")])
    for cf in chunk_files:
        idx = int(cf.replace("chunk_", "").replace(".json", ""))
        if idx in processed_chunks:
            continue
        # Ensure sequential processing
        expected = max(processed_chunks) + 1 if processed_chunks else 1
        if idx != expected:
            continue
        with open(session_path / cf) as f:
            chunk = json.load(f)
        state.process_chunk(chunk)
        processed_chunks.add(idx)
        new_chunks.append(idx)

    # Process NEW AI deltas
    new_deltas = []
    delta_files = sorted([f for f in files if f.startswith("ai_delta_") and f.endswith(".json")])
    for df in delta_files:
        if df in processed_deltas:
            continue
        try:
            with open(session_path / df) as f:
                delta = json.load(f)
            state.apply_delta(delta)
            processed_deltas.add(df)
            new_deltas.append(df)
        except Exception as e:
            print(json.dumps({"warning": f"Failed to read {df}: {e}"}), file=sys.stderr)

    # Save session state
    state.save(session_path)

    # Save pipeline tracking state
    save_pipeline_state(session_path, {
        "processed_chunks": sorted(processed_chunks),
        "processed_deltas": sorted(processed_deltas)
    })

    # Check for completion
    complete = "session_complete.json" in files

    # Output status as JSON
    result = {
        "session_path": str(session_path),
        "session_id": info.get("session_id", ""),
        "new_chunks": new_chunks,
        "new_deltas": new_deltas,
        "total_chunks": len(processed_chunks),
        "total_deltas": len(processed_deltas),
        "complete": complete
    }
    print(json.dumps(result))

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"error": "usage", "message": "session_pipeline.py <root_export_folder>"}))
        sys.exit(1)
    run_once(sys.argv[1])
