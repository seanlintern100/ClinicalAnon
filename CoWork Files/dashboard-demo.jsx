import { useState, useEffect, useRef } from "react";

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

/* ─── ARC GAUGE (percentage) ─── */
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
  // ratio is a number e.g. 1.8 meaning 1.8:1
  // display range 0–4, threshold at 2.0
  const MAX_RATIO = 4;
  const THRESHOLD = 2.0;
  const cx = size / 2, cy = size / 2 + 4, r = size / 2 - 10;
  const START = 218, SWEEP = 284;

  const vSweep = Math.max(0, Math.min(SWEEP, (ratio / MAX_RATIO) * SWEEP));
  const threshSweep = (THRESHOLD / MAX_RATIO) * SWEEP;

  const color = ratio >= THRESHOLD ? T.teal : ratio >= 1.0 ? T.amber : T.red;
  const [nx, ny] = vSweep > 0 ? toXY(cx, cy, r, START + vSweep) : [0, 0];
  // threshold tick
  const [tx, ty] = toXY(cx, cy, r, START + threshSweep);
  const [txi, tyi] = toXY(cx, cy, r - 7, START + threshSweep);

  const display = ratio > 0 ? `${ratio.toFixed(1)}:1` : "—";

  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 3 }}>
      <svg width={size} height={size * 0.82} style={{ overflow: "visible" }}>
        {/* track */}
        <path d={arcD(cx, cy, r, START, SWEEP)} fill="none" stroke={T.border} strokeWidth={5} strokeLinecap="round" />
        {/* fill */}
        {vSweep > 0 && <path d={arcD(cx, cy, r, START, vSweep)} fill="none" stroke={color} strokeWidth={5} strokeLinecap="round" />}
        {/* threshold tick */}
        <line x1={txi.toFixed(2)} y1={tyi.toFixed(2)} x2={tx.toFixed(2)} y2={ty.toFixed(2)}
          stroke={T.white} strokeWidth={2} strokeLinecap="round" opacity={0.6} />
        {/* needle tip */}
        {vSweep > 0 && <circle cx={nx} cy={ny} r={3.5} fill={color} />}
        {/* value */}
        <text x={cx} y={cy + 3} textAnchor="middle" fill={T.white} fontSize={11}
          fontFamily="'IBM Plex Mono', monospace" fontWeight="700">{display}</text>
        {/* threshold label */}
        <text x={cx} y={cy + 14} textAnchor="middle" fill={T.dim} fontSize={7}
          fontFamily="'IBM Plex Mono', monospace">2:1</text>
      </svg>
      <span style={{ fontSize: 8, color: T.muted, fontFamily: "'Outfit', sans-serif",
        textTransform: "uppercase", letterSpacing: "0.1em" }}>R:Q Ratio</span>
    </div>
  );
}

/* ─── STATUS CONFIGS (spec v2 names) ─── */
const SC = {
  not_discussed:      { sym: "○", color: T.dim,   bg: "transparent",             label: "Not discussed" },
  partially_discussed:{ sym: "◑", color: T.amber, bg: "rgba(240,164,41,0.08)",   label: "Partial" },
  fully_discussed:    { sym: "●", color: T.green, bg: "rgba(34,200,122,0.08)",   label: "Discussed" },
};

