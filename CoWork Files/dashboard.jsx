import { useState, useEffect, useRef, useCallback } from "react";

/* ─── TOKENS ─── */
const T = {
  bg:     '#070C17',
  panel:  '#0B1422',
  card:   '#0F1D30',
  border: '#162338',
  text:   '#C4D8F0',
  dim:    '#3D5A78',
  muted:  '#6E8FA8',
  subtle: '#12243A',
  teal:   '#1ECFB0',
  blue:   '#4A9EFF',
  amber:  '#F0A429',
  red:    '#F05050',
  green:  '#22C87A',
  white:  '#E4F0FF',
};

const SERVER = "http://127.0.0.1:8787";
const POLL_MS = 5000;

// Auth token injected by pipeline at render time — replaced before presenting dashboard
const AUTH_TOKEN = "__SESSION_TOKEN__";

/* ─── ENTITY SUBSTITUTION ─── */
function substitute(text, entityMap) {
  if (!text || !entityMap) return text;
  let result = text;
  for (const [code, realValue] of Object.entries(entityMap)) {
    // Replace [CODE] with real value for therapist display
    result = result.replace(new RegExp(`\\[${code}\\]`, 'g'), realValue);
  }
  return result;
}

/* ─── ARC GAUGE ─── */
function toXY(cx, cy, r, deg) {
  const rad = ((deg - 90) * Math.PI) / 180;
  return [cx + r * Math.cos(rad), cy + r * Math.sin(rad)];
}
function arcD(cx, cy, r, startDeg, sweepDeg) {
  if (sweepDeg <= 0) return "";
  const [sx, sy] = toXY(cx, cy, r, startDeg);
  const [ex, ey] = toXY(cx, cy, r, startDeg + sweepDeg);
  const large = sweepDeg > 180 ? 1 : 0;
  return `M ${sx.toFixed(2)} ${sy.toFixed(2)} A ${r} ${r} 0 ${large} 1 ${ex.toFixed(2)} ${ey.toFixed(2)}`;
}
function gaugeColor(v, zones) {
  for (const z of zones) if (v >= z.min && v <= z.max) return z.color;
  return T.dim;
}
function ArcGauge({ value, max = 100, label, zones, size = 88 }) {
  const cx = size / 2, cy = size / 2 + 4, r = size / 2 - 10;
  const START = 218, SWEEP = 284;
  const vSweep = Math.max(0, Math.min(SWEEP, (value / max) * SWEEP));
  const color = zones ? gaugeColor(value, zones) : T.teal;
  const [nx, ny] = vSweep > 0 ? toXY(cx, cy, r, START + vSweep) : [0, 0];
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 3 }}>
      <svg width={size} height={size * 0.82} style={{ overflow: "visible" }}>
        <path d={arcD(cx, cy, r, START, SWEEP)} fill="none" stroke={T.border} strokeWidth={5} strokeLinecap="round" />
        {vSweep > 0 && <path d={arcD(cx, cy, r, START, vSweep)} fill="none" stroke={color} strokeWidth={5} strokeLinecap="round" />}
        {vSweep > 0 && <circle cx={nx} cy={ny} r={3.5} fill={color} />}
        <text x={cx} y={cy + 3} textAnchor="middle" fill={T.white} fontSize={13}
          fontFamily="'IBM Plex Mono', monospace" fontWeight="700">{Math.round(value)}%</text>
      </svg>
      <span style={{ fontSize: 8, color: T.muted, fontFamily: "'Outfit', sans-serif",
        textTransform: "uppercase", letterSpacing: "0.1em" }}>{label}</span>
    </div>
  );
}

