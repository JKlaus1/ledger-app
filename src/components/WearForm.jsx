import React, { useState, useEffect } from 'react';
import { Sun, Moon, Check } from 'lucide-react';
import { Modal } from './Common';
import { LocationIcon } from './LocationManager';
import {
  ABSORBENCY, uid, guessPeriod,
  toLocalInputValue, fromLocalInputValue,
  productDisplayName, stockAt,
} from '../lib/helpers';

// WearForm — "put one on". Creates an active wear session: a log entry
// with putOnAt set and takenOffAt: null. Stock is decremented at the
// chosen location when saved.
export default function WearForm({
  open, onClose, onSave, products, locations, defaultProductId, title,
}) {
  const makeBlank = () => ({
    productId: defaultProductId || (products[0]?.id || ''),
    locationId: '', // ALWAYS ASK — no default
    putOnAt: Date.now(),
    period: guessPeriod(Date.now()),
    notes: '',
  });
  const [form, setForm] = useState(makeBlank());

  useEffect(() => {
    if (open) {
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

  const product = products.find((p) => p.id === form.productId);
  const availableLocations = locations
    .filter((loc) => stockAt(product, loc.id) > 0)
    .sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0));

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
          <label className="label">Which product?</label>
          <select
            className="select"
            value={form.productId}
            onChange={(e) => update('productId', e.target.value)}
          >
            {products.map((p) => (
              <option key={p.id} value={p.id}>
                {productDisplayName(p)} — {p.size}, {ABSORBENCY.find((a) => a.value === p.absorbency)?.label}
              </option>
            ))}
          </select>
        </div>

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
