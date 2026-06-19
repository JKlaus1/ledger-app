#!/usr/bin/env bash
# Ledger — core integrity + activity tracking (push 3)
# Run from the repo root:
#   cp ~/storage/downloads/push-core-activity.sh ~/ledger-app/ && cd ~/ledger-app && bash push-core-activity.sh
set -e

if [ ! -d src/components ] || [ ! -d src/lib ]; then
  echo "!! Run this from inside ~/ledger-app (src/components / src/lib not found here)."
  exit 1
fi
echo "Writing src/lib/session.js ..."
cat > src/lib/session.js << 'LEDGER_EOF'
// Wear-session metadata — the small vocabularies for context, change
// reason, and skin check. Kept in its own module (not helpers.js) so these
// shared constants live in one place and can grow without touching helpers.
//
// All three are optional on a log and backward-compatible: older logs that
// predate these fields simply have them undefined, which every consumer
// treats as "not set".

// Where/what you were doing while wearing it. Helps explain why some
// sessions leak or run short (exercise, travel) vs. hold fine (sleep).
export const CONTEXTS = [
  { value: 'home',     label: 'At home' },
  { value: 'work',     label: 'Work' },
  { value: 'out',      label: 'Out / errands' },
  { value: 'travel',   label: 'Travel' },
  { value: 'exercise', label: 'Exercise' },
  { value: 'sleep',    label: 'Sleeping' },
];

// Why the diaper came off. Sharpens performance data: a routine change is
// very different from one forced by a leak or saturation.
export const CHANGE_REASONS = [
  { value: 'routine',       label: 'Routine change' },
  { value: 'saturated',     label: 'Full / saturated' },
  { value: 'leak',          label: 'Leaked' },
  { value: 'uncomfortable', label: 'Uncomfortable' },
  { value: 'bedtime',       label: 'Bedtime / waking up' },
  { value: 'other',         label: 'Other' },
];

// A quick skin check at change time. Ordered so we can flag the worst.
export const SKIN_STATES = [
  { value: 'fine',      label: 'Fine',          order: 1 },
  { value: 'pink',      label: 'A little pink', order: 2 },
  { value: 'irritated', label: 'Irritated',     order: 3 },
];

// Product construction — how the diaper is backed, and how the tabs fasten.
// Optional on a product; older products without them read as "not set".
export const BACKINGS = [
  { value: 'plastic', label: 'Plastic-backed' },
  { value: 'cloth',   label: 'Cloth-backed' },
];

export const TAB_TYPES = [
  { value: 'taped',    label: 'Taped' },
  { value: 'velcro',   label: 'Velcro' },
  { value: 'tearaway', label: 'Tear-away (pull-up)' },
];

// How physically active you were over the wear — recorded at take-off.
// Ordered so Insights can later relate activity to how the core held up
// (the hunch being that active + wet breaks a core down faster than rest).
export const ACTIVITY_LEVELS = [
  { value: 'rest',     label: 'Rest / sitting',        order: 1 },
  { value: 'light',    label: 'Light / around home',   order: 2 },
  { value: 'moderate', label: 'Moderate / on my feet', order: 3 },
  { value: 'vigorous', label: 'Vigorous / very active', order: 4 },
];

// How the absorbent core held together by take-off. Ordered worst-ascending
// so a future view can flag the sessions where it fell apart.
export const CORE_CONDITIONS = [
  { value: 'held',     label: 'Held its shape',    order: 1 },
  { value: 'softened', label: 'Softened',          order: 2 },
  { value: 'clumped',  label: 'Clumped / shifted', order: 3 },
  { value: 'broke',    label: 'Broke apart',       order: 4 },
];

const labelOf = (arr, v) => arr.find((x) => x.value === v)?.label || null;

export const contextLabel = (v) => labelOf(CONTEXTS, v);
export const reasonLabel = (v) => labelOf(CHANGE_REASONS, v);
export const skinLabel = (v) => labelOf(SKIN_STATES, v);
export const backingLabel = (v) => labelOf(BACKINGS, v);
export const tabsLabel = (v) => labelOf(TAB_TYPES, v);
export const activityLabel = (v) => labelOf(ACTIVITY_LEVELS, v);
export const coreLabel = (v) => labelOf(CORE_CONDITIONS, v);

// Per-unit cost from a product's pack cost / pack size, or null if either
// is missing. Centralized so the inventory and insights agree.
export const unitCost = (product) => {
  if (!product) return null;
  const cost = Number(product.cost);
  const pack = Number(product.packSize);
  if (!Number.isFinite(cost) || !Number.isFinite(pack) || pack <= 0) return null;
  return cost / pack;
};

// Format a number as money in the user's locale, no fixed currency symbol
// (the app never asked which currency the pack cost is in).
export const fmtMoney = (n) =>
  n == null || !Number.isFinite(n)
    ? '—'
    : n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
LEDGER_EOF

