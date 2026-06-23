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
                              {Number(l.oz) > 0 && <span style={{ color: 'var(--ink-mute)' }}> · {l.oz}oz</span>}
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
