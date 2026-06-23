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
