#!/usr/bin/env bash
# push-wetting-posture-capacity.sh
# Adds: per-wetting body-position (posture) field, a live capacity-ceiling
# warning on the wettings screen, and a legacy-record flag + global capacity
# line in Insights. Whole-file writes; safe to re-run.
set -e

# --- guard: must run from the ledger-app repo root ---
if [ ! -f package.json ] || ! grep -q '"name": "ledger"' package.json || [ ! -d src/components ]; then
  echo "Error: run this from the ledger-app repo root (where package.json lives)." >&2
  exit 1
fi

echo "Writing files..."

mkdir -p "$(dirname src/lib/wetting.js)"
cat > src/lib/wetting.js << 'LEDGER_EOF'
// Wetting events recorded against a wear session (a worn diaper).
//
// Each wear-session log (a "use" entry with a putOnAt time) may carry an
// optional `wettings` array, stored inline on the log object:
//
//   wettings: [{ id, at, amount, feel, core, tapes, posture, note }]
//
// Because it rides along on the existing log records, it needs no new
// IndexedDB store and is automatically included in backup export/import.
// Older logs without a field are treated as not set.
//
//   amount  — how heavy the wetting was (light → very heavy)
//   feel    — how the diaper felt afterwards (a saturation scale)
//   core    — optional in-the-moment read on the padding itself
//   tapes   — optional tape behaviour at that moment
//   posture — optional body position when it happened (sitting → active);
//             notes repeatedly show standing/active floods stress capacity
//             differently than resting, so it's worth capturing structurally.

export const WETNESS = [
  { value: 'light',    label: 'Light',      weight: 1, order: 1 },
  { value: 'moderate', label: 'Moderate',   weight: 2, order: 2 },
  { value: 'heavy',    label: 'Heavy',      weight: 3, order: 3 },
  { value: 'flood',    label: 'Very heavy', weight: 4, order: 4 },
];

// How the diaper feels *after* a wetting — a rough saturation scale.
export const DIAPER_FEEL = [
  { value: 'dry',       label: 'Still dry / barely noticeable', order: 1 },
  { value: 'damp',      label: 'Slightly damp',                 order: 2 },
  { value: 'wet',       label: 'Noticeably wet',                order: 3 },
  { value: 'heavy',     label: 'Heavy / swollen',               order: 4 },
  { value: 'saturated', label: 'Saturated — near its limit',    order: 5 },
];

// Optional in-the-moment read on the core itself when you notice a wetting —
// is the padding still intact, or starting to break down? Ordered
// worst-ascending to line up with CORE_CONDITIONS recorded at take-off.
export const CORE_FEEL = [
  { value: 'firm',      label: 'Still firm',          order: 1 },
  { value: 'softening', label: 'Softening',           order: 2 },
  { value: 'clumping',  label: 'Clumping',            order: 3 },
  { value: 'shifting',  label: 'Shifting / bunching', order: 4 },
];

// Body position at the moment of the wetting. Optional and backward
// compatible. Ordered roughly rest → active; this is a position label, not a
// severity scale, so consumers should not assume higher order = worse.
export const POSTURES = [
  { value: 'lying',    label: 'Lying down',          order: 1 },
  { value: 'sitting',  label: 'Sitting',             order: 2 },
  { value: 'standing', label: 'Standing',            order: 3 },
  { value: 'active',   label: 'Walking / active',    order: 4 },
];

export const wetnessMeta = (v) => WETNESS.find((w) => w.value === v) || null;
export const feelMeta = (v) => DIAPER_FEEL.find((f) => f.value === v) || null;
export const coreFeelMeta = (v) => CORE_FEEL.find((c) => c.value === v) || null;
export const postureMeta = (v) => POSTURES.find((p) => p.value === v) || null;

export const wetnessLabel = (v) => wetnessMeta(v)?.label || '—';
export const feelLabel = (v) => feelMeta(v)?.label || '—';
export const coreFeelLabel = (v) => coreFeelMeta(v)?.label || '—';
export const postureLabel = (v) => postureMeta(v)?.label || '—';

// Always returns a time-sorted array, tolerant of older logs with no field.
export const getWettings = (log) => {
  if (!log || !Array.isArray(log.wettings)) return [];
  return [...log.wettings].sort((a, b) => (a.at || 0) - (b.at || 0));
};

// Roll a session's wettings into a small performance summary.
//   count    — number of wettings
//   load     — summed "heaviness" weight (a rough saturation total)
//   lastFeel — feel recorded on the most recent wetting
//   peakFeel — most saturated feel reached across the session
//   byAmount — { light, moderate, heavy, flood } counts
export const wettingStats = (log) => {
  const list = getWettings(log);
  const byAmount = { light: 0, moderate: 0, heavy: 0, flood: 0 };
  let load = 0;
  let peakOrder = 0;
  let peakFeel = null;
  list.forEach((w) => {
    if (byAmount[w.amount] != null) byAmount[w.amount] += 1;
    load += wetnessMeta(w.amount)?.weight || 0;
    const fo = feelMeta(w.feel)?.order || 0;
    if (fo >= peakOrder) { peakOrder = fo; peakFeel = w.feel; }
  });
  const lastFeel = list.length ? list[list.length - 1].feel : null;
  return { count: list.length, load, lastFeel, peakFeel, byAmount, list };
};

// ---- Capacity profiling --------------------------------------------------
// Learn, per product, how much "load" (summed wetting weight) it has held
// before vs. without leaking, so the app can warn as a worn diaper nears the
// point it has historically given out. Pure functions of the logs array.
//
//   dryCeiling — most load held on a session that did NOT leak
//   leakFloor  — least load on a session that DID leak (the soonest it failed)
//   dryN/leakN — how many sessions back each number (so callers can judge n)

const sessionLoad = (log) => wettingStats(log).load;

export const capacityProfile = (logs, productId, excludeLogId = null) => {
  const sessions = (logs || []).filter(
    (l) => l.productId === productId && l.putOnAt &&
           l.id !== excludeLogId && getWettings(l).length > 0
  );
  let dryCeiling = null;
  let leakFloor = null;
  let dryN = 0;
  let leakN = 0;
  sessions.forEach((l) => {
    const load = sessionLoad(l);
    if (l.performance === 'leak') {
      leakN += 1;
      if (leakFloor == null || load < leakFloor) leakFloor = load;
    } else {
      dryN += 1;
      if (dryCeiling == null || load > dryCeiling) dryCeiling = load;
    }
  });
  return { dryCeiling, leakFloor, dryN, leakN, sampleN: sessions.length };
};

// A fallback profile across every product, for when a single product has too
// little history to say anything on its own.
export const globalCapacity = (logs, excludeLogId = null) => {
  const sessions = (logs || []).filter(
    (l) => l.putOnAt && l.id !== excludeLogId && getWettings(l).length > 0
  );
  let dryCeiling = null;
  let leakFloor = null;
  let dryN = 0;
  let leakN = 0;
  sessions.forEach((l) => {
    const load = sessionLoad(l);
    if (l.performance === 'leak') {
      leakN += 1;
      if (leakFloor == null || load < leakFloor) leakFloor = load;
    } else {
      dryN += 1;
      if (dryCeiling == null || load > dryCeiling) dryCeiling = load;
    }
  });
  return { dryCeiling, leakFloor, dryN, leakN, sampleN: sessions.length };
};

// Given a running load and a capacity profile (plus optional fallback),
// classify how close the diaper is to its historical limit.
//   level — 'none' (no basis) | 'ok' | 'watch' | 'over'
//   basis — 'leak' (vs the load it has leaked at) | 'dry' (vs most held dry)
//   ceiling — the number `load` is being compared against
//   fromProduct — true if the basis came from this product, not the fallback
export const capacityStatus = (load, profile, fallback = null) => {
  if (!load || load <= 0) return { level: 'none' };
  const usable = (o) => (o && (o.leakFloor != null || o.dryCeiling != null)) ? o : null;
  const src = usable(profile) || usable(fallback);
  if (!src) return { level: 'none' };
  const leakBasis = src.leakFloor != null;
  const ceiling = leakBasis ? src.leakFloor : src.dryCeiling;
  if (ceiling == null || ceiling <= 0) return { level: 'none' };
  const ratio = load / ceiling;
  let level = 'ok';
  if (leakBasis) {
    if (load >= ceiling) level = 'over';
    else if (ratio >= 0.75) level = 'watch';
  } else {
    if (load > ceiling) level = 'over';
    else if (ratio >= 0.85) level = 'watch';
  }
  return { level, basis: leakBasis ? 'leak' : 'dry', ceiling, ratio, fromProduct: src === profile };
};
LEDGER_EOF

mkdir -p "$(dirname src/components/WettingForm.jsx)"
cat > src/components/WettingForm.jsx << 'LEDGER_EOF'
import React, { useState, useEffect } from 'react';
import { Check, X, Droplets, Droplet, Pencil, AlertTriangle, ShieldCheck } from 'lucide-react';
import { Modal } from './Common';
import {
  uid, toLocalInputValue, fromLocalInputValue,
  productDisplayName, formatTime, formatDuration, wearDuration,
} from '../lib/helpers';
import {
  WETNESS, DIAPER_FEEL, CORE_FEEL, POSTURES, getWettings, wettingStats,
  wetnessLabel, feelLabel, coreFeelLabel, postureLabel,
  capacityProfile, globalCapacity, capacityStatus,
} from '../lib/wetting';
import { TAPE_STATES, tapeLabel } from '../lib/session';

