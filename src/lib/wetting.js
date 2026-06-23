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
