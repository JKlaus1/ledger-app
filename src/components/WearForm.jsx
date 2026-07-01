import React, { useState, useEffect } from 'react';
import { Sun, Moon, Check, Package, MapPin } from 'lucide-react';
import { Modal, ProductThumb } from './Common';
import { LocationIcon } from './LocationManager';
import {
  ABSORBENCY, uid, guessPeriod,
  toLocalInputValue, fromLocalInputValue,
  stockAt, totalStock,
} from '../lib/helpers';
import { CONTEXTS } from '../lib/session';
import { groupProducts } from '../lib/variants';

// WearForm — "put one on". Creates an active wear session: a log entry
// with putOnAt set and takenOffAt: null. Stock is decremented at the
// chosen location when saved.
//
// Two ways to get there, toggled by `mode`:
//   'product'  — pick the product/variant first, then see which locations
//                actually stock it. The original flow; still the default.
//   'location' — pick a location first, then see only what's in stock
//                there. Handy when you know where you're grabbing from but
//                not which variant is left.
export default function WearForm({
  open, onClose, onSave, products, locations, defaultProductId, title,
}) {
  const makeBlank = () => ({
    productId: defaultProductId || (products[0]?.id || ''),
    locationId: '', // ALWAYS ASK — no default
    putOnAt: Date.now(),
    period: guessPeriod(Date.now()),
    booster: false,
    context: '',
    notes: '',
  });
  const [form, setForm] = useState(makeBlank());
  const [mode, setMode] = useState('product');

  useEffect(() => {
    if (open) {
      setMode('product');
      setForm({
        ...makeBlank(),
        productId: defaultProductId || (products[0]?.id || ''),
        putOnAt: Date.now(),
        period: guessPeriod(Date.now()),
      });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, defaultProductId]);

  const update = (k, v) => setForm((f) => ({ ...f, [k]: v }));

  // Switching modes only touches the product/location picks — time, period,
  // booster, context and notes carry over untouched either way.
  const switchMode = (m) => {
    if (m === mode) return;
    setMode(m);
    setForm((f) => ({
      ...f,
      productId: m === 'product' ? (defaultProductId || (products[0]?.id || '')) : '',
      locationId: '',
    }));
  };

  const product = products.find((p) => p.id === form.productId);

  // === Product-first (mode: 'product') ===
  // Variant grouping: pick a model first, then a variant within it.
  const groups = groupProducts(products);
  const currentGroup =
    groups.find((g) => g.products.some((p) => p.id === form.productId)) || null;

  // Select a specific product; drop the chosen location if it has no stock for it.
  const selectProduct = (id) => setForm((f) => {
    const np = products.find((p) => p.id === id);
    const keepLoc = np && stockAt(np, f.locationId) > 0 ? f.locationId : '';
    return { ...f, productId: id, locationId: keepLoc };
  });

  // Select a model (group); default to the variant with the most stock on hand.
  const selectGroup = (key) => {
    const g = groups.find((x) => x.key === key);
    if (!g) return;
    const best = [...g.products].sort((a, b) => totalStock(b) - totalStock(a))[0];
    selectProduct(best?.id || g.products[0].id);
  };

  const availableLocations = locations
    .filter((loc) => stockAt(product, loc.id) > 0)
    .sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0));

  // === Location-first (mode: 'location') ===
  const sortedLocationsAll = [...locations].sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0));
  const totalAtLocation = (locId) => products.reduce((s, p) => s + stockAt(p, locId), 0);

  const selectLocation = (locId) => setForm((f) => ({ ...f, locationId: locId, productId: '' }));

  const productsAtLocation = form.locationId
    ? products.filter((p) => stockAt(p, form.locationId) > 0)
    : [];
  const groupsAtLocation = groupProducts(productsAtLocation);
  const currentGroupAtLocation =
    groupsAtLocation.find((g) => g.products.some((p) => p.id === form.productId)) || null;

  // Select a model at this location; default to its best-stocked variant HERE.
  const selectGroupAtLocation = (key) => {
    const g = groupsAtLocation.find((x) => x.key === key);
    if (!g) return;
    const best = [...g.products].sort(
      (a, b) => stockAt(b, form.locationId) - stockAt(a, form.locationId)
    )[0];
    update('productId', best?.id || g.products[0].id);
  };

  const valid = form.productId && form.locationId && product;

  const submit = () => {
    if (!valid) return;
    onSave({
      id: uid(),
      type: 'use',
      productId: form.productId,
      locationId: form.locationId,
      putOnAt: form.putOnAt,
      takenOffAt: null,
      timestamp: form.putOnAt, // kept in sync with put-on for sorting/filtering
      period: form.period,
      performance: null, // recorded at take-off
      booster: !!form.booster,
      context: form.context || null,
      notes: form.notes.trim(),
    });
  };

  if (open && (products.length === 0 || locations.length === 0)) {
    return (
      <Modal
        open={open} onClose={onClose} title="Put one on"
        footer={<button className="btn btn-primary" onClick={onClose}>OK</button>}
      >
        <p style={{ color: 'var(--ink-soft)', margin: 0 }}>
          {locations.length === 0
            ? 'Add at least one location first.'
            : 'Add a product to your inventory first.'}
        </p>
      </Modal>
    );
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={title || 'Put one on'}
      footer={
        <>
          <button className="btn btn-ghost" onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" onClick={submit} disabled={!valid}>
            Put on
          </button>
        </>
      }
    >
      <div style={{ display: 'grid', gap: 14 }}>
        <div>
          <label className="label">Choose by</label>
          <div className="seg" style={{ width: '100%' }}>
            <button
              type="button" style={{ flex: 1 }}
              className={`seg-btn ${mode === 'product' ? 'active' : ''}`}
              onClick={() => switchMode('product')}
            >
              <Package size={14} /> Product
            </button>
            <button
              type="button" style={{ flex: 1 }}
              className={`seg-btn ${mode === 'location' ? 'active' : ''}`}
              onClick={() => switchMode('location')}
            >
              <MapPin size={14} /> Location
            </button>
          </div>
        </div>

        {mode === 'product' ? (
          <>
            <div>
              <label className="label">Which product?</label>
              <select
                className="select"
                value={currentGroup?.key || ''}
                onChange={(e) => selectGroup(e.target.value)}
              >
                {groups.map((g) => (
                  <option key={g.key} value={g.key}>
                    {g.label}{g.isMulti ? ` · ${g.products.length} variants` : ''}
                  </option>
                ))}
              </select>
              {product && (
                <div style={{ fontSize: 11, color: 'var(--ink-mute)', marginTop: 6, fontStyle: 'italic' }}>
                  {product.size} · {ABSORBENCY.find((a) => a.value === product.absorbency)?.label}
                </div>
              )}
            </div>

            {currentGroup?.isMulti && (
              <div>
                <label className="label">Which variant?</label>
                <div style={{ display: 'grid', gap: 8 }}>
                  {currentGroup.products.map((p) => {
                    const st = totalStock(p);
                    return (
                      <button
                        key={p.id}
                        type="button"
                        className={`check-row ${form.productId === p.id ? 'active' : ''}`}
                        onClick={() => selectProduct(p.id)}
                      >
                        <ProductThumb product={p} size={20} />
                        <span style={{ flex: 1 }}>{(p.print && p.print.trim()) || 'Default'}</span>
                        <span style={{ fontSize: 12, color: 'var(--ink-mute)', marginRight: 6 }}>
                          {st} total
                        </span>
                        {form.productId === p.id && <Check size={14} />}
                      </button>
                    );
                  })}
                </div>
              </div>
            )}

            <div>
              <label className="label">Taking it from where?</label>
              {availableLocations.length === 0 ? (
                <div className="card" style={{ padding: 12, fontSize: 13, color: 'var(--ink-soft)' }}>
                  No location currently has this product in stock. Restock first, or pick another product.
                </div>
              ) : (
                <div style={{ display: 'grid', gap: 8 }}>
                  {availableLocations.map((loc) => {
                    const stock = stockAt(product, loc.id);
                    return (
                      <button
                        key={loc.id}
                        type="button"
                        className={`check-row ${form.locationId === loc.id ? 'active' : ''}`}
                        onClick={() => update('locationId', loc.id)}
                      >
                        <LocationIcon name={loc.icon} size={14} style={{ color: 'var(--ink-soft)' }} />
                        <span style={{ flex: 1 }}>{loc.name}</span>
                        <span style={{ fontSize: 12, color: 'var(--ink-mute)', marginRight: 6 }}>
                          {stock} on hand
                        </span>
                        {form.locationId === loc.id && <Check size={14} />}
                      </button>
                    );
                  })}
                </div>
              )}
            </div>
          </>
        ) : (
          <>
            <div>
              <label className="label">Which location?</label>
              <div style={{ display: 'grid', gap: 8 }}>
                {sortedLocationsAll.map((loc) => {
                  const total = totalAtLocation(loc.id);
                  return (
                    <button
                      key={loc.id}
                      type="button"
                      className={`check-row ${form.locationId === loc.id ? 'active' : ''}`}
                      onClick={() => selectLocation(loc.id)}
                    >
                      <LocationIcon name={loc.icon} size={14} style={{ color: 'var(--ink-soft)' }} />
                      <span style={{ flex: 1 }}>{loc.name}</span>
                      <span style={{ fontSize: 12, color: 'var(--ink-mute)', marginRight: 6 }}>
                        {total} on hand
                      </span>
                      {form.locationId === loc.id && <Check size={14} />}
                    </button>
                  );
                })}
              </div>
            </div>

            {form.locationId && (
              <div>
                <label className="label">What's available there?</label>
                {groupsAtLocation.length === 0 ? (
                  <div className="card" style={{ padding: 12, fontSize: 13, color: 'var(--ink-soft)' }}>
                    Nothing in stock at this location right now. Restock here, or pick another location.
                  </div>
                ) : (
                  <>
                    <select
                      className="select"
                      value={currentGroupAtLocation?.key || ''}
                      onChange={(e) => selectGroupAtLocation(e.target.value)}
                    >
                      <option value="" disabled>Choose one…</option>
                      {groupsAtLocation.map((g) => (
                        <option key={g.key} value={g.key}>
                          {g.label}{g.isMulti ? ` · ${g.products.length} variants` : ''}
                        </option>
                      ))}
                    </select>
                    {product && (
                      <div style={{ fontSize: 11, color: 'var(--ink-mute)', marginTop: 6, fontStyle: 'italic' }}>
                        {product.size} · {ABSORBENCY.find((a) => a.value === product.absorbency)?.label}
                      </div>
                    )}
                  </>
                )}
              </div>
            )}

            {currentGroupAtLocation?.isMulti && (
              <div>
                <label className="label">Which variant?</label>
                <div style={{ display: 'grid', gap: 8 }}>
                  {currentGroupAtLocation.products.map((p) => {
                    const st = stockAt(p, form.locationId);
                    return (
                      <button
                        key={p.id}
                        type="button"
                        className={`check-row ${form.productId === p.id ? 'active' : ''}`}
                        onClick={() => update('productId', p.id)}
                      >
                        <ProductThumb product={p} size={20} />
                        <span style={{ flex: 1 }}>{(p.print && p.print.trim()) || 'Default'}</span>
                        <span style={{ fontSize: 12, color: 'var(--ink-mute)', marginRight: 6 }}>
                          {st} here
                        </span>
                        {form.productId === p.id && <Check size={14} />}
                      </button>
                    );
                  })}
                </div>
              </div>
            )}
          </>
        )}

        <div>
          <label className="label">When did you put it on?</label>
          <input
            className="input" type="datetime-local"
            value={toLocalInputValue(form.putOnAt)}
            onChange={(e) => update('putOnAt', fromLocalInputValue(e.target.value))}
          />
        </div>

        <div>
          <label className="label">Period</label>
          <div className="seg" style={{ width: '100%' }}>
            <button
              type="button" style={{ flex: 1 }}
              className={`seg-btn ${form.period === 'day' ? 'active' : ''}`}
              onClick={() => update('period', 'day')}
            >
              <Sun size={14} /> Daytime
            </button>
            <button
              type="button" style={{ flex: 1 }}
              className={`seg-btn ${form.period === 'night' ? 'active' : ''}`}
              onClick={() => update('period', 'night')}
            >
              <Moon size={14} /> Overnight
            </button>
          </div>
        </div>

        <div>
          <label className="label">Booster / doubler added?</label>
          <button
            type="button"
            className={`check-row ${form.booster ? 'active' : ''}`}
            onClick={() => update('booster', !form.booster)}
          >
            <span style={{ flex: 1 }}>
              {form.booster ? 'Yes — booster added' : 'No booster'}
            </span>
            {form.booster && <Check size={14} />}
          </button>
        </div>

        <div>
          <label className="label">Context (optional)</label>
          <select
            className="select"
            value={form.context}
            onChange={(e) => update('context', e.target.value)}
          >
            <option value="">Not set</option>
            {CONTEXTS.map((c) => (
              <option key={c.value} value={c.value}>{c.label}</option>
            ))}
          </select>
        </div>

        <div>
          <label className="label">Notes (optional)</label>
          <textarea
            className="textarea"
            placeholder="Anything you want to remember about this one…"
            value={form.notes}
            onChange={(e) => update('notes', e.target.value)}
          />
        </div>
      </div>
    </Modal>
  );
}
