import React, { useState, useEffect } from 'react';
import { Sun, Moon, Check } from 'lucide-react';
import { Modal } from './Common';
import { LocationIcon } from './LocationManager';
import {
  PERFORMANCE, ABSORBENCY, uid, guessPeriod,
  toLocalInputValue, fromLocalInputValue,
  productDisplayName, stockAt,
} from '../lib/helpers';

export default function LogForm({
  open, onClose, onSave, products, locations, initial, defaultProductId,
}) {
  const blank = {
    productId: defaultProductId || (products[0]?.id || ''),
    locationId: '', // ALWAYS ASK - no default
    timestamp: Date.now(),
    period: guessPeriod(Date.now()),
    performance: 'used',
    notes: '',
    decrementInventory: true,
  };
  const [form, setForm] = useState(blank);

  useEffect(() => {
    if (open) {
      if (initial) {
        setForm({
          productId: initial.productId,
          locationId: initial.locationId || '',
          timestamp: initial.timestamp,
          period: initial.period,
          performance: initial.performance || 'used',
          notes: initial.notes || '',
          decrementInventory: false,
        });
      } else {
        setForm({
          ...blank,
          productId: defaultProductId || (products[0]?.id || ''),
          locationId: '',
          timestamp: Date.now(),
          period: guessPeriod(Date.now()),
        });
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, initial, defaultProductId]);

  const update = (k, v) => setForm((f) => ({ ...f, [k]: v }));

  const product = products.find((p) => p.id === form.productId);
  // Limit location choices to those where this product currently has stock
  const availableLocations = locations
    .filter((loc) => initial ? true : stockAt(product, loc.id) > 0)
    .sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0));

  const valid = form.productId && form.locationId;

  const submit = () => {
    if (!valid) return;
    const base = initial ? { ...initial } : {};
    const out = {
      ...base,
      id: initial?.id || uid(),
      type: initial?.type && initial.type !== 'move' ? initial.type : 'use',
      productId: form.productId,
      locationId: form.locationId,
      timestamp: form.timestamp,
      period: form.period,
      performance: form.performance,
      notes: form.notes.trim(),
    };
    // For wear-based entries, keep the put-on time in sync with the edited time
    if (initial?.putOnAt) out.putOnAt = form.timestamp;
    onSave(out, form.decrementInventory && !initial);
  };

  if (open && (products.length === 0 || locations.length === 0)) {
    return (
      <Modal
        open={open} onClose={onClose} title="Log usage"
        footer={<button className="btn btn-primary" onClick={onClose}>OK</button>}
      >
        <p style={{ color: 'var(--ink-soft)', margin: 0 }}>
          {locations.length === 0
            ? 'Add at least one location before logging usage.'
            : 'Add a product to your inventory before logging usage.'}
        </p>
      </Modal>
    );
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={initial ? 'Edit log entry' : 'Log a use'}
      footer={
        <>
          <button className="btn btn-ghost" onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" onClick={submit} disabled={!valid}>
            {initial ? 'Save changes' : 'Save log'}
          </button>
        </>
      }
    >
      <div style={{ display: 'grid', gap: 14 }}>
        <div>
          <label className="label">Product</label>
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
          <label className="label">From which location?</label>
          {availableLocations.length === 0 ? (
            <div className="card" style={{ padding: 12, fontSize: 13, color: 'var(--ink-soft)' }}>
              No location currently has this product in stock.
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
          <label className="label">When</label>
          <input
            className="input" type="datetime-local"
            value={toLocalInputValue(form.timestamp)}
            onChange={(e) => update('timestamp', fromLocalInputValue(e.target.value))}
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
          <label className="label">How did it perform?</label>
          <div style={{ display: 'grid', gap: 8 }}>
            {PERFORMANCE.map((p) => (
              <button
                key={p.value} type="button"
                className={`check-row ${form.performance === p.value ? 'active' : ''}`}
                onClick={() => update('performance', p.value)}
              >
                <span style={{ flex: 1 }}>{p.label}</span>
                {form.performance === p.value && <Check size={14} />}
              </button>
            ))}
          </div>
        </div>

        <div>
          <label className="label">Notes (optional)</label>
          <textarea
            className="textarea"
            placeholder="Any observations about fit, comfort, time worn…"
            value={form.notes}
            onChange={(e) => update('notes', e.target.value)}
          />
        </div>

        {!initial && (
          <label style={{
            display: 'flex', alignItems: 'center', gap: 10,
            cursor: 'pointer', fontSize: 14, color: 'var(--ink-soft)',
          }}>
            <input
              type="checkbox"
              checked={form.decrementInventory}
              onChange={(e) => update('decrementInventory', e.target.checked)}
            />
            Subtract one from this location's stock
          </label>
        )}
      </div>
    </Modal>
  );
}
