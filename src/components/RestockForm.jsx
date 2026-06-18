import React, { useState, useEffect } from 'react';
import { Check } from 'lucide-react';
import { Modal } from './Common';
import { LocationIcon } from './LocationManager';
import { productDisplayName, totalStock, stockAt } from '../lib/helpers';

export default function RestockForm({
  open, onClose, product, locations, onSave, defaultLocationId,
}) {
  const [mode, setMode] = useState('add'); // add | set
  const [locationId, setLocationId] = useState('');
  const [value, setValue] = useState('');

  useEffect(() => {
    if (open) {
      setMode('add');
      setLocationId(defaultLocationId || locations[0]?.id || '');
      setValue(product?.packSize ? String(product.packSize) : '');
    }
  }, [open, product, defaultLocationId, locations]);

  if (!product) return null;

  const sortedLocations = [...locations].sort(
    (a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)
  );

  const submit = () => {
    const n = Number(value);
    if (Number.isNaN(n) || n < 0 || !locationId) return;
    const currentAtLocation = stockAt(product, locationId);
    const newAtLocation = mode === 'add' ? currentAtLocation + n : n;
    const newStock = {
      ...product.stock,
      [locationId]: Math.max(0, newAtLocation),
    };
    onSave({ ...product, stock: newStock });
  };

  const valid = locationId && value !== '' && Number(value) >= 0;

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Adjust stock"
      footer={
        <>
          <button className="btn btn-ghost" onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" onClick={submit} disabled={!valid}>Save</button>
        </>
      }
    >
      <div style={{ display: 'grid', gap: 14 }}>
        <div>
          <div className="eyebrow" style={{ marginBottom: 4 }}>{productDisplayName(product)}</div>
          <div className="num" style={{ fontSize: 28 }}>
            {totalStock(product)}{' '}
            <span style={{ fontSize: 13, color: 'var(--ink-mute)', fontFamily: 'inherit' }}>
              total across all locations
            </span>
          </div>
        </div>

        <div>
          <label className="label">Location</label>
          <div style={{ display: 'grid', gap: 8 }}>
            {sortedLocations.map((loc) => {
              const stock = stockAt(product, loc.id);
              return (
                <button
                  key={loc.id}
                  type="button"
                  className={`check-row ${locationId === loc.id ? 'active' : ''}`}
                  onClick={() => setLocationId(loc.id)}
                >
                  <LocationIcon name={loc.icon} size={14} style={{ color: 'var(--ink-soft)' }} />
                  <span style={{ flex: 1 }}>{loc.name}</span>
                  <span style={{ fontSize: 12, color: 'var(--ink-mute)', marginRight: 6 }}>
                    {stock} here
                  </span>
                  {locationId === loc.id && <Check size={14} />}
                </button>
              );
            })}
          </div>
        </div>

        <div className="seg" style={{ width: '100%' }}>
          <button
            type="button" style={{ flex: 1 }}
            className={`seg-btn ${mode === 'add' ? 'active' : ''}`}
            onClick={() => setMode('add')}
          >
            Add stock
          </button>
          <button
            type="button" style={{ flex: 1 }}
            className={`seg-btn ${mode === 'set' ? 'active' : ''}`}
            onClick={() => setMode('set')}
          >
            Set exact count
          </button>
        </div>

        <div>
          <label className="label">{mode === 'add' ? 'How many to add' : 'New total at this location'}</label>
          <input
            className="input" type="number" min="0"
            value={value}
            onChange={(e) => setValue(e.target.value)}
            autoFocus
          />
          {mode === 'add' && product.packSize && (
            <p style={{ fontSize: 12, color: 'var(--ink-mute)', marginTop: 6 }}>
              Pack size: {product.packSize}
            </p>
          )}
        </div>
      </div>
    </Modal>
  );
}
