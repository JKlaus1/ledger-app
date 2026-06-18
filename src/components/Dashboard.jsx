import React, { useMemo, useState, useEffect } from 'react';
import { Plus, ChevronRight, Sun, Moon, ArrowRight, Repeat, X, Clock, Droplets } from 'lucide-react';
import { ProductThumb, Eyebrow, SectionHeader, Pill } from './Common';
import { LocationIcon } from './LocationManager';
import { WettingSummary } from './WettingForm';
import {
  ABSORBENCY, formatDate, formatTime, isToday,
  productDisplayName, totalStock, formatDuration, wearDuration,
} from '../lib/helpers';

export default function Dashboard({
  products, logs, locations, thumbs, activeWear,
  onAddProduct, onAddLocation,
  onPutOn, onChangeOut, onTakeOff, onUndoWear, onLogWetting,
  onRestock, onMove, onPhotoTap,
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

  // Most-used products in last 14 days
  const quickProducts = useMemo(() => {
    const cutoff = Date.now() - 14 * 24 * 3600 * 1000;
    const counts = new Map();
    usageLogs.filter((l) => l.timestamp >= cutoff).forEach((l) => {
      counts.set(l.productId, (counts.get(l.productId) || 0) + 1);
    });
    return [...counts.entries()]
      .sort((a, b) => b[1] - a[1])
      .map(([id]) => products.find((p) => p.id === id))
      .filter((p) => p && totalStock(p) > 0)
      .slice(0, 3);
  }, [usageLogs, products]);

  const recentLogs = [...logs]
    .sort((a, b) => b.timestamp - a.timestamp)
    .slice(0, 5);

  const quickVisible = !activeWear && quickProducts.length > 0;

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
      {!activeWear && quickProducts.length > 0 && (
        <section>
          <SectionHeader number="02" title="Quick start" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)', marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            Tap a product to put one on. You'll pick the location next.
          </p>
          <div style={{ display: 'grid', gap: 8 }}>
            {quickProducts.map((p) => (
              <button
                key={p.id}
                onClick={() => onPutOn(p.id)}
                className="card row-hover"
                style={{
                  textAlign: 'left', padding: '14px 16px',
                  display: 'flex', alignItems: 'center', gap: 12,
                  border: '1px solid var(--line)', cursor: 'pointer',
                  font: 'inherit', color: 'inherit', width: '100%',
                }}
              >
                <ProductThumb product={p} thumbs={thumbs} size={32} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div className="display" style={{ fontSize: 15 }}>{productDisplayName(p)}</div>
                  <div style={{ fontSize: 12, color: 'var(--ink-mute)' }}>
                    {p.size} · {ABSORBENCY.find((a) => a.value === p.absorbency)?.label} · {totalStock(p)} total
                  </div>
                </div>
                <span style={{
                  fontSize: 13, color: 'var(--ink-soft)',
                  display: 'inline-flex', alignItems: 'center', gap: 4,
                }}>
                  Put on <ChevronRight size={14} />
                </span>
              </button>
            ))}
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
