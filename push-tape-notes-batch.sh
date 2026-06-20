#!/usr/bin/env bash
# Ledger — batched push: tape tracking + note logs + sorted history filter
# Builds on pushes 1-3 (already deployed). Run from the repo root:
#   cp ~/storage/downloads/push-tape-notes-batch.sh ~/ledger-app/ && cd ~/ledger-app && bash push-tape-notes-batch.sh
set -e

if [ ! -d src/components ] || [ ! -d src/lib ]; then
  echo "!! Run this from inside ~/ledger-app (src/components / src/lib not found here)."
  exit 1
fi
if [ ! -f src/lib/variants.js ]; then
  echo "!! src/lib/variants.js missing — pushes 1-3 not applied. Push those first."
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

// Did the tapes/fasteners give trouble? Distinct from a product's `tabs`
// (which is the tab TYPE — taped/velcro/tearaway); this is behavior on a
// given wear. Shared by the take-off summary and per-wetting notes, ordered
// worst-ascending so it can later be cross-tabbed against tab type.
export const TAPE_STATES = [
  { value: 'held',     label: 'Held fine',                    order: 1 },
  { value: 'loosened', label: 'Loosened / needed a re-press', order: 2 },
  { value: 'popped',   label: 'A tab popped open',            order: 3 },
  { value: 'failed',   label: 'Tab failed (tore / lost stick)', order: 4 },
];

const labelOf = (arr, v) => arr.find((x) => x.value === v)?.label || null;

export const contextLabel = (v) => labelOf(CONTEXTS, v);
export const reasonLabel = (v) => labelOf(CHANGE_REASONS, v);
export const skinLabel = (v) => labelOf(SKIN_STATES, v);
export const backingLabel = (v) => labelOf(BACKINGS, v);
export const tabsLabel = (v) => labelOf(TAB_TYPES, v);
export const activityLabel = (v) => labelOf(ACTIVITY_LEVELS, v);
export const coreLabel = (v) => labelOf(CORE_CONDITIONS, v);
export const tapeLabel = (v) => labelOf(TAPE_STATES, v);

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