echo "Writing src/lib/wetting.js ..."
cat > src/lib/wetting.js << 'LEDGER_EOF'
// Wetting events recorded against a wear session (a worn diaper).
//
// Each wear-session log (a "use" entry with a putOnAt time) may carry an
// optional `wettings` array, stored inline on the log object:
//
//   wettings: [{ id, at, amount, feel, note }]
//
// Because it rides along on the existing log records, it needs no new
// IndexedDB store and is automatically included in backup export/import
// and the GitHub-synced... (nothing — data stays on device). Older logs
// without the field are treated as having no wettings.
//
//   amount — how heavy the wetting was (light → very heavy)
//   feel   — how the diaper felt afterwards (a saturation scale)
//   core   — optional in-the-moment read on the padding itself (intact → breaking down)

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

export const wetnessMeta = (v) => WETNESS.find((w) => w.value === v) || null;
export const feelMeta = (v) => DIAPER_FEEL.find((f) => f.value === v) || null;
export const coreFeelMeta = (v) => CORE_FEEL.find((c) => c.value === v) || null;

export const wetnessLabel = (v) => wetnessMeta(v)?.label || '—';
export const feelLabel = (v) => feelMeta(v)?.label || '—';
export const coreFeelLabel = (v) => coreFeelMeta(v)?.label || '—';

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
LEDGER_EOF

echo "Writing src/components/TakeOffForm.jsx ..."
cat > src/components/TakeOffForm.jsx << 'LEDGER_EOF'
import React, { useState, useEffect } from 'react';
import { Check, ArrowRight } from 'lucide-react';
import { Modal } from './Common';
import {
  PERFORMANCE, toLocalInputValue, fromLocalInputValue,
  productDisplayName, formatDuration,
} from '../lib/helpers';
import { CHANGE_REASONS, SKIN_STATES, ACTIVITY_LEVELS, CORE_CONDITIONS } from '../lib/session';

