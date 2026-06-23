import React, { useState, useEffect } from 'react';
import { Check, GlassWater } from 'lucide-react';
import { Modal } from './Common';
import { uid, toLocalInputValue, fromLocalInputValue } from '../lib/helpers';
import { DRINK_KINDS, DRINK_SIZES, drinkSizeOz } from '../lib/intake';

// DrinkForm — log a fluid intake (type: 'drink'). Free-standing and
// backdatable. `size` is a quick bucket; the exact-oz field is optional and,
// when filled, becomes the volume used in totals. `presets` supplies the
// per-bucket ounce values shown alongside each size.
export default function DrinkForm({ open, onClose, onSave, initial, presets = null }) {
  const [kind, setKind] = useState('water');
  const [size, setSize] = useState('medium');
  const [oz, setOz] = useState('');
  const [at, setAt] = useState('');
  const [note, setNote] = useState('');

  useEffect(() => {
    if (!open) return;
    if (initial) {
      setKind(initial.kind || 'water');
      setSize(initial.size || 'medium');
      setOz(initial.oz != null ? String(initial.oz) : '');
      setAt(toLocalInputValue(initial.timestamp || Date.now()));
      setNote(initial.note || '');
    } else {
      setKind('water');
      setSize('medium');
      setOz('');
      setAt(toLocalInputValue(Date.now()));
      setNote('');
    }
  }, [open, initial]);

  const submit = () => {
    const ts = fromLocalInputValue(at) || Date.now();
    const exact = Number(oz);
    onSave({
      id: initial?.id || uid(),
      type: 'drink',
      timestamp: ts,
      kind,
      size,
      oz: Number.isFinite(exact) && exact > 0 ? exact : null,
      note: note.trim() || null,
      createdAt: initial?.createdAt || Date.now(),
      updatedAt: Date.now(),
    });
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={initial ? 'Edit drink' : 'Log a drink'}
      footer={
        <>
          <button className="btn btn-ghost" onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" onClick={submit}>
            {initial ? 'Save drink' : 'Add drink'}
          </button>
        </>
      }
    >
      <div style={{ display: 'grid', gap: 14 }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8,
          fontSize: 13, color: 'var(--ink-soft)',
        }}>
          <GlassWater size={14} /> <span>What did you drink?</span>
        </div>

        <div>
          <label className="label">Type</label>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
            {DRINK_KINDS.map((d) => (
              <button
                key={d.value} type="button"
                className={`check-row ${kind === d.value ? 'active' : ''}`}
                onClick={() => setKind(d.value)}
              >
                <span style={{ flex: 1 }}>{d.label}</span>
                {kind === d.value && <Check size={14} />}
              </button>
            ))}
          </div>
        </div>

        <div>
          <label className="label">Size</label>
          <div className="seg" style={{ width: '100%' }}>
            {DRINK_SIZES.map((s) => (
              <button
                key={s.value}
                type="button" style={{ flex: 1 }}
                className={`seg-btn ${size === s.value ? 'active' : ''}`}
                onClick={() => setSize(s.value)}
              >
                {s.label}
                <span style={{ opacity: 0.6, marginLeft: 4 }}>{drinkSizeOz(s.value, presets)}oz</span>
              </button>
            ))}
          </div>
        </div>

        <div>
          <label className="label">Exact amount (oz, optional)</label>
          <input
            className="input"
            type="number"
            inputMode="decimal"
            min="0"
            step="1"
            placeholder={`Defaults to ${drinkSizeOz(size, presets)}oz for ${size}`}
            value={oz}
            onChange={(e) => setOz(e.target.value)}
          />
          <p style={{ fontSize: 11, color: 'var(--ink-mute)', marginTop: 6, fontStyle: 'italic' }}>
            Fill this in when you know the real amount (a 20oz bottle, a 12oz can). Leave blank to use the size estimate.
          </p>
        </div>

        <div>
          <label className="label">When</label>
          <input
            className="input"
            type="datetime-local"
            value={at}
            onChange={(e) => setAt(e.target.value)}
          />
        </div>

        <div>
          <label className="label">Note (optional)</label>
          <input
            className="input"
            placeholder="e.g. big glass before bed"
            value={note}
            onChange={(e) => setNote(e.target.value)}
          />
        </div>
      </div>
    </Modal>
  );
}