echo "Writing src/components/TakeOffForm.jsx ..."
cat > src/components/TakeOffForm.jsx << 'LEDGER_EOF'
import React, { useState, useEffect } from 'react';
import { Check, ArrowRight } from 'lucide-react';
import { Modal } from './Common';
import {
  PERFORMANCE, toLocalInputValue, fromLocalInputValue,
  productDisplayName, formatDuration,
} from '../lib/helpers';
import { CHANGE_REASONS, SKIN_STATES, ACTIVITY_LEVELS, CORE_CONDITIONS, TAPE_STATES } from '../lib/session';

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
  const [tapes, setTapes] = useState('');
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
      setTapes('');
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
        tapes: tapes || null,
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
          <label className="label">Any tape trouble? (optional)</label>
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
  const [tapes, setTapes] = useState('');
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
        w.id === editingId ? { ...w, at, amount, feel: feel || null, core: core || null, tapes: tapes || null, note: note.trim() } : w
      ));
    } else {
      persist([...list, { id: uid(), at, amount, feel: feel || null, core: core || null, tapes: tapes || null, note: note.trim() }]);
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
                      {w.tapes && (
                        <span style={{ color: 'var(--ink-mute)' }}> · tapes {tapeLabel(w.tapes).toLowerCase()}</span>
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

echo "Writing src/components/NoteForm.jsx ..."
cat > src/components/NoteForm.jsx << 'LEDGER_EOF'
import React, { useState, useEffect } from 'react';
import { StickyNote } from 'lucide-react';
import { Modal } from './Common';
import {
  uid, toLocalInputValue, fromLocalInputValue, productDisplayName,
} from '../lib/helpers';

// A note is its own kind of log (type: 'note'): a free-standing, timestamped
// entry. When opened from the diaper on now it carries that wear's product /
// location / session so it reads as "a note about this wear"; opened on its
// own it's a general context note with an editable time (so it can be backdated).
export default function NoteForm({
  open, onClose, onSave, locations, products, initial, context,
}) {
  const [text, setText] = useState('');
  const [at, setAt] = useState('');
  const [locationId, setLocationId] = useState('');

  useEffect(() => {
    if (!open) return;
    if (initial) {
      setText(initial.text || '');
      setAt(toLocalInputValue(initial.timestamp || Date.now()));
      setLocationId(initial.locationId || '');
    } else {
      setText('');
      setAt(toLocalInputValue(Date.now()));
      setLocationId(context?.locationId || '');
    }
  }, [open, initial, context]);

  const aboutProductId = initial ? initial.productId : context?.productId;
  const aboutProduct = aboutProductId ? (products || []).find((p) => p.id === aboutProductId) : null;
  const sessionId = initial ? initial.sessionId : context?.sessionId;

  const valid = text.trim().length > 0;

  const submit = () => {
    if (!valid) return;
    const ts = fromLocalInputValue(at) || Date.now();
    onSave({
      id: initial?.id || uid(),
      type: 'note',
      text: text.trim(),
      timestamp: ts,
      productId: aboutProductId || null,
      locationId: locationId || null,
      sessionId: sessionId || null,
      createdAt: initial?.createdAt || Date.now(),
      updatedAt: Date.now(),
    });
  };

  const sortedLocations = [...(locations || [])].sort(
    (a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)
  );

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={initial ? 'Edit note' : 'Add a note'}
      footer={
        <>
          <button className="btn btn-ghost" onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" disabled={!valid} onClick={submit}>
            {initial ? 'Save note' : 'Add note'}
          </button>
        </>
      }
    >
      <div style={{ display: 'grid', gap: 14 }}>
        {aboutProduct && (
          <div style={{
            display: 'flex', alignItems: 'center', gap: 8,
            fontSize: 13, color: 'var(--ink-soft)',
          }}>
            <StickyNote size={14} />
            <span>Note on: <strong>{productDisplayName(aboutProduct)}</strong></span>
          </div>
        )}

        <div>
          <label className="label">Note</label>
          <textarea
            className="textarea"
            placeholder="Anything worth remembering — context, what you noticed, how it went…"
            value={text}
            onChange={(e) => setText(e.target.value)}
            autoFocus
          />
        </div>

        <div>
          <label className="label">When</label>
          <input
            className="input"
            type="datetime-local"
            value={at}
            onChange={(e) => setAt(e.target.value)}
          />
        </div>

        {sortedLocations.length > 0 && (
          <div>
            <label className="label">Location (optional)</label>
            <select
              className="select"
              value={locationId}
              onChange={(e) => setLocationId(e.target.value)}
            >
              <option value="">None</option>
              {sortedLocations.map((loc) => (
                <option key={loc.id} value={loc.id}>{loc.name}</option>
              ))}
            </select>
          </div>
        )}
      </div>
    </Modal>
  );
}
LEDGER_EOF

echo "Writing src/App.jsx ..."
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
    await saveLog(entry);
    setLogs((prev) => [...prev, entry]);
    // Decrement stock at the source location
    const product = products.find((p) => p.id === entry.productId);
    if (product && entry.locationId) {
      const currentAt = stockAt(product, entry.locationId);
      const updated = {
        ...product,
        stock: { ...product.stock, [entry.locationId]: Math.max(0, currentAt - 1) },
      };
      await saveProduct(updated);
      setProducts((prev) => prev.map((p) => p.id === updated.id ? updated : p));
    }
    setWearFormOpen(false);
    setWearDefaultProduct(null);
    setToastMsg('Put on');
  };

  const handleTakeOff = async (updatedEntry, thenReplace) => {
    await saveLog(updatedEntry);
    setLogs((prev) => prev.map((l) => l.id === updatedEntry.id ? updatedEntry : l));
    setTakeOffEntry(null);
    setToastMsg('Taken off');
    if (thenReplace) {
      // Default the new one to the same product for a quick change-out
      setWearDefaultProduct(updatedEntry.productId);
      setWearFormOpen(true);
    }
  };

  // Undo a put-on done by mistake: remove the open session and refund stock
  const handleCancelWear = async (entry) => {
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
        onClose={() => { setWearFormOpen(false); setWearDefaultProduct(null); }}
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

echo "Writing src/components/Dashboard.jsx ..."
cat > src/components/Dashboard.jsx << 'LEDGER_EOF'
import React, { useMemo, useState, useEffect } from 'react';
import { Plus, ChevronRight, Sun, Moon, ArrowRight, Repeat, X, Clock, Droplets, StickyNote } from 'lucide-react';
import { ProductThumb, Eyebrow, SectionHeader, Pill } from './Common';
import { LocationIcon } from './LocationManager';
import { WettingSummary } from './WettingForm';
import {
  ABSORBENCY, formatDate, formatTime, isToday,
  productDisplayName, totalStock, formatDuration, wearDuration,
} from '../lib/helpers';
import { groupProducts, groupKeyOf } from '../lib/variants';

export default function Dashboard({
  products, logs, locations, thumbs, activeWear,
  onAddProduct, onAddLocation,
  onPutOn, onChangeOut, onTakeOff, onUndoWear, onLogWetting,
  onRestock, onMove, onAddNote, onPhotoTap,
}) {
  const today = new Date();

  // Tick every minute so the "worn for…" duration stays fresh
  const [, setTick] = useState(0);
  useEffect(() => {
    if (!activeWear) return;
    const t = setInterval(() => setTick((n) => n + 1), 60000);
    return () => clearInterval(t);
  }, [activeWear]);

  // "Real" usage logs (not moves)
  const usageLogs = logs.filter((l) => l.type !== 'move');
  const todayLogs = usageLogs.filter((l) => isToday(l.timestamp));
  const grandTotal = products.reduce((s, p) => s + totalStock(p), 0);

  // Low stock = total across all locations <= 5 (matches spirit of original)
  const lowStock = products
    .filter((p) => totalStock(p) > 0 && totalStock(p) <= 5)
    .sort((a, b) => totalStock(a) - totalStock(b));
  const outOfStock = products.filter((p) => totalStock(p) <= 0);

  // Most-used products (grouped by variant) in the last 14 days
  const quickGroups = useMemo(() => {
    const cutoff = Date.now() - 14 * 24 * 3600 * 1000;
    const groups = groupProducts(products);
    const byKey = new Map(groups.map((g) => [g.key, g]));
    const counts = new Map();
    usageLogs.filter((l) => l.timestamp >= cutoff).forEach((l) => {
      const p = products.find((x) => x.id === l.productId);
      if (!p) return;
      const k = groupKeyOf(p);
      counts.set(k, (counts.get(k) || 0) + 1);
    });
    return [...counts.entries()]
      .sort((a, b) => b[1] - a[1])
      .map(([k]) => byKey.get(k))
      .filter((g) => g && g.total > 0)
      .slice(0, 3);
  }, [usageLogs, products]);

  const recentLogs = [...logs]
    .sort((a, b) => b.timestamp - a.timestamp)
    .slice(0, 5);

  const quickVisible = !activeWear && quickGroups.length > 0;

  // Empty state - no locations yet
  if (locations.length === 0) {
    return (
      <div className="empty-state" style={{ paddingTop: 60 }}>
        <div className="display-italic" style={{ fontSize: 32, color: 'var(--ink)' }}>
          Welcome
        </div>
        <p style={{
          marginTop: 12, fontSize: 15, color: 'var(--ink-soft)',
          maxWidth: 380, marginInline: 'auto',
        }}>
          Start by adding the locations where you keep stock — like a closet, dresser, work bag, or your truck.
        </p>
        <button className="btn btn-primary" onClick={onAddLocation} style={{ marginTop: 24 }}>
          <Plus size={16} /> Add your first location
        </button>
      </div>
    );
  }

  // Empty state - no products yet
  if (products.length === 0) {
    return (
      <div className="empty-state" style={{ paddingTop: 60 }}>
        <div className="display-italic" style={{ fontSize: 32, color: 'var(--ink)' }}>
          Ready when you are
        </div>
        <p style={{
          marginTop: 12, fontSize: 15, color: 'var(--ink-soft)',
          maxWidth: 380, marginInline: 'auto',
        }}>
          You have {locations.length} location{locations.length !== 1 ? 's' : ''} set up.
          Now add the products you keep at them.
        </p>
        <button className="btn btn-primary" onClick={onAddProduct} style={{ marginTop: 24 }}>
          <Plus size={16} /> Add your first product
        </button>
      </div>
    );
  }

  return (
    <div style={{ display: 'grid', gap: 36 }}>
      {/* Today summary */}
      <section>
        <Eyebrow>{today.toLocaleDateString(undefined, { weekday: 'long' })} · {formatDate(today)}</Eyebrow>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 20, marginTop: 12 }}>
          <div className="stat-divider" style={{ paddingTop: 10 }}>
            <div className="num" style={{ fontSize: 38, lineHeight: 1 }}>{todayLogs.length}</div>
            <div className="eyebrow" style={{ marginTop: 6 }}>Used today</div>
          </div>
          <div className="stat-divider" style={{ paddingTop: 10 }}>
            <div className="num" style={{ fontSize: 38, lineHeight: 1 }}>{grandTotal}</div>
            <div className="eyebrow" style={{ marginTop: 6 }}>Total stock</div>
          </div>
          <div className="stat-divider" style={{ paddingTop: 10 }}>
            <div className="num" style={{ fontSize: 38, lineHeight: 1 }}>{products.length}</div>
            <div className="eyebrow" style={{ marginTop: 6 }}>Products</div>
          </div>
        </div>
      </section>

      <button
        className="btn btn-ghost"
        onClick={() => onAddNote()}
        style={{ width: '100%' }}
      >
        <StickyNote size={15} /> Add a note
      </button>

      {/* Currently wearing */}
      {activeWear && (() => {
        const wp = products.find((p) => p.id === activeWear.productId);
        const loc = locations.find((l) => l.id === activeWear.locationId);
        const dur = formatDuration(Date.now() - activeWear.putOnAt) || 'a moment';
        return (
          <section>
            <Eyebrow>Right now</Eyebrow>
            <div className="card" style={{
              padding: 16,
              border: '1px solid var(--primary)',
              background: 'var(--primary-soft)',
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                {wp && (
                  <ProductThumb
                    product={wp} thumbs={thumbs} size={44}
                    onClick={() => thumbs[wp.id] && onPhotoTap(wp.id)}
                  />
                )}
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{
                    fontSize: 10, textTransform: 'uppercase', letterSpacing: '0.1em',
                    color: 'var(--primary)', fontWeight: 600,
                  }}>
                    Currently wearing
                  </div>
                  <div className="display" style={{ fontSize: 18, marginTop: 3 }}>
                    {wp ? productDisplayName(wp) : 'Unknown product'}
                  </div>
                  <div style={{
                    fontSize: 12.5, color: 'var(--ink-soft)', marginTop: 5,
                    display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap',
                  }}>
                    <Clock size={12} />
                    <span>On for {dur}</span>
                    <span>· since {formatTime(activeWear.putOnAt)}</span>
                    {activeWear.period === 'night'
                      ? <><span>·</span><Moon size={12} /></>
                      : <><span>·</span><Sun size={12} /></>}
                    {loc && <><span>·</span><LocationIcon name={loc.icon} size={12} /><span>{loc.name}</span></>}
                  </div>
                  <WettingSummary log={activeWear} compact style={{ marginTop: 6, fontSize: 12.5 }} />
                </div>
              </div>

              {/* Log a wetting on the diaper that's on right now */}
              <button
                className="btn btn-ghost"
                onClick={() => onLogWetting(activeWear)}
                style={{ width: '100%', marginTop: 14 }}
              >
                <Droplets size={15} /> Log a wetting
              </button>

              <button
                className="btn btn-ghost"
                onClick={() => onAddNote({
                  productId: activeWear.productId,
                  locationId: activeWear.locationId,
                  sessionId: activeWear.id,
                })}
                style={{ width: '100%', marginTop: 8 }}
              >
                <StickyNote size={15} /> Note on this diaper
              </button>

              <div style={{ display: 'flex', gap: 8, marginTop: 8, flexWrap: 'wrap' }}>
                <button
                  className="btn btn-primary"
                  onClick={() => onChangeOut(activeWear)}
                  style={{ flex: '1 1 auto' }}
                >
                  <Repeat size={15} /> Change out
                </button>
                <button
                  className="btn btn-ghost"
                  onClick={() => onTakeOff(activeWear)}
                  style={{ flex: '1 1 auto' }}
                >
                  Take off
                </button>
              </div>
              <button
                onClick={() => onUndoWear(activeWear)}
                style={{
                  marginTop: 10, background: 'none', border: 'none',
                  color: 'var(--ink-mute)', fontSize: 12, cursor: 'pointer',
                  display: 'inline-flex', alignItems: 'center', gap: 4,
                  padding: 0, font: 'inherit',
                }}
              >
                <X size={12} /> Put back — I didn't wear this
              </button>
            </div>
          </section>
        );
      })()}

      {/* Stock by location summary */}
      <section>
        <SectionHeader number="01" title="Locations at a glance" />
        <div className="card" style={{ padding: 4 }}>
          {[...locations]
            .sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0))
            .map((loc) => {
              const total = products.reduce(
                (s, p) => s + (p.stock?.[loc.id] || 0),
                0
              );
              return (
                <div
                  key={loc.id}
                  className="row-divider"
                  style={{
                    padding: '12px 14px',
                    display: 'flex', alignItems: 'center', gap: 10,
                  }}
                >
                  <div style={{
                    width: 32, height: 32, borderRadius: 8,
                    background: 'var(--surface-2)',
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    color: 'var(--ink-soft)',
                  }}>
                    <LocationIcon name={loc.icon} size={16} />
                  </div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontSize: 14 }}>{loc.name}</div>
                  </div>
                  <div className="num" style={{ fontSize: 22 }}>{total}</div>
                </div>
              );
            })}
        </div>
      </section>

      {/* Quick log */}
      {!activeWear && quickGroups.length > 0 && (
        <section>
          <SectionHeader number="02" title="Quick start" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)', marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            Tap a product to put one on. You'll pick the variant (if any) and location next.
          </p>
          <div style={{ display: 'grid', gap: 8 }}>
            {quickGroups.map((g) => {
              const rep = g.rep;
              const absorb = ABSORBENCY.find((a) => a.value === rep.absorbency)?.label;
              return (
                <button
                  key={g.key}
                  onClick={() => onPutOn(rep.id)}
                  className="card row-hover"
                  style={{
                    textAlign: 'left', padding: '14px 16px',
                    display: 'flex', alignItems: 'center', gap: 12,
                    border: '1px solid var(--line)', cursor: 'pointer',
                    font: 'inherit', color: 'inherit', width: '100%',
                  }}
                >
                  <ProductThumb product={rep} thumbs={thumbs} size={32} />
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div className="display" style={{ fontSize: 15 }}>{g.label}</div>
                    <div style={{ fontSize: 12, color: 'var(--ink-mute)' }}>
                      {rep.size} · {absorb}
                      {g.isMulti ? ` · ${g.products.length} variants` : ''} · {g.total} total
                    </div>
                  </div>
                  <span style={{
                    fontSize: 13, color: 'var(--ink-soft)',
                    display: 'inline-flex', alignItems: 'center', gap: 4,
                  }}>
                    {g.isMulti ? 'Choose' : 'Put on'} <ChevronRight size={14} />
                  </span>
                </button>
              );
            })}
          </div>
        </section>
      )}

      {/* Low stock */}
      {(lowStock.length > 0 || outOfStock.length > 0) && (
        <section>
          <SectionHeader number={quickVisible ? '03' : '02'} title="Running low" />
          <div className="card" style={{ padding: 4 }}>
            {[...outOfStock, ...lowStock].map((p) => (
              <div
                key={p.id}
                className="row-divider"
                style={{
                  padding: '12px 14px',
                  display: 'flex', alignItems: 'center', gap: 10,
                }}
              >
                <ProductThumb
                  product={p} thumbs={thumbs} size={28}
                  onClick={() => thumbs[p.id] && onPhotoTap(p.id)}
                />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 14 }}>{productDisplayName(p)}</div>
                  <div style={{ fontSize: 12, color: 'var(--ink-mute)' }}>
                    {totalStock(p) === 0 ? 'Out of stock' : `${totalStock(p)} left across all locations`}
                  </div>
                </div>
                <button
                  className="btn btn-ghost"
                  onClick={() => onRestock(p)}
                  style={{ padding: '6px 12px', fontSize: 13 }}
                >
                  Restock
                </button>
              </div>
            ))}
          </div>
        </section>
      )}

      {/* Recent activity */}
      {recentLogs.length > 0 && (
        <section>
          <SectionHeader
            number={
              quickVisible && (lowStock.length || outOfStock.length) ? '04' :
              (quickVisible || lowStock.length || outOfStock.length) ? '03' : '02'
            }
            title="Recent activity"
          />
          <div className="card" style={{ padding: 4 }}>
            {recentLogs.map((l) => {
              const p = products.find((x) => x.id === l.productId);
              const isMove = l.type === 'move';
              const fromLoc = isMove ? locations.find((loc) => loc.id === l.fromLocationId) : null;
              const toLoc = isMove ? locations.find((loc) => loc.id === l.toLocationId) : null;
              const useLoc = !isMove ? locations.find((loc) => loc.id === l.locationId) : null;
              return (
                <div
                  key={l.id}
                  className="row-divider"
                  style={{
                    padding: '12px 14px',
                    display: 'flex', alignItems: 'center', gap: 12,
                  }}
                >
                  {p && (
                    <ProductThumb
                      product={p} thumbs={thumbs} size={28}
                      onClick={() => thumbs[p.id] && onPhotoTap(p.id)}
                    />
                  )}
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontSize: 14 }}>
                      {p ? productDisplayName(p) : <span style={{ color: 'var(--ink-mute)' }}>Removed product</span>}
                    </div>
                    <div style={{
                      fontSize: 12, color: 'var(--ink-mute)',
                      display: 'flex', alignItems: 'center', gap: 6, marginTop: 2,
                      flexWrap: 'wrap',
                    }}>
                      {isMove ? (
                        <>
                          <span>Moved {l.quantity} ·</span>
                          {fromLoc && <LocationIcon name={fromLoc.icon} size={11} />}
                          <span>{fromLoc?.name || 'Unknown'}</span>
                          <ArrowRight size={11} />
                          {toLoc && <LocationIcon name={toLoc.icon} size={11} />}
                          <span>{toLoc?.name || 'Unknown'}</span>
                        </>
                      ) : (
                        <>
                          {l.period === 'night' ? <Moon size={11} /> : <Sun size={11} />}
                          <span>
                            {isToday(l.timestamp) ? `Today, ${formatTime(l.timestamp)}` : `${formatDate(l.timestamp)}, ${formatTime(l.timestamp)}`}
                          </span>
                          {useLoc && <span>· {useLoc.name}</span>}
                          {l.putOnAt && l.takenOffAt == null && (
                            <span style={{ color: 'var(--primary)' }}>· on now</span>
                          )}
                          {wearDuration(l) != null && (
                            <span>· worn {formatDuration(wearDuration(l))}</span>
                          )}
                          <WettingSummary log={l} compact style={{ fontSize: 12 }} />
                        </>
                      )}
                    </div>
                  </div>
                  {!isMove && l.performance === 'leak' && <Pill variant="danger">Leaked</Pill>}
                  {!isMove && l.performance === 'dry' && <Pill variant="primary">Dry</Pill>}
                </div>
              );
            })}
          </div>
        </section>
      )}
    </div>
  );
}
LEDGER_EOF

