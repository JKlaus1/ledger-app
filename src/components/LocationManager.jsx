import React, { useState, useEffect } from 'react';
import { Plus, Pencil, Trash2, ChevronUp, ChevronDown, Home, Briefcase, Truck, Car, Box, Star, Building2, Bed, ShoppingBag, Dumbbell, Archive, MapPin } from 'lucide-react';
import { Modal, ConfirmDialog } from './Common';
import { uid } from '../lib/helpers';

// Available icons for locations - keyed by name string
const ICONS = {
  home: Home, briefcase: Briefcase, truck: Truck, car: Car,
  box: Box, star: Star, building: Building2, bed: Bed,
  bag: ShoppingBag, gym: Dumbbell, archive: Archive, pin: MapPin,
};

export const LocationIcon = ({ name, size = 14, style = {} }) => {
  const Icon = ICONS[name] || MapPin;
  return <Icon size={size} style={style} />;
};

function LocationForm({ open, onClose, onSave, initial }) {
  const [name, setName] = useState('');
  const [icon, setIcon] = useState('home');
  const [notes, setNotes] = useState('');

  useEffect(() => {
    if (open) {
      setName(initial?.name || '');
      setIcon(initial?.icon || 'home');
      setNotes(initial?.notes || '');
    }
  }, [open, initial]);

  const valid = name.trim().length > 0;

  const submit = () => {
    if (!valid) return;
    onSave({
      id: initial?.id || uid(),
      name: name.trim(),
      icon,
      notes: notes.trim(),
      createdAt: initial?.createdAt || Date.now(),
      sortOrder: initial?.sortOrder ?? Date.now(),
    });
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={initial ? 'Edit location' : 'Add location'}
      footer={
        <>
          <button className="btn btn-ghost" onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" disabled={!valid} onClick={submit}>
            {initial ? 'Save changes' : 'Add location'}
          </button>
        </>
      }
    >
      <div style={{ display: 'grid', gap: 14 }}>
        <div>
          <label className="label">Name</label>
          <input
            className="input"
            placeholder="e.g. Closet, Truck, Work bag"
            value={name}
            onChange={(e) => setName(e.target.value)}
            autoFocus={!initial}
          />
        </div>
        <div>
          <label className="label">Icon</label>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
            {Object.keys(ICONS).map((key) => {
              const Icon = ICONS[key];
              return (
                <button
                  key={key}
                  type="button"
                  onClick={() => setIcon(key)}
                  style={{
                    width: 40, height: 40,
                    borderRadius: 8,
                    border: '1px solid ' + (icon === key ? 'var(--ink)' : 'var(--line)'),
                    background: icon === key ? 'var(--ink)' : 'var(--surface)',
                    color: icon === key ? 'var(--bg)' : 'var(--ink-soft)',
                    cursor: 'pointer',
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                  }}
                >
                  <Icon size={18} />
                </button>
              );
            })}
          </div>
        </div>
        <div>
          <label className="label">Notes (optional)</label>
          <textarea
            className="textarea"
            placeholder="Anything to remember about this location"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
          />
        </div>
      </div>
    </Modal>
  );
}

