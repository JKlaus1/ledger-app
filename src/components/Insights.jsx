import React, { useMemo } from 'react';
import {
  BarChart, Bar, XAxis, YAxis, ResponsiveContainer, Tooltip,
  PieChart, Pie, Cell,
} from 'recharts';
import { BarChart3 } from 'lucide-react';
import { ProductThumb, SectionHeader } from './Common';
import { LocationIcon } from './LocationManager';
import {
  productDisplayName, totalStock, dayKey, formatDuration,
} from '../lib/helpers';

export default function Insights({ products, logs, locations, thumbs, daysRemainingMap }) {
  // Filter out moves - they're inventory transfers, not consumption
  const usageLogs = logs.filter((l) => l.type !== 'move');

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

      {/* Daily chart */}
      <section style={{ marginBottom: 36 }}>
        <SectionHeader number="01" title="Last 14 days" />
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
        <SectionHeader number="02" title="Day vs. night" />
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

      {/* Usage by location */}
      {locationUsage.length > 0 && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number="03" title="Usage by location" />
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
          <SectionHeader number={locationUsage.length > 0 ? '04' : '03'} title="Most used" />
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
          <SectionHeader number={locationUsage.length > 0 ? '05' : '04'} title="Performance" />
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
        <SectionHeader
          number={
            locationUsage.length > 0 && performance.length > 0 ? '06' :
            locationUsage.length > 0 || performance.length > 0 ? '05' : '04'
          }
          title="Estimated days remaining"
        />
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
