#!/usr/bin/env bash
# push-drink-presets.sh
# Adjustable per-bucket drink ounces (editable in Settings, stored in kv) +
# an optional exact-oz field on each drink. Insights intake volume uses the
# exact amount when given, otherwise the preset bucket. Whole-file writes.
set -e

if [ ! -f package.json ] || ! grep -q '"name": "ledger"' package.json || [ ! -d src/components ]; then
  echo "Error: run this from the ledger-app repo root (where package.json lives)." >&2
  exit 1
fi

echo "Writing files..."

mkdir -p "$(dirname src/lib/intake.js)"
cat > src/lib/intake.js << 'LEDGER_EOF'
// Fluid intake — its own kind of log (type: 'drink'): a free-standing,
// timestamped record of something you drank. Kept separate from wear sessions
// because intake isn't tied to a particular diaper; the value is correlating
// it against wetting timing/volume over time. Backward compatible by
// construction (a new log type older code simply ignores as "not a use").
//
//   { id, type: 'drink', timestamp, kind, size, oz, note, createdAt, updatedAt }
//
// `size` is a rough bucket (small/medium/large). `oz` is an optional exact
// amount — when present it wins over the bucket for volume estimates. The
// ounce value behind each bucket is user-adjustable and stored in kv under
// `drinkSizePresets`; DRINK_SIZES below only supplies the defaults.

export const DRINK_KINDS = [
  { value: 'water',   label: 'Water' },
  { value: 'coffee',  label: 'Coffee' },
  { value: 'tea',     label: 'Tea' },
  { value: 'soda',    label: 'Soda' },
  { value: 'juice',   label: 'Juice' },
  { value: 'alcohol', label: 'Alcohol' },
  { value: 'other',   label: 'Other' },
];

// Rough sizes with a default nominal ounce value, so intake can be totalled
// without asking for exact volumes every time. The oz here are defaults only —
// the live values come from the user's presets (see normalizeDrinkPresets).
export const DRINK_SIZES = [
  { value: 'small',  label: 'Small',  oz: 8,  order: 1 },
  { value: 'medium', label: 'Medium', oz: 16, order: 2 },
  { value: 'large',  label: 'Large',  oz: 24, order: 3 },
];

export const DEFAULT_DRINK_PRESETS = Object.fromEntries(
  DRINK_SIZES.map((s) => [s.value, s.oz])
);

export const drinkKindLabel = (v) => DRINK_KINDS.find((d) => d.value === v)?.label || 'Drink';
export const drinkSizeLabel = (v) => DRINK_SIZES.find((d) => d.value === v)?.label || '';
export const isDrink = (l) => !!l && l.type === 'drink';

// Coerce a raw kv value into a complete, sane {small,medium,large} preset map,
// keeping any valid positive numbers and filling the rest from defaults.
export const normalizeDrinkPresets = (raw) => {
  const out = { ...DEFAULT_DRINK_PRESETS };
  if (raw && typeof raw === 'object') {
    DRINK_SIZES.forEach((s) => {
      const n = Number(raw[s.value]);
      if (Number.isFinite(n) && n > 0) out[s.value] = n;
    });
  }
  return out;
};

// Ounces for a size bucket, honouring user presets and falling back to the
// built-in default when no preset is supplied.
export const drinkSizeOz = (v, presets = null) => {
  const p = presets && presets[v];
  if (Number.isFinite(Number(p)) && Number(p) > 0) return Number(p);
  return DRINK_SIZES.find((d) => d.value === v)?.oz || 0;
};

// Best volume estimate for a logged drink: the exact amount if recorded,
// otherwise the (preset-aware) bucket nominal.
export const drinkVolumeOz = (drink, presets = null) => {
  if (!drink) return 0;
  const exact = Number(drink.oz);
  if (Number.isFinite(exact) && exact > 0) return exact;
  return drinkSizeOz(drink.size, presets);
};
LEDGER_EOF

mkdir -p "$(dirname src/components/DrinkForm.jsx)"
cat > src/components/DrinkForm.jsx << 'LEDGER_EOF'
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
LEDGER_EOF

mkdir -p "$(dirname src/components/Settings.jsx)"
cat > src/components/Settings.jsx << 'LEDGER_EOF'
import React, { useRef, useState, useEffect } from 'react';
import { Download, Upload, MapPin, AlertTriangle, GlassWater } from 'lucide-react';
import { Modal, ConfirmDialog } from './Common';
import { exportAll, importAll, clearAll, kvSet } from '../lib/storage';
import { formatDate } from '../lib/helpers';
import { DRINK_SIZES, normalizeDrinkPresets } from '../lib/intake';

export default function Settings({
  open, onClose, onOpenLocations, onDataChanged, onShowToast,
  lastBackupAt, onBackedUp, drinkPresets, onSaveDrinkPresets,
}) {
  const fileRef = useRef(null);
  const [confirmClear, setConfirmClear] = useState(false);
  const [confirmImport, setConfirmImport] = useState(null);

  // Editable copy of the per-bucket drink ounces, seeded from the live presets.
  const [sizeDraft, setSizeDraft] = useState(() => normalizeDrinkPresets(drinkPresets));
  useEffect(() => {
    if (open) setSizeDraft(normalizeDrinkPresets(drinkPresets));
  }, [open, drinkPresets]);

  const saveSizes = async () => {
    const next = normalizeDrinkPresets(sizeDraft);
    try {
      await kvSet('drinkSizePresets', next);
      onSaveDrinkPresets?.(next);
      onShowToast?.('Drink sizes saved');
    } catch {
      onShowToast?.('Could not save drink sizes');
    }
  };

  const handleExport = async () => {
    try {
      const data = await exportAll();
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      const date = new Date().toISOString().slice(0, 10);
      a.href = url;
      a.download = `ledger-backup-${date}.json`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      const now = Date.now();
      try { await kvSet('lastBackupAt', now); } catch {}
      onBackedUp?.(now);
      onShowToast?.('Backup downloaded');
    } catch (e) {
      onShowToast?.('Export failed');
    }
  };

  const handleImportFile = (file) => {
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (e) => {
      try {
        const data = JSON.parse(e.target.result);
        if (data?.version !== 1) throw new Error('bad version');
        setConfirmImport(data);
      } catch {
        onShowToast?.('Could not read that file');
      }
    };
    reader.onerror = () => onShowToast?.('Could not read that file');
    reader.readAsText(file);
  };

  const doImport = async () => {
    try {
      await importAll(confirmImport);
      setConfirmImport(null);
      onShowToast?.('Restored from backup');
      onDataChanged?.();
      onClose();
    } catch (e) {
      onShowToast?.('Import failed');
      setConfirmImport(null);
    }
  };

  const doClear = async () => {
    try {
      await clearAll();
      setConfirmClear(false);
      onShowToast?.('All data cleared');
      onDataChanged?.();
      onClose();
    } catch {
      onShowToast?.('Could not clear data');
      setConfirmClear(false);
    }
  };

  return (
    <>
      <Modal open={open} onClose={onClose} title="Settings"
        footer={<button className="btn btn-ghost" onClick={onClose}>Done</button>}
      >
        <div style={{ display: 'grid', gap: 14 }}>
          <button
            className="btn btn-ghost"
            style={{ justifyContent: 'flex-start', width: '100%', padding: 14 }}
            onClick={() => { onClose(); onOpenLocations(); }}
          >
            <MapPin size={16} />
            <span style={{ flex: 1, textAlign: 'left' }}>Manage locations</span>
          </button>

          <hr className="hairline" />

          <div className="eyebrow">Backup</div>
          <p style={{ fontSize: 13, color: 'var(--ink-soft)', margin: 0 }}>
            Export your data as a JSON file. Save it somewhere safe in case your phone dies or browser data gets cleared. Re-import to restore.
          </p>
          <div style={{ fontSize: 12, color: lastBackupAt ? 'var(--ink-mute)' : 'var(--accent)', fontStyle: 'italic' }}>
            {lastBackupAt
              ? `Last backed up ${formatDate(lastBackupAt, { year: true })}.`
              : 'No backup yet on this device.'}
          </div>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            <button className="btn btn-ghost" onClick={handleExport}>
              <Download size={14} /> Export backup
            </button>
            <button className="btn btn-ghost" onClick={() => fileRef.current?.click()}>
              <Upload size={14} /> Restore from file
            </button>
            <input
              ref={fileRef}
              type="file"
              accept="application/json,.json"
              style={{ display: 'none' }}
              onChange={(e) => {
                const f = e.target.files?.[0];
                if (f) handleImportFile(f);
                e.target.value = '';
              }}
            />
          </div>

          <hr className="hairline" />

          <div className="eyebrow">Drink sizes</div>
          <p style={{ fontSize: 13, color: 'var(--ink-soft)', margin: 0 }}>
            Ounces behind each size bucket, used to estimate daily intake. Set these to your usual cups and bottles. A logged drink's exact amount, when given, overrides these.
          </p>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8 }}>
            {DRINK_SIZES.map((sz) => (
              <div key={sz.value}>
                <label className="label">{sz.label}</label>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <input
                    className="input"
                    type="number" inputMode="decimal" min="1" step="1"
                    value={sizeDraft[sz.value]}
                    onChange={(e) => setSizeDraft((d) => ({ ...d, [sz.value]: e.target.value }))}
                  />
                  <span style={{ fontSize: 12, color: 'var(--ink-mute)' }}>oz</span>
                </div>
              </div>
            ))}
          </div>
          <div>
            <button className="btn btn-ghost" onClick={saveSizes}>
              <GlassWater size={14} /> Save drink sizes
            </button>
          </div>

          <hr className="hairline" />

          <div className="eyebrow" style={{ color: 'var(--danger)' }}>Danger zone</div>
          <button className="btn btn-danger" onClick={() => setConfirmClear(true)}>
            <AlertTriangle size={14} /> Erase all data
          </button>
        </div>
      </Modal>

      <ConfirmDialog
        open={confirmClear}
        title="Erase all data?"
        body="This deletes every product, location, log, and photo. The action can't be undone unless you have a backup file."
        confirmLabel="Erase everything"
        onCancel={() => setConfirmClear(false)}
        onConfirm={doClear}
      />

      <ConfirmDialog
        open={!!confirmImport}
        title="Restore from backup?"
        body="This replaces all your current data with the contents of the backup file."
        confirmLabel="Restore"
        danger={false}
        onCancel={() => setConfirmImport(null)}
        onConfirm={doImport}
      />
    </>
  );
}
LEDGER_EOF

mkdir -p "$(dirname src/components/History.jsx)"
cat > src/components/History.jsx << 'LEDGER_EOF'
import React, { useState, useMemo } from 'react';
import { Pencil, Trash2, Sun, Moon, ClipboardList, ArrowRight, Droplets, StickyNote, Repeat, GlassWater } from 'lucide-react';
import { ProductThumb } from './Common';
import { LocationIcon } from './LocationManager';
import { WettingSummary } from './WettingForm';
import { contextLabel, reasonLabel } from '../lib/session';
import { isDrink, drinkKindLabel, drinkSizeLabel } from '../lib/intake';
import {
  formatDate, formatTime, dayKey, productDisplayName,
  formatDuration, wearDuration,
} from '../lib/helpers';