// WettingSummary — compact, reusable read-out of a wear session's wettings.
// Used on the dashboard's "currently wearing" card and in History rows.
// In compact mode it renders nothing when there are no wettings yet.
export function WettingSummary({ log, compact = false, style = {} }) {
  const { count, peakFeel, byAmount } = wettingStats(log);

  if (count === 0) {
    if (compact) return null;
    return (
      <div style={{ fontSize: 12, color: 'var(--ink-mute)', ...style }}>
        No wettings logged yet.
      </div>
    );
  }

  const breakdown = WETNESS
    .filter((w) => byAmount[w.value] > 0)
    .map((w) => `${byAmount[w.value]} ${w.label.toLowerCase()}`)
    .join(' · ');

  if (compact) {
    return (
      <span style={{
        display: 'inline-flex', alignItems: 'center', gap: 5,
        color: 'var(--accent)', ...style,
      }}>
        <Droplet size={11} />
        {count} wetting{count !== 1 ? 's' : ''}
        {peakFeel && (
          <span style={{ color: 'var(--ink-mute)' }}>· {feelLabel(peakFeel).toLowerCase()}</span>
        )}
      </span>
    );
  }

  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 8, ...style }}>
      <span style={{
        display: 'inline-flex', alignItems: 'center', gap: 5,
        fontSize: 13, color: 'var(--accent)', fontWeight: 600,
      }}>
        <Droplets size={14} /> {count} wetting{count !== 1 ? 's' : ''}
      </span>
      {breakdown && <span style={{ fontSize: 12, color: 'var(--ink-soft)' }}>{breakdown}</span>}
      {peakFeel && (
        <span style={{ fontSize: 12, color: 'var(--ink-mute)' }}>
          · felt {feelLabel(peakFeel).toLowerCase()}
        </span>
      )}
    </div>
  );
}

// CapacityMeter — shows how close this diaper's running load is to the point
// it (or similar diapers) have historically leaked. Quiet when there's no
// basis to judge yet; turns amber on approach and red once at/over the line.
function CapacityMeter({ load, status, isOn }) {
  if (status.level === 'none' || load <= 0) return null;

  const palette = {
    ok:    { bar: 'var(--primary)', fg: 'var(--ink-soft)',  Icon: ShieldCheck },
    watch: { bar: '#C9985A',        fg: '#9A6A2E',          Icon: AlertTriangle },
    over:  { bar: 'var(--danger)',  fg: 'var(--danger)',    Icon: AlertTriangle },
  }[status.level];
  const { bar, fg, Icon } = palette;

  const pct = Math.max(6, Math.min(100, Math.round((status.ratio || 0) * 100)));
  const where = status.fromProduct ? 'this diaper' : 'similar diapers';
  const ceilTxt = Number.isInteger(status.ceiling) ? status.ceiling : status.ceiling.toFixed(1);

  let msg;
  if (status.level === 'over') {
    msg = status.basis === 'leak'
      ? `At/over the load ${where} has leaked at (~${ceilTxt}).${isOn ? ' Consider changing soon.' : ''}`
      : `Past the most ${where} held dry (${ceilTxt}) — uncharted territory.`;
  } else if (status.level === 'watch') {
    msg = status.basis === 'leak'
      ? `Nearing the load ${where} has leaked at (~${ceilTxt}).`
      : `Approaching the most ${where} held dry (${ceilTxt}).`;
  } else {
    msg = status.basis === 'leak'
      ? `Comfortably under the ~${ceilTxt} load ${where} has leaked at.`
      : `Under the ${ceilTxt} load ${where} has held dry.`;
  }

  return (
    <div style={{ marginTop: 10 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, color: fg }}>
        <Icon size={13} />
        <span style={{ flex: 1 }}>{msg}</span>
        <span className="num" style={{ color: fg }}>{load}</span>
      </div>
      <div style={{
        height: 4, background: 'var(--line-soft)',
        borderRadius: 3, marginTop: 6, overflow: 'hidden',
      }}>
        <div style={{ height: '100%', width: `${pct}%`, background: bar, borderRadius: 3 }} />
      </div>
    </div>
  );
}

