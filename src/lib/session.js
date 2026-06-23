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

// How far a wetting wicked through the padding by take-off — i.e. how much of
// the pad actually got used. Ordered by utilisation (front only → whole pad).
// A diaper that only swells in front has effectively used far less of its
// capacity than one that wicks evenly front-to-back.
export const WICKING = [
  { value: 'front', label: 'Front only', order: 1 },
  { value: 'crotch', label: 'Front & between legs', order: 2 },
  { value: 'rear', label: 'Reached the rear', order: 3 },
  { value: 'even', label: 'Used evenly throughout', order: 4 },
];

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
export const wickingLabel = (v) => labelOf(WICKING, v);

// A wear/use log: a diaper actually put on (stock decrements at put-on). The
// modern kind has type 'use'; older entries predate the type field but carry a
// putOnAt time or a day/night period. Notes, drinks, toilet logs and moves are
// NOT wears — counting them as "uses" inflates daily/total use stats.
export const isWearLog = (l) =>
  !!(l && (l.type === 'use' || (!l.type && (l.putOnAt || l.period))));

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
