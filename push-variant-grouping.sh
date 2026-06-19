#!/usr/bin/env bash
# Ledger — variant grouping (push 1 of 2)
# Run from the repo root:
#   cp ~/storage/downloads/push-variant-grouping.sh ~/ledger-app/ && cd ~/ledger-app && bash push-variant-grouping.sh
set -e

if [ ! -d src/components ]; then
  echo "!! Run this from inside ~/ledger-app (src/components not found here)."
  exit 1
fi

echo "Writing src/lib/variants.js ..."
cat > src/lib/variants.js << 'LEDGER_EOF'
// Variant grouping for Ledger.
//
// Different colors / prints of the same diaper are separate product
// records (each carries its own stock, photo, and cost), but for the
// purposes of inventory display and — later — performance stats, they
// should be understood as variants of ONE product.
//
// How a product joins a group:
//   - explicit `product.groupId` wins when set
//       * a normal key string  -> joined to that group
//       * a "solo:..." key      -> deliberately standalone, never merges
//   - otherwise we derive a key from the normalized brand + model, so
//     same-brand/model items group automatically with no migration and
//     no manual tagging. Normalizing also collapses casing differences
//     (e.g. "InControl" vs "Incontrol") into a single group.

import { productDisplayName, totalStock } from './helpers';

const norm = (s) => (s || '').toLowerCase().replace(/\s+/g, ' ').trim();

// The effective grouping key for a product.
export const groupKeyOf = (p) => {
  if (!p) return '';
  const explicit = p.groupId == null ? '' : String(p.groupId).trim();
  if (explicit) return explicit;
  return 'name:' + norm(`${p.brand || ''} ${p.name || ''}`);
};

// Cluster products into groups.
// Returns: [{ key, products, rep, label, total, isMulti }]
//   rep    -> representative product (first variant, stable order)
//   label  -> brand + model, without the per-variant print
//   total  -> combined stock across all variants
//   isMulti-> true when the group holds more than one variant
export const groupProducts = (products, { sort = true } = {}) => {
  const map = new Map();
  for (const p of products) {
    const k = groupKeyOf(p);
    if (!map.has(k)) map.set(k, []);
    map.get(k).push(p);
  }

  let groups = [...map.entries()].map(([key, items]) => {
    const sorted = [...items].sort(
      (a, b) =>
        (a.print || '').localeCompare(b.print || '') ||
        productDisplayName(a).localeCompare(productDisplayName(b))
    );
    const rep = sorted[0];
    return {
      key,
      products: sorted,
      rep,
      label: productDisplayName(rep, { withPrint: false }),
      total: items.reduce((s, p) => s + totalStock(p), 0),
      isMulti: sorted.length > 1,
    };
  });

  if (sort) groups.sort((a, b) => a.label.localeCompare(b.label));
  return groups;
};

// Existing groups offered as "group with" choices in the product form.
// Excludes the product currently being edited.
// Returns: [{ key, label, count }]
export const groupOptions = (products, excludeId) =>
  groupProducts((products || []).filter((p) => p.id !== excludeId)).map((g) => ({
    key: g.key,
    label: g.label,
    count: g.products.length,
  }));
LEDGER_EOF

echo "Writing src/components/ProductForm.jsx ..."
cat > src/components/ProductForm.jsx << 'LEDGER_EOF'
import React, { useState, useEffect, useRef } from 'react';
import { Camera, Check, Trash2 } from 'lucide-react';
import { Modal } from './Common';
import { LocationIcon } from './LocationManager';
import { TYPES, ABSORBENCY, SIZES, COLORS, uid, totalStock } from '../lib/helpers';
import { BACKINGS, TAB_TYPES } from '../lib/session';
import { groupOptions } from '../lib/variants';
import { processImage, dataUrlSize } from '../lib/images';
import { savePhoto, removePhoto, getPhoto, getAllProducts } from '../lib/storage';

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
    print: '', backing: '', tabs: '', notes: '', groupId: null,
  };
  const [form, setForm] = useState(blank);
  // All products, loaded when the form opens — used to offer existing groups.
  const [allProducts, setAllProducts] = useState([]);
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

  // Load the catalog when opening, so we can offer existing groups to join.
  useEffect(() => {
    if (open) {
      getAllProducts().then((list) => setAllProducts(list || [])).catch(() => setAllProducts([]));
    }
  }, [open]);

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
      groupId: form.groupId || null,
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

  // --- variant grouping selector state ---
  const groupOpts = groupOptions(allProducts, initial?.id);
  const groupSelectValue =
    form.groupId == null
      ? ''
      : String(form.groupId).startsWith('solo:')
        ? '__standalone__'
        : form.groupId;
  // keep the current explicit group selectable even if it has no other members
  const groupOptsFinal =
    groupSelectValue && groupSelectValue !== '__standalone__'
      && !groupOpts.some((g) => g.key === groupSelectValue)
      ? [...groupOpts, { key: groupSelectValue, label: '(current group)', count: 1 }]
      : groupOpts;
  const onGroupChange = (v) => {
    if (v === '') update('groupId', null);
    else if (v === '__standalone__')
      update('groupId',
        String(form.groupId || '').startsWith('solo:') ? form.groupId : 'solo:' + uid());
    else update('groupId', v);
  };

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
          <label className="label">Groups with</label>
          <select
            className="select"
            value={groupSelectValue}
            onChange={(e) => onGroupChange(e.target.value)}
          >
            <option value="">Auto — same brand + model are one product</option>
            {groupOptsFinal.map((g) => (
              <option key={g.key} value={g.key}>
                Variant of: {g.label} ({g.count})
              </option>
            ))}
            <option value="__standalone__">Standalone — never group</option>
          </select>
          <div style={{ fontSize: 11, color: 'var(--ink-mute)', marginTop: 6, fontStyle: 'italic' }}>
            Variants (colors/prints) of the same diaper group together in inventory and will share performance stats.
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
LEDGER_EOF

