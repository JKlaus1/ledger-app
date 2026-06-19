import React, { useState, useMemo } from 'react';
import { Plus, Pencil, MinusCircle, PlusCircle, ArrowRightLeft, Package } from 'lucide-react';
import { ProductThumb, Pill } from './Common';
import { LocationIcon } from './LocationManager';
import {
  TYPES, ABSORBENCY, productDisplayName, totalStock, stockAt,
} from '../lib/helpers';
import { backingLabel, tabsLabel } from '../lib/session';
import { groupProducts } from '../lib/variants';

function ProductRow({
  product, locations, thumbs, daysRemaining, titleOverride = null,
  onLogQuick, onRestock, onMove, onEdit, onPhotoTap,
}) {
  const [expanded, setExpanded] = useState(false);
  const total = totalStock(product);
  const lowStock = total <= 5;
  const veryLow = total <= 2;
  const sortedLocations = [...locations].sort(
    (a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)
  );

  return (
    <div className="row-divider row-hover" style={{ padding: '16px 4px' }}>
      <div style={{ display: 'flex', gap: 14, alignItems: 'flex-start' }}>
        <ProductThumb
          product={product} thumbs={thumbs} size={48}
          style={{ marginTop: 2 }}
          onClick={() => thumbs[product.id] && onPhotoTap(product.id)}
        />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, flexWrap: 'wrap' }}>
            <span className="display" style={{ fontSize: 17 }}>{titleOverride ?? productDisplayName(product)}</span>
          </div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 6 }}>
            <Pill>{TYPES.find((t) => t.value === product.type)?.short}</Pill>
            <Pill>Size {product.size}</Pill>
            <Pill>{ABSORBENCY.find((a) => a.value === product.absorbency)?.label}</Pill>
            {product.backing && <Pill>{backingLabel(product.backing)}</Pill>}
            {product.tabs && <Pill>{tabsLabel(product.tabs)}</Pill>}
          </div>
          {product.notes && (
            <div style={{ fontSize: 13, color: 'var(--ink-soft)', marginTop: 8, fontStyle: 'italic' }}>
              {product.notes}
            </div>
          )}
        </div>

        <div style={{ textAlign: 'right', flexShrink: 0 }}>
          <div className="num" style={{
            fontSize: 32, lineHeight: 1,
            color: veryLow ? 'var(--danger)' : (lowStock ? 'var(--warn)' : 'var(--ink)'),
          }}>
            {total}
          </div>
          <div className="eyebrow" style={{ fontSize: 9.5, marginTop: 2 }}>total</div>
          {daysRemaining != null && Number.isFinite(daysRemaining) && (
            <div style={{ fontSize: 11, color: 'var(--ink-mute)', marginTop: 4, fontStyle: 'italic' }}>
              ~{daysRemaining}d left
            </div>
          )}
        </div>
      </div>

      {/* Per-location breakdown - collapsible */}
      {locations.length > 0 && (
        <div style={{ marginTop: 10, marginLeft: 62 }}>
          <button
            onClick={() => setExpanded(!expanded)}
            style={{
              background: 'transparent', border: 'none', cursor: 'pointer',
              fontFamily: 'inherit', fontSize: 11, color: 'var(--ink-mute)',
              padding: 0, letterSpacing: '0.06em', fontWeight: 500,
            }}
          >
            {expanded ? '− HIDE BREAKDOWN' : '+ SHOW BY LOCATION'}
          </button>
          {expanded && (
            <div style={{
              marginTop: 8, display: 'flex', flexWrap: 'wrap', gap: 6,
            }}>
              {sortedLocations.map((loc) => {
                const stock = stockAt(product, loc.id);
                return (
                  <span
                    key={loc.id}
                    className="location-chip"
                    style={{
                      opacity: stock === 0 ? 0.5 : 1,
                    }}
                  >
                    <LocationIcon name={loc.icon} size={11} />
                    {loc.name}
                    <span className="num" style={{ marginLeft: 2, fontSize: 12 }}>{stock}</span>
                  </span>
                );
              })}
            </div>
          )}
        </div>
      )}

      <div style={{ display: 'flex', gap: 6, marginTop: 12, flexWrap: 'wrap' }}>
        <button
          className="btn btn-ghost"
          onClick={() => onLogQuick(product.id)}
          disabled={total <= 0}
          style={{ fontSize: 13, padding: '7px 12px' }}
        >
          <MinusCircle size={14} /> Use one
        </button>
        <button
          className="btn btn-ghost"
          onClick={() => onRestock(product)}
          style={{ fontSize: 13, padding: '7px 12px' }}
        >
          <PlusCircle size={14} /> Restock
        </button>
        {locations.length >= 2 && total > 0 && (
          <button
            className="btn btn-ghost"
            onClick={() => onMove(product.id)}
            style={{ fontSize: 13, padding: '7px 12px' }}
          >
            <ArrowRightLeft size={14} /> Move
          </button>
        )}
        <button
          className="btn-icon"
          onClick={() => onEdit(product)}
          aria-label="Edit"
        >
          <Pencil size={15} />
        </button>
      </div>
    </div>
  );
}