// TakeOffForm — ends the active wear session. Records take-off time,
// how it performed, and optional notes. A "then" choice lets the user
// either go without or immediately put a fresh one on (change-out).
export default function TakeOffForm({
  open, onClose, onConfirm, entry, product, defaultThen,
}) {
  const [takenOffAt, setTakenOffAt] = useState(Date.now());
  const [performance, setPerformance] = useState('used');
  const [activity, setActivity] = useState('');
  const [core, setCore] = useState('');
  const [changeReason, setChangeReason] = useState('');
  const [skin, setSkin] = useState('');
  const [cream, setCream] = useState(false);
  const [notes, setNotes] = useState('');
  const [then, setThen] = useState('none'); // 'none' | 'replace'

  useEffect(() => {
    if (open) {
      setTakenOffAt(Date.now());
      setPerformance('used');
      setActivity('');
      setCore('');
      setChangeReason('');
      setSkin('');
      setCream(false);
      setNotes('');
      setThen(defaultThen === 'replace' ? 'replace' : 'none');
    }
  }, [open, defaultThen]);

  if (!open || !entry) return null;

  const putOnAt = entry.putOnAt;
  // Guard: take-off can't be before put-on
  const effectiveOff = Math.max(takenOffAt, putOnAt);
  const duration = effectiveOff - putOnAt;

  const submit = () => {
    const merged = entry.notes
      ? (notes.trim() ? `${entry.notes}\n${notes.trim()}` : entry.notes)
      : notes.trim();
    onConfirm(
      {
        ...entry,
        takenOffAt: effectiveOff,
        performance,
        activity: activity || null,
        core: core || null,
        changeReason: changeReason || null,
        skin: skin || null,
        cream: !!cream,
        notes: merged,
      },
      then === 'replace'
    );
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Take it off"
      footer={
        <>
          <button className="btn btn-ghost" onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" onClick={submit}>
            {then === 'replace' ? 'Take off & put on new' : 'Take off'}
          </button>
        </>
      }
    >
      <div style={{ display: 'grid', gap: 16 }}>
        <div className="card" style={{ padding: '12px 14px' }}>
          <div style={{ fontSize: 14 }}>
            {product ? productDisplayName(product) : 'This item'}
          </div>
          <div style={{ fontSize: 12, color: 'var(--ink-mute)', marginTop: 3 }}>
            Worn for {formatDuration(duration) || 'under a minute'}
          </div>
        </div>

        <div>
          <label className="label">When did you take it off?</label>
          <input
            className="input" type="datetime-local"
            value={toLocalInputValue(effectiveOff)}
            onChange={(e) => setTakenOffAt(fromLocalInputValue(e.target.value))}
          />
        </div>

        <div>
          <label className="label">How did it perform?</label>
          <div style={{ display: 'grid', gap: 8 }}>
            {PERFORMANCE.map((p) => (
              <button
                key={p.value} type="button"
                className={`check-row ${performance === p.value ? 'active' : ''}`}
                onClick={() => setPerformance(p.value)}
              >
                <span style={{ flex: 1 }}>{p.label}</span>
                {performance === p.value && <Check size={14} />}
              </button>
            ))}
          </div>
        </div>

        <div>
          <label className="label">How active were you? (optional)</label>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
            {ACTIVITY_LEVELS.map((a) => (
              <button
                key={a.value} type="button"
                className={`check-row ${activity === a.value ? 'active' : ''}`}
                onClick={() => setActivity(activity === a.value ? '' : a.value)}
              >
                <span style={{ flex: 1 }}>{a.label}</span>
                {activity === a.value && <Check size={14} />}
              </button>
            ))}
          </div>
        </div>

        <div>
          <label className="label">How did the padding hold up? (optional)</label>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
            {CORE_CONDITIONS.map((c) => (
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
          <label className="label">Why the change? (optional)</label>
          <select
            className="select"
            value={changeReason}
            onChange={(e) => setChangeReason(e.target.value)}
          >
            <option value="">Not set</option>
            {CHANGE_REASONS.map((r) => (
              <option key={r.value} value={r.value}>{r.label}</option>
            ))}
          </select>
        </div>

        <div>
          <label className="label">Skin check (optional)</label>
          <div className="seg" style={{ width: '100%' }}>
            {SKIN_STATES.map((s) => (
              <button
                key={s.value}
                type="button" style={{ flex: 1 }}
                className={`seg-btn ${skin === s.value ? 'active' : ''}`}
                onClick={() => setSkin(skin === s.value ? '' : s.value)}
              >
                {s.label}
              </button>
            ))}
          </div>
        </div>

        <div>
          <label className="label">Barrier cream applied?</label>
          <button
            type="button"
            className={`check-row ${cream ? 'active' : ''}`}
            onClick={() => setCream(!cream)}
          >
            <span style={{ flex: 1 }}>{cream ? 'Yes — applied' : 'No'}</span>
            {cream && <Check size={14} />}
          </button>
        </div>

        <div>
          <label className="label">Notes (optional)</label>
          <textarea
            className="textarea"
            placeholder="Time worn, comfort, leaks…"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
          />
        </div>

        <div>
          <label className="label">Then what?</label>
          <div className="seg" style={{ width: '100%' }}>
            <button
              type="button" style={{ flex: 1 }}
              className={`seg-btn ${then === 'none' ? 'active' : ''}`}
              onClick={() => setThen('none')}
            >
              Go without
            </button>
            <button
              type="button" style={{ flex: 1 }}
              className={`seg-btn ${then === 'replace' ? 'active' : ''}`}
              onClick={() => setThen('replace')}
            >
              Put on a new one <ArrowRight size={13} />
            </button>
          </div>
        </div>
      </div>
    </Modal>
  );
}
LEDGER_EOF

echo "Writing src/components/WettingForm.jsx ..."
cat > src/components/WettingForm.jsx << 'LEDGER_EOF'
import React, { useState, useEffect } from 'react';
import { Check, X, Droplets, Droplet, Pencil } from 'lucide-react';
import { Modal } from './Common';
import {
  uid, toLocalInputValue, fromLocalInputValue,
  productDisplayName, formatTime, formatDuration, wearDuration,
} from '../lib/helpers';
import {
  WETNESS, DIAPER_FEEL, CORE_FEEL, getWettings, wettingStats,
  wetnessLabel, feelLabel, coreFeelLabel,
} from '../lib/wetting';

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

// WettingForm — add / edit / remove wettings on a single wear session.
// Works for the diaper currently on, or any previously worn one. Persists
// immediately via onSave(logId, wettings) so nothing is lost on close.
export default function WettingForm({ open, onClose, entry, product, onSave }) {
  const [list, setList] = useState([]);
  const [editingId, setEditingId] = useState(null);
  const [at, setAt] = useState(Date.now());
  const [amount, setAmount] = useState('');
  const [feel, setFeel] = useState('');
  const [core, setCore] = useState('');
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
    if (editingId) {
      persist(list.map((w) =>
        w.id === editingId ? { ...w, at, amount, feel: feel || null, core: core || null, note: note.trim() } : w
      ));
    } else {
      persist([...list, { id: uid(), at, amount, feel: feel || null, core: core || null, note: note.trim() }]);
    }
    resetSubForm();
  };

  const editRow = (w) => {
    setEditingId(w.id);
    setAt(w.at || Date.now());
    setAmount(w.amount || '');
    setFeel(w.feel || '');
    setCore(w.core || '');
    setNote(w.note || '');
  };

  const removeRow = (id) => {
    persist(list.filter((w) => w.id !== id));
    if (editingId === id) resetSubForm();
  };

  const stats = wettingStats({ ...entry, wettings: list });
  const dur = wearDuration(entry);

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

echo "Files written. Committing and pushing ..."
git add -A && git commit -m "Track activity level + core condition at take-off; optional per-wetting core feel" && git push
echo "Done. Netlify will build from master; then tap Sync on the GitHub source in project knowledge."