echo "Writing src/components/Inventory.jsx ..."
cat > src/components/Inventory.jsx << 'LEDGER_EOF'
import React, { useState, useMemo } from 'react';
import { Plus, Pencil, MinusCircle, PlusCircle, ArrowRightLeft, Package } from 'lucide-react';
import { ProductThumb, Pill } from './Common';
import { LocationIcon } from './LocationManager';
import {
  TYPES, ABSORBENCY, productDisplayName, totalStock, stockAt,
} from '../lib/helpers';
import { backingLabel, tabsLabel } from '../lib/session';
import { groupProducts } from '../lib/variants';

function ProductRow({
  product, locations, thumbs, daysRemaining, titleOverride = null,
  onLogQuick, onRestock, onMove, onEdit, onPhotoTap,
}) {
  const [expanded, setExpanded] = useState(false);
  const total = totalStock(product);
  const lowStock = total <= 5;
  const veryLow = total <= 2;
  const sortedLocations = [...locations].sort(
    (a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)
  );

  return (
    <div className="row-divider row-hover" style={{ padding: '16px 4px' }}>
      <div style={{ display: 'flex', gap: 14, alignItems: 'flex-start' }}>
        <ProductThumb
          product={product} thumbs={thumbs} size={48}
          style={{ marginTop: 2 }}
          onClick={() => thumbs[product.id] && onPhotoTap(product.id)}
        />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, flexWrap: 'wrap' }}>
            <span className="display" style={{ fontSize: 17 }}>{titleOverride ?? productDisplayName(product)}</span>
          </div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 6 }}>
            <Pill>{TYPES.find((t) => t.value === product.type)?.short}</Pill>
            <Pill>Size {product.size}</Pill>
            <Pill>{ABSORBENCY.find((a) => a.value === product.absorbency)?.label}</Pill>
            {product.backing && <Pill>{backingLabel(product.backing)}</Pill>}
            {product.tabs && <Pill>{tabsLabel(product.tabs)}</Pill>}
          </div>
          {product.notes && (
            <div style={{ fontSize: 13, color: 'var(--ink-soft)', marginTop: 8, fontStyle: 'italic' }}>
              {product.notes}
            </div>
          )}
        </div>

        <div style={{ textAlign: 'right', flexShrink: 0 }}>
          <div className="num" style={{
            fontSize: 32, lineHeight: 1,
            color: veryLow ? 'var(--danger)' : (lowStock ? 'var(--warn)' : 'var(--ink)'),
          }}>
            {total}
          </div>
          <div className="eyebrow" style={{ fontSize: 9.5, marginTop: 2 }}>total</div>
          {daysRemaining != null && Number.isFinite(daysRemaining) && (
            <div style={{ fontSize: 11, color: 'var(--ink-mute)', marginTop: 4, fontStyle: 'italic' }}>
              ~{daysRemaining}d left
            </div>
          )}
        </div>
      </div>

      {/* Per-location breakdown - collapsible */}
      {locations.length > 0 && (
        <div style={{ marginTop: 10, marginLeft: 62 }}>
          <button
            onClick={() => setExpanded(!expanded)}
            style={{
              background: 'transparent', border: 'none', cursor: 'pointer',
              fontFamily: 'inherit', fontSize: 11, color: 'var(--ink-mute)',
              padding: 0, letterSpacing: '0.06em', fontWeight: 500,
            }}
          >
            {expanded ? '− HIDE BREAKDOWN' : '+ SHOW BY LOCATION'}
          </button>
          {expanded && (
            <div style={{
              marginTop: 8, display: 'flex', flexWrap: 'wrap', gap: 6,
            }}>
              {sortedLocations.map((loc) => {
                const stock = stockAt(product, loc.id);
                return (
                  <span
                    key={loc.id}
                    className="location-chip"
                    style={{
                      opacity: stock === 0 ? 0.5 : 1,
                    }}
                  >
                    <LocationIcon name={loc.icon} size={11} />
                    {loc.name}
                    <span className="num" style={{ marginLeft: 2, fontSize: 12 }}>{stock}</span>
                  </span>
                );
              })}
            </div>
          )}
        </div>
      )}

      <div style={{ display: 'flex', gap: 6, marginTop: 12, flexWrap: 'wrap' }}>
        <button
          className="btn btn-ghost"
          onClick={() => onLogQuick(product.id)}
          disabled={total <= 0}
          style={{ fontSize: 13, padding: '7px 12px' }}
        >
          <MinusCircle size={14} /> Use one
        </button>
        <button
          className="btn btn-ghost"
          onClick={() => onRestock(product)}
          style={{ fontSize: 13, padding: '7px 12px' }}
        >
          <PlusCircle size={14} /> Restock
        </button>
        {locations.length >= 2 && total > 0 && (
          <button
            className="btn btn-ghost"
            onClick={() => onMove(product.id)}
            style={{ fontSize: 13, padding: '7px 12px' }}
          >
            <ArrowRightLeft size={14} /> Move
          </button>
        )}
        <button
          className="btn-icon"
          onClick={() => onEdit(product)}
          aria-label="Edit"
        >
          <Pencil size={15} />
        </button>
      </div>
    </div>
  );
}