// WettingForm — add / edit / remove wettings on a single wear session.
// Works for the diaper currently on, or any previously worn one. Persists
// immediately via onSave(logId, wettings) so nothing is lost on close.
export default function WettingForm({ open, onClose, entry, product, onSave, logs = [] }) {
  const [list, setList] = useState([]);
  const [editingId, setEditingId] = useState(null);
  const [at, setAt] = useState(Date.now());
  const [amount, setAmount] = useState('');
  const [feel, setFeel] = useState('');
  const [core, setCore] = useState('');
  const [tapes, setTapes] = useState('');
  const [posture, setPosture] = useState('');
  const [note, setNote] = useState('');

  const defaultAt = () => {
    if (!entry) return Date.now();
    // Currently worn → now. Previously worn → the time it came off.
    return entry.takenOffAt == null ? Date.now() : entry.takenOffAt;
  };

  const resetSubForm = () => {
    setEditingId(null);
    setAt(defaultAt());
    setAmount('');
    setFeel('');
    setCore('');
    setTapes('');
    setPosture('');
    setNote('');
  };

  // Seed the working list when the modal opens for a given session.
  useEffect(() => {
    if (open && entry) {
      setList(getWettings(entry));
      resetSubForm();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, entry?.id]);

  if (!open || !entry) return null;

  const persist = (next) => {
    const sorted = [...next].sort((a, b) => (a.at || 0) - (b.at || 0));
    setList(sorted);
    onSave(entry.id, sorted);
  };

  const addOrUpdate = () => {
    if (!amount) return;
    const fields = {
      at, amount,
      feel: feel || null, core: core || null,
      tapes: tapes || null, posture: posture || null,
      note: note.trim(),
    };
    if (editingId) {
      persist(list.map((w) => (w.id === editingId ? { ...w, ...fields } : w)));
    } else {
      persist([...list, { id: uid(), ...fields }]);
    }
    resetSubForm();
  };

  const editRow = (w) => {
    setEditingId(w.id);
    setAt(w.at || Date.now());
    setAmount(w.amount || '');
    setFeel(w.feel || '');
    setCore(w.core || '');
    setTapes(w.tapes || '');
    setPosture(w.posture || '');
    setNote(w.note || '');
  };

  const removeRow = (id) => {
    persist(list.filter((w) => w.id !== id));
    if (editingId === id) resetSubForm();
  };

  const stats = wettingStats({ ...entry, wettings: list });
  const dur = wearDuration(entry);

  // Live capacity read: compare this session's running load against what this
  // product (and, as a fallback, all products) has held before. Exclude the
  // current entry so it never measures itself.
  const profile = capacityProfile(logs, entry.productId, entry.id);
  const gAll = globalCapacity(logs, entry.id);
  // Fallback compares only against the most any diaper has held dry. A global
  // leak floor would be dominated by the single weakest product and would cry
  // wolf on everything, so we deliberately drop it here.
  const fallback = { dryCeiling: gAll.dryCeiling };
  const capStatus = capacityStatus(stats.load, profile, fallback);
  const isOn = entry.takenOffAt == null;

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Wettings"
      footer={<button className="btn btn-primary" onClick={onClose}>Done</button>}
    >
      <div style={{ display: 'grid', gap: 16 }}>
        {/* Session summary — how this diaper is performing */}
        <div className="card" style={{ padding: '12px 14px' }}>
          <div style={{ fontSize: 14 }}>
            {product ? productDisplayName(product) : 'This diaper'}
          </div>
          <div style={{ fontSize: 12, color: 'var(--ink-mute)', marginTop: 3 }}>
            {entry.takenOffAt == null ? 'On now' : 'Previously worn'}
            {dur != null && ` · worn ${formatDuration(dur)}`}
            {` · ${stats.count} wetting${stats.count !== 1 ? 's' : ''}`}
            {stats.peakFeel && ` · felt ${feelLabel(stats.peakFeel).toLowerCase()}`}
          </div>
          <CapacityMeter load={stats.load} status={capStatus} isOn={isOn} />
        </div>

        {/* Existing wettings */}
        {list.length > 0 && (
          <div>
            <label className="label">Logged so far</label>
            <div className="card" style={{ padding: 4 }}>
              {list.map((w) => (
                <div
                  key={w.id}
                  className="row-divider"
                  style={{ padding: '10px 12px', display: 'flex', alignItems: 'center', gap: 10 }}
                >
                  <Droplet size={14} style={{ color: 'var(--accent)', flexShrink: 0 }} />
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontSize: 13 }}>
                      {wetnessLabel(w.amount)}
                      {w.feel && (
                        <span style={{ color: 'var(--ink-mute)' }}> · {feelLabel(w.feel).toLowerCase()}</span>
                      )}
                      {w.core && (
                        <span style={{ color: 'var(--ink-mute)' }}> · core {coreFeelLabel(w.core).toLowerCase()}</span>
                      )}
                      {w.tapes && (
                        <span style={{ color: 'var(--ink-mute)' }}> · tapes {tapeLabel(w.tapes).toLowerCase()}</span>
                      )}
                      {w.posture && (
                        <span style={{ color: 'var(--ink-mute)' }}> · {postureLabel(w.posture).toLowerCase()}</span>
                      )}
                    </div>
                    <div style={{ fontSize: 11, color: 'var(--ink-mute)', marginTop: 1 }}>
                      {formatTime(w.at)}{w.note ? ` · ${w.note}` : ''}
                    </div>
                  </div>
                  <button className="btn-icon" onClick={() => editRow(w)} aria-label="Edit wetting">
                    <Pencil size={13} />
                  </button>
                  <button className="btn-icon" onClick={() => removeRow(w.id)} aria-label="Remove wetting">
                    <X size={14} />
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}

        <hr className="hairline" />

        {/* Add / edit a single wetting */}
        <div style={{ display: 'grid', gap: 14 }}>
          <div className="eyebrow">{editingId ? 'Edit wetting' : 'Add a wetting'}</div>

          <div>
            <label className="label">When</label>
            <input
              className="input" type="datetime-local"
              value={toLocalInputValue(at)}
              onChange={(e) => setAt(fromLocalInputValue(e.target.value))}
            />
          </div>

          <div>
            <label className="label">How much?</label>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
              {WETNESS.map((w) => (
                <button
                  key={w.value} type="button"
                  className={`check-row ${amount === w.value ? 'active' : ''}`}
                  onClick={() => setAmount(w.value)}
                >
                  <span style={{ flex: 1 }}>{w.label}</span>
                  {amount === w.value && <Check size={14} />}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="label">How does it feel now? (optional)</label>
            <div style={{ display: 'grid', gap: 8 }}>
              {DIAPER_FEEL.map((f) => (
                <button
                  key={f.value} type="button"
                  className={`check-row ${feel === f.value ? 'active' : ''}`}
                  onClick={() => setFeel(feel === f.value ? '' : f.value)}
                >
                  <span style={{ flex: 1 }}>{f.label}</span>
                  {feel === f.value && <Check size={14} />}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="label">Core feel? (optional)</label>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
              {CORE_FEEL.map((c) => (
                <button
                  key={c.value} type="button"
                  className={`check-row ${core === c.value ? 'active' : ''}`}
                  onClick={() => setCore(core === c.value ? '' : c.value)}
                >
                  <span style={{ flex: 1 }}>{c.label}</span>
                  {core === c.value && <Check size={14} />}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="label">Body position? (optional)</label>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
              {POSTURES.map((p) => (
                <button
                  key={p.value} type="button"
                  className={`check-row ${posture === p.value ? 'active' : ''}`}
                  onClick={() => setPosture(posture === p.value ? '' : p.value)}
                >
                  <span style={{ flex: 1 }}>{p.label}</span>
                  {posture === p.value && <Check size={14} />}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="label">Tape trouble? (optional)</label>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
              {TAPE_STATES.map((t) => (
                <button
                  key={t.value} type="button"
                  className={`check-row ${tapes === t.value ? 'active' : ''}`}
                  onClick={() => setTapes(tapes === t.value ? '' : t.value)}
                >
                  <span style={{ flex: 1 }}>{t.label}</span>
                  {tapes === t.value && <Check size={14} />}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="label">Note (optional)</label>
            <input
              className="input"
              placeholder="e.g. after a big drink, woke up wet…"
              value={note}
              onChange={(e) => setNote(e.target.value)}
            />
          </div>

          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            <button
              className="btn btn-primary"
              onClick={addOrUpdate}
              disabled={!amount}
              style={{ flex: '1 1 auto' }}
            >
              <Droplets size={15} /> {editingId ? 'Update wetting' : 'Add wetting'}
            </button>
            {editingId && (
              <button className="btn btn-ghost" onClick={resetSubForm}>
                Cancel edit
              </button>
            )}
          </div>
        </div>
      </div>
    </Modal>
  );
}
LEDGER_EOF

mkdir -p "$(dirname src/components/Insights.jsx)"
cat > src/components/Insights.jsx << 'LEDGER_EOF'
import React, { useMemo } from 'react';
import {
  BarChart, Bar, XAxis, YAxis, ResponsiveContainer, Tooltip,
  PieChart, Pie, Cell,
} from 'recharts';
import { BarChart3, Droplets } from 'lucide-react';
import { ProductThumb, SectionHeader } from './Common';
import { LocationIcon } from './LocationManager';
import {
  productDisplayName, totalStock, dayKey, formatDuration,
} from '../lib/helpers';
import {
  WETNESS, getWettings, wettingStats, wetnessLabel, globalCapacity,
} from '../lib/wetting';
import {
  CHANGE_REASONS, contextLabel, unitCost, fmtMoney,
} from '../lib/session';

export default function Insights({ products, logs, locations, thumbs, daysRemainingMap }) {
  // Filter out moves - they're inventory transfers, not consumption
  const usageLogs = logs.filter((l) => l.type !== 'move');

  // A wear log is the modern put-on/take-off kind, or an older typed/untyped
  // entry that predates it. We surface how many predate the detailed schema so
  // sections that need putOnAt (timing, wettings, context) are read against
  // the right denominator instead of looking artificially sparse.
  const isWear = (l) => l.type === 'use' || (!l.type && (l.putOnAt || l.period));
  const legacyInfo = useMemo(() => {
    const wears = logs.filter(isWear);
    const detailed = wears.filter((l) => l.putOnAt);
    return { total: wears.length, detailed: detailed.length, legacy: wears.length - detailed.length };
  }, [logs]);

  // Last 14 days bar chart
  const dailyData = useMemo(() => {
    const days = 14;
    const out = [];
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    for (let i = days - 1; i >= 0; i--) {
      const d = new Date(today.getTime() - i * 24 * 3600 * 1000);
      const k = dayKey(d.getTime());
      const dayCount = usageLogs.filter((l) => dayKey(l.timestamp) === k && l.period === 'day').length;
      const nightCount = usageLogs.filter((l) => dayKey(l.timestamp) === k && l.period === 'night').length;
      out.push({
        date: d.toLocaleDateString(undefined, { month: 'numeric', day: 'numeric' }),
        Day: dayCount,
        Night: nightCount,
      });
    }
    return out;
  }, [usageLogs]);

  const periodSplit = useMemo(() => {
    const day = usageLogs.filter((l) => l.period === 'day').length;
    const night = usageLogs.filter((l) => l.period === 'night').length;
    return [
      { name: 'Daytime', value: day, color: '#C9985A' },
      { name: 'Overnight', value: night, color: '#2F4A3F' },
    ];
  }, [usageLogs]);

  // Average time worn per period, from completed wear sessions
  const avgWornByPeriod = useMemo(() => {
    const calc = (period) => {
      const durs = usageLogs
        .filter((l) => l.putOnAt && l.takenOffAt != null && l.period === period)
        .map((l) => l.takenOffAt - l.putOnAt)
        .filter((d) => d > 0);
      if (!durs.length) return null;
      return durs.reduce((a, b) => a + b, 0) / durs.length;
    };
    return { Daytime: calc('day'), Overnight: calc('night') };
  }, [usageLogs]);

  // ---- Wetting analytics ---------------------------------------------------
  // A "wear session" is any usage log with a putOnAt time. Wettings ride
  // inline on those logs. We look at how many wettings each diaper took and,
  // per product, how much load it held before leaking vs. while staying dry.
  const wettingAgg = useMemo(() => {
    const sessions = usageLogs.filter((l) => l.putOnAt);
    const withWet = sessions.filter((l) => getWettings(l).length > 0);
    const amountCounts = {};
    WETNESS.forEach((w) => { amountCounts[w.value] = 0; });
    let totalWettings = 0;
    sessions.forEach((l) => {
      getWettings(l).forEach((w) => {
        totalWettings += 1;
        if (amountCounts[w.amount] != null) amountCounts[w.amount] += 1;
      });
    });
    return {
      sessionCount: sessions.length,
      wetSessionCount: withWet.length,
      totalWettings,
      amountCounts,
      avgPerDiaper: sessions.length ? totalWettings / sessions.length : 0,
      avgPerWetDiaper: withWet.length ? totalWettings / withWet.length : 0,
    };
  }, [usageLogs]);

  // Per-product capacity: average "load" (summed wetting weight) on sessions
  // that leaked vs. the most it held on a session that did NOT leak.
  const capacityByProduct = useMemo(() => {
    const m = new Map();
    usageLogs.filter((l) => l.putOnAt).forEach((l) => {
      const st = wettingStats(l);
      if (st.count === 0) return;
      if (!m.has(l.productId)) m.set(l.productId, { leakLoads: [], heldLoads: [] });
      const e = m.get(l.productId);
      if (l.performance === 'leak') e.leakLoads.push(st.load);
      else e.heldLoads.push(st.load); // dry / used = held without leaking
    });
    const avg = (arr) => (arr.length ? arr.reduce((a, b) => a + b, 0) / arr.length : null);
    return [...m.entries()]
      .map(([id, e]) => ({
        product: products.find((p) => p.id === id),
        avgLeakLoad: avg(e.leakLoads),
        avgHeldLoad: avg(e.heldLoads),
        maxHeld: e.heldLoads.length ? Math.max(...e.heldLoads) : null,
        leakCount: e.leakLoads.length,
        heldCount: e.heldLoads.length,
      }))
      .filter((x) => x.product && (x.leakCount + x.heldCount) >= 1)
      .sort((a, b) => (b.avgLeakLoad ?? b.maxHeld ?? 0) - (a.avgLeakLoad ?? a.maxHeld ?? 0));
  }, [usageLogs, products]);

  // A blunt fallback ceiling across all products, shown so the live capacity
  // warning's basis is visible here too.
  const globalCap = useMemo(() => globalCapacity(usageLogs), [usageLogs]);

  // Wetting distribution by hour of day (0–23), across every session.
  const wettingByHour = useMemo(() => {
    const hours = Array.from({ length: 24 }, (_, h) => ({ hour: h, count: 0 }));
    usageLogs.filter((l) => l.putOnAt).forEach((l) => {
      getWettings(l).forEach((w) => {
        const h = new Date(w.at).getHours();
        if (h >= 0 && h < 24) hours[h].count += 1;
      });
    });
    return hours;
  }, [usageLogs]);

  // Booster effect: leak rate and average load with vs. without a booster.
  const boosterEffect = useMemo(() => {
    const sessions = usageLogs.filter((l) => l.putOnAt);
    const grp = (withB) => {
      const s = sessions.filter((l) => !!l.booster === withB);
      const perf = s.filter((l) => l.performance);
      const leaks = perf.filter((l) => l.performance === 'leak').length;
      const loads = s.map((l) => wettingStats(l).load).filter((x) => x > 0);
      return {
        n: s.length,
        leakRate: perf.length ? leaks / perf.length : null,
        avgLoad: loads.length ? loads.reduce((a, b) => a + b, 0) / loads.length : null,
      };
    };
    return { withB: grp(true), withoutB: grp(false) };
  }, [usageLogs]);

  // Usage + leak rate broken down by the context it was worn in.
  const contextStats = useMemo(() => {
    const m = new Map();
    usageLogs.filter((l) => l.putOnAt && l.context).forEach((l) => {
      if (!m.has(l.context)) m.set(l.context, { count: 0, perf: 0, leaks: 0 });
      const e = m.get(l.context);
      e.count += 1;
      if (l.performance) { e.perf += 1; if (l.performance === 'leak') e.leaks += 1; }
    });
    return [...m.entries()]
      .map(([value, e]) => ({ value, label: contextLabel(value) || value, ...e }))
      .sort((a, b) => b.count - a.count);
  }, [usageLogs]);

  // Why changes happen — distribution of change reasons.
  const reasonStats = useMemo(() => {
    const m = new Map();
    usageLogs.filter((l) => l.putOnAt && l.changeReason).forEach((l) => {
      m.set(l.changeReason, (m.get(l.changeReason) || 0) + 1);
    });
    const total = [...m.values()].reduce((a, b) => a + b, 0);
    return {
      total,
      rows: CHANGE_REASONS
        .map((r) => ({ ...r, count: m.get(r.value) || 0 }))
        .filter((r) => r.count > 0)
        .sort((a, b) => b.count - a.count),
    };
  }, [usageLogs]);

  // Skin check summary — how often skin was noted as pink or irritated.
  const skinStat = useMemo(() => {
    const sess = usageLogs.filter((l) => l.putOnAt && l.skin);
    const flagged = sess.filter((l) => l.skin === 'irritated' || l.skin === 'pink').length;
    return { total: sess.length, flagged };
  }, [usageLogs]);

  // Top products
  const topProducts = useMemo(() => {
    const m = new Map();
    usageLogs.forEach((l) => m.set(l.productId, (m.get(l.productId) || 0) + 1));
    return [...m.entries()]
      .map(([id, count]) => ({ product: products.find((p) => p.id === id), count }))
      .filter((x) => x.product)
      .sort((a, b) => b.count - a.count)
      .slice(0, 5);
  }, [usageLogs, products]);

  // Performance per product
  const performance = useMemo(() => {
    const m = new Map();
    usageLogs.forEach((l) => {
      if (!m.has(l.productId)) m.set(l.productId, { total: 0, leaks: 0, dry: 0 });
      const e = m.get(l.productId);
      e.total += 1;
      if (l.performance === 'leak') e.leaks += 1;
      if (l.performance === 'dry') e.dry += 1;
    });
    return [...m.entries()]
      .map(([id, e]) => ({ product: products.find((p) => p.id === id), ...e }))
      .filter((x) => x.product && x.total >= 2)
      .sort((a, b) => (b.leaks / b.total) - (a.leaks / a.total));
  }, [usageLogs, products]);

  // Usage by location
  const locationUsage = useMemo(() => {
    const m = new Map();
    usageLogs.forEach((l) => {
      if (!l.locationId) return;
      m.set(l.locationId, (m.get(l.locationId) || 0) + 1);
    });
    return [...m.entries()]
      .map(([id, count]) => ({
        location: locations.find((loc) => loc.id === id),
        count,
      }))
      .filter((x) => x.location)
      .sort((a, b) => b.count - a.count);
  }, [usageLogs, locations]);

  // Stats
  const totalUses = usageLogs.length;
  const firstLog = usageLogs.length ? Math.min(...usageLogs.map((l) => l.timestamp)) : null;
  const trackingDays = firstLog
    ? Math.max(1, Math.ceil((Date.now() - firstLog) / (24 * 3600 * 1000)))
    : 0;
  const avgPerDay = trackingDays > 0 ? (totalUses / trackingDays).toFixed(1) : '0';

  // Cost & value, from each product's pack cost ÷ pack size.
  const costAnalysis = useMemo(() => {
    const rows = [];
    let totalSpent = 0;
    products.forEach((p) => {
      const uc = unitCost(p);
      if (uc == null) return;
      const uses = usageLogs.filter((l) => l.productId === p.id).length;
      const spent = uses * uc;
      totalSpent += spent;
      const perf = usageLogs.filter((l) => l.productId === p.id && l.performance);
      const leaks = perf.filter((l) => l.performance === 'leak').length;
      const leakRate = perf.length ? leaks / perf.length : null;
      const perGood = leakRate != null && leakRate < 1 ? uc / (1 - leakRate) : uc;
      rows.push({ product: p, unit: uc, uses, spent, leakRate, perGood });
    });
    rows.sort((a, b) => b.spent - a.spent);
    const costPerDay = trackingDays > 0 ? totalSpent / trackingDays : 0;
    return { rows, totalSpent, costPerDay, monthly: costPerDay * 30 };
  }, [products, usageLogs, trackingDays]);

  // Format an hour (0–23) as a compact 12-hour label, e.g. 3a, 12p, 9p.
  const fmtHour = (h) => {
    const hr = ((h % 24) + 24) % 24;
    const h12 = hr % 12 === 0 ? 12 : hr % 12;
    return `${h12}${hr < 12 ? 'a' : 'p'}`;
  };

  // Auto section numbering — increments only for sections that actually render,
  // so inserting/removing a section never desyncs the labels.
  let secCount = 0;
  const secNum = () => String(++secCount).padStart(2, '0');

  const hasWetting = wettingAgg.totalWettings > 0;

  if (usageLogs.length === 0) {
    return (
      <div className="empty-state">
        <BarChart3 size={28} style={{ color: 'var(--ink-mute)' }} />
        <div className="display" style={{ fontSize: 22, marginTop: 12 }}>No data yet</div>
        <p style={{ marginTop: 8, color: 'var(--ink-soft)' }}>
          Log a few uses and patterns will start appearing here.
        </p>
      </div>
    );
  }

  return (
    <div>
      <div style={{ marginBottom: 24 }}>
        <span className="display" style={{ fontSize: 24 }}>Insights</span>
      </div>

      <div style={{
        display: 'grid', gridTemplateColumns: '1fr 1fr 1fr',
        gap: 16, marginBottom: 32,
      }}>
        <div className="stat-divider" style={{ paddingTop: 10 }}>
          <div className="num" style={{ fontSize: 32, lineHeight: 1 }}>{totalUses}</div>
          <div className="eyebrow" style={{ marginTop: 6 }}>Total uses</div>
        </div>
        <div className="stat-divider" style={{ paddingTop: 10 }}>
          <div className="num" style={{ fontSize: 32, lineHeight: 1 }}>{avgPerDay}</div>
          <div className="eyebrow" style={{ marginTop: 6 }}>Avg / day</div>
        </div>
        <div className="stat-divider" style={{ paddingTop: 10 }}>
          <div className="num" style={{ fontSize: 32, lineHeight: 1 }}>{trackingDays}</div>
          <div className="eyebrow" style={{ marginTop: 6 }}>Days tracked</div>
        </div>
      </div>

      {legacyInfo.legacy > 0 && (
        <div className="card" style={{
          padding: '12px 14px', marginBottom: 28,
          borderLeft: '3px solid var(--accent)',
        }}>
          <div style={{ fontSize: 13 }}>
            {legacyInfo.legacy} of {legacyInfo.total} logged wears predate detailed tracking
          </div>
          <div style={{ fontSize: 12, color: 'var(--ink-mute)', marginTop: 4, lineHeight: 1.45 }}>
            Those early logs have no put-on/take-off time, wettings, or context.
            Timing, wetting, capacity, booster and context sections below use only
            the {legacyInfo.detailed} detailed wear{legacyInfo.detailed !== 1 ? 's' : ''};
            totals, leak rate and cost include all {legacyInfo.total}.
          </div>
        </div>
      )}

      {/* Daily chart */}
      <section style={{ marginBottom: 36 }}>
        <SectionHeader number={secNum()} title="Last 14 days" />
        <div className="card" style={{ padding: 16 }}>
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={dailyData} margin={{ top: 8, right: 4, left: -16, bottom: 0 }}>
              <XAxis
                dataKey="date" tick={{ fontSize: 10, fill: '#8A8478' }}
                axisLine={{ stroke: '#DDD6C5' }} tickLine={false} interval={1}
              />
              <YAxis
                tick={{ fontSize: 10, fill: '#8A8478' }}
                axisLine={false} tickLine={false} allowDecimals={false}
              />
              <Tooltip
                contentStyle={{
                  background: '#FBF8F2', border: '1px solid #DDD6C5',
                  borderRadius: 6, fontSize: 12,
                }}
                cursor={{ fill: 'rgba(31,42,36,0.05)' }}
              />
              <Bar dataKey="Day" stackId="a" fill="#C9985A" radius={[0, 0, 0, 0]} />
              <Bar dataKey="Night" stackId="a" fill="#2F4A3F" radius={[3, 3, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
          <div style={{
            display: 'flex', gap: 16, justifyContent: 'center',
            marginTop: 8, fontSize: 12, color: 'var(--ink-soft)',
          }}>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
              <span style={{ width: 10, height: 10, background: '#C9985A', borderRadius: 2 }} /> Daytime
            </span>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
              <span style={{ width: 10, height: 10, background: '#2F4A3F', borderRadius: 2 }} /> Overnight
            </span>
          </div>
        </div>
      </section>

      {/* Day / night */}
      <section style={{ marginBottom: 36 }}>
        <SectionHeader number={secNum()} title="Day vs. night" />
        <div className="card" style={{
          padding: 16, display: 'flex', alignItems: 'center', gap: 16, flexWrap: 'wrap',
        }}>
          <div style={{ width: 160, height: 160, flexShrink: 0 }}>
            <ResponsiveContainer>
              <PieChart>
                <Pie data={periodSplit} dataKey="value" innerRadius={48} outerRadius={70} paddingAngle={2}>
                  {periodSplit.map((d, i) => <Cell key={i} fill={d.color} />)}
                </Pie>
              </PieChart>
            </ResponsiveContainer>
          </div>
          <div style={{ flex: 1, minWidth: 160 }}>
            {periodSplit.map((s) => (
              <div key={s.name} style={{ marginBottom: 14 }}>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: 6 }}>
                  <span style={{
                    width: 8, height: 8, borderRadius: 2,
                    background: s.color, display: 'inline-block',
                  }} />
                  <span style={{ fontSize: 13 }}>{s.name}</span>
                </div>
                <div className="num" style={{ fontSize: 24, marginTop: 2 }}>
                  {s.value}
                  <span style={{
                    fontSize: 13, color: 'var(--ink-mute)',
                    fontFamily: 'inherit', marginLeft: 6,
                  }}>
                    {totalUses ? `${Math.round((s.value / totalUses) * 100)}%` : '—'}
                  </span>
                </div>
                {avgWornByPeriod[s.name] != null && (
                  <div style={{ fontSize: 11, color: 'var(--ink-mute)', marginTop: 3 }}>
                    avg {formatDuration(avgWornByPeriod[s.name])} worn
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Wetting analysis */}
      {hasWetting && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="Wetting analysis" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)',
            marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            Across every diaper you've logged a wetting on. "Load" is a weighted
            saturation score — light 1, moderate 2, heavy 3, very heavy 4.
          </p>

          <div style={{
            display: 'grid', gridTemplateColumns: '1fr 1fr 1fr',
            gap: 16, marginBottom: 20,
          }}>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 28, lineHeight: 1 }}>
                {wettingAgg.totalWettings}
              </div>
              <div className="eyebrow" style={{ marginTop: 6 }}>Wettings</div>
            </div>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 28, lineHeight: 1 }}>
                {wettingAgg.avgPerDiaper.toFixed(1)}
              </div>
              <div className="eyebrow" style={{ marginTop: 6 }}>Avg / diaper</div>
            </div>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 28, lineHeight: 1 }}>
                {wettingAgg.avgPerWetDiaper.toFixed(1)}
              </div>
              <div className="eyebrow" style={{ marginTop: 6 }}>Avg / wet diaper</div>
            </div>
          </div>

          {/* Amount distribution */}
          <div className="card" style={{ padding: 4, marginBottom: 20 }}>
            {WETNESS.map((w) => {
              const count = wettingAgg.amountCounts[w.value] || 0;
              const pct = wettingAgg.totalWettings
                ? (count / wettingAgg.totalWettings) * 100 : 0;
              return (
                <div key={w.value} className="row-divider" style={{ padding: '12px 14px' }}>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                    <Droplets size={14} style={{ color: 'var(--accent)', alignSelf: 'center' }} />
                    <span style={{ flex: 1, fontSize: 14 }}>{w.label}</span>
                    <span className="num" style={{ fontSize: 16 }}>{count}</span>
                    <span style={{ fontSize: 11, color: 'var(--ink-mute)', marginLeft: 4 }}>
                      {wettingAgg.totalWettings ? `${Math.round(pct)}%` : ''}
                    </span>
                  </div>
                  <div style={{
                    height: 3, background: 'var(--line-soft)',
                    borderRadius: 2, marginTop: 8, marginLeft: 24,
                  }}>
                    <div style={{
                      height: '100%', width: `${pct}%`,
                      background: 'var(--accent)', borderRadius: 2,
                    }} />
                  </div>
                </div>
              );
            })}
          </div>

          {/* Wetting time of day */}
          <div style={{ marginBottom: 20 }}>
            <p style={{
              fontSize: 12, color: 'var(--ink-mute)',
              marginBottom: 8, fontStyle: 'italic',
            }}>
              When wettings tend to happen, by hour of day.
            </p>
            <div className="card" style={{ padding: 16 }}>
              <ResponsiveContainer width="100%" height={170}>
                <BarChart data={wettingByHour} margin={{ top: 8, right: 4, left: -16, bottom: 0 }}>
                  <XAxis
                    dataKey="hour" tick={{ fontSize: 10, fill: '#8A8478' }}
                    axisLine={{ stroke: '#DDD6C5' }} tickLine={false}
                    interval={2} tickFormatter={fmtHour}
                  />
                  <YAxis
                    tick={{ fontSize: 10, fill: '#8A8478' }}
                    axisLine={false} tickLine={false} allowDecimals={false}
                  />
                  <Tooltip
                    contentStyle={{
                      background: '#FBF8F2', border: '1px solid #DDD6C5',
                      borderRadius: 6, fontSize: 12,
                    }}
                    cursor={{ fill: 'rgba(31,42,36,0.05)' }}
                    labelFormatter={(h) => fmtHour(h)}
                  />
                  <Bar dataKey="count" fill="#C9985A" radius={[3, 3, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>
          </div>

          {/* Capacity before leak, per product */}
          {capacityByProduct.length > 0 && (
            <>
              <p style={{
                fontSize: 12, color: 'var(--ink-mute)',
                marginBottom: 12, fontStyle: 'italic',
              }}>
                How much each product tends to hold — the average load when it
                leaked vs. the most it held while staying dry.
              </p>
              <div className="card" style={{ padding: 4 }}>
                {capacityByProduct.map((c) => (
                  <div key={c.product.id} className="row-divider" style={{ padding: '12px 14px' }}>
                    <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                      <ProductThumb
                        product={c.product} thumbs={thumbs} size={20}
                        style={{ alignSelf: 'center' }}
                      />
                      <span style={{ flex: 1, fontSize: 14 }}>{productDisplayName(c.product)}</span>
                    </div>
                    <div style={{
                      display: 'flex', gap: 12, marginTop: 6,
                      marginLeft: 22, fontSize: 12, flexWrap: 'wrap',
                    }}>
                      <span style={{ color: c.avgLeakLoad != null ? 'var(--danger)' : 'var(--ink-mute)' }}>
                        {c.avgLeakLoad != null
                          ? <>leaked at <span className="num">~{c.avgLeakLoad.toFixed(1)}</span> load <span style={{ color: 'var(--ink-mute)' }}>({c.leakCount}×)</span></>
                          : 'no leaks logged'}
                      </span>
                      {c.maxHeld != null && (
                        <span style={{ color: 'var(--primary)' }}>
                          held up to <span className="num">{c.maxHeld}</span> dry <span style={{ color: 'var(--ink-mute)' }}>({c.heldCount}×)</span>
                        </span>
                      )}
                    </div>
                  </div>
                ))}
              </div>
              {(globalCap.dryCeiling != null || globalCap.leakFloor != null) && (
                <p style={{
                  fontSize: 11, color: 'var(--ink-mute)',
                  marginTop: 10, fontStyle: 'italic',
                }}>
                  Across all products, the most held dry was a load of{' '}
                  <span className="num">{globalCap.dryCeiling ?? '—'}</span>
                  {globalCap.leakFloor != null && (
                    <>; leaks have started as low as <span className="num">{globalCap.leakFloor}</span></>
                  )}. A worn diaper nearing these gets a heads-up on its wettings screen.
                </p>
              )}
            </>
          )}
        </section>
      )}

      {/* Cost & value */}
      {costAnalysis.rows.length > 0 && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="Cost & value" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)',
            marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            From each product's pack cost ÷ pack size, in whatever currency you entered. Add those on a product to include it here.
          </p>
          <div style={{
            display: 'grid', gridTemplateColumns: '1fr 1fr 1fr',
            gap: 16, marginBottom: 20,
          }}>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 24, lineHeight: 1 }}>{fmtMoney(costAnalysis.monthly)}</div>
              <div className="eyebrow" style={{ marginTop: 6 }}>Est. / month</div>
            </div>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 24, lineHeight: 1 }}>{fmtMoney(costAnalysis.costPerDay)}</div>
              <div className="eyebrow" style={{ marginTop: 6 }}>Avg / day</div>
            </div>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 24, lineHeight: 1 }}>{fmtMoney(costAnalysis.totalSpent)}</div>
              <div className="eyebrow" style={{ marginTop: 6 }}>Logged spend</div>
            </div>
          </div>
          <div className="card" style={{ padding: 4 }}>
            {costAnalysis.rows.map(({ product, unit, uses, spent, leakRate, perGood }) => (
              <div key={product.id} className="row-divider" style={{ padding: '12px 14px' }}>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                  <ProductThumb product={product} thumbs={thumbs} size={20} style={{ alignSelf: 'center' }} />
                  <span style={{ flex: 1, fontSize: 14 }}>{productDisplayName(product)}</span>
                  <span className="num" style={{ fontSize: 15 }}>{fmtMoney(unit)}</span>
                  <span style={{ fontSize: 11, color: 'var(--ink-mute)', marginLeft: 4 }}>each</span>
                </div>
                <div style={{
                  display: 'flex', gap: 12, marginTop: 6, marginLeft: 30,
                  fontSize: 12, color: 'var(--ink-mute)', flexWrap: 'wrap',
                }}>
                  <span>{uses} used · {fmtMoney(spent)} spent</span>
                  {leakRate != null && leakRate > 0 && (
                    <span style={{ color: 'var(--primary)' }}>
                      {fmtMoney(perGood)} per leak-free wear
                    </span>
                  )}
                </div>
              </div>
            ))}
          </div>
        </section>
      )}

      {/* Boosters */}
      {boosterEffect.withB.n > 0 && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="Boosters" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)',
            marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            Whether adding a booster changed how often things leaked or how much was held.
          </p>
          <div className="card" style={{ padding: 4 }}>
            {[{ key: 'withB', label: 'With booster' }, { key: 'withoutB', label: 'Without booster' }].map(({ key, label }) => {
              const g = boosterEffect[key];
              return (
                <div key={key} className="row-divider" style={{ padding: '12px 14px' }}>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                    <span style={{ flex: 1, fontSize: 14 }}>{label}</span>
                    <span style={{ fontSize: 12, color: 'var(--ink-mute)' }}>
                      {g.n} session{g.n !== 1 ? 's' : ''}
                    </span>
                  </div>
                  <div style={{
                    display: 'flex', gap: 12, marginTop: 6,
                    fontSize: 12, flexWrap: 'wrap',
                  }}>
                    <span style={{ color: g.leakRate ? 'var(--danger)' : 'var(--ink-mute)' }}>
                      {g.leakRate == null ? 'no leak data' : `${Math.round(g.leakRate * 100)}% leaked`}
                    </span>
                    <span style={{ color: 'var(--accent)' }}>
                      {g.avgLoad == null ? 'no load data' : `avg load ${g.avgLoad.toFixed(1)}`}
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}

      {/* By context */}
      {contextStats.length > 0 && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="By context" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)',
            marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            Where you were wearing it, and how often each leaked.
          </p>
          <div className="card" style={{ padding: 4 }}>
            {contextStats.map((c) => {
              const max = contextStats[0].count;
              const pct = (c.count / max) * 100;
              return (
                <div key={c.value} className="row-divider" style={{ padding: '12px 14px' }}>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                    <span style={{ flex: 1, fontSize: 14 }}>{c.label}</span>
                    <span className="num" style={{ fontSize: 16 }}>{c.count}</span>
                    {c.perf > 0 && (
                      <span style={{
                        fontSize: 11, marginLeft: 4,
                        color: c.leaks ? 'var(--danger)' : 'var(--ink-mute)',
                      }}>
                        {Math.round((c.leaks / c.perf) * 100)}% leak
                      </span>
                    )}
                  </div>
                  <div style={{
                    height: 3, background: 'var(--line-soft)',
                    borderRadius: 2, marginTop: 8,
                  }}>
                    <div style={{
                      height: '100%', width: `${pct}%`,
                      background: 'var(--primary)', borderRadius: 2,
                    }} />
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}

      {/* Why changes happen */}
      {reasonStats.total > 0 && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="Why changes happen" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)',
            marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            {skinStat.total > 0
              ? `Skin noted as pink or irritated on ${skinStat.flagged} of ${skinStat.total} change${skinStat.total !== 1 ? 's' : ''}.`
              : 'What prompts a change, across your logged take-offs.'}
          </p>
          <div className="card" style={{ padding: 4 }}>
            {reasonStats.rows.map((r) => {
              const pct = (r.count / reasonStats.total) * 100;
              return (
                <div key={r.value} className="row-divider" style={{ padding: '12px 14px' }}>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                    <span style={{ flex: 1, fontSize: 14 }}>{r.label}</span>
                    <span className="num" style={{ fontSize: 16 }}>{r.count}</span>
                    <span style={{ fontSize: 11, color: 'var(--ink-mute)', marginLeft: 4 }}>
                      {Math.round(pct)}%
                    </span>
                  </div>
                  <div style={{
                    height: 3, background: 'var(--line-soft)',
                    borderRadius: 2, marginTop: 8,
                  }}>
                    <div style={{
                      height: '100%', width: `${pct}%`,
                      background: 'var(--accent)', borderRadius: 2,
                    }} />
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}

      {/* Usage by location */}
      {locationUsage.length > 0 && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="Usage by location" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)',
            marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            Where you're consuming most. Helpful for knowing where to keep more stock.
          </p>
          <div className="card" style={{ padding: 4 }}>
            {locationUsage.map(({ location, count }) => {
              const max = locationUsage[0].count;
              const pct = (count / max) * 100;
              return (
                <div key={location.id} className="row-divider" style={{ padding: '12px 14px' }}>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                    <LocationIcon name={location.icon} size={14} style={{ color: 'var(--ink-soft)', alignSelf: 'center' }} />
                    <span style={{ flex: 1, fontSize: 14 }}>{location.name}</span>
                    <span className="num" style={{ fontSize: 16 }}>{count}</span>
                    <span style={{ fontSize: 11, color: 'var(--ink-mute)', marginLeft: 4 }}>
                      {totalUses ? `${Math.round((count / totalUses) * 100)}%` : ''}
                    </span>
                  </div>
                  <div style={{
                    height: 3, background: 'var(--line-soft)',
                    borderRadius: 2, marginTop: 8, marginLeft: 24,
                  }}>
                    <div style={{
                      height: '100%', width: `${pct}%`,
                      background: 'var(--accent)', borderRadius: 2,
                    }} />
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}

      {/* Top products */}
      {topProducts.length > 0 && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="Most used" />
          <div className="card" style={{ padding: 4 }}>
            {topProducts.map(({ product, count }, i) => {
              const max = topProducts[0].count;
              const pct = (count / max) * 100;
              return (
                <div key={product.id} className="row-divider" style={{ padding: '12px 14px' }}>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                    <span className="num" style={{
                      fontSize: 14, color: 'var(--ink-mute)', width: 18,
                    }}>
                      {i + 1}.
                    </span>
                    <ProductThumb
                      product={product} thumbs={thumbs} size={20}
                      style={{ alignSelf: 'center' }}
                    />
                    <span style={{ flex: 1, fontSize: 14 }}>{productDisplayName(product)}</span>
                    <span className="num" style={{ fontSize: 16 }}>{count}</span>
                  </div>
                  <div style={{
                    height: 3, background: 'var(--line-soft)',
                    borderRadius: 2, marginTop: 8, marginLeft: 28,
                  }}>
                    <div style={{
                      height: '100%', width: `${pct}%`,
                      background: 'var(--primary)', borderRadius: 2,
                    }} />
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}

      {/* Performance */}
      {performance.length > 0 && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="Performance" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)',
            marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            Leak rate per product (only products with 2+ logs shown).
          </p>
          <div className="card" style={{ padding: 4 }}>
            {performance.map(({ product, total, leaks, dry }) => {
              const leakRate = (leaks / total) * 100;
              const dryRate = (dry / total) * 100;
              return (
                <div key={product.id} className="row-divider" style={{ padding: '12px 14px' }}>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                    <ProductThumb
                      product={product} thumbs={thumbs} size={20}
                      style={{ alignSelf: 'center' }}
                    />
                    <span style={{ flex: 1, fontSize: 14 }}>{productDisplayName(product)}</span>
                    <span style={{ fontSize: 12, color: 'var(--ink-mute)' }}>
                      {total} log{total !== 1 ? 's' : ''}
                    </span>
                  </div>
                  <div style={{
                    display: 'flex', gap: 12, marginTop: 6,
                    marginLeft: 22, fontSize: 12,
                  }}>
                    <span style={{ color: leakRate > 0 ? 'var(--danger)' : 'var(--ink-mute)' }}>
                      {leaks} leak{leaks !== 1 ? 's' : ''} <span className="num">({Math.round(leakRate)}%)</span>
                    </span>
                    <span style={{ color: 'var(--primary)' }}>
                      {dry} dry <span className="num">({Math.round(dryRate)}%)</span>
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}

      {/* Days remaining */}
      <section style={{ marginBottom: 36 }}>
        <SectionHeader number={secNum()} title="Estimated days remaining" />
        <p style={{
          fontSize: 12, color: 'var(--ink-mute)',
          marginTop: -8, marginBottom: 12, fontStyle: 'italic',
        }}>
          Based on usage in the last 14 days. Restock before items run out.
        </p>
        <div className="card" style={{ padding: 4 }}>
          {products.length === 0 && (
            <div style={{ padding: 16, color: 'var(--ink-mute)', fontSize: 13 }}>
              No products yet.
            </div>
          )}
          {products.map((p) => {
            const days = daysRemainingMap[p.id];
            return (
              <div
                key={p.id}
                className="row-divider"
                style={{
                  padding: '12px 14px',
                  display: 'flex', alignItems: 'center', gap: 10,
                }}
              >
                <ProductThumb product={p} thumbs={thumbs} size={20} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 14 }}>{productDisplayName(p)}</div>
                  <div style={{ fontSize: 12, color: 'var(--ink-mute)' }}>
                    {totalStock(p)} on hand total
                  </div>
                </div>
                <div style={{ textAlign: 'right' }}>
                  <div className="num" style={{ fontSize: 18 }}>
                    {days == null ? '—' : (Number.isFinite(days) ? `${days}d` : '∞')}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </section>
    </div>
  );
}
LEDGER_EOF

mkdir -p "$(dirname src/App.jsx)"
cat > src/App.jsx << 'LEDGER_EOF'
import React, { useState, useEffect, useMemo } from 'react';
import {
  Plus, Settings as SettingsIcon, LayoutDashboard,
  Package, ClipboardList, BarChart3, Repeat,
  ShieldAlert, X,
} from 'lucide-react';

import { Toast, ConfirmDialog } from './components/Common';
import Dashboard from './components/Dashboard';
import Inventory from './components/Inventory';
import History from './components/History';
import Insights from './components/Insights';
import ProductForm from './components/ProductForm';
import LogForm from './components/LogForm';
import WearForm from './components/WearForm';
import TakeOffForm from './components/TakeOffForm';
import MoveForm from './components/MoveForm';
import RestockForm from './components/RestockForm';
import LocationManager from './components/LocationManager';
import Settings from './components/Settings';
import PhotoViewer from './components/PhotoViewer';
import WettingForm from './components/WettingForm';
import NoteForm from './components/NoteForm';
import { CHANGE_OUT_WINDOW_MS } from './lib/session';

import {
  getAllProducts, getAllLocations, getAllLogs, getAllThumbs,
  saveProduct, removeProduct, saveLocation, removeLocation,
  saveLog, removeLog, kvGet,
} from './lib/storage';
import { stockAt, isWornNow, formatDuration } from './lib/helpers';

export default function App() {
  // Core data
  const [products, setProducts] = useState([]);
  const [locations, setLocations] = useState([]);
  const [logs, setLogs] = useState([]);
  const [thumbs, setThumbs] = useState({});
  const [loading, setLoading] = useState(true);

  // Backup reminder
  const [lastBackupAt, setLastBackupAt] = useState(null);
  const [backupDismissed, setBackupDismissed] = useState(false);

  // UI state
  const [tab, setTab] = useState('home');
  const [toastMsg, setToastMsg] = useState('');

  // Modals
  const [productFormOpen, setProductFormOpen] = useState(false);
  const [editingProduct, setEditingProduct] = useState(null);

  const [logFormOpen, setLogFormOpen] = useState(false);
  const [editingLog, setEditingLog] = useState(null);
  const [defaultLogProduct, setDefaultLogProduct] = useState(null);

  // Wear-session modals
  const [wearFormOpen, setWearFormOpen] = useState(false);
  const [wearDefaultProduct, setWearDefaultProduct] = useState(null);
  // When the user picks "take off and change into another," this holds the
  // take-off's id so the next put-on can be marked as a direct change-out.
  const [pendingChangeFromId, setPendingChangeFromId] = useState(null);
  const [takeOffEntry, setTakeOffEntry] = useState(null);
  const [takeOffThen, setTakeOffThen] = useState('none');

  // Wetting tracking modal — holds the wear-session log being edited
  const [wettingEntry, setWettingEntry] = useState(null);

  // Note log modal
  const [noteFormOpen, setNoteFormOpen] = useState(false);
  const [editingNote, setEditingNote] = useState(null);
  const [noteContext, setNoteContext] = useState(null);

  const [moveFormOpen, setMoveFormOpen] = useState(false);
  const [moveProductId, setMoveProductId] = useState(null);

  const [restockProduct, setRestockProduct] = useState(null);
  const [locationsOpen, setLocationsOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [photoViewerProductId, setPhotoViewerProductId] = useState(null);

  const [confirmDeleteProduct, setConfirmDeleteProduct] = useState(null);
  const [confirmDeleteLog, setConfirmDeleteLog] = useState(null);

  // Initial load
  const loadAll = async () => {
    setLoading(true);
    try {
      const [p, l, lg, th] = await Promise.all([
        getAllProducts(),
        getAllLocations(),
        getAllLogs(),
        getAllThumbs(),
      ]);
      setProducts(p || []);
      setLocations(l || []);
      setLogs(lg || []);
      setThumbs(th || {});
      try { setLastBackupAt(await kvGet('lastBackupAt')); } catch { /* ignore */ }
    } catch (e) {
      console.error('Load failed', e);
    }
    setLoading(false);
  };

  useEffect(() => { loadAll(); }, []);

  // Derived: estimate days remaining based on last 14d usage
  const daysRemainingMap = useMemo(() => {
    const map = {};
    const cutoff = Date.now() - 14 * 24 * 3600 * 1000;
    const usageLogs = logs.filter((l) => l.type !== 'move');
    products.forEach((p) => {
      const productLogs = usageLogs.filter((l) => l.productId === p.id && l.timestamp >= cutoff);
      const total = Object.values(p.stock || {}).reduce((s, n) => s + (Number(n) || 0), 0);
      if (productLogs.length === 0) {
        map[p.id] = null;
      } else {
        const span = Math.max(1, Math.ceil((Date.now() - cutoff) / (24 * 3600 * 1000)));
        const perDay = productLogs.length / span;
        map[p.id] = perDay > 0 ? Math.floor(total / perDay) : Infinity;
      }
    });
    return map;
  }, [products, logs]);

  // The diaper currently being worn (if any) — derived from logs so it
  // survives reloads. At most one active session at a time.
  const activeWear = useMemo(() => logs.find(isWornNow) || null, [logs]);

  // === Wear-session handlers ===
  const handlePutOn = async (entry) => {
    // Auto-link: if there's a recent take-off within the change-out window
    // (and this put-on doesn't already carry a link from an explicit "change into"
    // flow), record it as a direct change-out on both sides.
    let toSave = entry;
    if (pendingChangeFromId) {
      toSave = { ...toSave, changedFromId: pendingChangeFromId };
      const src = logs.find((l) => l.id === pendingChangeFromId);
      if (src) {
        const linked = { ...src, changedToId: toSave.id };
        await saveLog(linked);
        setLogs((prev) => prev.map((l) => l.id === linked.id ? linked : l));
      }
    } else if (!toSave.changedFromId) {
      const recentTakeOff = [...logs]
        .filter((l) => l.type !== 'move' && l.type !== 'note' && l.takenOffAt && !l.changedToId)
        .sort((a, b) => (b.takenOffAt || 0) - (a.takenOffAt || 0))[0];
      if (recentTakeOff && toSave.putOnAt - recentTakeOff.takenOffAt <= CHANGE_OUT_WINDOW_MS) {
        toSave = { ...toSave, changedFromId: recentTakeOff.id };
        const linked = { ...recentTakeOff, changedToId: toSave.id };
        await saveLog(linked);
        setLogs((prev) => prev.map((l) => l.id === linked.id ? linked : l));
      }
    }
    await saveLog(toSave);
    setLogs((prev) => [...prev, toSave]);
    // Decrement stock at the source location
    const product = products.find((p) => p.id === toSave.productId);
    if (product && toSave.locationId) {
      const currentAt = stockAt(product, toSave.locationId);
      const updated = {
        ...product,
        stock: { ...product.stock, [toSave.locationId]: Math.max(0, currentAt - 1) },
      };
      await saveProduct(updated);
      setProducts((prev) => prev.map((p) => p.id === updated.id ? updated : p));
    }
    setWearFormOpen(false);
    setWearDefaultProduct(null);
    setPendingChangeFromId(null);
    setToastMsg(toSave.changedFromId ? 'Changed' : 'Put on');
  };

  const handleTakeOff = async (updatedEntry, thenReplace) => {
    await saveLog(updatedEntry);
    setLogs((prev) => prev.map((l) => l.id === updatedEntry.id ? updatedEntry : l));
    setTakeOffEntry(null);
    setToastMsg('Taken off');
    if (thenReplace) {
      // Default the new one to the same product for a quick change-out;
      // remember this take-off so the next put-on links back to it.
      setWearDefaultProduct(updatedEntry.productId);
      setPendingChangeFromId(updatedEntry.id);
      setWearFormOpen(true);
    }
  };

  // Undo a put-on done by mistake: remove the open session and refund stock
  const handleCancelWear = async (entry) => {
    // If this put-on was linked to a take-off as a change-out, unlink it.
    if (entry.changedFromId) {
      const src = logs.find((l) => l.id === entry.changedFromId);
      if (src && src.changedToId === entry.id) {
        const unlinked = { ...src, changedToId: null };
        await saveLog(unlinked);
        setLogs((prev) => prev.map((l) => l.id === unlinked.id ? unlinked : l));
      }
    }
    await removeLog(entry.id);
    setLogs((prev) => prev.filter((l) => l.id !== entry.id));
    const product = products.find((p) => p.id === entry.productId);
    if (product && entry.locationId) {
      const currentAt = stockAt(product, entry.locationId);
      const updated = {
        ...product,
        stock: { ...product.stock, [entry.locationId]: currentAt + 1 },
      };
      await saveProduct(updated);
      setProducts((prev) => prev.map((p) => p.id === updated.id ? updated : p));
    }
    setToastMsg('Put back');
  };

  const openWearForm = (productId) => {
    if (activeWear) {
      // Already wearing one — deal with it first via change-out
      setToastMsg('Take off the current one first');
      openTakeOff(activeWear, 'replace');
      return;
    }
    setWearDefaultProduct(productId || null);
    setWearFormOpen(true);
  };

  const openTakeOff = (entry, then = 'none') => {
    setTakeOffEntry(entry);
    setTakeOffThen(then);
  };

  // Save/persist the wettings array for a wear-session log. Works for the
  // diaper on now or any previously worn one. Called live as the user
  // adds/edits/removes entries in the WettingForm.
  const handleSaveWettings = async (logId, wettings) => {
    const target = logs.find((l) => l.id === logId);
    if (!target) return;
    const updated = { ...target, wettings };
    await saveLog(updated);
    setLogs((prev) => prev.map((l) => (l.id === logId ? updated : l)));
  };

  // === Save handlers ===
  const handleSaveProduct = async (product) => {
    const exists = products.find((p) => p.id === product.id);
    await saveProduct(product);
    setProducts(exists
      ? products.map((p) => p.id === product.id ? product : p)
      : [...products, product]
    );
    // Refresh thumbs map (in case photo was added/changed/removed)
    const th = await getAllThumbs();
    setThumbs(th);
    setProductFormOpen(false);
    setEditingProduct(null);
    setToastMsg(exists ? 'Product updated' : 'Product added');
  };

  const handleDeleteProduct = async (product) => {
    await removeProduct(product.id);
    setProducts(products.filter((p) => p.id !== product.id));
    const newThumbs = { ...thumbs };
    delete newThumbs[product.id];
    setThumbs(newThumbs);
    setConfirmDeleteProduct(null);
    setToastMsg('Product deleted');
  };

  const handleSaveLocation = async (location) => {
    const exists = locations.find((l) => l.id === location.id);
    await saveLocation(location);
    setLocations(exists
      ? locations.map((l) => l.id === location.id ? location : l)
      : [...locations, location]
    );
    setToastMsg(exists ? 'Location updated' : 'Location added');
  };

  const handleDeleteLocation = async (location) => {
    await removeLocation(location.id);
    setLocations(locations.filter((l) => l.id !== location.id));
    setToastMsg('Location deleted');
  };

  const handleReorderLocations = async (reordered) => {
    setLocations(reordered);
    await Promise.all(reordered.map((l) => saveLocation(l)));
  };

  const handleSaveLog = async (entry, decrementInventory) => {
    const exists = logs.find((l) => l.id === entry.id);
    await saveLog(entry);
    setLogs(exists
      ? logs.map((l) => l.id === entry.id ? entry : l)
      : [...logs, entry]
    );

    if (decrementInventory && entry.locationId) {
      const product = products.find((p) => p.id === entry.productId);
      if (product) {
        const currentAt = stockAt(product, entry.locationId);
        const updated = {
          ...product,
          stock: {
            ...product.stock,
            [entry.locationId]: Math.max(0, currentAt - 1),
          },
        };
        await saveProduct(updated);
        setProducts(products.map((p) => p.id === updated.id ? updated : p));
      }
    }

    setLogFormOpen(false);
    setEditingLog(null);
    setDefaultLogProduct(null);
    setToastMsg(exists ? 'Entry updated' : 'Logged');
  };

  const handleDeleteLog = async (entry) => {
    await removeLog(entry.id);
    setLogs(logs.filter((l) => l.id !== entry.id));
    setConfirmDeleteLog(null);
    setToastMsg('Entry deleted');
  };

  // Move stock between locations
  const handleSaveMove = async (move) => {
    const product = products.find((p) => p.id === move.productId);
    if (!product) return;
    const fromStock = stockAt(product, move.fromLocationId);
    const toStock = stockAt(product, move.toLocationId);

    const updated = {
      ...product,
      stock: {
        ...product.stock,
        [move.fromLocationId]: Math.max(0, fromStock - move.quantity),
        [move.toLocationId]: toStock + move.quantity,
      },
    };
    await saveProduct(updated);
    setProducts(products.map((p) => p.id === updated.id ? updated : p));

    // Log the move so it appears in history
    await saveLog(move);
    setLogs([...logs, move]);

    setMoveFormOpen(false);
    setMoveProductId(null);
    setToastMsg('Stock moved');
  };

  const handleRestockSave = async (updated) => {
    await saveProduct(updated);
    setProducts(products.map((p) => p.id === updated.id ? updated : p));
    setRestockProduct(null);
    setToastMsg('Stock updated');
  };

  const openMoveForm = (productId) => {
    setMoveProductId(productId || null);
    setMoveFormOpen(true);
  };

  // Note logs (type: 'note') — free-standing or attached to the diaper on now.
  const handleSaveNote = async (note) => {
    const exists = logs.find((l) => l.id === note.id);
    await saveLog(note);
    setLogs(exists ? logs.map((l) => (l.id === note.id ? note : l)) : [...logs, note]);
    setNoteFormOpen(false);
    setEditingNote(null);
    setNoteContext(null);
    setToastMsg(exists ? 'Note updated' : 'Note added');
  };

  const openNoteForm = (context) => {
    setEditingNote(null);
    setNoteContext(context || null);
    setNoteFormOpen(true);
  };

  const tabs = [
    { v: 'home', label: 'Today', icon: LayoutDashboard },
    { v: 'inventory', label: 'Inventory', icon: Package },
    { v: 'history', label: 'History', icon: ClipboardList },
    { v: 'insights', label: 'Insights', icon: BarChart3 },
  ];

  if (loading) {
    return (
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        minHeight: '100vh',
      }}>
        <div className="display-italic" style={{ fontSize: 24, color: 'var(--ink-mute)' }}>
          loading…
        </div>
      </div>
    );
  }

  const showFab = locations.length > 0 && products.length > 0;

  // Nudge a backup if there's data to lose and it's been >14 days (or never).
  const BACKUP_AGE_MS = 14 * 24 * 3600 * 1000;
  const needsBackup =
    logs.length > 0 &&
    !backupDismissed &&
    (lastBackupAt == null || Date.now() - lastBackupAt > BACKUP_AGE_MS);

  return (
    <div>
      <header className="app-header">
        <div style={{
          maxWidth: 760, margin: '0 auto',
          display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap',
        }}>
          <div style={{ flex: 1 }}>
            <span className="display-italic" style={{ fontSize: 26, letterSpacing: '-0.02em' }}>
              Diaper
            </span>
            <span className="eyebrow" style={{ marginLeft: 10, fontSize: 9.5 }}>
              usage and inventory tracking
            </span>
          </div>
          <nav className="top-tabs">
            {tabs.map((t) => {
              const Icon = t.icon;
              return (
                <button
                  key={t.v}
                  className={`top-tab ${tab === t.v ? 'active' : ''}`}
                  onClick={() => setTab(t.v)}
                >
                  <Icon size={14} /> {t.label}
                </button>
              );
            })}
          </nav>
          <button
            className="btn-icon"
            onClick={() => setSettingsOpen(true)}
            aria-label="Settings"
            style={{ marginLeft: 4 }}
          >
            <SettingsIcon size={18} />
          </button>
        </div>
      </header>

      <main className="with-bottom-nav" style={{
        maxWidth: 760, margin: '0 auto', padding: '24px 20px',
      }}>
        {needsBackup && (
          <div className="card" style={{
            padding: '12px 14px', marginBottom: 20,
            display: 'flex', alignItems: 'center', gap: 12,
            borderColor: 'var(--accent)',
          }}>
            <ShieldAlert size={18} style={{ color: 'var(--accent)', flexShrink: 0 }} />
            <div style={{ flex: 1, minWidth: 0, fontSize: 13 }}>
              <div style={{ fontWeight: 600 }}>Time to back up</div>
              <div style={{ color: 'var(--ink-soft)' }}>
                {lastBackupAt
                  ? `Last backup was ${formatDuration(Date.now() - lastBackupAt)} ago. `
                  : 'Your data lives only on this device. '}
                Export a copy so you don't lose it.
              </div>
            </div>
            <button
              className="btn btn-primary"
              style={{ flexShrink: 0 }}
              onClick={() => setSettingsOpen(true)}
            >
              Back up
            </button>
            <button
              className="btn-icon"
              aria-label="Dismiss backup reminder"
              style={{ flexShrink: 0 }}
              onClick={() => setBackupDismissed(true)}
            >
              <X size={16} />
            </button>
          </div>
        )}
        {tab === 'home' && (
          <Dashboard
            products={products} logs={logs} locations={locations} thumbs={thumbs}
            activeWear={activeWear}
            onAddProduct={() => { setEditingProduct(null); setProductFormOpen(true); }}
            onAddLocation={() => setLocationsOpen(true)}
            onPutOn={openWearForm}
            onChangeOut={(entry) => openTakeOff(entry, 'replace')}
            onTakeOff={(entry) => openTakeOff(entry, 'none')}
            onUndoWear={handleCancelWear}
            onLogWetting={(entry) => setWettingEntry(entry)}
            onRestock={(p) => setRestockProduct(p)}
            onMove={openMoveForm}
            onAddNote={openNoteForm}
            onPhotoTap={setPhotoViewerProductId}
          />
        )}
        {tab === 'inventory' && (
          <Inventory
            products={products} locations={locations} thumbs={thumbs}
            daysRemainingMap={daysRemainingMap}
            onAdd={() => { setEditingProduct(null); setProductFormOpen(true); }}
            onEdit={(p) => { setEditingProduct(p); setProductFormOpen(true); }}
            onLogQuick={openWearForm}
            onRestock={(p) => setRestockProduct(p)}
            onMove={openMoveForm}
            onPhotoTap={setPhotoViewerProductId}
          />
        )}
        {tab === 'history' && (
          <History
            logs={logs} products={products} locations={locations} thumbs={thumbs}
            onEdit={(l) => {
              if (l.type === 'note') { setEditingNote(l); setNoteContext(null); setNoteFormOpen(true); }
              else { setEditingLog(l); setLogFormOpen(true); }
            }}
            onDelete={(l) => setConfirmDeleteLog(l)}
            onManageWettings={(l) => setWettingEntry(l)}
            onPhotoTap={setPhotoViewerProductId}
          />
        )}
        {tab === 'insights' && (
          <Insights
            products={products} logs={logs} locations={locations} thumbs={thumbs}
            daysRemainingMap={daysRemainingMap}
          />
        )}
      </main>

      {showFab && (
        activeWear ? (
          <button className="fab" onClick={() => openTakeOff(activeWear, 'none')} aria-label="Manage what you're wearing">
            <Repeat size={22} />
          </button>
        ) : (
          <button className="fab" onClick={() => openWearForm(null)} aria-label="Put one on">
            <Plus size={24} />
          </button>
        )
      )}

      <nav className="bottom-nav">
        {tabs.map((t) => {
          const Icon = t.icon;
          return (
            <button
              key={t.v}
              className={`nav-btn ${tab === t.v ? 'active' : ''}`}
              onClick={() => setTab(t.v)}
            >
              <Icon size={18} />
              {t.label}
            </button>
          );
        })}
      </nav>

      {/* Modals */}
      <ProductForm
        open={productFormOpen}
        onClose={() => { setProductFormOpen(false); setEditingProduct(null); }}
        onSave={handleSaveProduct}
        onDelete={(p) => { setProductFormOpen(false); setConfirmDeleteProduct(p); }}
        initial={editingProduct}
        locations={locations}
      />

      <LogForm
        open={logFormOpen}
        onClose={() => { setLogFormOpen(false); setEditingLog(null); setDefaultLogProduct(null); }}
        onSave={handleSaveLog}
        products={products}
        locations={locations}
        initial={editingLog}
        defaultProductId={defaultLogProduct}
      />

      <WearForm
        open={wearFormOpen}
        onClose={() => { setWearFormOpen(false); setWearDefaultProduct(null); setPendingChangeFromId(null); }}
        onSave={handlePutOn}
        products={products}
        locations={locations}
        defaultProductId={wearDefaultProduct}
      />

      <TakeOffForm
        open={!!takeOffEntry}
        onClose={() => setTakeOffEntry(null)}
        onConfirm={handleTakeOff}
        entry={takeOffEntry}
        product={takeOffEntry ? products.find((p) => p.id === takeOffEntry.productId) : null}
        defaultThen={takeOffThen}
      />

      <WettingForm
        open={!!wettingEntry}
        onClose={() => setWettingEntry(null)}
        entry={wettingEntry ? (logs.find((l) => l.id === wettingEntry.id) || wettingEntry) : null}
        product={wettingEntry ? products.find((p) => p.id === wettingEntry.productId) : null}
        onSave={handleSaveWettings}
        logs={logs}
      />

      <NoteForm
        open={noteFormOpen}
        onClose={() => { setNoteFormOpen(false); setEditingNote(null); setNoteContext(null); }}
        onSave={handleSaveNote}
        initial={editingNote}
        context={noteContext}
        locations={locations}
        products={products}
      />

      <MoveForm
        open={moveFormOpen}
        onClose={() => { setMoveFormOpen(false); setMoveProductId(null); }}
        onSave={handleSaveMove}
        products={products}
        locations={locations}
        initialProductId={moveProductId}
      />

      <RestockForm
        open={!!restockProduct}
        onClose={() => setRestockProduct(null)}
        product={restockProduct}
        locations={locations}
        onSave={handleRestockSave}
      />

      <LocationManager
        open={locationsOpen}
        onClose={() => setLocationsOpen(false)}
        locations={locations}
        products={products}
        onSave={handleSaveLocation}
        onDelete={handleDeleteLocation}
        onReorder={handleReorderLocations}
      />

      <Settings
        open={settingsOpen}
        onClose={() => setSettingsOpen(false)}
        onOpenLocations={() => setLocationsOpen(true)}
        onDataChanged={loadAll}
        onShowToast={setToastMsg}
        lastBackupAt={lastBackupAt}
        onBackedUp={(ts) => { setLastBackupAt(ts); setBackupDismissed(true); }}
      />

      <PhotoViewer
        productId={photoViewerProductId}
        onClose={() => setPhotoViewerProductId(null)}
      />

      <ConfirmDialog
        open={!!confirmDeleteProduct}
        title="Delete product?"
        body={(() => {
          const b = confirmDeleteProduct?.brand || '';
          const n = confirmDeleteProduct?.name || '';
          const label = `${b} ${n}`.trim() || 'This product';
          return `"${label}" will be removed. Past usage logs are kept.`;
        })()}
        onCancel={() => setConfirmDeleteProduct(null)}
        onConfirm={() => handleDeleteProduct(confirmDeleteProduct)}
      />
      <ConfirmDialog
        open={!!confirmDeleteLog}
        title="Delete this entry?"
        body={
          confirmDeleteLog?.type === 'move'
            ? "This removes the move from history but won't undo the stock change. To reverse it, do another move in the opposite direction."
            : "This action can't be undone. Stock counts won't change."
        }
        onCancel={() => setConfirmDeleteLog(null)}
        onConfirm={() => handleDeleteLog(confirmDeleteLog)}
      />

      <Toast message={toastMsg} onDone={() => setToastMsg('')} />
    </div>
  );
}
LEDGER_EOF

echo "Committing and pushing..."
git add -A && git commit -m "Add wetting posture field, live capacity-ceiling warning, and legacy-record flag in insights" && git push

echo "Done. Netlify will redeploy from this push."
