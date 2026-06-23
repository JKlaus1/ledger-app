#!/usr/bin/env bash
# push-toilet-intake-where-leakdetail.sh
# Batches four features into one Netlify build:
#   1. Notes: "where I am" (context + free-text place), separate from storage spot
#   2. Diaper log: toilet uses + BM-in-diaper + voluntary/accident control;
#      toilet uses are excluded from capacity math
#   3. Fluid intake log (new "drink" type) + Insights intake section
#   4. Take-off leak detail (escape point + severity) + cleanup/skin routine
# Whole-file writes via quoted heredocs. Safe to re-run.
set -e

if [ ! -f package.json ] || ! grep -q '"name": "ledger"' package.json || [ ! -d src/components ]; then
  echo "Error: run this from the ledger-app repo root (where package.json lives)." >&2
  exit 1
fi

echo "Writing files..."

mkdir -p "$(dirname src/lib/session.js)"
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

// ---- Take-off leak & cleanup detail -------------------------------------
// Recorded at take-off. Leak fields only matter when performance is 'leak';
// cleanup fields apply to any change. All optional and backward compatible.

// Where the leak escaped from. Notes repeatedly cite the leg holes and back.
export const LEAK_ESCAPE = [
  { value: 'legs',     label: 'Leg holes' },
  { value: 'back',     label: 'Out the back' },
  { value: 'front',    label: 'Front / waistband' },
  { value: 'multiple', label: 'More than one spot' },
];

// How bad the leak was, worst-ascending.
export const LEAK_SEVERITY = [
  { value: 'spot',    label: 'A spot or two',        order: 1 },
  { value: 'clothes', label: 'Wet through clothes',  order: 2 },
  { value: 'soaked',  label: 'Soaked clothes',       order: 3 },
  { value: 'surface', label: 'Reached a surface',    order: 4 },
];

