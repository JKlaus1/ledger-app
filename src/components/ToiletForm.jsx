import React, { useState, useEffect } from 'react';
import { Check, Toilet } from 'lucide-react';
import { Modal } from './Common';
import { uid, toLocalInputValue, fromLocalInputValue } from '../lib/helpers';
import { TOILET_WHAT } from '../lib/wetting';
import { CONTEXTS } from '../lib/session';

// ToiletForm — log a toilet use when no diaper is on (type: 'toilet').
// Free-standing and backdatable, mirroring DrinkForm/NoteForm. Toilet uses
// done while wearing a diaper are still logged inline on that wear session;
// this is for the times there's nothing on.
export default function ToiletForm({ open, onClose, onSave, initial }) {
  const [what, setWhat] = useState('pee');
  const [whereContext, setWhereContext] = useState('');
  const [at, setAt] = useState('');
  const [note, setNote] = useState('');

  useEffect(() => {
    if (!open) return;
    if (initial) {
      setWhat(initial.what || 'pee');
      setWhereContext(initial.context || '');
      setAt(toLocalInputValue(initial.timestamp || Date.now()));
      setNote(initial.note || '');
    } else {
      setWhat('pee');
      setWhereContext('');
      setAt(toLocalInputValue(Date.now()));
      setNote('');
    }
  }, [open, initial]);

  const submit = () => {
    const ts = fromLocalInputValue(at) || Date.now();
    onSave({
      id: initial?.id || uid(),
      type: 'toilet',
      timestamp: ts,
      what,
      context: whereContext || null,
      note: note.trim() || null,
      createdAt: initial?.createdAt || Date.now(),
      updatedAt: Date.now(),
    });
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={initial ? 'Edit toilet use' : 'Log a toilet use'}
      footer={
        <>
          <button className="btn btn-ghost" onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" onClick={submit}>
            {initial ? 'Save' : 'Add'}
          </button>
        </>
      }
    >
      <div style={{ display: 'grid', gap: 14 }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8,
          fontSize: 13, color: 'var(--ink-soft)',
        }}>
          <Toilet size={14} /> <span>Toilet use with no diaper on.</span>
        </div>

        <div>
          <label className="label">What did you do?</label>
          <div className="seg" style={{ width: '100%' }}>
            {TOILET_WHAT.map((t) => (
              <button
                key={t.value}
                type="button" style={{ flex: 1 }}
                className={`seg-btn ${what === t.value ? 'active' : ''}`}
                onClick={() => setWhat(t.value)}
              >
                {t.label}
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
          <label className="label">Where were you? (optional)</label>
          <select
            className="select"
            value={whereContext}
            onChange={(e) => setWhereContext(e.target.value)}
          >
            <option value="">Not set</option>
            {CONTEXTS.map((c) => (
              <option key={c.value} value={c.value}>{c.label}</option>
            ))}
          </select>
        </div>

        <div>
          <label className="label">Note (optional)</label>
          <input
            className="input"
            placeholder="e.g. made it in time, close call…"
            value={note}
            onChange={(e) => setNote(e.target.value)}
          />
        </div>
      </div>
    </Modal>
  );
}
