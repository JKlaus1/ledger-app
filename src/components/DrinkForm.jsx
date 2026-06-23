import React, { useState, useEffect } from 'react';
import { Check, GlassWater } from 'lucide-react';
import { Modal } from './Common';
import { uid, toLocalInputValue, fromLocalInputValue } from '../lib/helpers';
import { DRINK_KINDS, DRINK_SIZES } from '../lib/intake';

// DrinkForm — log a fluid intake (type: 'drink'). Free-standing and
// backdatable, mirroring NoteForm. Intake is tracked to correlate against
// wetting timing and volume over time.
export default function DrinkForm({ open, onClose, onSave, initial }) {
  const [kind, setKind] = useState('water');
  const [size, setSize] = useState('medium');
  const [at, setAt] = useState('');
  const [note, setNote] = useState('');

  useEffect(() => {
    if (!open) return;
    if (initial) {
      setKind(initial.kind || 'water');
      setSize(initial.size || 'medium');
      setAt(toLocalInputValue(initial.timestamp || Date.now()));
      setNote(initial.note || '');
    } else {
      setKind('water');
      setSize('medium');
      setAt(toLocalInputValue(Date.now()));
      setNote('');
    }
  }, [open, initial]);

  const submit = () => {
    const ts = fromLocalInputValue(at) || Date.now();
    onSave({
      id: initial?.id || uid(),
      type: 'drink',
      timestamp: ts,
      kind,
      size,
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
              </button>
            ))}
          </div>
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
