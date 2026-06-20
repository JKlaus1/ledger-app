import React, { useState, useEffect } from 'react';
import { StickyNote } from 'lucide-react';
import { Modal } from './Common';
import {
  uid, toLocalInputValue, fromLocalInputValue, productDisplayName,
} from '../lib/helpers';

// A note is its own kind of log (type: 'note'): a free-standing, timestamped
// entry. When opened from the diaper on now it carries that wear's product /
// location / session so it reads as "a note about this wear"; opened on its
// own it's a general context note with an editable time (so it can be backdated).
export default function NoteForm({
  open, onClose, onSave, locations, products, initial, context,
}) {
  const [text, setText] = useState('');
  const [at, setAt] = useState('');
  const [locationId, setLocationId] = useState('');

  useEffect(() => {
    if (!open) return;
    if (initial) {
      setText(initial.text || '');
      setAt(toLocalInputValue(initial.timestamp || Date.now()));
      setLocationId(initial.locationId || '');
    } else {
      setText('');
      setAt(toLocalInputValue(Date.now()));
      setLocationId(context?.locationId || '');
    }
  }, [open, initial, context]);

  const aboutProductId = initial ? initial.productId : context?.productId;
  const aboutProduct = aboutProductId ? (products || []).find((p) => p.id === aboutProductId) : null;
  const sessionId = initial ? initial.sessionId : context?.sessionId;

  const valid = text.trim().length > 0;

  const submit = () => {
    if (!valid) return;
    const ts = fromLocalInputValue(at) || Date.now();
    onSave({
      id: initial?.id || uid(),
      type: 'note',
      text: text.trim(),
      timestamp: ts,
      productId: aboutProductId || null,
      locationId: locationId || null,
      sessionId: sessionId || null,
      createdAt: initial?.createdAt || Date.now(),
      updatedAt: Date.now(),
    });
  };

  const sortedLocations = [...(locations || [])].sort(
    (a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)
  );

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={initial ? 'Edit note' : 'Add a note'}
      footer={
        <>
          <button className="btn btn-ghost" onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" disabled={!valid} onClick={submit}>
            {initial ? 'Save note' : 'Add note'}
          </button>
        </>
      }
    >
      <div style={{ display: 'grid', gap: 14 }}>
        {aboutProduct && (
          <div style={{
            display: 'flex', alignItems: 'center', gap: 8,
            fontSize: 13, color: 'var(--ink-soft)',
          }}>
            <StickyNote size={14} />
            <span>Note on: <strong>{productDisplayName(aboutProduct)}</strong></span>
          </div>
        )}

        <div>
          <label className="label">Note</label>
          <textarea
            className="textarea"
            placeholder="Anything worth remembering — context, what you noticed, how it went…"
            value={text}
            onChange={(e) => setText(e.target.value)}
            autoFocus
          />
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

        {sortedLocations.length > 0 && (
          <div>
            <label className="label">Location (optional)</label>
            <select
              className="select"
              value={locationId}
              onChange={(e) => setLocationId(e.target.value)}
            >
              <option value="">None</option>
              {sortedLocations.map((loc) => (
                <option key={loc.id} value={loc.id}>{loc.name}</option>
              ))}
            </select>
          </div>
        )}
      </div>
    </Modal>
  );
}
