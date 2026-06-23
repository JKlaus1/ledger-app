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
import { isDrink, DRINK_KINDS, drinkKindLabel, drinkVolumeOz } from '../lib/intake';

export default function Insights({ products, logs, locations, thumbs, daysRemainingMap, drinkPresets = null }) {
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
    // Standalone toilet logs (toilet trips with no diaper on) count too.
    usageLogs.filter((l) => l.type === 'toilet').forEach((l) => {
      toilet += 1;
      if (l.what === 'pee') toiletPee += 1;
      else if (l.what === 'bm') toiletBM += 1;
      else if (l.what === 'both') toiletBoth += 1;
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
    const byKind = {}; let totalOz = 0; let exactCount = 0;
    drinks.forEach((d) => {
      byKind[d.kind] = (byKind[d.kind] || 0) + 1;
      totalOz += drinkVolumeOz(d, drinkPresets); // exact oz when given, else preset bucket
      if (Number(d.oz) > 0) exactCount += 1;
    });
    return {
      count: drinks.length,
      totalOz,
      exactCount,
      perDay: trackingDays > 0 ? drinks.length / trackingDays : 0,
      ozPerDay: trackingDays > 0 ? totalOz / trackingDays : 0,
      kindRows: DRINK_KINDS.map((k) => ({ ...k, count: byKind[k.value] || 0 })).filter((r) => r.count > 0),
    };
  }, [logs, trackingDays, drinkPresets]);

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
            Drinks you've logged. As this builds up it can be lined up against wetting timing and volume.{intakeAgg.count > 0 && (intakeAgg.exactCount > 0 ? ` Volume uses exact amounts where given (${intakeAgg.exactCount} of ${intakeAgg.count}) and your size presets otherwise.` : ' Volume uses your size presets — add exact amounts on a drink to refine it.')}
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