export default function History({
  logs, products, locations, thumbs,
  onEdit, onDelete, onManageWettings, onPhotoTap,
}) {
  const [periodFilter, setPeriodFilter] = useState('all');
  const [productFilter, setProductFilter] = useState('all');
  const [locationFilter, setLocationFilter] = useState('all');
  const [typeFilter, setTypeFilter] = useState('all'); // all | use | move

  const sortedLocations = [...locations].sort(
    (a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)
  );

  const sortedProducts = [...products].sort(
    (a, b) => productDisplayName(a).localeCompare(productDisplayName(b))
  );

  const filtered = useMemo(() => {
    return logs
      .filter((l) => {
        if (typeFilter === 'use') return l.type !== 'move' && l.type !== 'note' && l.type !== 'drink';
        if (typeFilter === 'move') return l.type === 'move';
        if (typeFilter === 'note') return l.type === 'note';
        if (typeFilter === 'drink') return l.type === 'drink';
        return true;
      })
      .filter((l) => {
        if (l.type === 'move' || l.type === 'note' || l.type === 'drink') return periodFilter === 'all';
        return periodFilter === 'all' || l.period === periodFilter;
      })
      .filter((l) => productFilter === 'all' || l.productId === productFilter)
      .filter((l) => {
        if (locationFilter === 'all') return true;
        if (l.type === 'move') {
          return l.fromLocationId === locationFilter || l.toLocationId === locationFilter;
        }
        return l.locationId === locationFilter;
      })
      .sort((a, b) => b.timestamp - a.timestamp);
  }, [logs, periodFilter, productFilter, locationFilter, typeFilter]);

  // Group by day
  const grouped = useMemo(() => {
    const m = new Map();
    filtered.forEach((l) => {
      const k = dayKey(l.timestamp);
      if (!m.has(k)) m.set(k, []);
      m.get(k).push(l);
    });
    return [...m.entries()];
  }, [filtered]);

  if (logs.length === 0) {
    return (
      <div className="empty-state">
        <ClipboardList size={28} style={{ color: 'var(--ink-mute)' }} />
        <div className="display" style={{ fontSize: 22, marginTop: 12 }}>No history yet</div>
        <p style={{ marginTop: 8, color: 'var(--ink-soft)' }}>
          Logged uses, moves, and notes will appear here.
        </p>
      </div>
    );
  }

  return (
    <div>
      <div style={{ marginBottom: 16 }}>
        <span className="display" style={{ fontSize: 24 }}>History</span>
      </div>

      {/* Filters */}
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, marginBottom: 12 }}>
        <div className="seg">
          <button
            className={`seg-btn ${typeFilter === 'all' ? 'active' : ''}`}
            onClick={() => setTypeFilter('all')}
          >
            All
          </button>
          <button
            className={`seg-btn ${typeFilter === 'use' ? 'active' : ''}`}
            onClick={() => setTypeFilter('use')}
          >
            Uses
          </button>
          <button
            className={`seg-btn ${typeFilter === 'move' ? 'active' : ''}`}
            onClick={() => setTypeFilter('move')}
          >
            Moves
          </button>
          <button
            className={`seg-btn ${typeFilter === 'note' ? 'active' : ''}`}
            onClick={() => setTypeFilter('note')}
          >
            Notes
          </button>
          <button
            className={`seg-btn ${typeFilter === 'drink' ? 'active' : ''}`}
            onClick={() => setTypeFilter('drink')}
          >
            Drinks
          </button>
        </div>
        {typeFilter !== 'move' && typeFilter !== 'note' && typeFilter !== 'drink' && (
          <div className="seg">
            <button
              className={`seg-btn ${periodFilter === 'all' ? 'active' : ''}`}
              onClick={() => setPeriodFilter('all')}
            >
              Day & Night
            </button>
            <button
              className={`seg-btn ${periodFilter === 'day' ? 'active' : ''}`}
              onClick={() => setPeriodFilter('day')}
            >
              <Sun size={13} /> Day
            </button>
            <button
              className={`seg-btn ${periodFilter === 'night' ? 'active' : ''}`}
              onClick={() => setPeriodFilter('night')}
            >
              <Moon size={13} /> Night
            </button>
          </div>
        )}
      </div>

      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, marginBottom: 20 }}>
        <select
          className="select"
          style={{ width: 'auto', flex: '1 1 180px' }}
          value={productFilter}
          onChange={(e) => setProductFilter(e.target.value)}
        >
          <option value="all">All products</option>
          {sortedProducts.map((p) => (
            <option key={p.id} value={p.id}>{productDisplayName(p)}</option>
          ))}
        </select>
        {locations.length > 0 && (
          <select
            className="select"
            style={{ width: 'auto', flex: '1 1 160px' }}
            value={locationFilter}
            onChange={(e) => setLocationFilter(e.target.value)}
          >
            <option value="all">All locations</option>
            {sortedLocations.map((loc) => (
              <option key={loc.id} value={loc.id}>{loc.name}</option>
            ))}
          </select>
        )}
      </div>

      {filtered.length === 0 ? (
        <div style={{ padding: 32, textAlign: 'center', color: 'var(--ink-mute)' }}>
          No entries match these filters.
        </div>
      ) : (
        <div style={{ display: 'grid', gap: 24 }}>
          {grouped.map(([day, entries]) => {
            const d = new Date(day + 'T00:00:00');
            const isT = dayKey(Date.now()) === day;
            return (
              <div key={day}>
                <div style={{
                  display: 'flex', alignItems: 'baseline', gap: 8, marginBottom: 10,
                }}>
                  <span className="display" style={{ fontSize: 16 }}>
                    {isT ? 'Today' : d.toLocaleDateString(undefined, { weekday: 'long' })}
                  </span>
                  <span className="eyebrow">
                    {d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })}
                  </span>
                  <span style={{ flex: 1, height: 1, background: 'var(--line)', marginLeft: 8 }} />
                  <span className="num" style={{ fontSize: 13, color: 'var(--ink-mute)' }}>
                    {entries.length}
                  </span>
                </div>

                <div className="card" style={{ padding: 4 }}>
                  {entries.map((l) => {
                    if (isDrink(l)) {
                      return (
                        <div
                          key={l.id}
                          className="row-divider"
                          style={{
                            padding: '12px 14px',
                            display: 'flex', alignItems: 'flex-start', gap: 12,
                          }}
                        >
                          <div style={{
                            width: 56, fontSize: 13, color: 'var(--ink-soft)',
                            paddingTop: 1, fontVariantNumeric: 'tabular-nums',
                          }}>
                            {formatTime(l.timestamp)}
                          </div>
                          <div style={{ marginTop: 2, color: 'var(--primary)', flexShrink: 0 }}>
                            <GlassWater size={16} />
                          </div>
                          <div style={{ flex: 1, minWidth: 0 }}>
                            <div style={{ fontSize: 14 }}>
                              {drinkKindLabel(l.kind)}
                              {l.size && <span style={{ color: 'var(--ink-mute)' }}> · {drinkSizeLabel(l.size).toLowerCase()}</span>}
                              {Number(l.oz) > 0 && <span style={{ color: 'var(--ink-mute)' }}> · {l.oz}oz</span>}
                            </div>
                            <div style={{ fontSize: 12, color: 'var(--ink-mute)', marginTop: 4 }}>
                              <span style={{ color: 'var(--primary)' }}>Drink</span>
                              {l.note && <span> · {l.note}</span>}
                            </div>
                          </div>
                          <div style={{ display: 'flex', gap: 2, flexShrink: 0 }}>
                            <button className="btn-icon" onClick={() => onEdit(l)} aria-label="Edit drink">
                              <Pencil size={14} />
                            </button>
                            <button className="btn-icon" onClick={() => onDelete(l)} aria-label="Delete drink">
                              <Trash2 size={14} />
                            </button>
                          </div>
                        </div>
                      );
                    }
                    if (l.type === 'note') {
                      const np = l.productId ? products.find((x) => x.id === l.productId) : null;
                      const nloc = l.locationId ? locations.find((x) => x.id === l.locationId) : null;
                      return (
                        <div
                          key={l.id}
                          className="row-divider"
                          style={{
                            padding: '12px 14px',
                            display: 'flex', alignItems: 'flex-start', gap: 12,
                          }}
                        >
                          <div style={{
                            width: 56, fontSize: 13, color: 'var(--ink-soft)',
                            paddingTop: 1, fontVariantNumeric: 'tabular-nums',
                          }}>
                            {formatTime(l.timestamp)}
                          </div>
                          <div style={{ marginTop: 2, color: 'var(--accent)', flexShrink: 0 }}>
                            <StickyNote size={16} />
                          </div>
                          <div style={{ flex: 1, minWidth: 0 }}>
                            <div style={{ fontSize: 14, whiteSpace: 'pre-wrap' }}>{l.text}</div>
                            <div style={{
                              fontSize: 12, color: 'var(--ink-mute)',
                              marginTop: 4, display: 'flex', alignItems: 'center', gap: 6,
                              flexWrap: 'wrap',
                            }}>
                              <span style={{ color: 'var(--accent)' }}>Note</span>
                              {l.context && <><span>·</span><span>{contextLabel(l.context) || l.context}</span></>}
                              {l.place && <><span>·</span><span>{l.place}</span></>}
                              {np && <><span>·</span><span>{productDisplayName(np)}</span></>}
                              {nloc && <><span>·</span><LocationIcon name={nloc.icon} size={11} /><span>{nloc.name}</span></>}
                            </div>
                          </div>
                          <div style={{ display: 'flex', gap: 2, flexShrink: 0 }}>
                            <button className="btn-icon" onClick={() => onEdit(l)} aria-label="Edit note">
                              <Pencil size={14} />
                            </button>
                            <button className="btn-icon" onClick={() => onDelete(l)} aria-label="Delete note">
                              <Trash2 size={14} />
                            </button>
                          </div>
                        </div>
                      );
                    }

                    const p = products.find((x) => x.id === l.productId);
                    const isMove = l.type === 'move';
                    const fromLoc = isMove ? locations.find((loc) => loc.id === l.fromLocationId) : null;
                    const toLoc = isMove ? locations.find((loc) => loc.id === l.toLocationId) : null;
                    const useLoc = !isMove ? locations.find((loc) => loc.id === l.locationId) : null;
                    // Wettings attach to wear sessions (a use with a put-on time),
                    // whether that diaper is on now or was worn previously.
                    const isWearSession = !isMove && !!l.putOnAt;
                    // A put-on that directly followed an explicit/auto-linked take-off.
                    const isChangeOut = isWearSession && !!l.changedFromId;

                    return (
                      <div
                        key={l.id}
                        className="row-divider"
                        style={{
                          padding: '12px 14px',
                          display: 'flex', alignItems: 'flex-start', gap: 12,
                        }}
                      >
                        <div style={{
                          width: 56, fontSize: 13, color: 'var(--ink-soft)',
                          paddingTop: 1, fontVariantNumeric: 'tabular-nums',
                        }}>
                          {formatTime(l.timestamp)}
                        </div>
                        {p && (
                          <ProductThumb
                            product={p} thumbs={thumbs} size={24}
                            style={{ marginTop: 1 }}
                            onClick={() => thumbs[p.id] && onPhotoTap(p.id)}
                          />
                        )}
                        <div style={{ flex: 1, minWidth: 0 }}>
                          <div style={{ fontSize: 14, display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
                            {isChangeOut && (
                              <span style={{ color: 'var(--accent)', display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                                <Repeat size={12} /> Changed into
                              </span>
                            )}
                            <span>
                              {p ? productDisplayName(p) : <span style={{ color: 'var(--ink-mute)' }}>Removed product</span>}
                            </span>
                          </div>
                          <div style={{
                            fontSize: 12, color: 'var(--ink-mute)',
                            marginTop: 2, display: 'flex', alignItems: 'center', gap: 6,
                            flexWrap: 'wrap',
                          }}>
                            {isMove ? (
                              <>
                                <span style={{ color: 'var(--accent)' }}>
                                  Moved {l.quantity}
                                </span>
                                <span>·</span>
                                {fromLoc && <LocationIcon name={fromLoc.icon} size={11} />}
                                <span>{fromLoc?.name || 'Unknown'}</span>
                                <ArrowRight size={11} />
                                {toLoc && <LocationIcon name={toLoc.icon} size={11} />}
                                <span>{toLoc?.name || 'Unknown'}</span>
                              </>
                            ) : (
                              <>
                                {l.period === 'night' ? <><Moon size={11} /> Overnight</> : <><Sun size={11} /> Daytime</>}
                                {useLoc && (
                                  <>
                                    <span>·</span>
                                    <LocationIcon name={useLoc.icon} size={11} />
                                    <span>{useLoc.name}</span>
                                  </>
                                )}
                                {l.putOnAt && l.takenOffAt == null && (
                                  <span style={{ color: 'var(--primary)' }}>· on now</span>
                                )}
                                {wearDuration(l) != null && (
                                  <span>· worn {formatDuration(wearDuration(l))}</span>
                                )}
                                {l.performance === 'leak' && <span style={{ color: 'var(--danger)' }}>· Leaked</span>}
                                {l.performance === 'dry' && <span style={{ color: 'var(--primary)' }}>· Stayed dry</span>}
                                {l.booster && <span style={{ color: 'var(--accent)' }}>· +booster</span>}
                                {l.context && <span>· {contextLabel(l.context) || l.context}</span>}
                                {l.changeReason && !['routine', 'leak'].includes(l.changeReason) && (
                                  <span>· {reasonLabel(l.changeReason) || l.changeReason}</span>
                                )}
                              </>
                            )}
                          </div>
                          {!isMove && (
                            <WettingSummary log={l} compact style={{ fontSize: 12, marginTop: 5 }} />
                          )}
                          {l.notes && (
                            <div style={{
                              fontSize: 12, color: 'var(--ink-soft)',
                              marginTop: 6, fontStyle: 'italic',
                            }}>
                              {l.notes}
                            </div>
                          )}
                        </div>
                        <div style={{ display: 'flex', gap: 2, flexShrink: 0 }}>
                          {isWearSession && onManageWettings && (
                            <button
                              className="btn-icon"
                              onClick={() => onManageWettings(l)}
                              aria-label="Log or edit wettings"
                            >
                              <Droplets size={14} />
                            </button>
                          )}
                          {!isMove && (l.putOnAt && l.takenOffAt == null) && (
                            <button
                              className="btn-icon"
                              onClick={() => onEdit(l)}
                              aria-label="Edit"
                            >
                              <Pencil size={14} />
                            </button>
                          )}
                          <button
                            className="btn-icon"
                            onClick={() => onDelete(l)}
                            aria-label="Delete"
                          >
                            <Trash2 size={14} />
                          </button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
LEDGER_EOF

mkdir -p "$(dirname src/components/Insights.jsx)"
cat > src/components/Insights.jsx << 'LEDGER_EOF'
import React, { useMemo } from 'react';
import {
  BarChart, Bar, XAxis, YAxis, ResponsiveContainer, Tooltip,
  PieChart, Pie, Cell,
} from 'recharts';
import { BarChart3, Droplets } from 'lucide-react';
import { ProductThumb, SectionHeader } from './Common';
import { LocationIcon } from './LocationManager';
import {
  productDisplayName, totalStock, dayKey, formatDuration,
} from '../lib/helpers';
import {
  WETNESS, getWettings, wettingStats, wetnessLabel, globalCapacity,
  eventKind, CONTROL_LEVELS, controlLabel,
} from '../lib/wetting';
import {
  CHANGE_REASONS, contextLabel, unitCost, fmtMoney,
  LEAK_ESCAPE, LEAK_SEVERITY,
} from '../lib/session';
import { isDrink, DRINK_KINDS, drinkKindLabel, drinkVolumeOz } from '../lib/intake';

export default function Insights({ products, logs, locations, thumbs, daysRemainingMap, drinkPresets = null }) {
  // Filter out moves - they're inventory transfers, not consumption
  const usageLogs = logs.filter((l) => l.type !== 'move');

  // A wear log is the modern put-on/take-off kind, or an older typed/untyped
  // entry that predates it. We surface how many predate the detailed schema so
  // sections that need putOnAt (timing, wettings, context) are read against
  // the right denominator instead of looking artificially sparse.
  const isWear = (l) => l.type === 'use' || (!l.type && (l.putOnAt || l.period));
  const legacyInfo = useMemo(() => {
    const wears = logs.filter(isWear);
    const detailed = wears.filter((l) => l.putOnAt);
    return { total: wears.length, detailed: detailed.length, legacy: wears.length - detailed.length };
  }, [logs]);

  // Last 14 days bar chart
  const dailyData = useMemo(() => {
    const days = 14;
    const out = [];
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    for (let i = days - 1; i >= 0; i--) {
      const d = new Date(today.getTime() - i * 24 * 3600 * 1000);
      const k = dayKey(d.getTime());
      const dayCount = usageLogs.filter((l) => dayKey(l.timestamp) === k && l.period === 'day').length;
      const nightCount = usageLogs.filter((l) => dayKey(l.timestamp) === k && l.period === 'night').length;
      out.push({
        date: d.toLocaleDateString(undefined, { month: 'numeric', day: 'numeric' }),
        Day: dayCount,
        Night: nightCount,
      });
    }
    return out;
  }, [usageLogs]);

  const periodSplit = useMemo(() => {
    const day = usageLogs.filter((l) => l.period === 'day').length;
    const night = usageLogs.filter((l) => l.period === 'night').length;
    return [
      { name: 'Daytime', value: day, color: '#C9985A' },
      { name: 'Overnight', value: night, color: '#2F4A3F' },
    ];
  }, [usageLogs]);

  // Average time worn per period, from completed wear sessions
  const avgWornByPeriod = useMemo(() => {
    const calc = (period) => {
      const durs = usageLogs
        .filter((l) => l.putOnAt && l.takenOffAt != null && l.period === period)
        .map((l) => l.takenOffAt - l.putOnAt)
        .filter((d) => d > 0);
      if (!durs.length) return null;
      return durs.reduce((a, b) => a + b, 0) / durs.length;
    };
    return { Daytime: calc('day'), Overnight: calc('night') };
  }, [usageLogs]);

  // ---- Wetting analytics ---------------------------------------------------
  // A "wear session" is any usage log with a putOnAt time. Wettings ride
  // inline on those logs. We look at how many wettings each diaper took and,
  // per product, how much load it held before leaking vs. while staying dry.
  const wettingAgg = useMemo(() => {
    const sessions = usageLogs.filter((l) => l.putOnAt);
    const amountCounts = {};
    WETNESS.forEach((w) => { amountCounts[w.value] = 0; });
    let totalWettings = 0;
    let wetSessionCount = 0;
    sessions.forEach((l) => {
      const st = wettingStats(l); // wet-only counts; BM/toilet excluded
      if (st.count > 0) wetSessionCount += 1;
      totalWettings += st.count;
      WETNESS.forEach((w) => { amountCounts[w.value] += st.byAmount[w.value] || 0; });
    });
    return {
      sessionCount: sessions.length,
      wetSessionCount,
      totalWettings,
      amountCounts,
      avgPerDiaper: sessions.length ? totalWettings / sessions.length : 0,
      avgPerWetDiaper: wetSessionCount ? totalWettings / wetSessionCount : 0,
    };
  }, [usageLogs]);

  // Per-product capacity: average "load" (summed wetting weight) on sessions
  // that leaked vs. the most it held on a session that did NOT leak.
  const capacityByProduct = useMemo(() => {
    const m = new Map();
    usageLogs.filter((l) => l.putOnAt).forEach((l) => {
      const st = wettingStats(l);
      if (st.count === 0) return;
      if (!m.has(l.productId)) m.set(l.productId, { leakLoads: [], heldLoads: [] });
      const e = m.get(l.productId);
      if (l.performance === 'leak') e.leakLoads.push(st.load);
      else e.heldLoads.push(st.load); // dry / used = held without leaking
    });
    const avg = (arr) => (arr.length ? arr.reduce((a, b) => a + b, 0) / arr.length : null);
    return [...m.entries()]
      .map(([id, e]) => ({
        product: products.find((p) => p.id === id),
        avgLeakLoad: avg(e.leakLoads),
        avgHeldLoad: avg(e.heldLoads),
        maxHeld: e.heldLoads.length ? Math.max(...e.heldLoads) : null,
        leakCount: e.leakLoads.length,
        heldCount: e.heldLoads.length,
      }))
      .filter((x) => x.product && (x.leakCount + x.heldCount) >= 1)
      .sort((a, b) => (b.avgLeakLoad ?? b.maxHeld ?? 0) - (a.avgLeakLoad ?? a.maxHeld ?? 0));
  }, [usageLogs, products]);

  // A blunt fallback ceiling across all products, shown so the live capacity
  // warning's basis is visible here too.
  const globalCap = useMemo(() => globalCapacity(usageLogs), [usageLogs]);

  // Wetting distribution by hour of day (0–23), across every session.
  const wettingByHour = useMemo(() => {
    const hours = Array.from({ length: 24 }, (_, h) => ({ hour: h, count: 0 }));
    usageLogs.filter((l) => l.putOnAt).forEach((l) => {
      getWettings(l).forEach((w) => {
        if (eventKind(w) !== 'wet') return;
        const h = new Date(w.at).getHours();
        if (h >= 0 && h < 24) hours[h].count += 1;
      });
    });
    return hours;
  }, [usageLogs]);

  // Booster effect: leak rate and average load with vs. without a booster.
  const boosterEffect = useMemo(() => {
    const sessions = usageLogs.filter((l) => l.putOnAt);
    const grp = (withB) => {
      const s = sessions.filter((l) => !!l.booster === withB);
      const perf = s.filter((l) => l.performance);
      const leaks = perf.filter((l) => l.performance === 'leak').length;
      const loads = s.map((l) => wettingStats(l).load).filter((x) => x > 0);
      return {
        n: s.length,
        leakRate: perf.length ? leaks / perf.length : null,
        avgLoad: loads.length ? loads.reduce((a, b) => a + b, 0) / loads.length : null,
      };
    };
    return { withB: grp(true), withoutB: grp(false) };
  }, [usageLogs]);

  // Toilet uses, BM-in-diaper, and the voluntary/accident breakdown across
  // every event. This is the continence-pattern signal.
  const eliminationAgg = useMemo(() => {
    const sessions = usageLogs.filter((l) => l.putOnAt);
    let toilet = 0, bm = 0;
    let toiletPee = 0, toiletBM = 0, toiletBoth = 0;
    const control = { voluntary: 0, couldnt_hold: 0, accident: 0 };
    sessions.forEach((l) => {
      getWettings(l).forEach((w) => {
        const k = eventKind(w);
        if (k === 'toilet') {
          toilet += 1;
          if (w.toiletWhat === 'pee') toiletPee += 1;
          else if (w.toiletWhat === 'bm') toiletBM += 1;
          else if (w.toiletWhat === 'both') toiletBoth += 1;
        } else if (k === 'bm') {
          bm += 1;
        }
        if ((k === 'wet' || k === 'bm') && w.control && control[w.control] != null) {
          control[w.control] += 1;
        }
      });
    });
    const controlTotal = control.voluntary + control.couldnt_hold + control.accident;
    return { toilet, bm, control, controlTotal, toiletPee, toiletBM, toiletBoth,
      any: toilet > 0 || bm > 0 || controlTotal > 0 };
  }, [usageLogs]);

  // Leak detail — where leaks escaped and how bad, among sessions marked leak.
  const leakDetailAgg = useMemo(() => {
    const leaks = usageLogs.filter((l) => l.putOnAt && l.performance === 'leak');
    const escape = {}; const severity = {};
    leaks.forEach((l) => {
      if (l.leakEscape) escape[l.leakEscape] = (escape[l.leakEscape] || 0) + 1;
      if (l.leakSeverity) severity[l.leakSeverity] = (severity[l.leakSeverity] || 0) + 1;
    });
    return {
      leakCount: leaks.length,
      detailed: leaks.filter((l) => l.leakEscape || l.leakSeverity).length,
      escapeRows: LEAK_ESCAPE.map((e) => ({ ...e, count: escape[e.value] || 0 })).filter((r) => r.count > 0),
      severityRows: LEAK_SEVERITY.map((x) => ({ ...x, count: severity[x.value] || 0 })).filter((r) => r.count > 0),
    };
  }, [usageLogs]);

  // Usage + leak rate broken down by the context it was worn in.
  const contextStats = useMemo(() => {
    const m = new Map();
    usageLogs.filter((l) => l.putOnAt && l.context).forEach((l) => {
      if (!m.has(l.context)) m.set(l.context, { count: 0, perf: 0, leaks: 0 });
      const e = m.get(l.context);
      e.count += 1;
      if (l.performance) { e.perf += 1; if (l.performance === 'leak') e.leaks += 1; }
    });
    return [...m.entries()]
      .map(([value, e]) => ({ value, label: contextLabel(value) || value, ...e }))
      .sort((a, b) => b.count - a.count);
  }, [usageLogs]);

  // Why changes happen — distribution of change reasons.
  const reasonStats = useMemo(() => {
    const m = new Map();
    usageLogs.filter((l) => l.putOnAt && l.changeReason).forEach((l) => {
      m.set(l.changeReason, (m.get(l.changeReason) || 0) + 1);
    });
    const total = [...m.values()].reduce((a, b) => a + b, 0);
    return {
      total,
      rows: CHANGE_REASONS
        .map((r) => ({ ...r, count: m.get(r.value) || 0 }))
        .filter((r) => r.count > 0)
        .sort((a, b) => b.count - a.count),
    };
  }, [usageLogs]);

  // Skin check summary — how often skin was noted as pink or irritated.
  const skinStat = useMemo(() => {
    const sess = usageLogs.filter((l) => l.putOnAt && l.skin);
    const flagged = sess.filter((l) => l.skin === 'irritated' || l.skin === 'pink').length;
    return { total: sess.length, flagged };
  }, [usageLogs]);

  // Top products
  const topProducts = useMemo(() => {
    const m = new Map();
    usageLogs.forEach((l) => m.set(l.productId, (m.get(l.productId) || 0) + 1));
    return [...m.entries()]
      .map(([id, count]) => ({ product: products.find((p) => p.id === id), count }))
      .filter((x) => x.product)
      .sort((a, b) => b.count - a.count)
      .slice(0, 5);
  }, [usageLogs, products]);

  // Performance per product
  const performance = useMemo(() => {
    const m = new Map();
    usageLogs.forEach((l) => {
      if (!m.has(l.productId)) m.set(l.productId, { total: 0, leaks: 0, dry: 0 });
      const e = m.get(l.productId);
      e.total += 1;
      if (l.performance === 'leak') e.leaks += 1;
      if (l.performance === 'dry') e.dry += 1;
    });
    return [...m.entries()]
      .map(([id, e]) => ({ product: products.find((p) => p.id === id), ...e }))
      .filter((x) => x.product && x.total >= 2)
      .sort((a, b) => (b.leaks / b.total) - (a.leaks / a.total));
  }, [usageLogs, products]);

  // Usage by location
  const locationUsage = useMemo(() => {
    const m = new Map();
    usageLogs.forEach((l) => {
      if (!l.locationId) return;
      m.set(l.locationId, (m.get(l.locationId) || 0) + 1);
    });
    return [...m.entries()]
      .map(([id, count]) => ({
        location: locations.find((loc) => loc.id === id),
        count,
      }))
      .filter((x) => x.location)
      .sort((a, b) => b.count - a.count);
  }, [usageLogs, locations]);

  // Stats
  const totalUses = usageLogs.length;
  const firstLog = usageLogs.length ? Math.min(...usageLogs.map((l) => l.timestamp)) : null;
  const trackingDays = firstLog
    ? Math.max(1, Math.ceil((Date.now() - firstLog) / (24 * 3600 * 1000)))
    : 0;
  const avgPerDay = trackingDays > 0 ? (totalUses / trackingDays).toFixed(1) : '0';

  // Cost & value, from each product's pack cost ÷ pack size.
  const costAnalysis = useMemo(() => {
    const rows = [];
    let totalSpent = 0;
    products.forEach((p) => {
      const uc = unitCost(p);
      if (uc == null) return;
      const uses = usageLogs.filter((l) => l.productId === p.id).length;
      const spent = uses * uc;
      totalSpent += spent;
      const perf = usageLogs.filter((l) => l.productId === p.id && l.performance);
      const leaks = perf.filter((l) => l.performance === 'leak').length;
      const leakRate = perf.length ? leaks / perf.length : null;
      const perGood = leakRate != null && leakRate < 1 ? uc / (1 - leakRate) : uc;
      rows.push({ product: p, unit: uc, uses, spent, leakRate, perGood });
    });
    rows.sort((a, b) => b.spent - a.spent);
    const costPerDay = trackingDays > 0 ? totalSpent / trackingDays : 0;
    return { rows, totalSpent, costPerDay, monthly: costPerDay * 30 };
  }, [products, usageLogs, trackingDays]);

  // Fluid intake — drinks logged, by kind, and a rough daily volume.
  const intakeAgg = useMemo(() => {
    const drinks = logs.filter(isDrink);
    const byKind = {}; let totalOz = 0; let exactCount = 0;
    drinks.forEach((d) => {
      byKind[d.kind] = (byKind[d.kind] || 0) + 1;
      totalOz += drinkVolumeOz(d, drinkPresets); // exact oz when given, else preset bucket
      if (Number(d.oz) > 0) exactCount += 1;
    });
    return {
      count: drinks.length,
      totalOz,
      exactCount,
      perDay: trackingDays > 0 ? drinks.length / trackingDays : 0,
      ozPerDay: trackingDays > 0 ? totalOz / trackingDays : 0,
      kindRows: DRINK_KINDS.map((k) => ({ ...k, count: byKind[k.value] || 0 })).filter((r) => r.count > 0),
    };
  }, [logs, trackingDays, drinkPresets]);

  // Format an hour (0–23) as a compact 12-hour label, e.g. 3a, 12p, 9p.
  const fmtHour = (h) => {
    const hr = ((h % 24) + 24) % 24;
    const h12 = hr % 12 === 0 ? 12 : hr % 12;
    return `${h12}${hr < 12 ? 'a' : 'p'}`;
  };

  // Auto section numbering — increments only for sections that actually render,
  // so inserting/removing a section never desyncs the labels.
  let secCount = 0;
  const secNum = () => String(++secCount).padStart(2, '0');

  const hasWetting = wettingAgg.totalWettings > 0;

  if (usageLogs.length === 0) {
    return (
      <div className="empty-state">
        <BarChart3 size={28} style={{ color: 'var(--ink-mute)' }} />
        <div className="display" style={{ fontSize: 22, marginTop: 12 }}>No data yet</div>
        <p style={{ marginTop: 8, color: 'var(--ink-soft)' }}>
          Log a few uses and patterns will start appearing here.
        </p>
      </div>
    );
  }

  return (
    <div>
      <div style={{ marginBottom: 24 }}>
        <span className="display" style={{ fontSize: 24 }}>Insights</span>
      </div>

      <div style={{
        display: 'grid', gridTemplateColumns: '1fr 1fr 1fr',
        gap: 16, marginBottom: 32,
      }}>
        <div className="stat-divider" style={{ paddingTop: 10 }}>
          <div className="num" style={{ fontSize: 32, lineHeight: 1 }}>{totalUses}</div>
          <div className="eyebrow" style={{ marginTop: 6 }}>Total uses</div>
        </div>
        <div className="stat-divider" style={{ paddingTop: 10 }}>
          <div className="num" style={{ fontSize: 32, lineHeight: 1 }}>{avgPerDay}</div>
          <div className="eyebrow" style={{ marginTop: 6 }}>Avg / day</div>
        </div>
        <div className="stat-divider" style={{ paddingTop: 10 }}>
          <div className="num" style={{ fontSize: 32, lineHeight: 1 }}>{trackingDays}</div>
          <div className="eyebrow" style={{ marginTop: 6 }}>Days tracked</div>
        </div>
      </div>

      {legacyInfo.legacy > 0 && (
        <div className="card" style={{
          padding: '12px 14px', marginBottom: 28,
          borderLeft: '3px solid var(--accent)',
        }}>
          <div style={{ fontSize: 13 }}>
            {legacyInfo.legacy} of {legacyInfo.total} logged wears predate detailed tracking
          </div>
          <div style={{ fontSize: 12, color: 'var(--ink-mute)', marginTop: 4, lineHeight: 1.45 }}>
            Those early logs have no put-on/take-off time, wettings, or context.
            Timing, wetting, capacity, booster and context sections below use only
            the {legacyInfo.detailed} detailed wear{legacyInfo.detailed !== 1 ? 's' : ''};
            totals, leak rate and cost include all {legacyInfo.total}.
          </div>
        </div>
      )}

      {/* Daily chart */}
      <section style={{ marginBottom: 36 }}>
        <SectionHeader number={secNum()} title="Last 14 days" />
        <div className="card" style={{ padding: 16 }}>
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={dailyData} margin={{ top: 8, right: 4, left: -16, bottom: 0 }}>
              <XAxis
                dataKey="date" tick={{ fontSize: 10, fill: '#8A8478' }}
                axisLine={{ stroke: '#DDD6C5' }} tickLine={false} interval={1}
              />
              <YAxis
                tick={{ fontSize: 10, fill: '#8A8478' }}
                axisLine={false} tickLine={false} allowDecimals={false}
              />
              <Tooltip
                contentStyle={{
                  background: '#FBF8F2', border: '1px solid #DDD6C5',
                  borderRadius: 6, fontSize: 12,
                }}
                cursor={{ fill: 'rgba(31,42,36,0.05)' }}
              />
              <Bar dataKey="Day" stackId="a" fill="#C9985A" radius={[0, 0, 0, 0]} />
              <Bar dataKey="Night" stackId="a" fill="#2F4A3F" radius={[3, 3, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
          <div style={{
            display: 'flex', gap: 16, justifyContent: 'center',
            marginTop: 8, fontSize: 12, color: 'var(--ink-soft)',
          }}>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
              <span style={{ width: 10, height: 10, background: '#C9985A', borderRadius: 2 }} /> Daytime
            </span>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
              <span style={{ width: 10, height: 10, background: '#2F4A3F', borderRadius: 2 }} /> Overnight
            </span>
          </div>
        </div>
      </section>

      {/* Day / night */}
      <section style={{ marginBottom: 36 }}>
        <SectionHeader number={secNum()} title="Day vs. night" />
        <div className="card" style={{
          padding: 16, display: 'flex', alignItems: 'center', gap: 16, flexWrap: 'wrap',
        }}>
          <div style={{ width: 160, height: 160, flexShrink: 0 }}>
            <ResponsiveContainer>
              <PieChart>
                <Pie data={periodSplit} dataKey="value" innerRadius={48} outerRadius={70} paddingAngle={2}>
                  {periodSplit.map((d, i) => <Cell key={i} fill={d.color} />)}
                </Pie>
              </PieChart>
            </ResponsiveContainer>
          </div>
          <div style={{ flex: 1, minWidth: 160 }}>
            {periodSplit.map((s) => (
              <div key={s.name} style={{ marginBottom: 14 }}>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: 6 }}>
                  <span style={{
                    width: 8, height: 8, borderRadius: 2,
                    background: s.color, display: 'inline-block',
                  }} />
                  <span style={{ fontSize: 13 }}>{s.name}</span>
                </div>
                <div className="num" style={{ fontSize: 24, marginTop: 2 }}>
                  {s.value}
                  <span style={{
                    fontSize: 13, color: 'var(--ink-mute)',
                    fontFamily: 'inherit', marginLeft: 6,
                  }}>
                    {totalUses ? `${Math.round((s.value / totalUses) * 100)}%` : '—'}
                  </span>
                </div>
                {avgWornByPeriod[s.name] != null && (
                  <div style={{ fontSize: 11, color: 'var(--ink-mute)', marginTop: 3 }}>
                    avg {formatDuration(avgWornByPeriod[s.name])} worn
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Wetting analysis */}
      {hasWetting && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="Wetting analysis" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)',
            marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            Across every diaper you've logged a wetting on. "Load" is a weighted
            saturation score — light 1, moderate 2, heavy 3, very heavy 4.
          </p>

          <div style={{
            display: 'grid', gridTemplateColumns: '1fr 1fr 1fr',
            gap: 16, marginBottom: 20,
          }}>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 28, lineHeight: 1 }}>
                {wettingAgg.totalWettings}
              </div>
              <div className="eyebrow" style={{ marginTop: 6 }}>Wettings</div>
            </div>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 28, lineHeight: 1 }}>
                {wettingAgg.avgPerDiaper.toFixed(1)}
              </div>
              <div className="eyebrow" style={{ marginTop: 6 }}>Avg / diaper</div>
            </div>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 28, lineHeight: 1 }}>
                {wettingAgg.avgPerWetDiaper.toFixed(1)}
              </div>
              <div className="eyebrow" style={{ marginTop: 6 }}>Avg / wet diaper</div>
            </div>
          </div>

          {/* Amount distribution */}
          <div className="card" style={{ padding: 4, marginBottom: 20 }}>
            {WETNESS.map((w) => {
              const count = wettingAgg.amountCounts[w.value] || 0;
              const pct = wettingAgg.totalWettings
                ? (count / wettingAgg.totalWettings) * 100 : 0;
              return (
                <div key={w.value} className="row-divider" style={{ padding: '12px 14px' }}>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                    <Droplets size={14} style={{ color: 'var(--accent)', alignSelf: 'center' }} />
                    <span style={{ flex: 1, fontSize: 14 }}>{w.label}</span>
                    <span className="num" style={{ fontSize: 16 }}>{count}</span>
                    <span style={{ fontSize: 11, color: 'var(--ink-mute)', marginLeft: 4 }}>
                      {wettingAgg.totalWettings ? `${Math.round(pct)}%` : ''}
                    </span>
                  </div>
                  <div style={{
                    height: 3, background: 'var(--line-soft)',
                    borderRadius: 2, marginTop: 8, marginLeft: 24,
                  }}>
                    <div style={{
                      height: '100%', width: `${pct}%`,
                      background: 'var(--accent)', borderRadius: 2,
                    }} />
                  </div>
                </div>
              );
            })}
          </div>

          {/* Wetting time of day */}
          <div style={{ marginBottom: 20 }}>
            <p style={{
              fontSize: 12, color: 'var(--ink-mute)',
              marginBottom: 8, fontStyle: 'italic',
            }}>
              When wettings tend to happen, by hour of day.
            </p>
            <div className="card" style={{ padding: 16 }}>
              <ResponsiveContainer width="100%" height={170}>
                <BarChart data={wettingByHour} margin={{ top: 8, right: 4, left: -16, bottom: 0 }}>
                  <XAxis
                    dataKey="hour" tick={{ fontSize: 10, fill: '#8A8478' }}
                    axisLine={{ stroke: '#DDD6C5' }} tickLine={false}
                    interval={2} tickFormatter={fmtHour}
                  />
                  <YAxis
                    tick={{ fontSize: 10, fill: '#8A8478' }}
                    axisLine={false} tickLine={false} allowDecimals={false}
                  />
                  <Tooltip
                    contentStyle={{
                      background: '#FBF8F2', border: '1px solid #DDD6C5',
                      borderRadius: 6, fontSize: 12,
                    }}
                    cursor={{ fill: 'rgba(31,42,36,0.05)' }}
                    labelFormatter={(h) => fmtHour(h)}
                  />
                  <Bar dataKey="count" fill="#C9985A" radius={[3, 3, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>
          </div>

          {/* Capacity before leak, per product */}
          {capacityByProduct.length > 0 && (
            <>
              <p style={{
                fontSize: 12, color: 'var(--ink-mute)',
                marginBottom: 12, fontStyle: 'italic',
              }}>
                How much each product tends to hold — the average load when it
                leaked vs. the most it held while staying dry.
              </p>
              <div className="card" style={{ padding: 4 }}>
                {capacityByProduct.map((c) => (
                  <div key={c.product.id} className="row-divider" style={{ padding: '12px 14px' }}>
                    <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                      <ProductThumb
                        product={c.product} thumbs={thumbs} size={20}
                        style={{ alignSelf: 'center' }}
                      />
                      <span style={{ flex: 1, fontSize: 14 }}>{productDisplayName(c.product)}</span>
                    </div>
                    <div style={{
                      display: 'flex', gap: 12, marginTop: 6,
                      marginLeft: 22, fontSize: 12, flexWrap: 'wrap',
                    }}>
                      <span style={{ color: c.avgLeakLoad != null ? 'var(--danger)' : 'var(--ink-mute)' }}>
                        {c.avgLeakLoad != null
                          ? <>leaked at <span className="num">~{c.avgLeakLoad.toFixed(1)}</span> load <span style={{ color: 'var(--ink-mute)' }}>({c.leakCount}×)</span></>
                          : 'no leaks logged'}
                      </span>
                      {c.maxHeld != null && (
                        <span style={{ color: 'var(--primary)' }}>
                          held up to <span className="num">{c.maxHeld}</span> dry <span style={{ color: 'var(--ink-mute)' }}>({c.heldCount}×)</span>
                        </span>
                      )}
                    </div>
                  </div>
                ))}
              </div>
              {(globalCap.dryCeiling != null || globalCap.leakFloor != null) && (
                <p style={{
                  fontSize: 11, color: 'var(--ink-mute)',
                  marginTop: 10, fontStyle: 'italic',
                }}>
                  Across all products, the most held dry was a load of{' '}
                  <span className="num">{globalCap.dryCeiling ?? '—'}</span>
                  {globalCap.leakFloor != null && (
                    <>; leaks have started as low as <span className="num">{globalCap.leakFloor}</span></>
                  )}. A worn diaper nearing these gets a heads-up on its wettings screen.
                </p>
              )}
            </>
          )}
        </section>
      )}

      {/* Toilet & accidents */}
      {eliminationAgg.any && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="Toilet & accidents" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)',
            marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            Toilet uses (diaper off, so excluded from capacity), BMs in the diaper,
            and how voluntary your wettings were.
          </p>
          <div style={{
            display: 'grid', gridTemplateColumns: '1fr 1fr 1fr',
            gap: 16, marginBottom: eliminationAgg.controlTotal > 0 ? 20 : 0,
          }}>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 28, lineHeight: 1 }}>{eliminationAgg.toilet}</div>
              <div className="eyebrow" style={{ marginTop: 6 }}>Toilet uses</div>
            </div>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 28, lineHeight: 1 }}>{eliminationAgg.bm}</div>
              <div className="eyebrow" style={{ marginTop: 6 }}>BMs in diaper</div>
            </div>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 28, lineHeight: 1 }}>{eliminationAgg.control.accident}</div>
              <div className="eyebrow" style={{ marginTop: 6 }}>Accidents</div>
            </div>
          </div>
          {eliminationAgg.controlTotal > 0 && (
            <div className="card" style={{ padding: 4 }}>
              {CONTROL_LEVELS.map((c) => {
                const count = eliminationAgg.control[c.value] || 0;
                const pct = eliminationAgg.controlTotal ? (count / eliminationAgg.controlTotal) * 100 : 0;
                return (
                  <div key={c.value} className="row-divider" style={{ padding: '12px 14px' }}>
                    <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                      <span style={{ flex: 1, fontSize: 14 }}>{c.label}</span>
                      <span className="num" style={{ fontSize: 16 }}>{count}</span>
                      <span style={{ fontSize: 11, color: 'var(--ink-mute)', marginLeft: 4 }}>
                        {Math.round(pct)}%
                      </span>
                    </div>
                    <div style={{ height: 3, background: 'var(--line-soft)', borderRadius: 2, marginTop: 8 }}>
                      <div style={{ height: '100%', width: `${pct}%`, background: 'var(--accent)', borderRadius: 2 }} />
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </section>
      )}

      {/* Leak detail */}
      {leakDetailAgg.leakCount > 0 && (leakDetailAgg.escapeRows.length > 0 || leakDetailAgg.severityRows.length > 0) && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="Leak detail" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)',
            marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            Where leaks escaped and how bad, on {leakDetailAgg.detailed} of {leakDetailAgg.leakCount} leak{leakDetailAgg.leakCount !== 1 ? 's' : ''} with detail recorded.
          </p>
          {leakDetailAgg.escapeRows.length > 0 && (
            <div className="card" style={{ padding: 4, marginBottom: leakDetailAgg.severityRows.length ? 16 : 0 }}>
              {leakDetailAgg.escapeRows.map((e) => (
                <div key={e.value} className="row-divider" style={{ padding: '12px 14px', display: 'flex', alignItems: 'baseline', gap: 10 }}>
                  <span style={{ flex: 1, fontSize: 14 }}>{e.label}</span>
                  <span className="num" style={{ fontSize: 16, color: 'var(--danger)' }}>{e.count}</span>
                </div>
              ))}
            </div>
          )}
          {leakDetailAgg.severityRows.length > 0 && (
            <div className="card" style={{ padding: 4 }}>
              {leakDetailAgg.severityRows.map((x) => (
                <div key={x.value} className="row-divider" style={{ padding: '12px 14px', display: 'flex', alignItems: 'baseline', gap: 10 }}>
                  <span style={{ flex: 1, fontSize: 14 }}>{x.label}</span>
                  <span className="num" style={{ fontSize: 16 }}>{x.count}</span>
                </div>
              ))}
            </div>
          )}
        </section>
      )}

      {/* Fluid intake */}
      {intakeAgg.count > 0 && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="Fluid intake" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)',
            marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            Drinks you've logged. As this builds up it can be lined up against wetting timing and volume.{intakeAgg.count > 0 && (intakeAgg.exactCount > 0 ? ` Volume uses exact amounts where given (${intakeAgg.exactCount} of ${intakeAgg.count}) and your size presets otherwise.` : ' Volume uses your size presets — add exact amounts on a drink to refine it.')}
          </p>
          <div style={{
            display: 'grid', gridTemplateColumns: '1fr 1fr 1fr',
            gap: 16, marginBottom: 20,
          }}>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 24, lineHeight: 1 }}>{intakeAgg.count}</div>
              <div className="eyebrow" style={{ marginTop: 6 }}>Drinks</div>
            </div>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 24, lineHeight: 1 }}>{intakeAgg.perDay.toFixed(1)}</div>
              <div className="eyebrow" style={{ marginTop: 6 }}>Per day</div>
            </div>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 24, lineHeight: 1 }}>{Math.round(intakeAgg.ozPerDay)}</div>
              <div className="eyebrow" style={{ marginTop: 6 }}>oz / day (est.)</div>
            </div>
          </div>
          <div className="card" style={{ padding: 4 }}>
            {intakeAgg.kindRows.map((k) => {
              const max = intakeAgg.kindRows[0].count;
              const pct = max ? (k.count / max) * 100 : 0;
              return (
                <div key={k.value} className="row-divider" style={{ padding: '12px 14px' }}>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                    <span style={{ flex: 1, fontSize: 14 }}>{k.label}</span>
                    <span className="num" style={{ fontSize: 16 }}>{k.count}</span>
                  </div>
                  <div style={{ height: 3, background: 'var(--line-soft)', borderRadius: 2, marginTop: 8 }}>
                    <div style={{ height: '100%', width: `${pct}%`, background: 'var(--primary)', borderRadius: 2 }} />
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}

      {/* Cost & value */}
      {costAnalysis.rows.length > 0 && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="Cost & value" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)',
            marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            From each product's pack cost ÷ pack size, in whatever currency you entered. Add those on a product to include it here.
          </p>
          <div style={{
            display: 'grid', gridTemplateColumns: '1fr 1fr 1fr',
            gap: 16, marginBottom: 20,
          }}>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 24, lineHeight: 1 }}>{fmtMoney(costAnalysis.monthly)}</div>
              <div className="eyebrow" style={{ marginTop: 6 }}>Est. / month</div>
            </div>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 24, lineHeight: 1 }}>{fmtMoney(costAnalysis.costPerDay)}</div>
              <div className="eyebrow" style={{ marginTop: 6 }}>Avg / day</div>
            </div>
            <div className="stat-divider" style={{ paddingTop: 10 }}>
              <div className="num" style={{ fontSize: 24, lineHeight: 1 }}>{fmtMoney(costAnalysis.totalSpent)}</div>
              <div className="eyebrow" style={{ marginTop: 6 }}>Logged spend</div>
            </div>
          </div>
          <div className="card" style={{ padding: 4 }}>
            {costAnalysis.rows.map(({ product, unit, uses, spent, leakRate, perGood }) => (
              <div key={product.id} className="row-divider" style={{ padding: '12px 14px' }}>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                  <ProductThumb product={product} thumbs={thumbs} size={20} style={{ alignSelf: 'center' }} />
                  <span style={{ flex: 1, fontSize: 14 }}>{productDisplayName(product)}</span>
                  <span className="num" style={{ fontSize: 15 }}>{fmtMoney(unit)}</span>
                  <span style={{ fontSize: 11, color: 'var(--ink-mute)', marginLeft: 4 }}>each</span>
                </div>
                <div style={{
                  display: 'flex', gap: 12, marginTop: 6, marginLeft: 30,
                  fontSize: 12, color: 'var(--ink-mute)', flexWrap: 'wrap',
                }}>
                  <span>{uses} used · {fmtMoney(spent)} spent</span>
                  {leakRate != null && leakRate > 0 && (
                    <span style={{ color: 'var(--primary)' }}>
                      {fmtMoney(perGood)} per leak-free wear
                    </span>
                  )}
                </div>
              </div>
            ))}
          </div>
        </section>
      )}

      {/* Boosters */}
      {boosterEffect.withB.n > 0 && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="Boosters" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)',
            marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            Whether adding a booster changed how often things leaked or how much was held.
          </p>
          <div className="card" style={{ padding: 4 }}>
            {[{ key: 'withB', label: 'With booster' }, { key: 'withoutB', label: 'Without booster' }].map(({ key, label }) => {
              const g = boosterEffect[key];
              return (
                <div key={key} className="row-divider" style={{ padding: '12px 14px' }}>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                    <span style={{ flex: 1, fontSize: 14 }}>{label}</span>
                    <span style={{ fontSize: 12, color: 'var(--ink-mute)' }}>
                      {g.n} session{g.n !== 1 ? 's' : ''}
                    </span>
                  </div>
                  <div style={{
                    display: 'flex', gap: 12, marginTop: 6,
                    fontSize: 12, flexWrap: 'wrap',
                  }}>
                    <span style={{ color: g.leakRate ? 'var(--danger)' : 'var(--ink-mute)' }}>
                      {g.leakRate == null ? 'no leak data' : `${Math.round(g.leakRate * 100)}% leaked`}
                    </span>
                    <span style={{ color: 'var(--accent)' }}>
                      {g.avgLoad == null ? 'no load data' : `avg load ${g.avgLoad.toFixed(1)}`}
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}

      {/* By context */}
      {contextStats.length > 0 && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="By context" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)',
            marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            Where you were wearing it, and how often each leaked.
          </p>
          <div className="card" style={{ padding: 4 }}>
            {contextStats.map((c) => {
              const max = contextStats[0].count;
              const pct = (c.count / max) * 100;
              return (
                <div key={c.value} className="row-divider" style={{ padding: '12px 14px' }}>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                    <span style={{ flex: 1, fontSize: 14 }}>{c.label}</span>
                    <span className="num" style={{ fontSize: 16 }}>{c.count}</span>
                    {c.perf > 0 && (
                      <span style={{
                        fontSize: 11, marginLeft: 4,
                        color: c.leaks ? 'var(--danger)' : 'var(--ink-mute)',
                      }}>
                        {Math.round((c.leaks / c.perf) * 100)}% leak
                      </span>
                    )}
                  </div>
                  <div style={{
                    height: 3, background: 'var(--line-soft)',
                    borderRadius: 2, marginTop: 8,
                  }}>
                    <div style={{
                      height: '100%', width: `${pct}%`,
                      background: 'var(--primary)', borderRadius: 2,
                    }} />
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}

      {/* Why changes happen */}
      {reasonStats.total > 0 && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="Why changes happen" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)',
            marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            {skinStat.total > 0
              ? `Skin noted as pink or irritated on ${skinStat.flagged} of ${skinStat.total} change${skinStat.total !== 1 ? 's' : ''}.`
              : 'What prompts a change, across your logged take-offs.'}
          </p>
          <div className="card" style={{ padding: 4 }}>
            {reasonStats.rows.map((r) => {
              const pct = (r.count / reasonStats.total) * 100;
              return (
                <div key={r.value} className="row-divider" style={{ padding: '12px 14px' }}>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                    <span style={{ flex: 1, fontSize: 14 }}>{r.label}</span>
                    <span className="num" style={{ fontSize: 16 }}>{r.count}</span>
                    <span style={{ fontSize: 11, color: 'var(--ink-mute)', marginLeft: 4 }}>
                      {Math.round(pct)}%
                    </span>
                  </div>
                  <div style={{
                    height: 3, background: 'var(--line-soft)',
                    borderRadius: 2, marginTop: 8,
                  }}>
                    <div style={{
                      height: '100%', width: `${pct}%`,
                      background: 'var(--accent)', borderRadius: 2,
                    }} />
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}

      {/* Usage by location */}
      {locationUsage.length > 0 && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="Usage by location" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)',
            marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            Where you're consuming most. Helpful for knowing where to keep more stock.
          </p>
          <div className="card" style={{ padding: 4 }}>
            {locationUsage.map(({ location, count }) => {
              const max = locationUsage[0].count;
              const pct = (count / max) * 100;
              return (
                <div key={location.id} className="row-divider" style={{ padding: '12px 14px' }}>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                    <LocationIcon name={location.icon} size={14} style={{ color: 'var(--ink-soft)', alignSelf: 'center' }} />
                    <span style={{ flex: 1, fontSize: 14 }}>{location.name}</span>
                    <span className="num" style={{ fontSize: 16 }}>{count}</span>
                    <span style={{ fontSize: 11, color: 'var(--ink-mute)', marginLeft: 4 }}>
                      {totalUses ? `${Math.round((count / totalUses) * 100)}%` : ''}
                    </span>
                  </div>
                  <div style={{
                    height: 3, background: 'var(--line-soft)',
                    borderRadius: 2, marginTop: 8, marginLeft: 24,
                  }}>
                    <div style={{
                      height: '100%', width: `${pct}%`,
                      background: 'var(--accent)', borderRadius: 2,
                    }} />
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}

      {/* Top products */}
      {topProducts.length > 0 && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="Most used" />
          <div className="card" style={{ padding: 4 }}>
            {topProducts.map(({ product, count }, i) => {
              const max = topProducts[0].count;
              const pct = (count / max) * 100;
              return (
                <div key={product.id} className="row-divider" style={{ padding: '12px 14px' }}>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                    <span className="num" style={{
                      fontSize: 14, color: 'var(--ink-mute)', width: 18,
                    }}>
                      {i + 1}.
                    </span>
                    <ProductThumb
                      product={product} thumbs={thumbs} size={20}
                      style={{ alignSelf: 'center' }}
                    />
                    <span style={{ flex: 1, fontSize: 14 }}>{productDisplayName(product)}</span>
                    <span className="num" style={{ fontSize: 16 }}>{count}</span>
                  </div>
                  <div style={{
                    height: 3, background: 'var(--line-soft)',
                    borderRadius: 2, marginTop: 8, marginLeft: 28,
                  }}>
                    <div style={{
                      height: '100%', width: `${pct}%`,
                      background: 'var(--primary)', borderRadius: 2,
                    }} />
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}

      {/* Performance */}
      {performance.length > 0 && (
        <section style={{ marginBottom: 36 }}>
          <SectionHeader number={secNum()} title="Performance" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)',
            marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            Leak rate per product (only products with 2+ logs shown).
          </p>
          <div className="card" style={{ padding: 4 }}>
            {performance.map(({ product, total, leaks, dry }) => {
              const leakRate = (leaks / total) * 100;
              const dryRate = (dry / total) * 100;
              return (
                <div key={product.id} className="row-divider" style={{ padding: '12px 14px' }}>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                    <ProductThumb
                      product={product} thumbs={thumbs} size={20}
                      style={{ alignSelf: 'center' }}
                    />
                    <span style={{ flex: 1, fontSize: 14 }}>{productDisplayName(product)}</span>
                    <span style={{ fontSize: 12, color: 'var(--ink-mute)' }}>
                      {total} log{total !== 1 ? 's' : ''}
                    </span>
                  </div>
                  <div style={{
                    display: 'flex', gap: 12, marginTop: 6,
                    marginLeft: 22, fontSize: 12,
                  }}>
                    <span style={{ color: leakRate > 0 ? 'var(--danger)' : 'var(--ink-mute)' }}>
                      {leaks} leak{leaks !== 1 ? 's' : ''} <span className="num">({Math.round(leakRate)}%)</span>
                    </span>
                    <span style={{ color: 'var(--primary)' }}>
                      {dry} dry <span className="num">({Math.round(dryRate)}%)</span>
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}

      {/* Days remaining */}
      <section style={{ marginBottom: 36 }}>
        <SectionHeader number={secNum()} title="Estimated days remaining" />
        <p style={{
          fontSize: 12, color: 'var(--ink-mute)',
          marginTop: -8, marginBottom: 12, fontStyle: 'italic',
        }}>
          Based on usage in the last 14 days. Restock before items run out.
        </p>
        <div className="card" style={{ padding: 4 }}>
          {products.length === 0 && (
            <div style={{ padding: 16, color: 'var(--ink-mute)', fontSize: 13 }}>
              No products yet.
            </div>
          )}
          {products.map((p) => {
            const days = daysRemainingMap[p.id];
            return (
              <div
                key={p.id}
                className="row-divider"
                style={{
                  padding: '12px 14px',
                  display: 'flex', alignItems: 'center', gap: 10,
                }}
              >
                <ProductThumb product={p} thumbs={thumbs} size={20} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 14 }}>{productDisplayName(p)}</div>
                  <div style={{ fontSize: 12, color: 'var(--ink-mute)' }}>
                    {totalStock(p)} on hand total
                  </div>
                </div>
                <div style={{ textAlign: 'right' }}>
                  <div className="num" style={{ fontSize: 18 }}>
                    {days == null ? '—' : (Number.isFinite(days) ? `${days}d` : '∞')}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </section>
    </div>
  );
}
LEDGER_EOF

mkdir -p "$(dirname src/App.jsx)"
cat > src/App.jsx << 'LEDGER_EOF'
import React, { useState, useEffect, useMemo } from 'react';
import {
  Plus, Settings as SettingsIcon, LayoutDashboard,
  Package, ClipboardList, BarChart3, Repeat,
  ShieldAlert, X,
} from 'lucide-react';

import { Toast, ConfirmDialog } from './components/Common';
import Dashboard from './components/Dashboard';
import Inventory from './components/Inventory';
import History from './components/History';
import Insights from './components/Insights';
import ProductForm from './components/ProductForm';
import LogForm from './components/LogForm';
import WearForm from './components/WearForm';
import TakeOffForm from './components/TakeOffForm';
import MoveForm from './components/MoveForm';
import RestockForm from './components/RestockForm';
import LocationManager from './components/LocationManager';
import Settings from './components/Settings';
import PhotoViewer from './components/PhotoViewer';
import WettingForm from './components/WettingForm';
import NoteForm from './components/NoteForm';
import DrinkForm from './components/DrinkForm';
import { DEFAULT_DRINK_PRESETS, normalizeDrinkPresets } from './lib/intake';
import { CHANGE_OUT_WINDOW_MS } from './lib/session';

import {
  getAllProducts, getAllLocations, getAllLogs, getAllThumbs,
  saveProduct, removeProduct, saveLocation, removeLocation,
  saveLog, removeLog, kvGet,
} from './lib/storage';
import { stockAt, isWornNow, formatDuration } from './lib/helpers';

export default function App() {
  // Core data
  const [products, setProducts] = useState([]);
  const [locations, setLocations] = useState([]);
  const [logs, setLogs] = useState([]);
  const [thumbs, setThumbs] = useState({});
  const [loading, setLoading] = useState(true);

  // Backup reminder
  const [lastBackupAt, setLastBackupAt] = useState(null);
  const [drinkPresets, setDrinkPresets] = useState(DEFAULT_DRINK_PRESETS);
  const [backupDismissed, setBackupDismissed] = useState(false);

  // UI state
  const [tab, setTab] = useState('home');
  const [toastMsg, setToastMsg] = useState('');

  // Modals
  const [productFormOpen, setProductFormOpen] = useState(false);
  const [editingProduct, setEditingProduct] = useState(null);

  const [logFormOpen, setLogFormOpen] = useState(false);
  const [editingLog, setEditingLog] = useState(null);
  const [defaultLogProduct, setDefaultLogProduct] = useState(null);

  // Wear-session modals
  const [wearFormOpen, setWearFormOpen] = useState(false);
  const [wearDefaultProduct, setWearDefaultProduct] = useState(null);
  // When the user picks "take off and change into another," this holds the
  // take-off's id so the next put-on can be marked as a direct change-out.
  const [pendingChangeFromId, setPendingChangeFromId] = useState(null);
  const [takeOffEntry, setTakeOffEntry] = useState(null);
  const [takeOffThen, setTakeOffThen] = useState('none');

  // Wetting tracking modal — holds the wear-session log being edited
  const [wettingEntry, setWettingEntry] = useState(null);

  // Note log modal
  const [noteFormOpen, setNoteFormOpen] = useState(false);
  const [editingNote, setEditingNote] = useState(null);
  const [noteContext, setNoteContext] = useState(null);

  const [drinkFormOpen, setDrinkFormOpen] = useState(false);
  const [editingDrink, setEditingDrink] = useState(null);

  const [moveFormOpen, setMoveFormOpen] = useState(false);
  const [moveProductId, setMoveProductId] = useState(null);

  const [restockProduct, setRestockProduct] = useState(null);
  const [locationsOpen, setLocationsOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [photoViewerProductId, setPhotoViewerProductId] = useState(null);

  const [confirmDeleteProduct, setConfirmDeleteProduct] = useState(null);
  const [confirmDeleteLog, setConfirmDeleteLog] = useState(null);

  // Initial load
  const loadAll = async () => {
    setLoading(true);
    try {
      const [p, l, lg, th] = await Promise.all([
        getAllProducts(),
        getAllLocations(),
        getAllLogs(),
        getAllThumbs(),
      ]);
      setProducts(p || []);
      setLocations(l || []);
      setLogs(lg || []);
      setThumbs(th || {});
      try { setLastBackupAt(await kvGet('lastBackupAt')); } catch { /* ignore */ }
      try { setDrinkPresets(normalizeDrinkPresets(await kvGet('drinkSizePresets'))); } catch { /* ignore */ }
    } catch (e) {
      console.error('Load failed', e);
    }
    setLoading(false);
  };

  useEffect(() => { loadAll(); }, []);

  // Derived: estimate days remaining based on last 14d usage
  const daysRemainingMap = useMemo(() => {
    const map = {};
    const cutoff = Date.now() - 14 * 24 * 3600 * 1000;
    const usageLogs = logs.filter((l) => l.type !== 'move');
    products.forEach((p) => {
      const productLogs = usageLogs.filter((l) => l.productId === p.id && l.timestamp >= cutoff);
      const total = Object.values(p.stock || {}).reduce((s, n) => s + (Number(n) || 0), 0);
      if (productLogs.length === 0) {
        map[p.id] = null;
      } else {
        const span = Math.max(1, Math.ceil((Date.now() - cutoff) / (24 * 3600 * 1000)));
        const perDay = productLogs.length / span;
        map[p.id] = perDay > 0 ? Math.floor(total / perDay) : Infinity;
      }
    });
    return map;
  }, [products, logs]);

  // The diaper currently being worn (if any) — derived from logs so it
  // survives reloads. At most one active session at a time.
  const activeWear = useMemo(() => logs.find(isWornNow) || null, [logs]);

  // === Wear-session handlers ===
  const handlePutOn = async (entry) => {
    // Auto-link: if there's a recent take-off within the change-out window
    // (and this put-on doesn't already carry a link from an explicit "change into"
    // flow), record it as a direct change-out on both sides.
    let toSave = entry;
    if (pendingChangeFromId) {
      toSave = { ...toSave, changedFromId: pendingChangeFromId };
      const src = logs.find((l) => l.id === pendingChangeFromId);
      if (src) {
        const linked = { ...src, changedToId: toSave.id };
        await saveLog(linked);
        setLogs((prev) => prev.map((l) => l.id === linked.id ? linked : l));
      }
    } else if (!toSave.changedFromId) {
      const recentTakeOff = [...logs]
        .filter((l) => l.type !== 'move' && l.type !== 'note' && l.takenOffAt && !l.changedToId)
        .sort((a, b) => (b.takenOffAt || 0) - (a.takenOffAt || 0))[0];
      if (recentTakeOff && toSave.putOnAt - recentTakeOff.takenOffAt <= CHANGE_OUT_WINDOW_MS) {
        toSave = { ...toSave, changedFromId: recentTakeOff.id };
        const linked = { ...recentTakeOff, changedToId: toSave.id };
        await saveLog(linked);
        setLogs((prev) => prev.map((l) => l.id === linked.id ? linked : l));
      }
    }
    await saveLog(toSave);
    setLogs((prev) => [...prev, toSave]);
    // Decrement stock at the source location
    const product = products.find((p) => p.id === toSave.productId);
    if (product && toSave.locationId) {
      const currentAt = stockAt(product, toSave.locationId);
      const updated = {
        ...product,
        stock: { ...product.stock, [toSave.locationId]: Math.max(0, currentAt - 1) },
      };
      await saveProduct(updated);
      setProducts((prev) => prev.map((p) => p.id === updated.id ? updated : p));
    }
    setWearFormOpen(false);
    setWearDefaultProduct(null);
    setPendingChangeFromId(null);
    setToastMsg(toSave.changedFromId ? 'Changed' : 'Put on');
  };

  const handleTakeOff = async (updatedEntry, thenReplace) => {
    await saveLog(updatedEntry);
    setLogs((prev) => prev.map((l) => l.id === updatedEntry.id ? updatedEntry : l));
    setTakeOffEntry(null);
    setToastMsg('Taken off');
    if (thenReplace) {
      // Default the new one to the same product for a quick change-out;
      // remember this take-off so the next put-on links back to it.
      setWearDefaultProduct(updatedEntry.productId);
      setPendingChangeFromId(updatedEntry.id);
      setWearFormOpen(true);
    }
  };

  // Undo a put-on done by mistake: remove the open session and refund stock
  const handleCancelWear = async (entry) => {
    // If this put-on was linked to a take-off as a change-out, unlink it.
    if (entry.changedFromId) {
      const src = logs.find((l) => l.id === entry.changedFromId);
      if (src && src.changedToId === entry.id) {
        const unlinked = { ...src, changedToId: null };
        await saveLog(unlinked);
        setLogs((prev) => prev.map((l) => l.id === unlinked.id ? unlinked : l));
      }
    }
    await removeLog(entry.id);
    setLogs((prev) => prev.filter((l) => l.id !== entry.id));
    const product = products.find((p) => p.id === entry.productId);
    if (product && entry.locationId) {
      const currentAt = stockAt(product, entry.locationId);
      const updated = {
        ...product,
        stock: { ...product.stock, [entry.locationId]: currentAt + 1 },
      };
      await saveProduct(updated);
      setProducts((prev) => prev.map((p) => p.id === updated.id ? updated : p));
    }
    setToastMsg('Put back');
  };

  const openWearForm = (productId) => {
    if (activeWear) {
      // Already wearing one — deal with it first via change-out
      setToastMsg('Take off the current one first');
      openTakeOff(activeWear, 'replace');
      return;
    }
    setWearDefaultProduct(productId || null);
    setWearFormOpen(true);
  };

  const openTakeOff = (entry, then = 'none') => {
    setTakeOffEntry(entry);
    setTakeOffThen(then);
  };

  // Save/persist the wettings array for a wear-session log. Works for the
  // diaper on now or any previously worn one. Called live as the user
  // adds/edits/removes entries in the WettingForm.
  const handleSaveWettings = async (logId, wettings) => {
    const target = logs.find((l) => l.id === logId);
    if (!target) return;
    const updated = { ...target, wettings };
    await saveLog(updated);
    setLogs((prev) => prev.map((l) => (l.id === logId ? updated : l)));
  };

  // === Save handlers ===
  const handleSaveProduct = async (product) => {
    const exists = products.find((p) => p.id === product.id);
    await saveProduct(product);
    setProducts(exists
      ? products.map((p) => p.id === product.id ? product : p)
      : [...products, product]
    );
    // Refresh thumbs map (in case photo was added/changed/removed)
    const th = await getAllThumbs();
    setThumbs(th);
    setProductFormOpen(false);
    setEditingProduct(null);
    setToastMsg(exists ? 'Product updated' : 'Product added');
  };

  const handleDeleteProduct = async (product) => {
    await removeProduct(product.id);
    setProducts(products.filter((p) => p.id !== product.id));
    const newThumbs = { ...thumbs };
    delete newThumbs[product.id];
    setThumbs(newThumbs);
    setConfirmDeleteProduct(null);
    setToastMsg('Product deleted');
  };

  const handleSaveLocation = async (location) => {
    const exists = locations.find((l) => l.id === location.id);
    await saveLocation(location);
    setLocations(exists
      ? locations.map((l) => l.id === location.id ? location : l)
      : [...locations, location]
    );
    setToastMsg(exists ? 'Location updated' : 'Location added');
  };

  const handleDeleteLocation = async (location) => {
    await removeLocation(location.id);
    setLocations(locations.filter((l) => l.id !== location.id));
    setToastMsg('Location deleted');
  };

  const handleReorderLocations = async (reordered) => {
    setLocations(reordered);
    await Promise.all(reordered.map((l) => saveLocation(l)));
  };

  const handleSaveLog = async (entry, decrementInventory) => {
    const exists = logs.find((l) => l.id === entry.id);
    await saveLog(entry);
    setLogs(exists
      ? logs.map((l) => l.id === entry.id ? entry : l)
      : [...logs, entry]
    );

    if (decrementInventory && entry.locationId) {
      const product = products.find((p) => p.id === entry.productId);
      if (product) {
        const currentAt = stockAt(product, entry.locationId);
        const updated = {
          ...product,
          stock: {
            ...product.stock,
            [entry.locationId]: Math.max(0, currentAt - 1),
          },
        };
        await saveProduct(updated);
        setProducts(products.map((p) => p.id === updated.id ? updated : p));
      }
    }

    setLogFormOpen(false);
    setEditingLog(null);
    setDefaultLogProduct(null);
    setToastMsg(exists ? 'Entry updated' : 'Logged');
  };

  const handleDeleteLog = async (entry) => {
    await removeLog(entry.id);
    setLogs(logs.filter((l) => l.id !== entry.id));
    setConfirmDeleteLog(null);
    setToastMsg('Entry deleted');
  };

  // Move stock between locations
  const handleSaveMove = async (move) => {
    const product = products.find((p) => p.id === move.productId);
    if (!product) return;
    const fromStock = stockAt(product, move.fromLocationId);
    const toStock = stockAt(product, move.toLocationId);

    const updated = {
      ...product,
      stock: {
        ...product.stock,
        [move.fromLocationId]: Math.max(0, fromStock - move.quantity),
        [move.toLocationId]: toStock + move.quantity,
      },
    };
    await saveProduct(updated);
    setProducts(products.map((p) => p.id === updated.id ? updated : p));

    // Log the move so it appears in history
    await saveLog(move);
    setLogs([...logs, move]);

    setMoveFormOpen(false);
    setMoveProductId(null);
    setToastMsg('Stock moved');
  };

  const handleRestockSave = async (updated) => {
    await saveProduct(updated);
    setProducts(products.map((p) => p.id === updated.id ? updated : p));
    setRestockProduct(null);
    setToastMsg('Stock updated');
  };

  const openMoveForm = (productId) => {
    setMoveProductId(productId || null);
    setMoveFormOpen(true);
  };

  // Note logs (type: 'note') — free-standing or attached to the diaper on now.
  const handleSaveNote = async (note) => {
    const exists = logs.find((l) => l.id === note.id);
    await saveLog(note);
    setLogs(exists ? logs.map((l) => (l.id === note.id ? note : l)) : [...logs, note]);
    setNoteFormOpen(false);
    setEditingNote(null);
    setNoteContext(null);
    setToastMsg(exists ? 'Note updated' : 'Note added');
  };

  const openNoteForm = (context) => {
    setEditingNote(null);
    setNoteContext(context || null);
    setNoteFormOpen(true);
  };

  // Drink logs (type: 'drink') — free-standing fluid intake.
  const handleSaveDrink = async (drink) => {
    const exists = logs.find((l) => l.id === drink.id);
    await saveLog(drink);
    setLogs(exists ? logs.map((l) => (l.id === drink.id ? drink : l)) : [...logs, drink]);
    setDrinkFormOpen(false);
    setEditingDrink(null);
    setToastMsg(exists ? 'Drink updated' : 'Drink logged');
  };

  const openDrinkForm = () => {
    setEditingDrink(null);
    setDrinkFormOpen(true);
  };

  const tabs = [
    { v: 'home', label: 'Today', icon: LayoutDashboard },
    { v: 'inventory', label: 'Inventory', icon: Package },
    { v: 'history', label: 'History', icon: ClipboardList },
    { v: 'insights', label: 'Insights', icon: BarChart3 },
  ];

  if (loading) {
    return (
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        minHeight: '100vh',
      }}>
        <div className="display-italic" style={{ fontSize: 24, color: 'var(--ink-mute)' }}>
          loading…
        </div>
      </div>
    );
  }

  const showFab = locations.length > 0 && products.length > 0;

  // Nudge a backup if there's data to lose and it's been >14 days (or never).
  const BACKUP_AGE_MS = 14 * 24 * 3600 * 1000;
  const needsBackup =
    logs.length > 0 &&
    !backupDismissed &&
    (lastBackupAt == null || Date.now() - lastBackupAt > BACKUP_AGE_MS);

  return (
    <div>
      <header className="app-header">
        <div style={{
          maxWidth: 760, margin: '0 auto',
          display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap',
        }}>
          <div style={{ flex: 1 }}>
            <span className="display-italic" style={{ fontSize: 26, letterSpacing: '-0.02em' }}>
              Diaper
            </span>
            <span className="eyebrow" style={{ marginLeft: 10, fontSize: 9.5 }}>
              usage and inventory tracking
            </span>
          </div>
          <nav className="top-tabs">
            {tabs.map((t) => {
              const Icon = t.icon;
              return (
                <button
                  key={t.v}
                  className={`top-tab ${tab === t.v ? 'active' : ''}`}
                  onClick={() => setTab(t.v)}
                >
                  <Icon size={14} /> {t.label}
                </button>
              );
            })}
          </nav>
          <button
            className="btn-icon"
            onClick={() => setSettingsOpen(true)}
            aria-label="Settings"
            style={{ marginLeft: 4 }}
          >
            <SettingsIcon size={18} />
          </button>
        </div>
      </header>

      <main className="with-bottom-nav" style={{
        maxWidth: 760, margin: '0 auto', padding: '24px 20px',
      }}>
        {needsBackup && (
          <div className="card" style={{
            padding: '12px 14px', marginBottom: 20,
            display: 'flex', alignItems: 'center', gap: 12,
            borderColor: 'var(--accent)',
          }}>
            <ShieldAlert size={18} style={{ color: 'var(--accent)', flexShrink: 0 }} />
            <div style={{ flex: 1, minWidth: 0, fontSize: 13 }}>
              <div style={{ fontWeight: 600 }}>Time to back up</div>
              <div style={{ color: 'var(--ink-soft)' }}>
                {lastBackupAt
                  ? `Last backup was ${formatDuration(Date.now() - lastBackupAt)} ago. `
                  : 'Your data lives only on this device. '}
                Export a copy so you don't lose it.
              </div>
            </div>
            <button
              className="btn btn-primary"
              style={{ flexShrink: 0 }}
              onClick={() => setSettingsOpen(true)}
            >
              Back up
            </button>
            <button
              className="btn-icon"
              aria-label="Dismiss backup reminder"
              style={{ flexShrink: 0 }}
              onClick={() => setBackupDismissed(true)}
            >
              <X size={16} />
            </button>
          </div>
        )}
        {tab === 'home' && (
          <Dashboard
            products={products} logs={logs} locations={locations} thumbs={thumbs}
            activeWear={activeWear}
            onAddProduct={() => { setEditingProduct(null); setProductFormOpen(true); }}
            onAddLocation={() => setLocationsOpen(true)}
            onPutOn={openWearForm}
            onChangeOut={(entry) => openTakeOff(entry, 'replace')}
            onTakeOff={(entry) => openTakeOff(entry, 'none')}
            onUndoWear={handleCancelWear}
            onLogWetting={(entry) => setWettingEntry(entry)}
            onRestock={(p) => setRestockProduct(p)}
            onMove={openMoveForm}
            onAddNote={openNoteForm}
            onAddDrink={openDrinkForm}
            onPhotoTap={setPhotoViewerProductId}
          />
        )}
        {tab === 'inventory' && (
          <Inventory
            products={products} locations={locations} thumbs={thumbs}
            daysRemainingMap={daysRemainingMap}
            onAdd={() => { setEditingProduct(null); setProductFormOpen(true); }}
            onEdit={(p) => { setEditingProduct(p); setProductFormOpen(true); }}
            onLogQuick={openWearForm}
            onRestock={(p) => setRestockProduct(p)}
            onMove={openMoveForm}
            onPhotoTap={setPhotoViewerProductId}
          />
        )}
        {tab === 'history' && (
          <History
            logs={logs} products={products} locations={locations} thumbs={thumbs}
            onEdit={(l) => {
              if (l.type === 'note') { setEditingNote(l); setNoteContext(null); setNoteFormOpen(true); }
              else if (l.type === 'drink') { setEditingDrink(l); setDrinkFormOpen(true); }
              else { setEditingLog(l); setLogFormOpen(true); }
            }}
            onDelete={(l) => setConfirmDeleteLog(l)}
            onManageWettings={(l) => setWettingEntry(l)}
            onPhotoTap={setPhotoViewerProductId}
          />
        )}
        {tab === 'insights' && (
          <Insights
            products={products} logs={logs} locations={locations} thumbs={thumbs}
            daysRemainingMap={daysRemainingMap}
            drinkPresets={drinkPresets}
          />
        )}
      </main>

      {showFab && (
        activeWear ? (
          <button className="fab" onClick={() => openTakeOff(activeWear, 'none')} aria-label="Manage what you're wearing">
            <Repeat size={22} />
          </button>
        ) : (
          <button className="fab" onClick={() => openWearForm(null)} aria-label="Put one on">
            <Plus size={24} />
          </button>
        )
      )}

      <nav className="bottom-nav">
        {tabs.map((t) => {
          const Icon = t.icon;
          return (
            <button
              key={t.v}
              className={`nav-btn ${tab === t.v ? 'active' : ''}`}
              onClick={() => setTab(t.v)}
            >
              <Icon size={18} />
              {t.label}
            </button>
          );
        })}
      </nav>

      {/* Modals */}
      <ProductForm
        open={productFormOpen}
        onClose={() => { setProductFormOpen(false); setEditingProduct(null); }}
        onSave={handleSaveProduct}
        onDelete={(p) => { setProductFormOpen(false); setConfirmDeleteProduct(p); }}
        initial={editingProduct}
        locations={locations}
      />

      <LogForm
        open={logFormOpen}
        onClose={() => { setLogFormOpen(false); setEditingLog(null); setDefaultLogProduct(null); }}
        onSave={handleSaveLog}
        products={products}
        locations={locations}
        initial={editingLog}
        defaultProductId={defaultLogProduct}
      />

      <WearForm
        open={wearFormOpen}
        onClose={() => { setWearFormOpen(false); setWearDefaultProduct(null); setPendingChangeFromId(null); }}
        onSave={handlePutOn}
        products={products}
        locations={locations}
        defaultProductId={wearDefaultProduct}
      />

      <TakeOffForm
        open={!!takeOffEntry}
        onClose={() => setTakeOffEntry(null)}
        onConfirm={handleTakeOff}
        entry={takeOffEntry}
        product={takeOffEntry ? products.find((p) => p.id === takeOffEntry.productId) : null}
        defaultThen={takeOffThen}
      />

      <WettingForm
        open={!!wettingEntry}
        onClose={() => setWettingEntry(null)}
        entry={wettingEntry ? (logs.find((l) => l.id === wettingEntry.id) || wettingEntry) : null}
        product={wettingEntry ? products.find((p) => p.id === wettingEntry.productId) : null}
        onSave={handleSaveWettings}
        logs={logs}
      />

      <NoteForm
        open={noteFormOpen}
        onClose={() => { setNoteFormOpen(false); setEditingNote(null); setNoteContext(null); }}
        onSave={handleSaveNote}
        initial={editingNote}
        context={noteContext}
        locations={locations}
        products={products}
      />

      <DrinkForm
        open={drinkFormOpen}
        onClose={() => { setDrinkFormOpen(false); setEditingDrink(null); }}
        onSave={handleSaveDrink}
        initial={editingDrink}
        presets={drinkPresets}
      />

      <MoveForm
        open={moveFormOpen}
        onClose={() => { setMoveFormOpen(false); setMoveProductId(null); }}
        onSave={handleSaveMove}
        products={products}
        locations={locations}
        initialProductId={moveProductId}
      />

      <RestockForm
        open={!!restockProduct}
        onClose={() => setRestockProduct(null)}
        product={restockProduct}
        locations={locations}
        onSave={handleRestockSave}
      />

      <LocationManager
        open={locationsOpen}
        onClose={() => setLocationsOpen(false)}
        locations={locations}
        products={products}
        onSave={handleSaveLocation}
        onDelete={handleDeleteLocation}
        onReorder={handleReorderLocations}
      />

      <Settings
        open={settingsOpen}
        onClose={() => setSettingsOpen(false)}
        onOpenLocations={() => setLocationsOpen(true)}
        onDataChanged={loadAll}
        onShowToast={setToastMsg}
        lastBackupAt={lastBackupAt}
        onBackedUp={(ts) => { setLastBackupAt(ts); setBackupDismissed(true); }}
        drinkPresets={drinkPresets}
        onSaveDrinkPresets={setDrinkPresets}
      />

      <PhotoViewer
        productId={photoViewerProductId}
        onClose={() => setPhotoViewerProductId(null)}
      />

      <ConfirmDialog
        open={!!confirmDeleteProduct}
        title="Delete product?"
        body={(() => {
          const b = confirmDeleteProduct?.brand || '';
          const n = confirmDeleteProduct?.name || '';
          const label = `${b} ${n}`.trim() || 'This product';
          return `"${label}" will be removed. Past usage logs are kept.`;
        })()}
        onCancel={() => setConfirmDeleteProduct(null)}
        onConfirm={() => handleDeleteProduct(confirmDeleteProduct)}
      />
      <ConfirmDialog
        open={!!confirmDeleteLog}
        title="Delete this entry?"
        body={
          confirmDeleteLog?.type === 'move'
            ? "This removes the move from history but won't undo the stock change. To reverse it, do another move in the opposite direction."
            : "This action can't be undone. Stock counts won't change."
        }
        onCancel={() => setConfirmDeleteLog(null)}
        onConfirm={() => handleDeleteLog(confirmDeleteLog)}
      />

      <Toast message={toastMsg} onDone={() => setToastMsg('')} />
    </div>
  );
}
LEDGER_EOF

echo "Committing and pushing..."
git add -A && git commit -m "Add adjustable drink-size presets and optional exact-oz on drinks" && git push

echo "Done. Netlify will redeploy from this push."