function GroupBlock({
  group, locations, thumbs, daysRemainingMap,
  onLogQuick, onRestock, onMove, onEdit, onPhotoTap,
}) {
  const rowProps = {
    locations, thumbs, onLogQuick, onRestock, onMove, onEdit, onPhotoTap,
  };

  // A single-variant group renders exactly like a normal row — no extra chrome.
  if (!group.isMulti) {
    const p = group.products[0];
    return (
      <ProductRow product={p} daysRemaining={daysRemainingMap[p.id]} {...rowProps} />
    );
  }

  // Multiple variants: a header for the shared product, variants nested beneath.
  return (
    <div
      style={{
        border: '1px solid var(--line)', borderRadius: 14,
        padding: '4px 10px', marginBottom: 12,
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 4px 4px' }}>
        <ProductThumb product={group.rep} thumbs={thumbs} size={30} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <span className="display" style={{ fontSize: 16 }}>{group.label}</span>
          <span className="eyebrow" style={{ fontSize: 9.5, marginLeft: 8 }}>
            {group.products.length} variants
          </span>
        </div>
        <div style={{ textAlign: 'right', flexShrink: 0 }}>
          <span className="num" style={{ fontSize: 20 }}>{group.total}</span>
          <span className="eyebrow" style={{ fontSize: 9, marginLeft: 4 }}>total</span>
        </div>
      </div>
      <div style={{ borderLeft: '2px solid var(--line)', marginLeft: 14, paddingLeft: 6 }}>
        {group.products.map((p) => (
          <ProductRow
            key={p.id}
            product={p}
            daysRemaining={daysRemainingMap[p.id]}
            titleOverride={(p.print && p.print.trim()) || 'Default'}
            {...rowProps}
          />
        ))}
      </div>
    </div>
  );
}

export default function Inventory({
  products, locations, thumbs, daysRemainingMap,
  onAdd, onEdit, onLogQuick, onRestock, onMove, onPhotoTap,
}) {
  const [filter, setFilter] = useState('all');
  const [locationFilter, setLocationFilter] = useState('all');

  const sortedLocations = [...locations].sort(
    (a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)
  );

  const filtered = useMemo(() => {
    let list = [...products];
    if (filter === 'low') {
      list = list.filter((p) => totalStock(p) <= 5);
    } else if (['brief', 'pullup', 'pad', 'booster'].includes(filter)) {
      list = list.filter((p) => p.type === filter);
    }
    if (locationFilter !== 'all') {
      list = list.filter((p) => stockAt(p, locationFilter) > 0);
    }
    return list.sort((a, b) =>
      productDisplayName(a).localeCompare(productDisplayName(b))
    );
  }, [products, filter, locationFilter]);

  if (products.length === 0) {
    return (
      <div className="empty-state">
        <Package size={28} style={{ color: 'var(--ink-mute)' }} />
        <div className="display" style={{ fontSize: 22, marginTop: 12 }}>No products yet</div>
        <p style={{ marginTop: 8, color: 'var(--ink-soft)' }}>
          Add your first item to get started.
        </p>
        <button className="btn btn-primary" onClick={onAdd} style={{ marginTop: 16 }}>
          <Plus size={16} /> Add product
        </button>
      </div>
    );
  }

  const filterOpts = [
    { v: 'all', l: 'All' },
    { v: 'low', l: 'Low stock' },
    { v: 'brief', l: 'Briefs' },
    { v: 'pullup', l: 'Pull-ups' },
    { v: 'pad', l: 'Pads' },
    { v: 'booster', l: 'Boosters' },
  ];

  return (
    <div>
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        marginBottom: 16, gap: 10,
      }}>
        <span className="display" style={{ fontSize: 24 }}>Inventory</span>
        <button
          className="btn btn-primary"
          onClick={onAdd}
          style={{ padding: '8px 14px', fontSize: 13 }}
        >
          <Plus size={15} /> Add
        </button>
      </div>

      <div className="scroll-x" style={{ marginBottom: 8, paddingBottom: 4 }}>
        <div style={{ display: 'inline-flex', gap: 6 }}>
          {filterOpts.map((f) => (
            <button
              key={f.v}
              onClick={() => setFilter(f.v)}
              style={{
                padding: '6px 12px', borderRadius: 999, fontSize: 12,
                border: '1px solid ' + (filter === f.v ? 'var(--ink)' : 'var(--line)'),
                background: filter === f.v ? 'var(--ink)' : 'transparent',
                color: filter === f.v ? 'var(--bg)' : 'var(--ink-soft)',
                cursor: 'pointer', fontFamily: 'inherit', fontWeight: 500,
                whiteSpace: 'nowrap',
              }}
            >
              {f.l}
            </button>
          ))}
        </div>
      </div>

      {/* Location filter */}
      {locations.length > 0 && (
        <div className="scroll-x" style={{ marginBottom: 16, paddingBottom: 4 }}>
          <div style={{ display: 'inline-flex', gap: 6 }}>
            <button
              onClick={() => setLocationFilter('all')}
              style={{
                padding: '6px 12px', borderRadius: 999, fontSize: 12,
                border: '1px solid ' + (locationFilter === 'all' ? 'var(--ink)' : 'var(--line)'),
                background: locationFilter === 'all' ? 'var(--ink)' : 'transparent',
                color: locationFilter === 'all' ? 'var(--bg)' : 'var(--ink-soft)',
                cursor: 'pointer', fontFamily: 'inherit', fontWeight: 500,
                whiteSpace: 'nowrap',
                display: 'inline-flex', alignItems: 'center', gap: 5,
              }}
            >
              All locations
            </button>
            {sortedLocations.map((loc) => (
              <button
                key={loc.id}
                onClick={() => setLocationFilter(loc.id)}
                style={{
                  padding: '6px 12px', borderRadius: 999, fontSize: 12,
                  border: '1px solid ' + (locationFilter === loc.id ? 'var(--ink)' : 'var(--line)'),
                  background: locationFilter === loc.id ? 'var(--ink)' : 'transparent',
                  color: locationFilter === loc.id ? 'var(--bg)' : 'var(--ink-soft)',
                  cursor: 'pointer', fontFamily: 'inherit', fontWeight: 500,
                  whiteSpace: 'nowrap',
                  display: 'inline-flex', alignItems: 'center', gap: 5,
                }}
              >
                <LocationIcon name={loc.icon} size={11} />
                {loc.name}
              </button>
            ))}
          </div>
        </div>
      )}

      <div>
        {filtered.length === 0 ? (
          <div style={{ padding: 32, textAlign: 'center', color: 'var(--ink-mute)' }}>
            No items match this filter.
          </div>
        ) : (
          groupProducts(filtered).map((g) => (
            <GroupBlock
              key={g.key}
              group={g}
              locations={locations}
              thumbs={thumbs}
              daysRemainingMap={daysRemainingMap}
              onLogQuick={onLogQuick}
              onRestock={onRestock}
              onMove={onMove}
              onEdit={onEdit}
              onPhotoTap={onPhotoTap}
            />
          ))
        )}
      </div>
    </div>
  );
}