function GroupBlock({
  group, locations, thumbs, daysRemainingMap,
  onLogQuick, onRestock, onMove, onEdit, onPhotoTap,
}) {
  const rowProps = {
    locations, thumbs, onLogQuick, onRestock, onMove, onEdit, onPhotoTap,
  };

  // A single-variant group renders exactly like a normal row — no extra chrome.
  if (!group.isMulti) {
    const p = group.products[0];
    return (
      <ProductRow product={p} daysRemaining={daysRemainingMap[p.id]} {...rowProps} />
    );
  }

  // Multiple variants: a header for the shared product, variants nested beneath.
  return (
    <div
      style={{
        border: '1px solid var(--line)', borderRadius: 14,
        padding: '4px 10px', marginBottom: 12,
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 4px 4px' }}>
        <ProductThumb product={group.rep} thumbs={thumbs} size={30} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <span className="display" style={{ fontSize: 16 }}>{group.label}</span>
          <span className="eyebrow" style={{ fontSize: 9.5, marginLeft: 8 }}>
            {group.products.length} variants
          </span>
        </div>
        <div style={{ textAlign: 'right', flexShrink: 0 }}>
          <span className="num" style={{ fontSize: 20 }}>{group.total}</span>
          <span className="eyebrow" style={{ fontSize: 9, marginLeft: 4 }}>total</span>
        </div>
      </div>
      <div style={{ borderLeft: '2px solid var(--line)', marginLeft: 14, paddingLeft: 6 }}>
        {group.products.map((p) => (
          <ProductRow
            key={p.id}
            product={p}
            daysRemaining={daysRemainingMap[p.id]}
            titleOverride={(p.print && p.print.trim()) || 'Default'}
            {...rowProps}
          />
        ))}
      </div>
    </div>
  );
}

export default function Inventory({
  products, locations, thumbs, daysRemainingMap,
  onAdd, onEdit, onLogQuick, onRestock, onMove, onPhotoTap,
}) {
  const [filter, setFilter] = useState('all');
  const [locationFilter, setLocationFilter] = useState('all');

  const sortedLocations = [...locations].sort(
    (a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)
  );

  const filtered = useMemo(() => {
    let list = [...products];
    if (filter === 'low') {
      list = list.filter((p) => totalStock(p) <= 5);
    } else if (['brief', 'pullup', 'pad', 'booster'].includes(filter)) {
      list = list.filter((p) => p.type === filter);
    }
    if (locationFilter !== 'all') {
      list = list.filter((p) => stockAt(p, locationFilter) > 0);
    }
    return list.sort((a, b) =>
      productDisplayName(a).localeCompare(productDisplayName(b))
    );
  }, [products, filter, locationFilter]);

  if (products.length === 0) {
    return (
      <div className="empty-state">
        <Package size={28} style={{ color: 'var(--ink-mute)' }} />
        <div className="display" style={{ fontSize: 22, marginTop: 12 }}>No products yet</div>
        <p style={{ marginTop: 8, color: 'var(--ink-soft)' }}>
          Add your first item to get started.
        </p>
        <button className="btn btn-primary" onClick={onAdd} style={{ marginTop: 16 }}>
          <Plus size={16} /> Add product
        </button>
      </div>
    );
  }

  const filterOpts = [
    { v: 'all', l: 'All' },
    { v: 'low', l: 'Low stock' },
    { v: 'brief', l: 'Briefs' },
    { v: 'pullup', l: 'Pull-ups' },
    { v: 'pad', l: 'Pads' },
    { v: 'booster', l: 'Boosters' },
  ];

  return (
    <div>
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        marginBottom: 16, gap: 10,
      }}>
        <span className="display" style={{ fontSize: 24 }}>Inventory</span>
        <button
          className="btn btn-primary"
          onClick={onAdd}
          style={{ padding: '8px 14px', fontSize: 13 }}
        >
          <Plus size={15} /> Add
        </button>
      </div>

      <div className="scroll-x" style={{ marginBottom: 8, paddingBottom: 4 }}>
        <div style={{ display: 'inline-flex', gap: 6 }}>
          {filterOpts.map((f) => (
            <button
              key={f.v}
              onClick={() => setFilter(f.v)}
              style={{
                padding: '6px 12px', borderRadius: 999, fontSize: 12,
                border: '1px solid ' + (filter === f.v ? 'var(--ink)' : 'var(--line)'),
                background: filter === f.v ? 'var(--ink)' : 'transparent',
                color: filter === f.v ? 'var(--bg)' : 'var(--ink-soft)',
                cursor: 'pointer', fontFamily: 'inherit', fontWeight: 500,
                whiteSpace: 'nowrap',
              }}
            >
              {f.l}
            </button>
          ))}
        </div>
      </div>

      {/* Location filter */}
      {locations.length > 0 && (
        <div className="scroll-x" style={{ marginBottom: 16, paddingBottom: 4 }}>
          <div style={{ display: 'inline-flex', gap: 6 }}>
            <button
              onClick={() => setLocationFilter('all')}
              style={{
                padding: '6px 12px', borderRadius: 999, fontSize: 12,
                border: '1px solid ' + (locationFilter === 'all' ? 'var(--ink)' : 'var(--line)'),
                background: locationFilter === 'all' ? 'var(--ink)' : 'transparent',
                color: locationFilter === 'all' ? 'var(--bg)' : 'var(--ink-soft)',
                cursor: 'pointer', fontFamily: 'inherit', fontWeight: 500,
                whiteSpace: 'nowrap',
                display: 'inline-flex', alignItems: 'center', gap: 5,
              }}
            >
              All locations
            </button>
            {sortedLocations.map((loc) => (
              <button
                key={loc.id}
                onClick={() => setLocationFilter(loc.id)}
                style={{
                  padding: '6px 12px', borderRadius: 999, fontSize: 12,
                  border: '1px solid ' + (locationFilter === loc.id ? 'var(--ink)' : 'var(--line)'),
                  background: locationFilter === loc.id ? 'var(--ink)' : 'transparent',
                  color: locationFilter === loc.id ? 'var(--bg)' : 'var(--ink-soft)',
                  cursor: 'pointer', fontFamily: 'inherit', fontWeight: 500,
                  whiteSpace: 'nowrap',
                  display: 'inline-flex', alignItems: 'center', gap: 5,
                }}
              >
                <LocationIcon name={loc.icon} size={11} />
                {loc.name}
              </button>
            ))}
          </div>
        </div>
      )}

      <div>
        {filtered.length === 0 ? (
          <div style={{ padding: 32, textAlign: 'center', color: 'var(--ink-mute)' }}>
            No items match this filter.
          </div>
        ) : (
          groupProducts(filtered).map((g) => (
            <GroupBlock
              key={g.key}
              group={g}
              locations={locations}
              thumbs={thumbs}
              daysRemainingMap={daysRemainingMap}
              onLogQuick={onLogQuick}
              onRestock={onRestock}
              onMove={onMove}
              onEdit={onEdit}
              onPhotoTap={onPhotoTap}
            />
          ))
        )}
      </div>
    </div>
  );
}
LEDGER_EOF

echo "Files written. Committing and pushing ..."
git add -A && git commit -m "Recognize product variants; group them in inventory" && git push
echo "Done. Netlify will build from master; then tap Sync on the GitHub source in project knowledge."