export default function LocationManager({ open, onClose, locations, onSave, onDelete, onReorder, products }) {
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState(null);
  const [confirmDel, setConfirmDel] = useState(null);

  // Check if a location has stock — if so, deletion is blocked
  const hasStock = (locationId) => {
    return products.some((p) => (p.stock?.[locationId] || 0) > 0);
  };

  const sorted = [...locations].sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0));

  const moveUp = (idx) => {
    if (idx === 0) return;
    const reordered = [...sorted];
    [reordered[idx - 1], reordered[idx]] = [reordered[idx], reordered[idx - 1]];
    onReorder(reordered.map((l, i) => ({ ...l, sortOrder: i })));
  };

  const moveDown = (idx) => {
    if (idx === sorted.length - 1) return;
    const reordered = [...sorted];
    [reordered[idx], reordered[idx + 1]] = [reordered[idx + 1], reordered[idx]];
    onReorder(reordered.map((l, i) => ({ ...l, sortOrder: i })));
  };

  return (
    <>
      <Modal
        open={open}
        onClose={onClose}
        title="Locations"
        footer={
          <>
            <button className="btn btn-ghost" onClick={onClose}>Done</button>
            <button
              className="btn btn-primary"
              onClick={() => { setEditing(null); setFormOpen(true); }}
            >
              <Plus size={14} /> Add location
            </button>
          </>
        }
      >
        {locations.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '24px 0', color: 'var(--ink-soft)' }}>
            <p style={{ margin: 0 }}>
              You haven't added any locations yet. Locations are places where you keep stock — like a closet, dresser, work, or your truck.
            </p>
            <p style={{ marginTop: 8, marginBottom: 0, fontSize: 13, color: 'var(--ink-mute)' }}>
              Add at least one location to start tracking inventory.
            </p>
          </div>
        ) : (
          <div className="card" style={{ padding: 4 }}>
            {sorted.map((loc, idx) => {
              const stockCount = products.reduce(
                (sum, p) => sum + (p.stock?.[loc.id] || 0),
                0
              );
              return (
                <div
                  key={loc.id}
                  className="row-divider"
                  style={{
                    padding: '12px 12px',
                    display: 'flex', alignItems: 'center', gap: 10,
                  }}
                >
                  <div style={{
                    width: 32, height: 32, borderRadius: 8,
                    background: 'var(--surface-2)',
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    color: 'var(--ink-soft)',
                  }}>
                    <LocationIcon name={loc.icon} size={16} />
                  </div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontSize: 14 }}>{loc.name}</div>
                    <div style={{ fontSize: 12, color: 'var(--ink-mute)' }}>
                      {stockCount} item{stockCount !== 1 ? 's' : ''} stored here
                    </div>
                  </div>
                  <div style={{ display: 'flex', gap: 0 }}>
                    <button
                      className="btn-icon"
                      onClick={() => moveUp(idx)}
                      disabled={idx === 0}
                      style={{ opacity: idx === 0 ? 0.3 : 1 }}
                      aria-label="Move up"
                    >
                      <ChevronUp size={16} />
                    </button>
                    <button
                      className="btn-icon"
                      onClick={() => moveDown(idx)}
                      disabled={idx === sorted.length - 1}
                      style={{ opacity: idx === sorted.length - 1 ? 0.3 : 1 }}
                      aria-label="Move down"
                    >
                      <ChevronDown size={16} />
                    </button>
                    <button
                      className="btn-icon"
                      onClick={() => { setEditing(loc); setFormOpen(true); }}
                      aria-label="Edit"
                    >
                      <Pencil size={14} />
                    </button>
                    <button
                      className="btn-icon"
                      onClick={() => setConfirmDel(loc)}
                      aria-label="Delete"
                    >
                      <Trash2 size={14} />
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </Modal>

      <LocationForm
        open={formOpen}
        onClose={() => { setFormOpen(false); setEditing(null); }}
        onSave={(loc) => {
          onSave(loc);
          setFormOpen(false);
          setEditing(null);
        }}
        initial={editing}
      />

      <ConfirmDialog
        open={!!confirmDel}
        title={
          confirmDel && hasStock(confirmDel.id)
            ? 'Move stock first'
            : 'Delete this location?'
        }
        body={
          confirmDel && hasStock(confirmDel.id)
            ? `"${confirmDel.name}" still has stock in it. Move that stock to another location before deleting.`
            : `"${confirmDel?.name}" will be removed. Past usage logs that reference this location will keep showing the name as a record.`
        }
        confirmLabel={
          confirmDel && hasStock(confirmDel.id) ? 'OK' : 'Delete'
        }
        danger={!(confirmDel && hasStock(confirmDel.id))}
        onCancel={() => setConfirmDel(null)}
        onConfirm={() => {
          if (confirmDel && !hasStock(confirmDel.id)) {
            onDelete(confirmDel);
          }
          setConfirmDel(null);
        }}
      />
    </>
  );
}