echo "Writing src/components/History.jsx ..."
cat > src/components/History.jsx << 'LEDGER_EOF'
import React, { useState, useMemo } from 'react';
import { Pencil, Trash2, Sun, Moon, ClipboardList, ArrowRight, Droplets, StickyNote } from 'lucide-react';
import { ProductThumb } from './Common';
import { LocationIcon } from './LocationManager';
import { WettingSummary } from './WettingForm';
import { contextLabel, reasonLabel } from '../lib/session';
import {
  formatDate, formatTime, dayKey, productDisplayName,
  formatDuration, wearDuration,
} from '../lib/helpers';

export default function History({
  logs, products, locations, thumbs,
  onEdit, onDelete, onManageWettings, onPhotoTap,
}) {
  const [periodFilter, setPeriodFilter] = useState('all');
  const [productFilter, setProductFilter] = useState('all');
  const [locationFilter, setLocationFilter] = useState('all');
  const [typeFilter, setTypeFilter] = useState('all'); // all | use | move

  const sortedLocations = [...locations].sort(
    (a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)
  );

  const sortedProducts = [...products].sort(
    (a, b) => productDisplayName(a).localeCompare(productDisplayName(b))
  );

  const filtered = useMemo(() => {
    return logs
      .filter((l) => {
        if (typeFilter === 'use') return l.type !== 'move' && l.type !== 'note';
        if (typeFilter === 'move') return l.type === 'move';
        if (typeFilter === 'note') return l.type === 'note';
        return true;
      })
      .filter((l) => {
        if (l.type === 'move' || l.type === 'note') return periodFilter === 'all';
        return periodFilter === 'all' || l.period === periodFilter;
      })
      .filter((l) => productFilter === 'all' || l.productId === productFilter)
      .filter((l) => {
        if (locationFilter === 'all') return true;
        if (l.type === 'move') {
          return l.fromLocationId === locationFilter || l.toLocationId === locationFilter;
        }
        return l.locationId === locationFilter;
      })
      .sort((a, b) => b.timestamp - a.timestamp);
  }, [logs, periodFilter, productFilter, locationFilter, typeFilter]);

  // Group by day
  const grouped = useMemo(() => {
    const m = new Map();
    filtered.forEach((l) => {
      const k = dayKey(l.timestamp);
      if (!m.has(k)) m.set(k, []);
      m.get(k).push(l);
    });
    return [...m.entries()];
  }, [filtered]);

  if (logs.length === 0) {
    return (
      <div className="empty-state">
        <ClipboardList size={28} style={{ color: 'var(--ink-mute)' }} />
        <div className="display" style={{ fontSize: 22, marginTop: 12 }}>No history yet</div>
        <p style={{ marginTop: 8, color: 'var(--ink-soft)' }}>
          Logged uses, moves, and notes will appear here.
        </p>
      </div>
    );
  }

  return (
    <div>
      <div style={{ marginBottom: 16 }}>
        <span className="display" style={{ fontSize: 24 }}>History</span>
      </div>

      {/* Filters */}
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, marginBottom: 12 }}>
        <div className="seg">
          <button
            className={`seg-btn ${typeFilter === 'all' ? 'active' : ''}`}
            onClick={() => setTypeFilter('all')}
          >
            All
          </button>
          <button
            className={`seg-btn ${typeFilter === 'use' ? 'active' : ''}`}
            onClick={() => setTypeFilter('use')}
          >
            Uses
          </button>
          <button
            className={`seg-btn ${typeFilter === 'move' ? 'active' : ''}`}
            onClick={() => setTypeFilter('move')}
          >
            Moves
          </button>
          <button
            className={`seg-btn ${typeFilter === 'note' ? 'active' : ''}`}
            onClick={() => setTypeFilter('note')}
          >
            Notes
          </button>
        </div>
        {typeFilter !== 'move' && typeFilter !== 'note' && (
          <div className="seg">
            <button
              className={`seg-btn ${periodFilter === 'all' ? 'active' : ''}`}
              onClick={() => setPeriodFilter('all')}
            >
              Day & Night
            </button>
            <button
              className={`seg-btn ${periodFilter === 'day' ? 'active' : ''}`}
              onClick={() => setPeriodFilter('day')}
            >
              <Sun size={13} /> Day
            </button>
            <button
              className={`seg-btn ${periodFilter === 'night' ? 'active' : ''}`}
              onClick={() => setPeriodFilter('night')}
            >
              <Moon size={13} /> Night
            </button>
          </div>
        )}
      </div>

      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, marginBottom: 20 }}>
        <select
          className="select"
          style={{ width: 'auto', flex: '1 1 180px' }}
          value={productFilter}
          onChange={(e) => setProductFilter(e.target.value)}
        >
          <option value="all">All products</option>
          {sortedProducts.map((p) => (
            <option key={p.id} value={p.id}>{productDisplayName(p)}</option>
          ))}
        </select>
        {locations.length > 0 && (
          <select
            className="select"
            style={{ width: 'auto', flex: '1 1 160px' }}
            value={locationFilter}
            onChange={(e) => setLocationFilter(e.target.value)}
          >
            <option value="all">All locations</option>
            {sortedLocations.map((loc) => (
              <option key={loc.id} value={loc.id}>{loc.name}</option>
            ))}
          </select>
        )}
      </div>

      {filtered.length === 0 ? (
        <div style={{ padding: 32, textAlign: 'center', color: 'var(--ink-mute)' }}>
          No entries match these filters.
        </div>
      ) : (
        <div style={{ display: 'grid', gap: 24 }}>
          {grouped.map(([day, entries]) => {
            const d = new Date(day + 'T00:00:00');
            const isT = dayKey(Date.now()) === day;
            return (
              <div key={day}>
                <div style={{
                  display: 'flex', alignItems: 'baseline', gap: 8, marginBottom: 10,
                }}>
                  <span className="display" style={{ fontSize: 16 }}>
                    {isT ? 'Today' : d.toLocaleDateString(undefined, { weekday: 'long' })}
                  </span>
                  <span className="eyebrow">
                    {d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })}
                  </span>
                  <span style={{ flex: 1, height: 1, background: 'var(--line)', marginLeft: 8 }} />
                  <span className="num" style={{ fontSize: 13, color: 'var(--ink-mute)' }}>
                    {entries.length}
                  </span>
                </div>

                <div className="card" style={{ padding: 4 }}>
                  {entries.map((l) => {
                    if (l.type === 'note') {
                      const np = l.productId ? products.find((x) => x.id === l.productId) : null;
                      const nloc = l.locationId ? locations.find((x) => x.id === l.locationId) : null;
                      return (
                        <div
                          key={l.id}
                          className="row-divider"
                          style={{
                            padding: '12px 14px',
                            display: 'flex', alignItems: 'flex-start', gap: 12,
                          }}
                        >
                          <div style={{
                            width: 56, fontSize: 13, color: 'var(--ink-soft)',
                            paddingTop: 1, fontVariantNumeric: 'tabular-nums',
                          }}>
                            {formatTime(l.timestamp)}
                          </div>
                          <div style={{ marginTop: 2, color: 'var(--accent)', flexShrink: 0 }}>
                            <StickyNote size={16} />
                          </div>
                          <div style={{ flex: 1, minWidth: 0 }}>
                            <div style={{ fontSize: 14, whiteSpace: 'pre-wrap' }}>{l.text}</div>
                            <div style={{
                              fontSize: 12, color: 'var(--ink-mute)',
                              marginTop: 4, display: 'flex', alignItems: 'center', gap: 6,
                              flexWrap: 'wrap',
                            }}>
                              <span style={{ color: 'var(--accent)' }}>Note</span>
                              {np && <><span>·</span><span>{productDisplayName(np)}</span></>}
                              {nloc && <><span>·</span><LocationIcon name={nloc.icon} size={11} /><span>{nloc.name}</span></>}
                            </div>
                          </div>
                          <div style={{ display: 'flex', gap: 2, flexShrink: 0 }}>
                            <button className="btn-icon" onClick={() => onEdit(l)} aria-label="Edit note">
                              <Pencil size={14} />
                            </button>
                            <button className="btn-icon" onClick={() => onDelete(l)} aria-label="Delete note">
                              <Trash2 size={14} />
                            </button>
                          </div>
                        </div>
                      );
                    }

                    const p = products.find((x) => x.id === l.productId);
                    const isMove = l.type === 'move';
                    const fromLoc = isMove ? locations.find((loc) => loc.id === l.fromLocationId) : null;
                    const toLoc = isMove ? locations.find((loc) => loc.id === l.toLocationId) : null;
                    const useLoc = !isMove ? locations.find((loc) => loc.id === l.locationId) : null;
                    // Wettings attach to wear sessions (a use with a put-on time),
                    // whether that diaper is on now or was worn previously.
                    const isWearSession = !isMove && !!l.putOnAt;

                    return (
                      <div
                        key={l.id}
                        className="row-divider"
                        style={{
                          padding: '12px 14px',
                          display: 'flex', alignItems: 'flex-start', gap: 12,
                        }}
                      >
                        <div style={{
                          width: 56, fontSize: 13, color: 'var(--ink-soft)',
                          paddingTop: 1, fontVariantNumeric: 'tabular-nums',
                        }}>
                          {formatTime(l.timestamp)}
                        </div>
                        {p && (
                          <ProductThumb
                            product={p} thumbs={thumbs} size={24}
                            style={{ marginTop: 1 }}
                            onClick={() => thumbs[p.id] && onPhotoTap(p.id)}
                          />
                        )}
                        <div style={{ flex: 1, minWidth: 0 }}>
                          <div style={{ fontSize: 14 }}>
                            {p ? productDisplayName(p) : <span style={{ color: 'var(--ink-mute)' }}>Removed product</span>}
                          </div>
                          <div style={{
                            fontSize: 12, color: 'var(--ink-mute)',
                            marginTop: 2, display: 'flex', alignItems: 'center', gap: 6,
                            flexWrap: 'wrap',
                          }}>
                            {isMove ? (
                              <>
                                <span style={{ color: 'var(--accent)' }}>
                                  Moved {l.quantity}
                                </span>
                                <span>·</span>
                                {fromLoc && <LocationIcon name={fromLoc.icon} size={11} />}
                                <span>{fromLoc?.name || 'Unknown'}</span>
                                <ArrowRight size={11} />
                                {toLoc && <LocationIcon name={toLoc.icon} size={11} />}
                                <span>{toLoc?.name || 'Unknown'}</span>
                              </>
                            ) : (
                              <>
                                {l.period === 'night' ? <><Moon size={11} /> Overnight</> : <><Sun size={11} /> Daytime</>}
                                {useLoc && (
                                  <>
                                    <span>·</span>
                                    <LocationIcon name={useLoc.icon} size={11} />
                                    <span>{useLoc.name}</span>
                                  </>
                                )}
                                {l.putOnAt && l.takenOffAt == null && (
                                  <span style={{ color: 'var(--primary)' }}>· on now</span>
                                )}
                                {wearDuration(l) != null && (
                                  <span>· worn {formatDuration(wearDuration(l))}</span>
                                )}
                                {l.performance === 'leak' && <span style={{ color: 'var(--danger)' }}>· Leaked</span>}
                                {l.performance === 'dry' && <span style={{ color: 'var(--primary)' }}>· Stayed dry</span>}
                                {l.booster && <span style={{ color: 'var(--accent)' }}>· +booster</span>}
                                {l.context && <span>· {contextLabel(l.context) || l.context}</span>}
                                {l.changeReason && !['routine', 'leak'].includes(l.changeReason) && (
                                  <span>· {reasonLabel(l.changeReason) || l.changeReason}</span>
                                )}
                              </>
                            )}
                          </div>
                          {!isMove && (
                            <WettingSummary log={l} compact style={{ fontSize: 12, marginTop: 5 }} />
                          )}
                          {l.notes && (
                            <div style={{
                              fontSize: 12, color: 'var(--ink-soft)',
                              marginTop: 6, fontStyle: 'italic',
                            }}>
                              {l.notes}
                            </div>
                          )}
                        </div>
                        <div style={{ display: 'flex', gap: 2, flexShrink: 0 }}>
                          {isWearSession && onManageWettings && (
                            <button
                              className="btn-icon"
                              onClick={() => onManageWettings(l)}
                              aria-label="Log or edit wettings"
                            >
                              <Droplets size={14} />
                            </button>
                          )}
                          {!isMove && (l.putOnAt && l.takenOffAt == null) && (
                            <button
                              className="btn-icon"
                              onClick={() => onEdit(l)}
                              aria-label="Edit"
                            >
                              <Pencil size={14} />
                            </button>
                          )}
                          <button
                            className="btn-icon"
                            onClick={() => onDelete(l)}
                            aria-label="Delete"
                          >
                            <Trash2 size={14} />
                          </button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
LEDGER_EOF

echo "Files written. Committing and pushing ..."
git add -A && git commit -m "Add tape tracking, note logs, and sorted history product filter" && git push
echo "Done. Netlify will auto-build from master; then tap Sync on the GitHub source in project knowledge."