// What was done to clean up / protect skin at the change. Multi-select.
export const CLEANUP_METHODS = [
  { value: 'wipes',  label: 'Wipes' },
  { value: 'rinse',  label: 'Rinse' },
  { value: 'shower', label: 'Shower' },
  { value: 'powder', label: 'Powder' },
  { value: 'airdry', label: 'Air-dried' },
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
export const leakEscapeLabel = (v) => labelOf(LEAK_ESCAPE, v);
export const leakSeverityLabel = (v) => labelOf(LEAK_SEVERITY, v);
export const cleanupLabel = (v) => labelOf(CLEANUP_METHODS, v);

// A put-on within this many ms after a take-off is treated as a direct
// change-out (not a fresh wear with a gap). Used both by explicit "change into"
// flows and the auto-link fallback for separate take-off + put-on actions.
export const CHANGE_OUT_WINDOW_MS = 10 * 60 * 1000;

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

mkdir -p "$(dirname src/lib/wetting.js)"
cat > src/lib/wetting.js << 'LEDGER_EOF'
// Events recorded against a wear session (a worn diaper).
//
// Each wear-session log (a "use" entry with a putOnAt time) may carry an
// optional `wettings` array, stored inline on the log object. Despite the
// name, an entry can now be one of several kinds:
//
//   { id, at, kind, amount, feel, core, tapes, posture, control, toiletWhat, note }
//
//   kind — 'wet' (default, in-diaper wetting) · 'bm' (mess in the diaper) ·
//          'toilet' (got to the toilet; the diaper came off and back on).
//          Older entries have no kind and are treated as 'wet'.
//   control — for wet/bm: 'voluntary' · 'couldnt_hold' · 'accident'.
//   toiletWhat — for toilet: 'pee' · 'bm' · 'both'.
//
// Because it rides along on the existing log records, it needs no new
// IndexedDB store and is automatically included in backup export/import.
// Toilet uses are deliberately EXCLUDED from a diaper's load/capacity, since
// nothing went into the diaper — counting them would inflate its ceiling.

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

// Optional in-the-moment read on the core itself when you notice a wetting.
export const CORE_FEEL = [
  { value: 'firm',      label: 'Still firm',          order: 1 },
  { value: 'softening', label: 'Softening',           order: 2 },
  { value: 'clumping',  label: 'Clumping',            order: 3 },
  { value: 'shifting',  label: 'Shifting / bunching', order: 4 },
];

// Body position at the moment of the event. Optional, backward compatible.
export const POSTURES = [
  { value: 'lying',    label: 'Lying down',       order: 1 },
  { value: 'sitting',  label: 'Sitting',          order: 2 },
  { value: 'standing', label: 'Standing',         order: 3 },
  { value: 'active',   label: 'Walking / active', order: 4 },
];

// What kind of event this entry is.
export const EVENT_KINDS = [
  { value: 'wet',    label: 'Wetting' },
  { value: 'bm',     label: 'BM (in diaper)' },
  { value: 'toilet', label: 'Toilet use' },
];

// How voluntary a wetting/BM was — the "did I mean to" axis. Optional.
export const CONTROL_LEVELS = [
  { value: 'voluntary',    label: 'On purpose',       order: 1 },
  { value: 'couldnt_hold', label: "Couldn't hold it", order: 2 },
  { value: 'accident',     label: 'True accident',    order: 3 },
];

// For a toilet use: what was done at the toilet.
export const TOILET_WHAT = [
  { value: 'pee',  label: 'Pee' },
  { value: 'bm',   label: 'BM' },
  { value: 'both', label: 'Both' },
];

export const wetnessMeta = (v) => WETNESS.find((w) => w.value === v) || null;
export const feelMeta = (v) => DIAPER_FEEL.find((f) => f.value === v) || null;
export const coreFeelMeta = (v) => CORE_FEEL.find((c) => c.value === v) || null;
export const postureMeta = (v) => POSTURES.find((p) => p.value === v) || null;

export const wetnessLabel = (v) => wetnessMeta(v)?.label || '—';
export const feelLabel = (v) => feelMeta(v)?.label || '—';
export const coreFeelLabel = (v) => coreFeelMeta(v)?.label || '—';
export const postureLabel = (v) => postureMeta(v)?.label || '—';

export const eventKind = (e) => (e && e.kind) || 'wet';
export const eventIsWet = (e) => eventKind(e) === 'wet';
export const kindLabel = (v) => EVENT_KINDS.find((k) => k.value === v)?.label || 'Wetting';
export const controlLabel = (v) => CONTROL_LEVELS.find((c) => c.value === v)?.label || null;
export const toiletWhatLabel = (v) => TOILET_WHAT.find((t) => t.value === v)?.label || null;

// Always returns a time-sorted array, tolerant of older logs with no field.
export const getWettings = (log) => {
  if (!log || !Array.isArray(log.wettings)) return [];
  return [...log.wettings].sort((a, b) => (a.at || 0) - (b.at || 0));
};

// Roll a session's events into a small summary. `count`, `byAmount`, `load`,
// `peakFeel` cover wettings only (the things that actually loaded the diaper);
// BM and toilet uses are reported as separate counts so they never distort
// capacity. `list` is every event, time-sorted, for timeline rendering.
export const wettingStats = (log) => {
  const all = getWettings(log);
  const wets = all.filter(eventIsWet);
  const byAmount = { light: 0, moderate: 0, heavy: 0, flood: 0 };
  let load = 0;
  let peakOrder = 0;
  let peakFeel = null;
  wets.forEach((w) => {
    if (byAmount[w.amount] != null) byAmount[w.amount] += 1;
    load += wetnessMeta(w.amount)?.weight || 0;
    const fo = feelMeta(w.feel)?.order || 0;
    if (fo >= peakOrder) { peakOrder = fo; peakFeel = w.feel; }
  });
  const lastFeel = wets.length ? wets[wets.length - 1].feel : null;
  const bmCount = all.filter((e) => eventKind(e) === 'bm').length;
  const toiletCount = all.filter((e) => eventKind(e) === 'toilet').length;
  const accidents = all.filter(
    (e) => (eventKind(e) === 'wet' || eventKind(e) === 'bm') && e.control === 'accident'
  ).length;
  return {
    count: wets.length, load, lastFeel, peakFeel, byAmount, list: all,
    wetCount: wets.length, bmCount, toiletCount, eventCount: all.length, accidents,
  };
};

// ---- Capacity profiling --------------------------------------------------
// Learn, per product, how much wetting "load" it has held before vs. without
// leaking, so the app can warn as a worn diaper nears the point it has
// historically given out. Toilet uses contribute nothing (load is wet-only).

const sessionLoad = (log) => wettingStats(log).load;

export const capacityProfile = (logs, productId, excludeLogId = null) => {
  const sessions = (logs || []).filter(
    (l) => l.productId === productId && l.putOnAt &&
           l.id !== excludeLogId && wettingStats(l).count > 0
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
    (l) => l.putOnAt && l.id !== excludeLogId && wettingStats(l).count > 0
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

mkdir -p "$(dirname src/lib/intake.js)"
cat > src/lib/intake.js << 'LEDGER_EOF'
// Fluid intake — its own kind of log (type: 'drink'): a free-standing,
// timestamped record of something you drank. Kept separate from wear sessions
// because intake isn't tied to a particular diaper; the value is correlating
// it against wetting timing/volume over time. Backward compatible by
// construction (a new log type older code simply ignores as "not a use").
//
//   { id, type: 'drink', timestamp, kind, size, note, createdAt, updatedAt }

export const DRINK_KINDS = [
  { value: 'water',   label: 'Water' },
  { value: 'coffee',  label: 'Coffee' },
  { value: 'tea',     label: 'Tea' },
  { value: 'soda',    label: 'Soda' },
  { value: 'juice',   label: 'Juice' },
  { value: 'alcohol', label: 'Alcohol' },
  { value: 'other',   label: 'Other' },
];

// Rough sizes with a nominal ounce value, so intake can be totalled without
// asking for exact volumes every time.
export const DRINK_SIZES = [
  { value: 'small',  label: 'Small',  oz: 8,  order: 1 },
  { value: 'medium', label: 'Medium', oz: 16, order: 2 },
  { value: 'large',  label: 'Large',  oz: 24, order: 3 },
];

export const drinkKindLabel = (v) => DRINK_KINDS.find((d) => d.value === v)?.label || 'Drink';
export const drinkSizeLabel = (v) => DRINK_SIZES.find((d) => d.value === v)?.label || '';
export const drinkSizeOz = (v) => DRINK_SIZES.find((d) => d.value === v)?.oz || 0;
export const isDrink = (l) => !!l && l.type === 'drink';
LEDGER_EOF

mkdir -p "$(dirname src/components/NoteForm.jsx)"
cat > src/components/NoteForm.jsx << 'LEDGER_EOF'
import React, { useState, useEffect } from 'react';
import { StickyNote } from 'lucide-react';
import { Modal } from './Common';
import {
  uid, toLocalInputValue, fromLocalInputValue, productDisplayName,
} from '../lib/helpers';
import { CONTEXTS } from '../lib/session';

// A note is its own kind of log (type: 'note'): a free-standing, timestamped
// entry. When opened from the diaper on now it carries that wear's product /
// session so it reads as "a note about this wear"; opened on its own it's a
// general note with an editable time (so it can be backdated).
//
// "Where I am" (context + free-text place) is distinct from the storage spot:
// the former is where you physically were, the latter is which stash a note
// might reference. They used to share one field, which conflated the two.
export default function NoteForm({
  open, onClose, onSave, locations, products, initial, context,
}) {
  const [text, setText] = useState('');
  const [at, setAt] = useState('');
  const [whereContext, setWhereContext] = useState('');
  const [place, setPlace] = useState('');
  const [locationId, setLocationId] = useState('');

  useEffect(() => {
    if (!open) return;
    if (initial) {
      setText(initial.text || '');
      setAt(toLocalInputValue(initial.timestamp || Date.now()));
      setWhereContext(initial.context || '');
      setPlace(initial.place || '');
      setLocationId(initial.locationId || '');
    } else {
      setText('');
      setAt(toLocalInputValue(Date.now()));
      setWhereContext(context?.context || '');
      setPlace('');
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
      context: whereContext || null,
      place: place.trim() || null,
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

        <div>
          <label className="label">Where were you? (optional)</label>
          <select
            className="select"
            value={whereContext}
            onChange={(e) => setWhereContext(e.target.value)}
          >
            <option value="">Not set</option>
            {CONTEXTS.map((c) => (
              <option key={c.value} value={c.value}>{c.label}</option>
            ))}
          </select>
          <input
            className="input"
            style={{ marginTop: 8 }}
            placeholder="Place (optional) — e.g. wedding venue, Harwood"
            value={place}
            onChange={(e) => setPlace(e.target.value)}
          />
        </div>

        {sortedLocations.length > 0 && (
          <div>
            <label className="label">Storage spot it's about (optional)</label>
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

mkdir -p "$(dirname src/components/DrinkForm.jsx)"
cat > src/components/DrinkForm.jsx << 'LEDGER_EOF'
import React, { useState, useEffect } from 'react';
import { Check, GlassWater } from 'lucide-react';
import { Modal } from './Common';
import { uid, toLocalInputValue, fromLocalInputValue } from '../lib/helpers';
import { DRINK_KINDS, DRINK_SIZES } from '../lib/intake';

// DrinkForm — log a fluid intake (type: 'drink'). Free-standing and
// backdatable, mirroring NoteForm. Intake is tracked to correlate against
// wetting timing and volume over time.
export default function DrinkForm({ open, onClose, onSave, initial }) {
  const [kind, setKind] = useState('water');
  const [size, setSize] = useState('medium');
  const [at, setAt] = useState('');
  const [note, setNote] = useState('');

  useEffect(() => {
    if (!open) return;
    if (initial) {
      setKind(initial.kind || 'water');
      setSize(initial.size || 'medium');
      setAt(toLocalInputValue(initial.timestamp || Date.now()));
      setNote(initial.note || '');
    } else {
      setKind('water');
      setSize('medium');
      setAt(toLocalInputValue(Date.now()));
      setNote('');
    }
  }, [open, initial]);

  const submit = () => {
    const ts = fromLocalInputValue(at) || Date.now();
    onSave({
      id: initial?.id || uid(),
      type: 'drink',
      timestamp: ts,
      kind,
      size,
      note: note.trim() || null,
      createdAt: initial?.createdAt || Date.now(),
      updatedAt: Date.now(),
    });
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={initial ? 'Edit drink' : 'Log a drink'}
      footer={
        <>
          <button className="btn btn-ghost" onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" onClick={submit}>
            {initial ? 'Save drink' : 'Add drink'}
          </button>
        </>
      }
    >
      <div style={{ display: 'grid', gap: 14 }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8,
          fontSize: 13, color: 'var(--ink-soft)',
        }}>
          <GlassWater size={14} /> <span>What did you drink?</span>
        </div>

        <div>
          <label className="label">Type</label>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
            {DRINK_KINDS.map((d) => (
              <button
                key={d.value} type="button"
                className={`check-row ${kind === d.value ? 'active' : ''}`}
                onClick={() => setKind(d.value)}
              >
                <span style={{ flex: 1 }}>{d.label}</span>
                {kind === d.value && <Check size={14} />}
              </button>
            ))}
          </div>
        </div>

        <div>
          <label className="label">Size</label>
          <div className="seg" style={{ width: '100%' }}>
            {DRINK_SIZES.map((s) => (
              <button
                key={s.value}
                type="button" style={{ flex: 1 }}
                className={`seg-btn ${size === s.value ? 'active' : ''}`}
                onClick={() => setSize(s.value)}
              >
                {s.label}
              </button>
            ))}
          </div>
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

        <div>
          <label className="label">Note (optional)</label>
          <input
            className="input"
            placeholder="e.g. big glass before bed"
            value={note}
            onChange={(e) => setNote(e.target.value)}
          />
        </div>
      </div>
    </Modal>
  );
}
LEDGER_EOF

mkdir -p "$(dirname src/components/WettingForm.jsx)"
cat > src/components/WettingForm.jsx << 'LEDGER_EOF'
import React, { useState, useEffect } from 'react';
import { Check, X, Droplets, Droplet, Pencil, AlertTriangle, ShieldCheck, Toilet } from 'lucide-react';
import { Modal } from './Common';
import {
  uid, toLocalInputValue, fromLocalInputValue,
  productDisplayName, formatTime, formatDuration, wearDuration,
} from '../lib/helpers';
import {
  WETNESS, DIAPER_FEEL, CORE_FEEL, POSTURES, EVENT_KINDS, CONTROL_LEVELS, TOILET_WHAT,
  getWettings, wettingStats, eventKind,
  wetnessLabel, feelLabel, coreFeelLabel, postureLabel,
  kindLabel, controlLabel, toiletWhatLabel,
  capacityProfile, globalCapacity, capacityStatus,
} from '../lib/wetting';
import { TAPE_STATES, tapeLabel } from '../lib/session';

// One-line description of a single event for the logged-so-far list.
function describeEvent(w) {
  const k = eventKind(w);
  if (k === 'toilet') {
    const what = toiletWhatLabel(w.toiletWhat);
    return `Toilet use${what ? ` · ${what.toLowerCase()}` : ''}`;
  }
  const head = k === 'bm' ? 'BM' : wetnessLabel(w.amount);
  const bits = [];
  if (w.feel) bits.push(feelLabel(w.feel).toLowerCase());
  if (w.core) bits.push(`core ${coreFeelLabel(w.core).toLowerCase()}`);
  if (w.posture) bits.push(postureLabel(w.posture).toLowerCase());
  if (w.tapes) bits.push(`tapes ${tapeLabel(w.tapes).toLowerCase()}`);
  if (w.control) bits.push(controlLabel(w.control).toLowerCase());
  return head + (bits.length ? ` · ${bits.join(' · ')}` : '');
}

// WettingSummary — compact, reusable read-out of a wear session's events.
export function WettingSummary({ log, compact = false, style = {} }) {
  const { count, peakFeel, byAmount, bmCount, toiletCount } = wettingStats(log);
  const extras = [];
  if (bmCount > 0) extras.push(`${bmCount} BM`);
  if (toiletCount > 0) extras.push(`${toiletCount} toilet`);

  if (count === 0 && extras.length === 0) {
    if (compact) return null;
    return (
      <div style={{ fontSize: 12, color: 'var(--ink-mute)', ...style }}>
        No events logged yet.
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
        color: 'var(--accent)', flexWrap: 'wrap', ...style,
      }}>
        <Droplet size={11} />
        {count} wetting{count !== 1 ? 's' : ''}
        {peakFeel && (
          <span style={{ color: 'var(--ink-mute)' }}>· {feelLabel(peakFeel).toLowerCase()}</span>
        )}
        {extras.length > 0 && (
          <span style={{ color: 'var(--ink-mute)' }}>· {extras.join(' · ')}</span>
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
      {extras.length > 0 && (
        <span style={{ fontSize: 12, color: 'var(--ink-mute)' }}>· {extras.join(' · ')}</span>
      )}
    </div>
  );
}

// CapacityMeter — how close this diaper's running load is to where it (or
// similar diapers) have historically leaked. Quiet when there's no basis yet.
function CapacityMeter({ load, status, isOn }) {
  if (status.level === 'none' || load <= 0) return null;

  const palette = {
    ok:    { bar: 'var(--primary)', fg: 'var(--ink-soft)', Icon: ShieldCheck },
    watch: { bar: '#C9985A',        fg: '#9A6A2E',         Icon: AlertTriangle },
    over:  { bar: 'var(--danger)',  fg: 'var(--danger)',   Icon: AlertTriangle },
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

// A small selectable grid of options.
function OptionGrid({ options, value, onPick, cols = 2 }) {
  return (
    <div style={{ display: 'grid', gridTemplateColumns: `repeat(${cols}, 1fr)`, gap: 8 }}>
      {options.map((o) => (
        <button
          key={o.value} type="button"
          className={`check-row ${value === o.value ? 'active' : ''}`}
          onClick={() => onPick(value === o.value ? '' : o.value)}
        >
          <span style={{ flex: 1 }}>{o.label}</span>
          {value === o.value && <Check size={14} />}
        </button>
      ))}
    </div>
  );
}

// WettingForm — add / edit / remove events on a single wear session.
export default function WettingForm({ open, onClose, entry, product, onSave, logs = [] }) {
  const [list, setList] = useState([]);
  const [editingId, setEditingId] = useState(null);
  const [kind, setKind] = useState('wet');
  const [at, setAt] = useState(Date.now());
  const [amount, setAmount] = useState('');
  const [feel, setFeel] = useState('');
  const [core, setCore] = useState('');
  const [tapes, setTapes] = useState('');
  const [posture, setPosture] = useState('');
  const [control, setControl] = useState('');
  const [toiletWhat, setToiletWhat] = useState('');
  const [note, setNote] = useState('');

  const defaultAt = () => {
    if (!entry) return Date.now();
    return entry.takenOffAt == null ? Date.now() : entry.takenOffAt;
  };

  const resetSubForm = () => {
    setEditingId(null);
    setKind('wet');
    setAt(defaultAt());
    setAmount('');
    setFeel('');
    setCore('');
    setTapes('');
    setPosture('');
    setControl('');
    setToiletWhat('');
    setNote('');
  };

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

  const canAdd =
    (kind === 'wet' && !!amount) ||
    (kind === 'bm') ||
    (kind === 'toilet' && !!toiletWhat);

  const addOrUpdate = () => {
    if (!canAdd) return;
    const base = { at, kind, note: note.trim() };
    let fields;
    if (kind === 'toilet') {
      fields = { ...base, toiletWhat: toiletWhat || null,
        amount: null, feel: null, core: null, tapes: null, posture: null, control: null };
    } else {
      fields = { ...base,
        amount: kind === 'wet' ? amount : null,
        feel: feel || null, core: core || null, tapes: tapes || null,
        posture: posture || null, control: control || null, toiletWhat: null };
    }
    if (editingId) {
      persist(list.map((w) => (w.id === editingId ? { ...w, ...fields } : w)));
    } else {
      persist([...list, { id: uid(), ...fields }]);
    }
    resetSubForm();
  };

  const editRow = (w) => {
    setEditingId(w.id);
    setKind(eventKind(w));
    setAt(w.at || Date.now());
    setAmount(w.amount || '');
    setFeel(w.feel || '');
    setCore(w.core || '');
    setTapes(w.tapes || '');
    setPosture(w.posture || '');
    setControl(w.control || '');
    setToiletWhat(w.toiletWhat || '');
    setNote(w.note || '');
  };

  const removeRow = (id) => {
    persist(list.filter((w) => w.id !== id));
    if (editingId === id) resetSubForm();
  };

  const stats = wettingStats({ ...entry, wettings: list });
  const dur = wearDuration(entry);

  // Live capacity read against this product's (and all products') history.
  const profile = capacityProfile(logs, entry.productId, entry.id);
  const gAll = globalCapacity(logs, entry.id);
  const fallback = { dryCeiling: gAll.dryCeiling };
  const capStatus = capacityStatus(stats.load, profile, fallback);
  const isOn = entry.takenOffAt == null;

  const isToilet = kind === 'toilet';
  const isBM = kind === 'bm';

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Diaper log"
      footer={<button className="btn btn-primary" onClick={onClose}>Done</button>}
    >
      <div style={{ display: 'grid', gap: 16 }}>
        {/* Session summary */}
        <div className="card" style={{ padding: '12px 14px' }}>
          <div style={{ fontSize: 14 }}>
            {product ? productDisplayName(product) : 'This diaper'}
          </div>
          <div style={{ fontSize: 12, color: 'var(--ink-mute)', marginTop: 3 }}>
            {entry.takenOffAt == null ? 'On now' : 'Previously worn'}
            {dur != null && ` · worn ${formatDuration(dur)}`}
            {` · ${stats.count} wetting${stats.count !== 1 ? 's' : ''}`}
            {stats.bmCount > 0 && ` · ${stats.bmCount} BM`}
            {stats.toiletCount > 0 && ` · ${stats.toiletCount} toilet`}
          </div>
          <CapacityMeter load={stats.load} status={capStatus} isOn={isOn} />
        </div>

        {/* Existing events */}
        {list.length > 0 && (
          <div>
            <label className="label">Logged so far</label>
            <div className="card" style={{ padding: 4 }}>
              {list.map((w) => {
                const k = eventKind(w);
                const Icon = k === 'toilet' ? Toilet : Droplet;
                const tint = k === 'toilet' ? 'var(--primary)' : 'var(--accent)';
                return (
                  <div
                    key={w.id}
                    className="row-divider"
                    style={{ padding: '10px 12px', display: 'flex', alignItems: 'center', gap: 10 }}
                  >
                    <Icon size={14} style={{ color: tint, flexShrink: 0 }} />
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontSize: 13 }}>{describeEvent(w)}</div>
                      <div style={{ fontSize: 11, color: 'var(--ink-mute)', marginTop: 1 }}>
                        {formatTime(w.at)}{w.note ? ` · ${w.note}` : ''}
                      </div>
                    </div>
                    <button className="btn-icon" onClick={() => editRow(w)} aria-label="Edit event">
                      <Pencil size={13} />
                    </button>
                    <button className="btn-icon" onClick={() => removeRow(w.id)} aria-label="Remove event">
                      <X size={14} />
                    </button>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        <hr className="hairline" />

        {/* Add / edit a single event */}
        <div style={{ display: 'grid', gap: 14 }}>
          <div className="eyebrow">{editingId ? 'Edit entry' : 'Add an entry'}</div>

          <div>
            <label className="label">What happened?</label>
            <OptionGrid options={EVENT_KINDS} value={kind} onPick={(v) => setKind(v || 'wet')} cols={3} />
          </div>

          <div>
            <label className="label">When</label>
            <input
              className="input" type="datetime-local"
              value={toLocalInputValue(at)}
              onChange={(e) => setAt(fromLocalInputValue(e.target.value))}
            />
          </div>

          {isToilet ? (
            <div>
              <label className="label">What did you do?</label>
              <OptionGrid options={TOILET_WHAT} value={toiletWhat} onPick={setToiletWhat} cols={3} />
              <p style={{ fontSize: 11, color: 'var(--ink-mute)', marginTop: 6, fontStyle: 'italic' }}>
                Toilet uses don't count toward the diaper's capacity.
              </p>
            </div>
          ) : (
            <>
              {!isBM && (
                <div>
                  <label className="label">How much?</label>
                  <OptionGrid options={WETNESS} value={amount} onPick={setAmount} cols={2} />
                </div>
              )}

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
                <label className="label">Was it…? (optional)</label>
                <OptionGrid options={CONTROL_LEVELS} value={control} onPick={setControl} cols={3} />
              </div>

              <div>
                <label className="label">Core feel? (optional)</label>
                <OptionGrid options={CORE_FEEL} value={core} onPick={setCore} cols={2} />
              </div>

              <div>
                <label className="label">Body position? (optional)</label>
                <OptionGrid options={POSTURES} value={posture} onPick={setPosture} cols={2} />
              </div>

              <div>
                <label className="label">Tape trouble? (optional)</label>
                <OptionGrid options={TAPE_STATES} value={tapes} onPick={setTapes} cols={2} />
              </div>
            </>
          )}

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
              disabled={!canAdd}
              style={{ flex: '1 1 auto' }}
            >
              <Droplets size={15} /> {editingId ? 'Update entry' : 'Add entry'}
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

mkdir -p "$(dirname src/components/TakeOffForm.jsx)"
cat > src/components/TakeOffForm.jsx << 'LEDGER_EOF'
import React, { useState, useEffect } from 'react';
import { Check, ArrowRight } from 'lucide-react';
import { Modal } from './Common';
import {
  PERFORMANCE, toLocalInputValue, fromLocalInputValue,
  productDisplayName, formatDuration,
} from '../lib/helpers';
import {
  CHANGE_REASONS, SKIN_STATES, ACTIVITY_LEVELS, CORE_CONDITIONS, TAPE_STATES,
  LEAK_ESCAPE, LEAK_SEVERITY, CLEANUP_METHODS,
} from '../lib/session';

// TakeOffForm — ends the active wear session. Records take-off time, how it
// performed, optional take-off detail, and (when it leaked) where/how badly it
// leaked, plus the cleanup/skin routine. A "then" choice lets the user go
// without or immediately put a fresh one on (change-out).
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
  const [creamProduct, setCreamProduct] = useState('');
  const [leakEscape, setLeakEscape] = useState('');
  const [leakSeverity, setLeakSeverity] = useState('');
  const [cleanup, setCleanup] = useState([]);
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
      setCreamProduct('');
      setLeakEscape('');
      setLeakSeverity('');
      setCleanup([]);
      setNotes('');
      setThen(defaultThen === 'replace' ? 'replace' : 'none');
    }
  }, [open, defaultThen]);

  if (!open || !entry) return null;

  const putOnAt = entry.putOnAt;
  const effectiveOff = Math.max(takenOffAt, putOnAt);
  const duration = effectiveOff - putOnAt;
  const isLeak = performance === 'leak';

  const toggleCleanup = (v) =>
    setCleanup((prev) => (prev.includes(v) ? prev.filter((x) => x !== v) : [...prev, v]));

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
        creamProduct: cream ? (creamProduct.trim() || null) : null,
        leakEscape: isLeak ? (leakEscape || null) : null,
        leakSeverity: isLeak ? (leakSeverity || null) : null,
        cleanup: cleanup.length ? cleanup : null,
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

        {isLeak && (
          <>
            <div>
              <label className="label">Where did it leak?</label>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
                {LEAK_ESCAPE.map((e) => (
                  <button
                    key={e.value} type="button"
                    className={`check-row ${leakEscape === e.value ? 'active' : ''}`}
                    onClick={() => setLeakEscape(leakEscape === e.value ? '' : e.value)}
                  >
                    <span style={{ flex: 1 }}>{e.label}</span>
                    {leakEscape === e.value && <Check size={14} />}
                  </button>
                ))}
              </div>
            </div>
            <div>
              <label className="label">How bad?</label>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
                {LEAK_SEVERITY.map((s) => (
                  <button
                    key={s.value} type="button"
                    className={`check-row ${leakSeverity === s.value ? 'active' : ''}`}
                    onClick={() => setLeakSeverity(leakSeverity === s.value ? '' : s.value)}
                  >
                    <span style={{ flex: 1 }}>{s.label}</span>
                    {leakSeverity === s.value && <Check size={14} />}
                  </button>
                ))}
              </div>
            </div>
          </>
        )}

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
          <label className="label">Cleanup (optional)</label>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
            {CLEANUP_METHODS.map((m) => (
              <button
                key={m.value} type="button"
                className={`check-row ${cleanup.includes(m.value) ? 'active' : ''}`}
                onClick={() => toggleCleanup(m.value)}
              >
                <span style={{ flex: 1 }}>{m.label}</span>
                {cleanup.includes(m.value) && <Check size={14} />}
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
          {cream && (
            <input
              className="input"
              style={{ marginTop: 8 }}
              placeholder="Which cream? (optional) — e.g. Desitin Max"
              value={creamProduct}
              onChange={(e) => setCreamProduct(e.target.value)}
            />
          )}
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

mkdir -p "$(dirname src/components/Dashboard.jsx)"
cat > src/components/Dashboard.jsx << 'LEDGER_EOF'
import React, { useMemo, useState, useEffect } from 'react';
import { Plus, ChevronRight, Sun, Moon, ArrowRight, Repeat, X, Clock, Droplets, StickyNote, GlassWater } from 'lucide-react';
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
  onRestock, onMove, onAddNote, onAddDrink, onPhotoTap,
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

      <div style={{ display: 'flex', gap: 8 }}>
        <button
          className="btn btn-ghost"
          onClick={() => onAddNote()}
          style={{ flex: 1 }}
        >
          <StickyNote size={15} /> Add a note
        </button>
        <button
          className="btn btn-ghost"
          onClick={() => onAddDrink && onAddDrink()}
          style={{ flex: 1 }}
        >
          <GlassWater size={15} /> Log a drink
        </button>
      </div>

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

mkdir -p "$(dirname src/components/History.jsx)"
cat > src/components/History.jsx << 'LEDGER_EOF'
import React, { useState, useMemo } from 'react';
import { Pencil, Trash2, Sun, Moon, ClipboardList, ArrowRight, Droplets, StickyNote, Repeat, GlassWater } from 'lucide-react';
import { ProductThumb } from './Common';
import { LocationIcon } from './LocationManager';
import { WettingSummary } from './WettingForm';
import { contextLabel, reasonLabel } from '../lib/session';
import { isDrink, drinkKindLabel, drinkSizeLabel } from '../lib/intake';
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
        if (typeFilter === 'use') return l.type !== 'move' && l.type !== 'note' && l.type !== 'drink';
        if (typeFilter === 'move') return l.type === 'move';
        if (typeFilter === 'note') return l.type === 'note';
        if (typeFilter === 'drink') return l.type === 'drink';
        return true;
      })
      .filter((l) => {
        if (l.type === 'move' || l.type === 'note' || l.type === 'drink') return periodFilter === 'all';
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
          <button
            className={`seg-btn ${typeFilter === 'drink' ? 'active' : ''}`}
            onClick={() => setTypeFilter('drink')}
          >
            Drinks
          </button>
        </div>
        {typeFilter !== 'move' && typeFilter !== 'note' && typeFilter !== 'drink' && (
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
                    if (isDrink(l)) {
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
                          <div style={{ marginTop: 2, color: 'var(--primary)', flexShrink: 0 }}>
                            <GlassWater size={16} />
                          </div>
                          <div style={{ flex: 1, minWidth: 0 }}>
                            <div style={{ fontSize: 14 }}>
                              {drinkKindLabel(l.kind)}
                              {l.size && <span style={{ color: 'var(--ink-mute)' }}> · {drinkSizeLabel(l.size).toLowerCase()}</span>}
                            </div>
                            <div style={{ fontSize: 12, color: 'var(--ink-mute)', marginTop: 4 }}>
                              <span style={{ color: 'var(--primary)' }}>Drink</span>
                              {l.note && <span> · {l.note}</span>}
                            </div>
                          </div>
                          <div style={{ display: 'flex', gap: 2, flexShrink: 0 }}>
                            <button className="btn-icon" onClick={() => onEdit(l)} aria-label="Edit drink">
                              <Pencil size={14} />
                            </button>
                            <button className="btn-icon" onClick={() => onDelete(l)} aria-label="Delete drink">
                              <Trash2 size={14} />
                            </button>
                          </div>
                        </div>
                      );
                    }
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
                              {l.context && <><span>·</span><span>{contextLabel(l.context) || l.context}</span></>}
                              {l.place && <><span>·</span><span>{l.place}</span></>}
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
                    // A put-on that directly followed an explicit/auto-linked take-off.
                    const isChangeOut = isWearSession && !!l.changedFromId;

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
                          <div style={{ fontSize: 14, display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
                            {isChangeOut && (
                              <span style={{ color: 'var(--accent)', display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                                <Repeat size={12} /> Changed into
                              </span>
                            )}
                            <span>
                              {p ? productDisplayName(p) : <span style={{ color: 'var(--ink-mute)' }}>Removed product</span>}
                            </span>
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
  eventKind, CONTROL_LEVELS, controlLabel,
} from '../lib/wetting';
import {
  CHANGE_REASONS, contextLabel, unitCost, fmtMoney,
  LEAK_ESCAPE, LEAK_SEVERITY,
} from '../lib/session';
import { isDrink, DRINK_KINDS, drinkKindLabel, drinkSizeOz } from '../lib/intake';

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
    const amountCounts = {};
    WETNESS.forEach((w) => { amountCounts[w.value] = 0; });
    let totalWettings = 0;
    let wetSessionCount = 0;
    sessions.forEach((l) => {
      const st = wettingStats(l); // wet-only counts; BM/toilet excluded
      if (st.count > 0) wetSessionCount += 1;
      totalWettings += st.count;
      WETNESS.forEach((w) => { amountCounts[w.value] += st.byAmount[w.value] || 0; });
    });
    return {
      sessionCount: sessions.length,
      wetSessionCount,
      totalWettings,
      amountCounts,
      avgPerDiaper: sessions.length ? totalWettings / sessions.length : 0,
      avgPerWetDiaper: wetSessionCount ? totalWettings / wetSessionCount : 0,
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
        if (eventKind(w) !== 'wet') return;
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

  // Toilet uses, BM-in-diaper, and the voluntary/accident breakdown across
  // every event. This is the continence-pattern signal.
  const eliminationAgg = useMemo(() => {
    const sessions = usageLogs.filter((l) => l.putOnAt);
    let toilet = 0, bm = 0;
    let toiletPee = 0, toiletBM = 0, toiletBoth = 0;
    const control = { voluntary: 0, couldnt_hold: 0, accident: 0 };
    sessions.forEach((l) => {
      getWettings(l).forEach((w) => {
        const k = eventKind(w);
        if (k === 'toilet') {
          toilet += 1;
          if (w.toiletWhat === 'pee') toiletPee += 1;
          else if (w.toiletWhat === 'bm') toiletBM += 1;
          else if (w.toiletWhat === 'both') toiletBoth += 1;
        } else if (k === 'bm') {
          bm += 1;
        }
        if ((k === 'wet' || k === 'bm') && w.control && control[w.control] != null) {
          control[w.control] += 1;
        }
      });
    });
    const controlTotal = control.voluntary + control.couldnt_hold + control.accident;
    return { toilet, bm, control, controlTotal, toiletPee, toiletBM, toiletBoth,
      any: toilet > 0 || bm > 0 || controlTotal > 0 };
  }, [usageLogs]);

  // Leak detail — where leaks escaped and how bad, among sessions marked leak.
  const leakDetailAgg = useMemo(() => {
    const leaks = usageLogs.filter((l) => l.putOnAt && l.performance === 'leak');
    const escape = {}; const severity = {};
    leaks.forEach((l) => {
      if (l.leakEscape) escape[l.leakEscape] = (escape[l.leakEscape] || 0) + 1;
      if (l.leakSeverity) severity[l.leakSeverity] = (severity[l.leakSeverity] || 0) + 1;
    });
    return {
      leakCount: leaks.length,
      detailed: leaks.filter((l) => l.leakEscape || l.leakSeverity).length,
      escapeRows: LEAK_ESCAPE.map((e) => ({ ...e, count: escape[e.value] || 0 })).filter((r) => r.count > 0),
      severityRows: LEAK_SEVERITY.map((x) => ({ ...x, count: severity[x.value] || 0 })).filter((r) => r.count > 0),
    };
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

  // Fluid intake — drinks logged, by kind, and a rough daily volume.
  const intakeAgg = useMemo(() => {
    const drinks = logs.filter(isDrink);
    const byKind = {}; let totalOz = 0;
    drinks.forEach((d) => { byKind[d.kind] = (byKind[d.kind] || 0) + 1; totalOz += drinkSizeOz(d.size); });
    return {
      count: drinks.length,
      totalOz,
      perDay: trackingDays > 0 ? drinks.length / trackingDays : 0,
      ozPerDay: trackingDays > 0 ? totalOz / trackingDays : 0,
      kindRows: DRINK_KINDS.map((k) => ({ ...k, count: byKind[k.value] || 0 })).filter((r) => r.count > 0),
    };
  }, [logs, trackingDays]);

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

      {/* Toilet & accidents */}
      {eliminationAgg.any && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="Toilet & accidents" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)',
            marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            Toilet uses (diaper off, so excluded from capacity), BMs in the diaper,
            and how voluntary your wettings were.
          </p>
          <div style={{
            display: 'grid', gridTemplateColumns: '1fr 1fr 1fr',
            gap: 16, marginBottom: eliminationAgg.controlTotal > 0 ? 20 : 0,
          }}>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 28, lineHeight: 1 }}>{eliminationAgg.toilet}</div>
              <div className="eyebrow" style={{ marginTop: 6 }}>Toilet uses</div>
            </div>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 28, lineHeight: 1 }}>{eliminationAgg.bm}</div>
              <div className="eyebrow" style={{ marginTop: 6 }}>BMs in diaper</div>
            </div>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 28, lineHeight: 1 }}>{eliminationAgg.control.accident}</div>
              <div className="eyebrow" style={{ marginTop: 6 }}>Accidents</div>
            </div>
          </div>
          {eliminationAgg.controlTotal > 0 && (
            <div className="card" style={{ padding: 4 }}>
              {CONTROL_LEVELS.map((c) => {
                const count = eliminationAgg.control[c.value] || 0;
                const pct = eliminationAgg.controlTotal ? (count / eliminationAgg.controlTotal) * 100 : 0;
                return (
                  <div key={c.value} className="row-divider" style={{ padding: '12px 14px' }}>
                    <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                      <span style={{ flex: 1, fontSize: 14 }}>{c.label}</span>
                      <span className="num" style={{ fontSize: 16 }}>{count}</span>
                      <span style={{ fontSize: 11, color: 'var(--ink-mute)', marginLeft: 4 }}>
                        {Math.round(pct)}%
                      </span>
                    </div>
                    <div style={{ height: 3, background: 'var(--line-soft)', borderRadius: 2, marginTop: 8 }}>
                      <div style={{ height: '100%', width: `${pct}%`, background: 'var(--accent)', borderRadius: 2 }} />
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </section>
      )}

      {/* Leak detail */}
      {leakDetailAgg.leakCount > 0 && (leakDetailAgg.escapeRows.length > 0 || leakDetailAgg.severityRows.length > 0) && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="Leak detail" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)',
            marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            Where leaks escaped and how bad, on {leakDetailAgg.detailed} of {leakDetailAgg.leakCount} leak{leakDetailAgg.leakCount !== 1 ? 's' : ''} with detail recorded.
          </p>
          {leakDetailAgg.escapeRows.length > 0 && (
            <div className="card" style={{ padding: 4, marginBottom: leakDetailAgg.severityRows.length ? 16 : 0 }}>
              {leakDetailAgg.escapeRows.map((e) => (
                <div key={e.value} className="row-divider" style={{ padding: '12px 14px', display: 'flex', alignItems: 'baseline', gap: 10 }}>
                  <span style={{ flex: 1, fontSize: 14 }}>{e.label}</span>
                  <span className="num" style={{ fontSize: 16, color: 'var(--danger)' }}>{e.count}</span>
                </div>
              ))}
            </div>
          )}
          {leakDetailAgg.severityRows.length > 0 && (
            <div className="card" style={{ padding: 4 }}>
              {leakDetailAgg.severityRows.map((x) => (
                <div key={x.value} className="row-divider" style={{ padding: '12px 14px', display: 'flex', alignItems: 'baseline', gap: 10 }}>
                  <span style={{ flex: 1, fontSize: 14 }}>{x.label}</span>
                  <span className="num" style={{ fontSize: 16 }}>{x.count}</span>
                </div>
              ))}
            </div>
          )}
        </section>
      )}

      {/* Fluid intake */}
      {intakeAgg.count > 0 && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="Fluid intake" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)',
            marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            Drinks you've logged. As this builds up it can be lined up against wetting timing and volume.
          </p>
          <div style={{
            display: 'grid', gridTemplateColumns: '1fr 1fr 1fr',
            gap: 16, marginBottom: 20,
          }}>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 24, lineHeight: 1 }}>{intakeAgg.count}</div>
              <div className="eyebrow" style={{ marginTop: 6 }}>Drinks</div>
            </div>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 24, lineHeight: 1 }}>{intakeAgg.perDay.toFixed(1)}</div>
              <div className="eyebrow" style={{ marginTop: 6 }}>Per day</div>
            </div>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 24, lineHeight: 1 }}>{Math.round(intakeAgg.ozPerDay)}</div>
              <div className="eyebrow" style={{ marginTop: 6 }}>oz / day (est.)</div>
            </div>
          </div>
          <div className="card" style={{ padding: 4 }}>
            {intakeAgg.kindRows.map((k) => {
              const max = intakeAgg.kindRows[0].count;
              const pct = max ? (k.count / max) * 100 : 0;
              return (
                <div key={k.value} className="row-divider" style={{ padding: '12px 14px' }}>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                    <span style={{ flex: 1, fontSize: 14 }}>{k.label}</span>
                    <span className="num" style={{ fontSize: 16 }}>{k.count}</span>
                  </div>
                  <div style={{ height: 3, background: 'var(--line-soft)', borderRadius: 2, marginTop: 8 }}>
                    <div style={{ height: '100%', width: `${pct}%`, background: 'var(--primary)', borderRadius: 2 }} />
                  </div>
                </div>
              );
            })}
          </div>
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
import DrinkForm from './components/DrinkForm';
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

  const [drinkFormOpen, setDrinkFormOpen] = useState(false);
  const [editingDrink, setEditingDrink] = useState(null);

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

  // Drink logs (type: 'drink') — free-standing fluid intake.
  const handleSaveDrink = async (drink) => {
    const exists = logs.find((l) => l.id === drink.id);
    await saveLog(drink);
    setLogs(exists ? logs.map((l) => (l.id === drink.id ? drink : l)) : [...logs, drink]);
    setDrinkFormOpen(false);
    setEditingDrink(null);
    setToastMsg(exists ? 'Drink updated' : 'Drink logged');
  };

  const openDrinkForm = () => {
    setEditingDrink(null);
    setDrinkFormOpen(true);
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
            onAddDrink={openDrinkForm}
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
              else if (l.type === 'drink') { setEditingDrink(l); setDrinkFormOpen(true); }
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

      <DrinkForm
        open={drinkFormOpen}
        onClose={() => { setDrinkFormOpen(false); setEditingDrink(null); }}
        onSave={handleSaveDrink}
        initial={editingDrink}
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
git add -A && git commit -m "Add note location/place, toilet+BM+control logging, fluid intake, and take-off leak/cleanup detail" && git push

echo "Done. Netlify will redeploy from this push."
