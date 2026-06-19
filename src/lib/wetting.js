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
