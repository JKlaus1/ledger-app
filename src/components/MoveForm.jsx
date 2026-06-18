import React, { useState, useEffect } from 'react';
import { ArrowRight, Check } from 'lucide-react';
import { Modal } from './Common';
import { LocationIcon } from './LocationManager';
import {
  ABSORBENCY, productDisplayName, stockAt, uid,
} from '../lib/helpers';

export default function MoveForm({
  open, onClose, onSave, products, locations, initialProductId,
}) {
  const [productId, setProductId] = useState('');
  const [fromId, setFromId] = useState('');
  const [toId, setToId] = useState('');
  const [quantity, setQuantity] = useState(1);
  const [notes, setNotes] = useState('');

  useEffect(() => {
    if (open) {
      setProductId(initialProductId || products[0]?.id || '');
      setFromId('');
      setToId('');
      setQuantity(1);
      setNotes('');
    }
  }, [open, initialProductId, products]);

  const product = products.find((p) => p.id === productId);
  const sortedLocations = [...locations].sort(
    (a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)
  );

  const fromStock = product && fromId ? stockAt(product, fromId) : 0;
  const numQty = Number(quantity) || 0;

  const valid =
    productId &&
    fromId &&
    toId &&
    fromId !== toId &&
    numQty > 0 &&
    numQty <= fromStock;

  const submit = () => {
    if (!valid) return;
    onSave({
      id: uid(),
      type: 'move',
      productId,
      fromLocationId: fromId,
      toLocationId: toId,
      quantity: numQty,
      timestamp: Date.now(),
      notes: notes.trim(),
    });
  };

  if (open && (products.length === 0 || locations.length < 2)) {
    return (
      <Modal
        open={open} onClose={onClose} title="Move stock"
        footer={<button className="btn btn-primary" onClick={onClose}>OK</button>}
      >
        <p style={{ color: 'var(--ink-soft)', margin: 0 }}>
          {locations.length < 2
            ? 'You need at least two locations before you can move stock between them.'
            : 'Add some products first.'}
        </p>
      </Modal>
    );
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Move stock"
      footer={
        <>
          <button className="btn btn-ghost" onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" onClick={submit} disabled={!valid}>
            Move {numQty > 0 ? numQty : ''}
          </button>
        </>
      }
    >
      <div style={{ display: 'grid', gap: 14 }}>
        <div>
          <label className="label">Product</label>
          <select
            className="select"
            value={productId}
            onChange={(e) => {
              setProductId(e.target.value);
              setFromId('');
              setToId('');
            }}
          >
            {products.map((p) => (
              <option key={p.id} value={p.id}>
                {productDisplayName(p)} — {p.size}, {ABSORBENCY.find((a) => a.value === p.absorbency)?.label}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="label">From</label>
          <div style={{ display: 'grid', gap: 8 }}>
            {sortedLocations.map((loc) => {
              const stock = stockAt(product, loc.id);
              const disabled = stock === 0;
              return (
                <button
                  key={loc.id}
                  type="button"
                  disabled={disabled}
                  className={`check-row ${fromId === loc.id ? 'active' : ''}`}
                  onClick={() => {
                    setFromId(loc.id);
                    if (toId === loc.id) setToId('');
                  }}
                  style={{ opacity: disabled ? 0.45 : 1 }}
                >
                  <LocationIcon name={loc.icon} size={14} style={{ color: 'var(--ink-soft)' }} />
                  <span style={{ flex: 1 }}>{loc.name}</span>
                  <span style={{ fontSize: 12, color: 'var(--ink-mute)', marginRight: 6 }}>
                    {stock} on hand
                  </span>
                  {fromId === loc.id && <Check size={14} />}
                </button>
              );
            })}
          </div>
        </div>

        {fromId && (
          <>
            <div style={{
              display: 'flex', justifyContent: 'center',
              color: 'var(--ink-mute)',
            }}>
              <ArrowRight size={18} />
            </div>

            <div>
              <label className="label">To</label>
              <div style={{ display: 'grid', gap: 8 }}>
                {sortedLocations
                  .filter((l) => l.id !== fromId)
                  .map((loc) => (
                    <button
                      key={loc.id}
                      type="button"
                      className={`check-row ${toId === loc.id ? 'active' : ''}`}
                      onClick={() => setToId(loc.id)}
                    >
                      <LocationIcon name={loc.icon} size={14} style={{ color: 'var(--ink-soft)' }} />
                      <span style={{ flex: 1 }}>{loc.name}</span>
                      {toId === loc.id && <Check size={14} />}
                    </button>
                  ))}
              </div>
            </div>

            <div>
              <label className="label">How many to move?</label>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <input
                  className="input"
                  type="number"
                  min="1"
                  max={fromStock}
                  value={quantity}
                  onChange={(e) => setQuantity(e.target.value)}
                  style={{ flex: 1 }}
                />
                <button
                  type="button"
                  className="btn btn-ghost"
                  onClick={() => setQuantity(fromStock)}
                  style={{ fontSize: 13, padding: '8px 12px' }}
                >
                  All ({fromStock})
                </button>
              </div>
              {numQty > fromStock && (
                <div style={{ fontSize: 12, color: 'var(--danger)', marginTop: 6 }}>
                  Not enough stock — only {fromStock} available.
                </div>
              )}
            </div>

            <div>
              <label className="label">Notes (optional)</label>
              <textarea
                className="textarea"
                placeholder="e.g. Restocking from bulk order"
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
              />
            </div>
          </>
        )}
      </div>
    </Modal>
  );
}