/* ─── R:Q RATIO GAUGE ─── */
function RQGauge({ ratio, size = 88 }) {
  const MAX_RATIO = 4, THRESHOLD = 2.0;
  const cx = size / 2, cy = size / 2 + 4, r = size / 2 - 10;
  const START = 218, SWEEP = 284;
  const vSweep = Math.max(0, Math.min(SWEEP, (ratio / MAX_RATIO) * SWEEP));
  const threshSweep = (THRESHOLD / MAX_RATIO) * SWEEP;
  const color = ratio >= THRESHOLD ? T.teal : ratio >= 1.0 ? T.amber : T.red;
  const [nx, ny] = vSweep > 0 ? toXY(cx, cy, r, START + vSweep) : [0, 0];
  const [tx, ty] = toXY(cx, cy, r, START + threshSweep);
  const [txi, tyi] = toXY(cx, cy, r - 7, START + threshSweep);
  const display = ratio > 0 ? `${ratio.toFixed(1)}:1` : "\u2014";
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 3 }}>
      <svg width={size} height={size * 0.82} style={{ overflow: "visible" }}>
        <path d={arcD(cx, cy, r, START, SWEEP)} fill="none" stroke={T.border} strokeWidth={5} strokeLinecap="round" />
        {vSweep > 0 && <path d={arcD(cx, cy, r, START, vSweep)} fill="none" stroke={color} strokeWidth={5} strokeLinecap="round" />}
        <line x1={txi.toFixed(2)} y1={tyi.toFixed(2)} x2={tx.toFixed(2)} y2={ty.toFixed(2)}
          stroke={T.white} strokeWidth={2} strokeLinecap="round" opacity={0.6} />
        {vSweep > 0 && <circle cx={nx} cy={ny} r={3.5} fill={color} />}
        <text x={cx} y={cy + 3} textAnchor="middle" fill={T.white} fontSize={11}
          fontFamily="'IBM Plex Mono', monospace" fontWeight="700">{display}</text>
        <text x={cx} y={cy + 14} textAnchor="middle" fill={T.dim} fontSize={7}
          fontFamily="'IBM Plex Mono', monospace">2:1</text>
      </svg>
      <span style={{ fontSize: 8, color: T.muted, fontFamily: "'Outfit', sans-serif",
        textTransform: "uppercase", letterSpacing: "0.1em" }}>R:Q Ratio</span>
    </div>
  );
}

/* ─── STATUS CONFIGS ─── */
const SC = {
  not_discussed:      { sym: "\u25CB", color: T.dim,   bg: "transparent" },
  partially_discussed:{ sym: "\u25D1", color: T.amber, bg: "rgba(240,164,41,0.08)" },
  fully_discussed:    { sym: "\u25CF", color: T.green, bg: "rgba(34,200,122,0.08)" },
};