/* ─── AGENDA ITEM ─── */
function AgendaItem({ item, expanded, onToggle }) {
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
          {item.text}
        </span>
        {item.evidence.length > 0 && <>
          <span style={{ fontSize: 9, color: T.muted, fontFamily: "'IBM Plex Mono', monospace" }}>
            {item.evidence.length}
          </span>
          <span style={{ fontSize: 9, color: T.dim, transform: expanded ? "rotate(180deg)" : "none",
            transition: "transform 0.2s", lineHeight: 1 }}>▾</span>
        </>}
      </button>
      {expanded && item.evidence.length > 0 && (
        <div style={{ padding: "4px 8px 8px 29px", display: "flex", flexDirection: "column", gap: 4 }}>
          {item.evidence.map((e, i) => (
            <div key={i} style={{ fontSize: 10.5, lineHeight: 1.45,
              color: e.type === "quote" ? T.teal : T.muted,
              fontFamily: e.type === "quote" ? "'IBM Plex Mono', monospace" : "'Outfit', sans-serif",
              background: e.type === "quote" ? "rgba(30,207,176,0.06)" : T.subtle,
              borderLeft: `2px solid ${e.type === "quote" ? T.teal : T.border}`,
              padding: "4px 8px", borderRadius: "0 4px 4px 0" }}>
              {e.type === "quote" ? `"${e.text}"` : e.text}
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
function ThemeItem({ theme, color, expanded, onToggle }) {
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
        {theme.phrases.length > 0 && <>
          <span style={{ fontSize: 9, color: color + 'AA', fontFamily: "'IBM Plex Mono', monospace" }}>
            {theme.phrases.length}
          </span>
          <span style={{ fontSize: 9, color: color + '88',
            transform: expanded ? "rotate(180deg)" : "none",
            transition: "transform 0.2s", lineHeight: 1 }}>▾</span>
        </>}
      </button>
      {expanded && theme.phrases.length > 0 && (
        <div style={{ padding: "0 10px 8px 25px", display: "flex", flexDirection: "column", gap: 4 }}>
          {theme.phrases.map((p, i) => (
            <div key={i} style={{ fontSize: 10.5, color: T.teal,
              fontFamily: "'IBM Plex Mono', monospace",
              background: "rgba(30,207,176,0.06)",
              borderLeft: `2px solid ${T.teal}`,
              padding: "4px 9px", borderRadius: "0 4px 4px 0", lineHeight: 1.4 }}>
              "{p}"
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

/* ─── PERSON CARD ─── */
function PersonCard({ person }) {
  const details = [];
  if (person.role) details.push(person.role);
  if (person.age) details.push(`age ${person.age}`);
  if (person.location) details.push(person.location);
  return (
    <div style={{ background: T.subtle, border: `1px solid ${T.border}`, borderRadius: 6,
      padding: "6px 9px", marginBottom: 5 }}>
      <div style={{ display: "flex", alignItems: "baseline", gap: 6, marginBottom: details.length || person.events?.length ? 3 : 0 }}>
        <span style={{ fontSize: 11, color: T.blue, fontFamily: "'Outfit', sans-serif", fontWeight: 600 }}>
          {person.name}
        </span>
        {details.length > 0 && (
          <span style={{ fontSize: 9.5, color: T.muted, fontFamily: "'Outfit', sans-serif" }}>
            {details.join(" · ")}
          </span>
        )}
        <span style={{ fontSize: 9, color: T.dim, fontFamily: "'IBM Plex Mono', monospace",
          marginLeft: "auto" }}>×{person.mentions}</span>
      </div>
      {person.events?.map((ev, i) => (
        <div key={i} style={{ fontSize: 10, color: T.muted, fontFamily: "'Outfit', sans-serif",
          paddingLeft: 8, borderLeft: `1px solid ${T.border}`, lineHeight: 1.4 }}>
          {ev}
        </div>
      ))}
    </div>
  );
}

/* ─── SIMULATION DATA ─── */
const INIT_THERAPIST = [
  { id: "ta1", text: "Sleep patterns and fatigue levels", status: "not_discussed", evidence: [] },
  { id: "ta2", text: "Boundary-setting with mother", status: "not_discussed", evidence: [] },
  { id: "ta3", text: "Review coping strategies", status: "not_discussed", evidence: [] },
];

const EVENTS = [
  { t: 6,  type: "client_agenda",  item: { id: "ca1", text: "Argument with partner last week", status: "partially_discussed", evidence: [] } },
  { t: 11, type: "client_agenda",  item: { id: "ca2", text: "Feeling overwhelmed at work", status: "not_discussed", evidence: [] } },
  { t: 14, type: "t_status",       id: "ta1", status: "partially_discussed" },
  { t: 17, type: "metrics",        talk: { client: 55, therapist: 45 }, rq: 0.8, eng: { session: 42, recent: 44 } },
  { t: 19, type: "person",         person: { name: "Jamie", role: "partner", age: null, location: null, events: [], mentions: 2 } },
  { t: 22, type: "person",         person: { name: "Sandra", role: "manager", age: null, location: null, events: [], mentions: 1 } },
  { t: 25, type: "theme",          theme: { id: "th1", text: "Self-blame as default", phrases: ["I just can't seem to do anything right"] } },
  { t: 30, type: "t_evidence",     id: "ta1", ev: { type: "summary", text: "Waking at 3am, unable to return to sleep 4–5 nights per week" } },
  { t: 34, type: "metrics",        talk: { client: 63, therapist: 37 }, rq: 1.4, eng: { session: 51, recent: 55 } },
  { t: 37, type: "c_evidence",     id: "ca1", ev: { type: "quote", text: "He said I was being irrational and I just shut down" } },
  { t: 39, type: "theme",          theme: { id: "th2", text: "Shutdown under conflict", phrases: ["He said I was being irrational and I just shut down"] } },
  { t: 41, type: "t_status",       id: "ta1", status: "fully_discussed" },
  { t: 43, type: "t_evidence",     id: "ta1", ev: { type: "summary", text: "Sleep hygiene explored — screen time and work rumination identified as triggers. 5-4-3-2-1 grounding suggested." } },
  { t: 45, type: "t_status",       id: "ta2", status: "partially_discussed" },
  { t: 47, type: "metrics",        talk: { client: 68, therapist: 32 }, rq: 1.9, eng: { session: 60, recent: 66 } },
  { t: 49, type: "person_update",  name: "Jamie", updates: { events: ["Argument last week"] } },
  { t: 50, type: "person",         person: { name: "Carol", role: "mother", age: null, location: null, events: [], mentions: 1 } },
  { t: 54, type: "t_evidence",     id: "ta2", ev: { type: "summary", text: "Cancelled plans twice rather than saying no directly" } },
  { t: 56, type: "theme",          theme: { id: "th3", text: "Boundary patterns with family", phrases: ["She still treats me like I'm sixteen"] } },
  { t: 58, type: "c_status",       id: "ca2", status: "partially_discussed" },
  { t: 61, type: "c_evidence",     id: "ca2", ev: { type: "quote", text: "I stayed until 8pm three nights in a row just to avoid Sandra's emails" } },
  { t: 63, type: "theme",          theme: { id: "th4", text: "Avoidance under pressure", phrases: ["I stayed until 8pm three nights in a row just to avoid Sandra's emails"] } },
  { t: 65, type: "metrics",        talk: { client: 72, therapist: 28 }, rq: 2.2, eng: { session: 67, recent: 71 } },
  { t: 67, type: "theme_phrase",   id: "th3", phrase: "Maybe I just need to stop caring so much" },
  { t: 68, type: "rupture",        rtype: "withdrawal" },
  { t: 70, type: "t_evidence",     id: "ta2", ev: { type: "quote", text: "I couldn't even answer her call — I just let it ring" } },
  { t: 73, type: "t_status",       id: "ta3", status: "partially_discussed" },
  { t: 75, type: "theme",          theme: { id: "th5", text: "Emotional exhaustion", phrases: ["I'm just so tired of trying to hold everything together"] } },
  { t: 77, type: "metrics",        talk: { client: 73, therapist: 27 }, rq: 2.5, eng: { session: 70, recent: 74 } },
  { t: 80, type: "t_status",       id: "ta2", status: "fully_discussed" },
  { t: 82, type: "c_status",       id: "ca1", status: "fully_discussed" },
  { t: 84, type: "theme_phrase",   id: "th2", phrase: "What if I'm just not built for this kind of closeness" },
  { t: 86, type: "theme_phrase",   id: "th1", phrase: "I always end up being the problem" },
  { t: 87, type: "t_evidence",     id: "ta3", ev: { type: "summary", text: "5-4-3-2-1 grounding reviewed — used once, helpful but inconsistent. Agreed to daily practice." } },
  { t: 90, type: "metrics",        talk: { client: 74, therapist: 26 }, rq: 2.7, eng: { session: 72, recent: 69 } },
  { t: 93, type: "c_status",       id: "ca2", status: "fully_discussed" },
  { t: 95, type: "t_status",       id: "ta3", status: "fully_discussed" },
];

/* ─── MAIN ─── */
export default function TherapyDashboard() {
  const [active, setActive]         = useState(false);
  const [elapsed, setElapsed]       = useState(0);
  const [sessionSec, setSessionSec] = useState(0);
  const SESSION_DUR = 50 * 60;
  const SPEED = 28;

  const [therapistAgenda, setTherapistAgenda] = useState(INIT_THERAPIST);
  const [clientAgenda, setClientAgenda]       = useState([]);
  const [people, setPeople]                   = useState([]);
  const [themes, setThemes]                   = useState([]);
  const [talkTime, setTalkTime]               = useState({ client: 0, therapist: 100 });
  const [rqRatio, setRqRatio]                 = useState(0);
  const [eng, setEng]                         = useState({ session: 0, recent: 0 });
  const [rupture, setRupture]                 = useState(false);
  const [risk, setRisk]                       = useState(false);
  const [expanded, setExpanded]               = useState(null);
  const [viewMode, setViewMode]               = useState("session");
  const processed = useRef(new Set());

  useEffect(() => {
    if (!active) return;
    const iv = setInterval(() => {
      setElapsed(e => e + 0.25);
      setSessionSec(s => Math.min(s + SPEED * 0.25, SESSION_DUR));
    }, 250);
    return () => clearInterval(iv);
  }, [active]);

  useEffect(() => {
    if (!active) return;
    EVENTS.forEach(ev => {
      if (processed.current.has(ev.t) || elapsed < ev.t) return;
      processed.current.add(ev.t);
      switch (ev.type) {
        case "client_agenda":
          setClientAgenda(p => [...p, ev.item]); break;
        case "c_status":
          setClientAgenda(p => p.map(i => i.id === ev.id ? {...i, status: ev.status} : i)); break;
        case "c_evidence":
          setClientAgenda(p => p.map(i => i.id === ev.id ? {...i, evidence: [...i.evidence, ev.ev]} : i)); break;
        case "t_status":
          setTherapistAgenda(p => p.map(i => i.id === ev.id ? {...i, status: ev.status} : i)); break;
        case "t_evidence":
          setTherapistAgenda(p => p.map(i => i.id === ev.id ? {...i, evidence: [...i.evidence, ev.ev]} : i)); break;
        case "metrics":
          setTalkTime(ev.talk); setRqRatio(ev.rq); setEng(ev.eng); break;
        case "person":
          setPeople(p => p.find(x => x.name === ev.person.name) ? p : [...p, ev.person]); break;
        case "person_update":
          setPeople(p => p.map(x => x.name === ev.name
            ? {...x, ...ev.updates, mentions: x.mentions + 1}
            : x)); break;
        case "theme":
          setThemes(p => p.find(t => t.id === ev.theme.id) ? p : [...p, ev.theme]); break;
        case "theme_phrase":
          setThemes(p => p.map(t => t.id === ev.id ? {...t, phrases: [...t.phrases, ev.phrase]} : t)); break;
        case "rupture":
          setRupture(true); break;
        case "risk":
          setRisk(true); break;
      }
    });
  }, [elapsed, active]);

  const reset = () => {
    setActive(false); setElapsed(0); setSessionSec(0);
    processed.current = new Set();
    setTherapistAgenda(INIT_THERAPIST); setClientAgenda([]);
    setPeople([]); setThemes([]);
    setTalkTime({ client: 0, therapist: 100 }); setRqRatio(0);
    setEng({ session: 0, recent: 0 });
    setRupture(false); setRisk(false); setExpanded(null);
  };

  const fmt = s => `${Math.floor(s / 60)}:${Math.floor(s % 60).toString().padStart(2, "0")}`;
  const remaining  = SESSION_DUR - sessionSec;
  const progPct    = (sessionSec / SESSION_DUR) * 100;
  const progColor  = remaining < 5 * 60 ? T.red : remaining < 12 * 60 ? T.amber : T.teal;

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

  /* ── PRE-SESSION ── */
  if (!active) return (
    <div style={{ background: T.bg, minHeight: "100vh", display: "flex",
      alignItems: "center", justifyContent: "center", fontFamily: "'Outfit', sans-serif" }}>
      <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600;700&family=Outfit:wght@300;400;500;600;700&display=swap" rel="stylesheet" />
      <div style={{ textAlign: "center", maxWidth: 440 }}>
        <div style={{ fontSize: 10, color: T.dim, letterSpacing: "0.2em",
          textTransform: "uppercase", marginBottom: 12,
          fontFamily: "'IBM Plex Mono', monospace" }}>3 Big Things · Session Intelligence</div>
        <div style={{ fontSize: 32, color: T.white, fontWeight: 700, marginBottom: 6, lineHeight: 1.2 }}>
          Live Session<br />Dashboard
        </div>
        <div style={{ fontSize: 13, color: T.muted, marginBottom: 32, lineHeight: 1.6 }}>
          Ambient tracking of engagement, agenda progress, and key content — without breaking your presence.
        </div>
        <div style={{ background: T.panel, border: `1px solid ${T.border}`, borderRadius: 10,
          padding: 16, marginBottom: 24, textAlign: "left" }}>
          <div style={{ fontSize: 9, color: T.dim, letterSpacing: "0.14em",
            textTransform: "uppercase", marginBottom: 10,
            fontFamily: "'IBM Plex Mono', monospace" }}>Therapist focus — today</div>
          {INIT_THERAPIST.map(i => (
            <div key={i.id} style={{ display: "flex", alignItems: "center", gap: 8,
              padding: "6px 0", borderBottom: `1px solid ${T.border}`,
              fontSize: 12, color: T.muted }}>
              <span style={{ color: T.dim }}>○</span> {i.text}
            </div>
          ))}
        </div>
        <button onClick={() => setActive(true)} style={{
          background: T.teal, color: T.bg, border: "none", borderRadius: 8,
          padding: "12px 32px", fontSize: 13, fontWeight: 700, cursor: "pointer",
          fontFamily: "'Outfit', sans-serif", letterSpacing: "0.04em" }}>
          Start Demo Session
        </button>
      </div>
    </div>
  );

  /* ── LIVE DASHBOARD ── */
  return (
    <div style={{ background: T.bg, minHeight: "100vh", padding: "10px 14px",
      fontFamily: "'Outfit', sans-serif", color: T.text, boxSizing: "border-box" }}>
      <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600;700&family=Outfit:wght@300;400;500;600;700&display=swap" rel="stylesheet" />

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
          {fmt(remaining)} remaining
        </div>
        <button onClick={reset} style={{ background: "transparent",
          border: `1px solid ${T.border}`, color: T.muted, borderRadius: 5,
          padding: "3px 10px", fontSize: 10, cursor: "pointer",
          fontFamily: "'Outfit', sans-serif" }}>
          End
        </button>
      </div>

      {/* ── METRICS STRIP ── */}
      <div style={{ ...panel, flexDirection: "row", alignItems: "center",
        gap: 0, marginBottom: 10, padding: "10px 20px", flexShrink: 0 }}>

        {/* Three gauges */}
        <div style={{ display: "flex", gap: 28, alignItems: "center", flex: 1 }}>
          <ArcGauge
            value={talkTime.client}
            label="Client Talk"
            zones={talkZones}
            size={88}
          />
          <RQGauge ratio={rqRatio} size={88} />
          <ArcGauge
            value={viewMode === "session" ? eng.session : eng.recent}
            label="Engagement"
            zones={engZones}
            size={88}
          />
        </div>

        {/* Divider */}
        <div style={{ width: 1, background: T.border, alignSelf: "stretch", margin: "0 20px" }} />

        {/* Full / 10m toggle */}
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

        {/* Divider */}
        <div style={{ width: 1, background: T.border, alignSelf: "stretch", margin: "0 20px" }} />

        {/* Rupture indicator */}
        <div style={{ borderRadius: 7, padding: "8px 14px", textAlign: "center", minWidth: 90,
          background: rupture ? "rgba(240,164,41,0.1)" : T.subtle,
          border: `1px solid ${rupture ? T.amber : T.border}`,
          transition: "all 0.4s ease", marginRight: 10 }}>
          <div style={{ fontSize: 14, marginBottom: 3 }}>{rupture ? "◉" : "◯"}</div>
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
          <div style={{ fontSize: 14, marginBottom: 3 }}>{risk ? "⚠" : "✓"}</div>
          <div style={{ fontSize: 8, color: risk ? T.red : T.dim,
            fontFamily: "'IBM Plex Mono', monospace", textTransform: "uppercase",
            letterSpacing: "0.1em", fontWeight: 700, lineHeight: 1.5 }}>
            {risk ? "Risk" : "Risk Clear"}
          </div>
        </div>

      </div>

      {/* ── TWO COLUMNS ── */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10,
        height: "calc(100vh - 185px)" }}>

        {/* ─── LEFT: AGENDA ─── */}
        <div style={{ ...panel, gap: 12, overflow: "hidden" }}>

          {/* Therapist Focus */}
          <div style={{ flex: 1, overflow: "hidden", display: "flex", flexDirection: "column" }}>
            <SL label="Therapist Focus" />
            <div style={{ flex: 1, overflowY: "auto" }}>
              {therapistAgenda.map(item => (
                <AgendaItem key={item.id} item={item}
                  expanded={expanded === item.id}
                  onToggle={() => setExpanded(expanded === item.id ? null : item.id)} />
              ))}
            </div>
          </div>

          {/* Client Agenda */}
          <div style={{ flex: 1, overflow: "hidden", display: "flex", flexDirection: "column" }}>
            <SL label="Client Agenda" />
            <div style={{ flex: 1, overflowY: "auto" }}>
              {clientAgenda.length === 0
                ? <div style={{ fontSize: 11, color: T.dim, fontStyle: "italic" }}>Detecting…</div>
                : clientAgenda.map(item => (
                  <AgendaItem key={item.id} item={item}
                    expanded={expanded === item.id}
                    onToggle={() => setExpanded(expanded === item.id ? null : item.id)} />
                ))}
            </div>
          </div>

        </div>

        {/* ─── RIGHT: SCRATCH PAD ─── */}
        <div style={{ ...panel, gap: 12, overflow: "hidden" }}>

          {/* People & Details */}
          <div style={{ flexShrink: 0, maxHeight: "38%", overflow: "hidden",
            display: "flex", flexDirection: "column" }}>
            <SL label="People & Details" />
            <div style={{ overflowY: "auto" }}>
              {people.length === 0
                ? <span style={{ fontSize: 11, color: T.dim, fontStyle: "italic" }}>Listening…</span>
                : people.map(p => <PersonCard key={p.name} person={p} />)
              }
            </div>
          </div>

          {/* Themes */}
          <div style={{ flex: 1, overflow: "hidden", display: "flex", flexDirection: "column" }}>
            <SL label={`Themes${themes.length > 0 ? `  ·  ${themes.length}` : ""}`} />
            <div style={{ flex: 1, overflowY: "auto" }}>
              {themes.length === 0
                ? <span style={{ fontSize: 11, color: T.dim, fontStyle: "italic" }}>Synthesising…</span>
                : themes.map((th, i) => (
                  <ThemeItem key={th.id} theme={th}
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
