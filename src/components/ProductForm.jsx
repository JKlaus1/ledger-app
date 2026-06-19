import React, { useState, useEffect, useRef } from 'react';
import { Camera, Check, Trash2 } from 'lucide-react';
import { Modal } from './Common';
import { LocationIcon } from './LocationManager';
import { TYPES, ABSORBENCY, SIZES, COLORS, uid, totalStock } from '../lib/helpers';
import { BACKINGS, TAB_TYPES } from '../lib/session';
import { processImage, dataUrlSize } from '../lib/images';
import { savePhoto, removePhoto, getPhoto } from '../lib/storage';

function PhotoField({ productId, initialThumb, onPhotoChange }) {
  const inputRef = useRef(null);
  const [preview, setPreview] = useState(initialThumb || null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [sizeNote, setSizeNote] = useState('');

  useEffect(() => {
    setPreview(initialThumb || null);
  }, [initialThumb]);

  const handleFile = async (file) => {
    if (!file) return;
    setBusy(true);
    setError('');
    setSizeNote('');
    try {
      const { thumb, full } = await processImage(file);
      setPreview(thumb);
      const totalSize = dataUrlSize(thumb) + dataUrlSize(full);
      setSizeNote(`Saved at ~${Math.round(totalSize / 1024)} KB`);
      // Pass both versions up to be saved when the form is submitted
      onPhotoChange({ thumb, full });
    } catch (e) {
      setError('Could not process that image. Try another.');
    }
    setBusy(false);
  };

  const remove = () => {
    setPreview(null);
    setSizeNote('');
    onPhotoChange(null);
  };

  return (
    <div>
      <label className="label">Photo (optional)</label>
      <div style={{ display: 'flex', gap: 12, alignItems: 'center', flexWrap: 'wrap' }}>
        {preview ? (
          <img
            src={preview}
            alt="Product preview"
            style={{
              width: 72, height: 72, objectFit: 'cover',
              borderRadius: 8, border: '1px solid var(--line)',
              flexShrink: 0,
            }}
          />
        ) : (
          <div style={{
            width: 72, height: 72, borderRadius: 8,
            border: '1px dashed var(--line)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: 'var(--ink-mute)', flexShrink: 0,
            background: 'var(--surface)',
          }}>
            <Camera size={22} />
          </div>
        )}
        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
          <button
            type="button"
            className="btn btn-ghost"
            disabled={busy}
            onClick={() => inputRef.current?.click()}
            style={{ fontSize: 13, padding: '7px 12px' }}
          >
            {busy ? 'Processing…' : (preview ? 'Replace' : 'Add photo')}
          </button>
          {preview && (
            <button
              type="button"
              className="btn btn-ghost"
              onClick={remove}
              style={{ fontSize: 13, padding: '7px 12px' }}
            >
              Remove
            </button>
          )}
        </div>
        <input
          ref={inputRef}
          type="file"
          accept="image/*"
          style={{ display: 'none' }}
          onChange={(e) => {
            const f = e.target.files?.[0];
            if (f) handleFile(f);
            e.target.value = '';
          }}
        />
      </div>
      {error && <div style={{ fontSize: 12, color: 'var(--danger)', marginTop: 6 }}>{error}</div>}
      <div style={{ fontSize: 11, color: 'var(--ink-mute)', marginTop: 6, fontStyle: 'italic' }}>
        Tap-to-view at full quality elsewhere in the app. {sizeNote}
      </div>
    </div>
  );
}

export default function ProductForm({
  open, onClose, onSave, onDelete, initial, locations,
}) {
  const blank = {
    brand: '', name: '', type: 'brief', absorbency: 'overnight',
    size: 'M', stock: {}, packSize: '', cost: '', color: COLORS[0].hex,
    print: '', backing: '', tabs: '', notes: '',
  };
  const [form, setForm] = useState(blank);
  // Pending photo data: null = no change, undefined = clear, { thumb, full } = new photo
  const [pendingPhoto, setPendingPhoto] = useState(null);
  const [initialThumb, setInitialThumb] = useState(null);

  // Load existing photo thumb when editing
  useEffect(() => {
    if (open && initial?.id) {
      getPhoto(initial.id).then((photo) => {
        setInitialThumb(photo?.thumb || null);
      }).catch(() => setInitialThumb(null));
    } else {
      setInitialThumb(null);
    }
  }, [open, initial]);

  useEffect(() => {
    if (open) {
      setForm(initial ? {
        ...blank, ...initial,
        packSize: initial.packSize ?? '',
        cost: initial.cost ?? '',
        stock: initial.stock || {},
      } : blank);
      setPendingPhoto(null);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, initial]);

  const update = (k, v) => setForm((f) => ({ ...f, [k]: v }));
  const updateStock = (locId, value) => {
    const n = value === '' ? 0 : Math.max(0, Number(value) || 0);
    setForm((f) => ({ ...f, stock: { ...f.stock, [locId]: n } }));
  };

  const valid = form.brand.trim() || form.name.trim();

  const submit = async () => {
    if (!valid) return;
    const id = initial?.id || uid();
    const product = {
      id,
      brand: form.brand.trim(),
      name: form.name.trim(),
      type: form.type,
      absorbency: form.absorbency,
      size: form.size,
      stock: form.stock,
      packSize: form.packSize === '' ? null : Number(form.packSize),
      cost: form.cost === '' ? null : Number(form.cost),
      color: form.color,
      print: form.print.trim(),
      backing: form.backing || null,
      tabs: form.tabs || null,
      notes: form.notes.trim(),
      createdAt: initial?.createdAt || Date.now(),
      updatedAt: Date.now(),
    };
    // Handle photo separately - saved directly to IndexedDB photo store
    if (pendingPhoto === undefined) {
      // User removed the photo
      await removePhoto(id);
    } else if (pendingPhoto && pendingPhoto.thumb && pendingPhoto.full) {
      await savePhoto(id, pendingPhoto);
    }
    onSave(product);
  };

  const total = totalStock(form);
  const hasLocations = locations.length > 0;

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={initial ? 'Edit product' : 'Add product'}
      footer={
        <>
          {initial && onDelete && (
            <button
              className="btn btn-danger"
              onClick={() => onDelete(initial)}
              style={{ marginRight: 'auto' }}
            >
              <Trash2 size={14} /> Delete
            </button>
          )}
          <button className="btn btn-ghost" onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" disabled={!valid} onClick={submit}>
            {initial ? 'Save changes' : 'Add to inventory'}
          </button>
        </>
      }
    >
      <div style={{ display: 'grid', gap: 14 }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          <div>
            <label className="label">Brand</label>
            <input
              className="input"
              placeholder="e.g. Northshore"
              value={form.brand}
              onChange={(e) => update('brand', e.target.value)}
            />
          </div>
          <div>
            <label className="label">Style / model</label>
            <input
              className="input"
              placeholder="e.g. MegaMax"
              value={form.name}
              onChange={(e) => update('name', e.target.value)}
            />
          </div>
        </div>

        <div>
          <label className="label">Color / print</label>
          <input
            className="input"
            placeholder="e.g. White, Blue, Camo print, Space pattern…"
            value={form.print}
            onChange={(e) => update('print', e.target.value)}
          />
          <div style={{ fontSize: 11, color: 'var(--ink-mute)', marginTop: 6, fontStyle: 'italic' }}>
            Shows next to the name so you can tell variants apart at a glance.
          </div>
        </div>

        <div>
          <label className="label">Type</label>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
            {TYPES.map((t) => (
              <button
                key={t.value}
                type="button"
                className={`check-row ${form.type === t.value ? 'active' : ''}`}
                onClick={() => update('type', t.value)}
              >
                <span style={{ flex: 1 }}>{t.label}</span>
                {form.type === t.value && <Check size={14} />}
              </button>
            ))}
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          <div>
            <label className="label">Size</label>
            <select className="select" value={form.size} onChange={(e) => update('size', e.target.value)}>
              {SIZES.map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
          </div>
          <div>
            <label className="label">Absorbency</label>
            <select className="select" value={form.absorbency} onChange={(e) => update('absorbency', e.target.value)}>
              {ABSORBENCY.map((a) => <option key={a.value} value={a.value}>{a.label}</option>)}
            </select>
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          <div>
            <label className="label">Backing</label>
            <select className="select" value={form.backing} onChange={(e) => update('backing', e.target.value)}>
              <option value="">Not set</option>
              {BACKINGS.map((b) => <option key={b.value} value={b.value}>{b.label}</option>)}
            </select>
          </div>
          <div>
            <label className="label">Tabs</label>
            <select className="select" value={form.tabs} onChange={(e) => update('tabs', e.target.value)}>
              <option value="">Not set</option>
              {TAB_TYPES.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
            </select>
          </div>
        </div>

        {/* Multi-location stock */}
        <div>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, marginBottom: 6 }}>
            <span className="label" style={{ marginBottom: 0 }}>Stock by location</span>
            <span style={{ flex: 1 }} />
            <span className="num" style={{ fontSize: 14, color: 'var(--ink-soft)' }}>
              Total: {total}
            </span>
          </div>
          {!hasLocations ? (
            <div className="card" style={{ padding: 14, fontSize: 13, color: 'var(--ink-soft)' }}>
              You haven't added any locations yet. Close this and add at least one location first (closet, dresser, etc.) — then you can come back and add this product.
            </div>
          ) : (
            <div className="card" style={{ padding: 4 }}>
              {[...locations]
                .sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0))
                .map((loc) => (
                  <div
                    key={loc.id}
                    className="row-divider"
                    style={{
                      padding: '10px 12px',
                      display: 'flex', alignItems: 'center', gap: 10,
                    }}
                  >
                    <LocationIcon name={loc.icon} size={14} style={{ color: 'var(--ink-soft)' }} />
                    <span style={{ flex: 1, fontSize: 14 }}>{loc.name}</span>
                    <input
                      className="input"
                      type="number"
                      min="0"
                      style={{ width: 80, padding: '6px 10px', fontSize: 14, textAlign: 'right' }}
                      value={form.stock[loc.id] ?? 0}
                      onChange={(e) => updateStock(loc.id, e.target.value)}
                    />
                  </div>
                ))}
            </div>
          )}
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          <div>
            <label className="label">Pack size</label>
            <input
              className="input" type="number" min="0" placeholder="—"
              value={form.packSize}
              onChange={(e) => update('packSize', e.target.value)}
            />
          </div>
          <div>
            <label className="label">Pack cost</label>
            <input
              className="input" type="number" min="0" step="0.01" placeholder="—"
              value={form.cost}
              onChange={(e) => update('cost', e.target.value)}
            />
          </div>
        </div>

        <PhotoField
          productId={initial?.id}
          initialThumb={initialThumb}
          onPhotoChange={(p) => setPendingPhoto(p === null ? undefined : p)}
        />

        <div>
          <label className="label">Color tag</label>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
            {COLORS.map((c) => (
              <button
                key={c.hex}
                type="button"
                className={`swatch-btn ${form.color === c.hex ? 'active' : ''}`}
                style={{ background: c.hex }}
                title={c.name}
                onClick={() => update('color', c.hex)}
              />
            ))}
          </div>
          <div style={{ fontSize: 11, color: 'var(--ink-mute)', marginTop: 6, fontStyle: 'italic' }}>
            Used as a fallback marker when no photo is set.
          </div>
        </div>

        <div>
          <label className="label">Notes</label>
          <textarea
            className="textarea"
            placeholder="Fit, comfort, where you bought it…"
            value={form.notes}
            onChange={(e) => update('notes', e.target.value)}
          />
        </div>
      </div>
    </Modal>
  );
}