/* ─── AGENDA ITEM ─── */
function AgendaItem({ item, expanded, onToggle, entityMap }) {
  const cfg = SC[item.status] || SC.not_discussed;
  return (
    <div style={{ borderRadius: 6, marginBottom: 4,
      border: `1px solid ${expanded ? T.border : "transparent"}`,
      background: expanded ? T.card : cfg.bg, transition: "all 0.2s ease" }}>
      <button onClick={onToggle} style={{ display: "flex", alignItems: "center", gap: 7,
        width: "100%", padding: "7px 8px", background: "transparent",
        border: "none", cursor: "pointer", borderRadius: expanded ? "6px 6px 0 0" : 6, textAlign: "left" }}>
        <span style={{ fontSize: 13, color: cfg.color, flexShrink: 0, width: 14, lineHeight: 1 }}>{cfg.sym}</span>
        <span style={{ fontSize: 11, color: T.text, fontFamily: "'Outfit', sans-serif", flex: 1, lineHeight: 1.35 }}>
          {substitute(item.text, entityMap)}
        </span>
        {item.evidence && item.evidence.length > 0 && <>
          <span style={{ fontSize: 9, color: T.muted, fontFamily: "'IBM Plex Mono', monospace" }}>
            {item.evidence.length}
          </span>
          <span style={{ fontSize: 9, color: T.dim, transform: expanded ? "rotate(180deg)" : "none",
            transition: "transform 0.2s", lineHeight: 1 }}>{"\u25BE"}</span>
        </>}
      </button>
      {expanded && item.evidence && item.evidence.length > 0 && (
        <div style={{ padding: "4px 8px 8px 29px", display: "flex", flexDirection: "column", gap: 4 }}>
          {item.evidence.map((e, i) => (
            <div key={i} style={{ fontSize: 10.5, lineHeight: 1.45,
              color: e.type === "quote" ? T.teal : T.muted,
              fontFamily: e.type === "quote" ? "'IBM Plex Mono', monospace" : "'Outfit', sans-serif",
              background: e.type === "quote" ? "rgba(30,207,176,0.06)" : T.subtle,
              borderLeft: `2px solid ${e.type === "quote" ? T.teal : T.border}`,
              padding: "4px 8px", borderRadius: "0 4px 4px 0" }}>
              {e.type === "quote" ? `"${substitute(e.text, entityMap)}"` : substitute(e.text, entityMap)}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

/* ─── SECTION LABEL ─── */
const SL = ({ label }) => (
  <div style={{ fontSize: 8, color: T.dim, fontFamily: "'Outfit', sans-serif",
    textTransform: "uppercase", letterSpacing: "0.14em", fontWeight: 700,
    paddingBottom: 6, marginBottom: 8, borderBottom: `1px solid ${T.border}` }}>
    {label}
  </div>
);

/* ─── THEME COLORS ─── */
const THEME_COLORS = [T.teal, '#4A9EFF', '#F0A429', '#A78BFA', '#F07A7A', '#5BE6B0', '#FFD580'];

/* ─── THEME ITEM ─── */
function ThemeItem({ theme, color, expanded, onToggle, entityMap }) {
  return (
    <div style={{ borderRadius: 6, marginBottom: 5,
      border: `1px solid ${expanded ? color + '40' : color + '20'}`,
      background: expanded ? color + '0D' : color + '08',
      transition: "all 0.2s ease" }}>
      <button onClick={onToggle} style={{ display: "flex", alignItems: "center", gap: 8,
        width: "100%", padding: "7px 10px", background: "transparent",
        border: "none", cursor: "pointer", textAlign: "left" }}>
        <span style={{ width: 7, height: 7, borderRadius: "50%", background: color,
          flexShrink: 0, marginTop: 1 }} />
        <span style={{ fontSize: 11.5, color, fontFamily: "'Outfit', sans-serif",
          fontWeight: 600, flex: 1, lineHeight: 1.3 }}>{theme.text}</span>
        {theme.phrases && theme.phrases.length > 0 && <>
          <span style={{ fontSize: 9, color: color + 'AA', fontFamily: "'IBM Plex Mono', monospace" }}>
            {theme.phrases.length}
          </span>
          <span style={{ fontSize: 9, color: color + '88',
            transform: expanded ? "rotate(180deg)" : "none",
            transition: "transform 0.2s", lineHeight: 1 }}>{"\u25BE"}</span>
        </>}
      </button>
      {expanded && theme.phrases && theme.phrases.length > 0 && (
        <div style={{ padding: "0 10px 8px 25px", display: "flex", flexDirection: "column", gap: 4 }}>
          {theme.phrases.map((p, i) => (
            <div key={i} style={{ fontSize: 10.5, color: T.teal,
              fontFamily: "'IBM Plex Mono', monospace",
              background: "rgba(30,207,176,0.06)",
              borderLeft: `2px solid ${T.teal}`,
              padding: "4px 9px", borderRadius: "0 4px 4px 0", lineHeight: 1.4 }}>
              "{substitute(p, entityMap)}"
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

/* ─── PERSON CARD ─── */
function PersonCard({ person, entityMap }) {
  const details = [];
  if (person.role && person.role !== "unknown") details.push(person.role);
  if (person.details) {
    if (person.details.age) details.push(`age ${substitute(person.details.age, entityMap)}`);
    if (person.details.location) details.push(substitute(person.details.location, entityMap));
  }
  // Resolve token to real name for display
  const displayName = person.token
    ? substitute(person.token, entityMap)
    : person.name || "Unknown";
  return (
    <div style={{ background: T.subtle, border: `1px solid ${T.border}`, borderRadius: 6,
      padding: "6px 9px", marginBottom: 5 }}>
      <div style={{ display: "flex", alignItems: "baseline", gap: 6,
        marginBottom: details.length || (person.events && person.events.length) ? 3 : 0 }}>
        <span style={{ fontSize: 11, color: T.blue, fontFamily: "'Outfit', sans-serif", fontWeight: 600 }}>
          {displayName}
        </span>
        {details.length > 0 && (
          <span style={{ fontSize: 9.5, color: T.muted, fontFamily: "'Outfit', sans-serif" }}>
            {details.join(" \u00B7 ")}
          </span>
        )}
      </div>
      {person.events && person.events.map((ev, i) => (
        <div key={i} style={{ fontSize: 10, color: T.muted, fontFamily: "'Outfit', sans-serif",
          paddingLeft: 8, borderLeft: `1px solid ${T.border}`, lineHeight: 1.4 }}>
          {substitute(ev, entityMap)}
        </div>
      ))}
    </div>
  );
}

/* ─── CONNECTION STATUS ─── */
function StatusDot({ connected, chunks }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
      <div style={{
        width: 6, height: 6, borderRadius: "50%",
        background: connected ? T.green : T.red,
        boxShadow: connected ? `0 0 6px ${T.green}` : "none",
        transition: "all 0.3s"
      }} />
      <span style={{ fontSize: 9, color: connected ? T.muted : T.red,
        fontFamily: "'IBM Plex Mono', monospace" }}>
        {connected ? `LIVE \u00B7 ${chunks} chunks` : "Connecting\u2026"}
      </span>
    </div>
  );
}

/* ─── MAIN DASHBOARD ─── */
export default function LiveTherapyDashboard() {
  const [state, setState] = useState(null);
  const [entityMap, setEntityMap] = useState({});
  const [connected, setConnected] = useState(false);
  const [complete, setComplete] = useState(false);
  const [expanded, setExpanded] = useState(null);
  const [viewMode, setViewMode] = useState("session");
  const pollRef = useRef(null);

  // Poll server for state + entities (token required on every request)
  const q = AUTH_TOKEN !== "__SESSION_TOKEN__" ? `?token=${AUTH_TOKEN}` : "";
  const poll = useCallback(async () => {
    try {
      const [stateRes, entityRes, completeRes] = await Promise.all([
        fetch(`${SERVER}/state${q}`),
        fetch(`${SERVER}/entities${q}`),
        fetch(`${SERVER}/complete${q}`),
      ]);
      if (stateRes.ok) {
        const data = await stateRes.json();
        setState(data);
        setConnected(true);
      }
      if (entityRes.ok) {
        const data = await entityRes.json();
        setEntityMap(data.mappings || {});
      }
      if (completeRes.ok) {
        const data = await completeRes.json();
        if (data.completed_at) setComplete(true);
      }
    } catch {
      setConnected(false);
    }
  }, []);

  useEffect(() => {
    poll(); // Initial fetch
    pollRef.current = setInterval(poll, POLL_MS);
    return () => clearInterval(pollRef.current);
  }, [poll]);

  // Stop polling once session is complete (one final fetch already done)
  useEffect(() => {
    if (complete && pollRef.current) {
      clearInterval(pollRef.current);
      pollRef.current = null;
    }
  }, [complete]);

  const s = state;

  const parseTS = (ts) => {
    if (!ts) return 0;
    const p = ts.split(":");
    return (parseInt(p[0])||0)*3600 + (parseInt(p[1])||0)*60 + (parseInt(p[2])||0);
  };

  const talkZones = [
    { min: 0,  max: 49, color: T.red   },
    { min: 50, max: 64, color: T.amber },
    { min: 65, max: 100, color: T.teal },
  ];
  const engZones = [
    { min: 0,  max: 44, color: T.red   },
    { min: 45, max: 64, color: T.amber },
    { min: 65, max: 100, color: T.teal },
  ];

  const panel = {
    background: T.panel, borderRadius: 10,
    border: `1px solid ${T.border}`, padding: 14,
    display: "flex", flexDirection: "column", overflow: "hidden",
  };

  /* ── WAITING FOR CONNECTION ── */
  if (!s) return (
    <div style={{ background: T.bg, minHeight: "100vh", display: "flex",
      alignItems: "center", justifyContent: "center", fontFamily: "'Outfit', sans-serif" }}>
      <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600;700&family=Outfit:wght@300;400;500;600;700&display=swap" rel="stylesheet" />
      <div style={{ textAlign: "center", maxWidth: 440 }}>
        <div style={{ fontSize: 10, color: T.dim, letterSpacing: "0.2em",
          textTransform: "uppercase", marginBottom: 12,
          fontFamily: "'IBM Plex Mono', monospace" }}>3 Big Things \u00B7 Session Intelligence</div>
        <div style={{ fontSize: 28, color: T.white, fontWeight: 700, marginBottom: 8, lineHeight: 1.2 }}>
          Waiting for Session
        </div>
        <div style={{ fontSize: 13, color: T.muted, marginBottom: 32, lineHeight: 1.6 }}>
          Start a recording in Redactor Lite. The dashboard will connect
          automatically when the session server detects activity.
        </div>
        <div style={{ display: "flex", justifyContent: "center", gap: 8 }}>
          <div style={{ width: 8, height: 8, borderRadius: "50%", background: T.amber,
            animation: "pulse 1.5s ease-in-out infinite" }} />
          <span style={{ fontSize: 11, color: T.amber, fontFamily: "'IBM Plex Mono', monospace" }}>
            {AUTH_TOKEN === "__SESSION_TOKEN__" ? "Awaiting token\u2026" : `Polling ${SERVER}`}
          </span>
        </div>
        <style>{`@keyframes pulse { 0%,100% { opacity: 0.3; } 50% { opacity: 1; } }`}</style>
      </div>
    </div>
  );

  /* ── LIVE / COMPLETE DASHBOARD ── */
  const SESSION_DUR = s.session_duration_seconds || 3000;
  const sessionSec = parseTS(s.last_chunk_timestamp);
  const fmt = sec => `${Math.floor(sec / 60)}:${Math.floor(sec % 60).toString().padStart(2, "0")}`;
  const remaining  = SESSION_DUR - sessionSec;
  const progPct    = (sessionSec / SESSION_DUR) * 100;
  const progColor  = complete ? T.green : remaining < 5 * 60 ? T.red : remaining < 12 * 60 ? T.amber : T.teal;

  const clientTalk = s.speaker_totals?.client_talk_pct || 0;
  const rqRatio = s.utterance_counts?.rq_ratio || 0;
  const engSession = s.engagement?.session_score || 0;
  const engRecent = s.rolling_10m?.engagement_score || 0;
  const therapistAgenda = s.therapist_agenda || [];
  const clientAgenda = s.client_agenda || [];
  const people = s.people || [];
  const themes = s.themes || [];
  const rupture = s.rupture?.detected || false;
  const risk = s.risk?.flagged || false;

  return (
    <div style={{ background: T.bg, minHeight: "100vh", padding: "10px 14px",
      fontFamily: "'Outfit', sans-serif", color: T.text, boxSizing: "border-box" }}>
      <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600;700&family=Outfit:wght@300;400;500;600;700&display=swap" rel="stylesheet" />

      {/* ── HEADER ── */}
      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 6 }}>
        <div style={{ fontSize: 9, color: T.dim, letterSpacing: "0.16em",
          textTransform: "uppercase", fontFamily: "'IBM Plex Mono', monospace" }}>
          3 Big Things
        </div>
        <StatusDot connected={connected} chunks={s.chunks_processed || 0} />
        {complete && (
          <span style={{ fontSize: 9, color: T.green, fontFamily: "'IBM Plex Mono', monospace",
            background: "rgba(34,200,122,0.1)", padding: "2px 8px", borderRadius: 4 }}>
            SESSION COMPLETE
          </span>
        )}
        <div style={{ fontSize: 9, color: T.muted, fontFamily: "'IBM Plex Mono', monospace", marginLeft: "auto" }}>
          {s.session_type} \u00B7 {s.session_date}
        </div>
      </div>

      {/* ── PROGRESS BAR ── */}
      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 10 }}>
        <div style={{ fontSize: 9, color: T.dim, letterSpacing: "0.16em",
          textTransform: "uppercase", fontFamily: "'IBM Plex Mono', monospace", flexShrink: 0 }}>
          Session
        </div>
        <div style={{ flex: 1, height: 5, background: T.border, borderRadius: 3, overflow: "hidden" }}>
          <div style={{ height: "100%", width: `${progPct}%`, background: progColor,
            borderRadius: 3, transition: "width 0.5s linear, background 1s" }} />
        </div>
        <div style={{ fontFamily: "'IBM Plex Mono', monospace", fontSize: 11, color: progColor,
          flexShrink: 0, minWidth: 88, textAlign: "right" }}>
          {complete ? "Complete" : `${fmt(remaining)} remaining`}
        </div>
      </div>

      {/* ── METRICS STRIP ── */}
      <div style={{ ...panel, flexDirection: "row", alignItems: "center",
        gap: 0, marginBottom: 10, padding: "10px 20px", flexShrink: 0 }}>

        <div style={{ display: "flex", gap: 28, alignItems: "center", flex: 1 }}>
          <ArcGauge value={clientTalk} label="Client Talk" zones={talkZones} size={88} />
          <RQGauge ratio={rqRatio} size={88} />
          <ArcGauge
            value={viewMode === "session" ? engSession : engRecent}
            label="Engagement"
            zones={engZones}
            size={88}
          />
        </div>

        <div style={{ width: 1, background: T.border, alignSelf: "stretch", margin: "0 20px" }} />

        <div style={{ display: "flex", flexDirection: "column", gap: 6, alignItems: "center" }}>
          <div style={{ fontSize: 8, color: T.dim, fontFamily: "'IBM Plex Mono', monospace",
            textTransform: "uppercase", letterSpacing: "0.12em" }}>View</div>
          <div style={{ display: "flex", background: T.subtle, borderRadius: 6, padding: 2 }}>
            {["session", "recent"].map(m => (
              <button key={m} onClick={() => setViewMode(m)} style={{
                padding: "4px 10px", fontSize: 9, fontFamily: "'Outfit', sans-serif",
                textTransform: "uppercase", letterSpacing: "0.1em", border: "none",
                cursor: "pointer", borderRadius: 5,
                background: viewMode === m ? T.card : "transparent",
                color: viewMode === m ? T.white : T.dim,
                transition: "all 0.15s", whiteSpace: "nowrap" }}>
                {m === "session" ? "Full" : "10m"}
              </button>
            ))}
          </div>
        </div>

        <div style={{ width: 1, background: T.border, alignSelf: "stretch", margin: "0 20px" }} />

        {/* Rupture indicator */}
        <div style={{ borderRadius: 7, padding: "8px 14px", textAlign: "center", minWidth: 90,
          background: rupture ? "rgba(240,164,41,0.1)" : T.subtle,
          border: `1px solid ${rupture ? T.amber : T.border}`,
          transition: "all 0.4s ease", marginRight: 10 }}>
          <div style={{ fontSize: 14, marginBottom: 3 }}>{rupture ? "\u25C9" : "\u25EF"}</div>
          <div style={{ fontSize: 8, color: rupture ? T.amber : T.dim,
            fontFamily: "'IBM Plex Mono', monospace", textTransform: "uppercase",
            letterSpacing: "0.1em", fontWeight: 700, lineHeight: 1.5 }}>
            {rupture ? "Rupture" : "Alliance"}
          </div>
        </div>

        {/* Risk indicator */}
        <div style={{ borderRadius: 7, padding: "8px 14px", textAlign: "center", minWidth: 90,
          background: risk ? "rgba(240,80,80,0.1)" : T.subtle,
          border: `1px solid ${risk ? T.red : T.border}`,
          transition: "all 0.4s ease" }}>
          <div style={{ fontSize: 14, marginBottom: 3 }}>{risk ? "\u26A0" : "\u2713"}</div>
          <div style={{ fontSize: 8, color: risk ? T.red : T.dim,
            fontFamily: "'IBM Plex Mono', monospace", textTransform: "uppercase",
            letterSpacing: "0.1em", fontWeight: 700, lineHeight: 1.5 }}>
            {risk ? "Risk" : "Risk Clear"}
          </div>
        </div>
      </div>

      {/* ── TWO COLUMNS ── */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10,
        height: "calc(100vh - 210px)" }}>

        {/* LEFT: AGENDA */}
        <div style={{ ...panel, gap: 12, overflow: "hidden" }}>
          <div style={{ flex: 1, overflow: "hidden", display: "flex", flexDirection: "column" }}>
            <SL label="Therapist Focus" />
            <div style={{ flex: 1, overflowY: "auto" }}>
              {therapistAgenda.map(item => (
                <AgendaItem key={item.id} item={item} entityMap={entityMap}
                  expanded={expanded === item.id}
                  onToggle={() => setExpanded(expanded === item.id ? null : item.id)} />
              ))}
            </div>
          </div>
          <div style={{ flex: 1, overflow: "hidden", display: "flex", flexDirection: "column" }}>
            <SL label="Client Agenda" />
            <div style={{ flex: 1, overflowY: "auto" }}>
              {clientAgenda.length === 0
                ? <div style={{ fontSize: 11, color: T.dim, fontStyle: "italic" }}>Detecting\u2026</div>
                : clientAgenda.map(item => (
                  <AgendaItem key={item.id} item={item} entityMap={entityMap}
                    expanded={expanded === item.id}
                    onToggle={() => setExpanded(expanded === item.id ? null : item.id)} />
                ))}
            </div>
          </div>
        </div>

        {/* RIGHT: SCRATCH PAD */}
        <div style={{ ...panel, gap: 12, overflow: "hidden" }}>
          <div style={{ flexShrink: 0, maxHeight: "38%", overflow: "hidden",
            display: "flex", flexDirection: "column" }}>
            <SL label="People & Details" />
            <div style={{ overflowY: "auto" }}>
              {people.length === 0
                ? <span style={{ fontSize: 11, color: T.dim, fontStyle: "italic" }}>Listening\u2026</span>
                : people.map((p, i) => <PersonCard key={i} person={p} entityMap={entityMap} />)
              }
            </div>
          </div>
          <div style={{ flex: 1, overflow: "hidden", display: "flex", flexDirection: "column" }}>
            <SL label={`Themes${themes.length > 0 ? `  \u00B7  ${themes.length}` : ""}`} />
            <div style={{ flex: 1, overflowY: "auto" }}>
              {themes.length === 0
                ? <span style={{ fontSize: 11, color: T.dim, fontStyle: "italic" }}>Synthesising\u2026</span>
                : themes.map((th, i) => (
                  <ThemeItem key={th.id} theme={th} entityMap={entityMap}
                    color={THEME_COLORS[i % THEME_COLORS.length]}
                    expanded={expanded === th.id}
                    onToggle={() => setExpanded(expanded === th.id ? null : th.id)} />
                ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
