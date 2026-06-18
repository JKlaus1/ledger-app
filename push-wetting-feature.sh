#!/usr/bin/env bash
# Ledger - wetting feature: writes every file touched this chat,
# then commits and pushes. Pushing to master auto-deploys on Netlify.
# Safe to re-run: it always pushes the latest, even if nothing changed.
set -e
cd ~/ledger-app

mkdir -p "src/lib"
cat > src/lib/wetting.js << 'LEDGER_EOF'
// Wetting events recorded against a wear session (a worn diaper).
//
// Each wear-session log (a "use" entry with a putOnAt time) may carry an
// optional `wettings` array, stored inline on the log object:
//
//   wettings: [{ id, at, amount, feel, note }]
//
// Because it rides along on the existing log records, it needs no new
// IndexedDB store and is automatically included in backup export/import
// and the GitHub-synced... (nothing — data stays on device). Older logs
// without the field are treated as having no wettings.
//
//   amount — how heavy the wetting was (light → very heavy)
//   feel   — how the diaper felt afterwards (a saturation scale)

export const WETNESS = [
  { value: 'light',    label: 'Light',      weight: 1, order: 1 },
  { value: 'moderate', label: 'Moderate',   weight: 2, order: 2 },
  { value: 'heavy',    label: 'Heavy',      weight: 3, order: 3 },
  { value: 'flood',    label: 'Very heavy', weight: 4, order: 4 },
];

// How the diaper feels *after* a wetting — a rough saturation scale.
export const DIAPER_FEEL = [
  { value: 'dry',       label: 'Still dry / barely noticeable', order: 1 },
  { value: 'damp',      label: 'Slightly damp',                 order: 2 },
  { value: 'wet',       label: 'Noticeably wet',                order: 3 },
  { value: 'heavy',     label: 'Heavy / swollen',               order: 4 },
  { value: 'saturated', label: 'Saturated — near its limit',    order: 5 },
];

export const wetnessMeta = (v) => WETNESS.find((w) => w.value === v) || null;
export const feelMeta = (v) => DIAPER_FEEL.find((f) => f.value === v) || null;

export const wetnessLabel = (v) => wetnessMeta(v)?.label || '—';
export const feelLabel = (v) => feelMeta(v)?.label || '—';

// Always returns a time-sorted array, tolerant of older logs with no field.
export const getWettings = (log) => {
  if (!log || !Array.isArray(log.wettings)) return [];
  return [...log.wettings].sort((a, b) => (a.at || 0) - (b.at || 0));
};

// Roll a session's wettings into a small performance summary.
//   count    — number of wettings
//   load     — summed "heaviness" weight (a rough saturation total)
//   lastFeel — feel recorded on the most recent wetting
//   peakFeel — most saturated feel reached across the session
//   byAmount — { light, moderate, heavy, flood } counts
export const wettingStats = (log) => {
  const list = getWettings(log);
  const byAmount = { light: 0, moderate: 0, heavy: 0, flood: 0 };
  let load = 0;
  let peakOrder = 0;
  let peakFeel = null;
  list.forEach((w) => {
    if (byAmount[w.amount] != null) byAmount[w.amount] += 1;
    load += wetnessMeta(w.amount)?.weight || 0;
    const fo = feelMeta(w.feel)?.order || 0;
    if (fo >= peakOrder) { peakOrder = fo; peakFeel = w.feel; }
  });
  const lastFeel = list.length ? list[list.length - 1].feel : null;
  return { count: list.length, load, lastFeel, peakFeel, byAmount, list };
};
LEDGER_EOF

mkdir -p "src/components"
cat > src/components/WettingForm.jsx << 'LEDGER_EOF'
import React, { useState, useEffect } from 'react';
import { Check, X, Droplets, Droplet, Pencil } from 'lucide-react';
import { Modal } from './Common';
import {
  uid, toLocalInputValue, fromLocalInputValue,
  productDisplayName, formatTime, formatDuration, wearDuration,
} from '../lib/helpers';
import {
  WETNESS, DIAPER_FEEL, getWettings, wettingStats,
  wetnessLabel, feelLabel,
} from '../lib/wetting';

// WettingSummary — compact, reusable read-out of a wear session's wettings.
// Used on the dashboard's "currently wearing" card and in History rows.
// In compact mode it renders nothing when there are no wettings yet.
export function WettingSummary({ log, compact = false, style = {} }) {
  const { count, peakFeel, byAmount } = wettingStats(log);

  if (count === 0) {
    if (compact) return null;
    return (
      <div style={{ fontSize: 12, color: 'var(--ink-mute)', ...style }}>
        No wettings logged yet.
      </div>
    );
  }

  const breakdown = WETNESS
    .filter((w) => byAmount[w.value] > 0)
    .map((w) => `${byAmount[w.value]} ${w.label.toLowerCase()}`)
    .join(' · ');

  if (compact) {
    return (
      <span style={{
        display: 'inline-flex', alignItems: 'center', gap: 5,
        color: 'var(--accent)', ...style,
      }}>
        <Droplet size={11} />
        {count} wetting{count !== 1 ? 's' : ''}
        {peakFeel && (
          <span style={{ color: 'var(--ink-mute)' }}>· {feelLabel(peakFeel).toLowerCase()}</span>
        )}
      </span>
    );
  }

  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 8, ...style }}>
      <span style={{
        display: 'inline-flex', alignItems: 'center', gap: 5,
        fontSize: 13, color: 'var(--accent)', fontWeight: 600,
      }}>
        <Droplets size={14} /> {count} wetting{count !== 1 ? 's' : ''}
      </span>
      {breakdown && <span style={{ fontSize: 12, color: 'var(--ink-soft)' }}>{breakdown}</span>}
      {peakFeel && (
        <span style={{ fontSize: 12, color: 'var(--ink-mute)' }}>
          · felt {feelLabel(peakFeel).toLowerCase()}
        </span>
      )}
    </div>
  );
}

// WettingForm — add / edit / remove wettings on a single wear session.
// Works for the diaper currently on, or any previously worn one. Persists
// immediately via onSave(logId, wettings) so nothing is lost on close.
export default function WettingForm({ open, onClose, entry, product, onSave }) {
  const [list, setList] = useState([]);
  const [editingId, setEditingId] = useState(null);
  const [at, setAt] = useState(Date.now());
  const [amount, setAmount] = useState('');
  const [feel, setFeel] = useState('');
  const [note, setNote] = useState('');

  const defaultAt = () => {
    if (!entry) return Date.now();
    // Currently worn → now. Previously worn → the time it came off.
    return entry.takenOffAt == null ? Date.now() : entry.takenOffAt;
  };

  const resetSubForm = () => {
    setEditingId(null);
    setAt(defaultAt());
    setAmount('');
    setFeel('');
    setNote('');
  };

  // Seed the working list when the modal opens for a given session.
  useEffect(() => {
    if (open && entry) {
      setList(getWettings(entry));
      resetSubForm();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, entry?.id]);

  if (!open || !entry) return null;

  const persist = (next) => {
    const sorted = [...next].sort((a, b) => (a.at || 0) - (b.at || 0));
    setList(sorted);
    onSave(entry.id, sorted);
  };

  const addOrUpdate = () => {
    if (!amount) return;
    if (editingId) {
      persist(list.map((w) =>
        w.id === editingId ? { ...w, at, amount, feel: feel || null, note: note.trim() } : w
      ));
    } else {
      persist([...list, { id: uid(), at, amount, feel: feel || null, note: note.trim() }]);
    }
    resetSubForm();
  };

  const editRow = (w) => {
    setEditingId(w.id);
    setAt(w.at || Date.now());
    setAmount(w.amount || '');
    setFeel(w.feel || '');
    setNote(w.note || '');
  };

  const removeRow = (id) => {
    persist(list.filter((w) => w.id !== id));
    if (editingId === id) resetSubForm();
  };

  const stats = wettingStats({ ...entry, wettings: list });
  const dur = wearDuration(entry);

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Wettings"
      footer={<button className="btn btn-primary" onClick={onClose}>Done</button>}
    >
      <div style={{ display: 'grid', gap: 16 }}>
        {/* Session summary — how this diaper is performing */}
        <div className="card" style={{ padding: '12px 14px' }}>
          <div style={{ fontSize: 14 }}>
            {product ? productDisplayName(product) : 'This diaper'}
          </div>
          <div style={{ fontSize: 12, color: 'var(--ink-mute)', marginTop: 3 }}>
            {entry.takenOffAt == null ? 'On now' : 'Previously worn'}
            {dur != null && ` · worn ${formatDuration(dur)}`}
            {` · ${stats.count} wetting${stats.count !== 1 ? 's' : ''}`}
            {stats.peakFeel && ` · felt ${feelLabel(stats.peakFeel).toLowerCase()}`}
          </div>
        </div>

        {/* Existing wettings */}
        {list.length > 0 && (
          <div>
            <label className="label">Logged so far</label>
            <div className="card" style={{ padding: 4 }}>
              {list.map((w) => (
                <div
                  key={w.id}
                  className="row-divider"
                  style={{ padding: '10px 12px', display: 'flex', alignItems: 'center', gap: 10 }}
                >
                  <Droplet size={14} style={{ color: 'var(--accent)', flexShrink: 0 }} />
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontSize: 13 }}>
                      {wetnessLabel(w.amount)}
                      {w.feel && (
                        <span style={{ color: 'var(--ink-mute)' }}> · {feelLabel(w.feel).toLowerCase()}</span>
                      )}
                    </div>
                    <div style={{ fontSize: 11, color: 'var(--ink-mute)', marginTop: 1 }}>
                      {formatTime(w.at)}{w.note ? ` · ${w.note}` : ''}
                    </div>
                  </div>
                  <button className="btn-icon" onClick={() => editRow(w)} aria-label="Edit wetting">
                    <Pencil size={13} />
                  </button>
                  <button className="btn-icon" onClick={() => removeRow(w.id)} aria-label="Remove wetting">
                    <X size={14} />
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}

        <hr className="hairline" />

        {/* Add / edit a single wetting */}
        <div style={{ display: 'grid', gap: 14 }}>
          <div className="eyebrow">{editingId ? 'Edit wetting' : 'Add a wetting'}</div>

          <div>
            <label className="label">When</label>
            <input
              className="input" type="datetime-local"
              value={toLocalInputValue(at)}
              onChange={(e) => setAt(fromLocalInputValue(e.target.value))}
            />
          </div>

          <div>
            <label className="label">How much?</label>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
              {WETNESS.map((w) => (
                <button
                  key={w.value} type="button"
                  className={`check-row ${amount === w.value ? 'active' : ''}`}
                  onClick={() => setAmount(w.value)}
                >
                  <span style={{ flex: 1 }}>{w.label}</span>
                  {amount === w.value && <Check size={14} />}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="label">How does it feel now? (optional)</label>
            <div style={{ display: 'grid', gap: 8 }}>
              {DIAPER_FEEL.map((f) => (
                <button
                  key={f.value} type="button"
                  className={`check-row ${feel === f.value ? 'active' : ''}`}
                  onClick={() => setFeel(feel === f.value ? '' : f.value)}
                >
                  <span style={{ flex: 1 }}>{f.label}</span>
                  {feel === f.value && <Check size={14} />}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="label">Note (optional)</label>
            <input
              className="input"
              placeholder="e.g. after a big drink, woke up wet…"
              value={note}
              onChange={(e) => setNote(e.target.value)}
            />
          </div>

          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            <button
              className="btn btn-primary"
              onClick={addOrUpdate}
              disabled={!amount}
              style={{ flex: '1 1 auto' }}
            >
              <Droplets size={15} /> {editingId ? 'Update wetting' : 'Add wetting'}
            </button>
            {editingId && (
              <button className="btn btn-ghost" onClick={resetSubForm}>
                Cancel edit
              </button>
            )}
          </div>
        </div>
      </div>
    </Modal>
  );
}
LEDGER_EOF

mkdir -p "src"
cat > src/App.jsx << 'LEDGER_EOF'
import React, { useState, useEffect, useMemo } from 'react';
import {
  Plus, Settings as SettingsIcon, LayoutDashboard,
  Package, ClipboardList, BarChart3, Repeat,
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

import {
  getAllProducts, getAllLocations, getAllLogs, getAllThumbs,
  saveProduct, removeProduct, saveLocation, removeLocation,
  saveLog, removeLog,
} from './lib/storage';
import { stockAt, isWornNow } from './lib/helpers';

export default function App() {
  // Core data
  const [products, setProducts] = useState([]);
  const [locations, setLocations] = useState([]);
  const [logs, setLogs] = useState([]);
  const [thumbs, setThumbs] = useState({});
  const [loading, setLoading] = useState(true);

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
  const [takeOffEntry, setTakeOffEntry] = useState(null);
  const [takeOffThen, setTakeOffThen] = useState('none');

  // Wetting tracking modal — holds the wear-session log being edited
  const [wettingEntry, setWettingEntry] = useState(null);

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
    await saveLog(entry);
    setLogs((prev) => [...prev, entry]);
    // Decrement stock at the source location
    const product = products.find((p) => p.id === entry.productId);
    if (product && entry.locationId) {
      const currentAt = stockAt(product, entry.locationId);
      const updated = {
        ...product,
        stock: { ...product.stock, [entry.locationId]: Math.max(0, currentAt - 1) },
      };
      await saveProduct(updated);
      setProducts((prev) => prev.map((p) => p.id === updated.id ? updated : p));
    }
    setWearFormOpen(false);
    setWearDefaultProduct(null);
    setToastMsg('Put on');
  };

  const handleTakeOff = async (updatedEntry, thenReplace) => {
    await saveLog(updatedEntry);
    setLogs((prev) => prev.map((l) => l.id === updatedEntry.id ? updatedEntry : l));
    setTakeOffEntry(null);
    setToastMsg('Taken off');
    if (thenReplace) {
      // Default the new one to the same product for a quick change-out
      setWearDefaultProduct(updatedEntry.productId);
      setWearFormOpen(true);
    }
  };

  // Undo a put-on done by mistake: remove the open session and refund stock
  const handleCancelWear = async (entry) => {
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
            onEdit={(l) => { setEditingLog(l); setLogFormOpen(true); }}
            onDelete={(l) => setConfirmDeleteLog(l)}
            onManageWettings={(l) => setWettingEntry(l)}
            onPhotoTap={setPhotoViewerProductId}
          />
        )}
        {tab === 'insights' && (
          <Insights
            products={products} logs={logs} locations={locations} thumbs={thumbs}
            daysRemainingMap={daysRemainingMap}
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
        onClose={() => { setWearFormOpen(false); setWearDefaultProduct(null); }}
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

mkdir -p "src/components"
cat > src/components/Dashboard.jsx << 'LEDGER_EOF'
import React, { useMemo, useState, useEffect } from 'react';
import { Plus, ChevronRight, Sun, Moon, ArrowRight, Repeat, X, Clock, Droplets } from 'lucide-react';
import { ProductThumb, Eyebrow, SectionHeader, Pill } from './Common';
import { LocationIcon } from './LocationManager';
import { WettingSummary } from './WettingForm';
import {
  ABSORBENCY, formatDate, formatTime, isToday,
  productDisplayName, totalStock, formatDuration, wearDuration,
} from '../lib/helpers';

export default function Dashboard({
  products, logs, locations, thumbs, activeWear,
  onAddProduct, onAddLocation,
  onPutOn, onChangeOut, onTakeOff, onUndoWear, onLogWetting,
  onRestock, onMove, onPhotoTap,
}) {
  const today = new Date();

  // Tick every minute so the "worn for…" duration stays fresh
  const [, setTick] = useState(0);
  useEffect(() => {
    if (!activeWear) return;
    const t = setInterval(() => setTick((n) => n + 1), 60000);
    return () => clearInterval(t);
  }, [activeWear]);

  // "Real" usage logs (not moves)
  const usageLogs = logs.filter((l) => l.type !== 'move');
  const todayLogs = usageLogs.filter((l) => isToday(l.timestamp));
  const grandTotal = products.reduce((s, p) => s + totalStock(p), 0);

  // Low stock = total across all locations <= 5 (matches spirit of original)
  const lowStock = products
    .filter((p) => totalStock(p) > 0 && totalStock(p) <= 5)
    .sort((a, b) => totalStock(a) - totalStock(b));
  const outOfStock = products.filter((p) => totalStock(p) <= 0);

  // Most-used products in last 14 days
  const quickProducts = useMemo(() => {
    const cutoff = Date.now() - 14 * 24 * 3600 * 1000;
    const counts = new Map();
    usageLogs.filter((l) => l.timestamp >= cutoff).forEach((l) => {
      counts.set(l.productId, (counts.get(l.productId) || 0) + 1);
    });
    return [...counts.entries()]
      .sort((a, b) => b[1] - a[1])
      .map(([id]) => products.find((p) => p.id === id))
      .filter((p) => p && totalStock(p) > 0)
      .slice(0, 3);
  }, [usageLogs, products]);

  const recentLogs = [...logs]
    .sort((a, b) => b.timestamp - a.timestamp)
    .slice(0, 5);

  const quickVisible = !activeWear && quickProducts.length > 0;

  // Empty state - no locations yet
  if (locations.length === 0) {
    return (
      <div className="empty-state" style={{ paddingTop: 60 }}>
        <div className="display-italic" style={{ fontSize: 32, color: 'var(--ink)' }}>
          Welcome
        </div>
        <p style={{
          marginTop: 12, fontSize: 15, color: 'var(--ink-soft)',
          maxWidth: 380, marginInline: 'auto',
        }}>
          Start by adding the locations where you keep stock — like a closet, dresser, work bag, or your truck.
        </p>
        <button className="btn btn-primary" onClick={onAddLocation} style={{ marginTop: 24 }}>
          <Plus size={16} /> Add your first location
        </button>
      </div>
    );
  }

  // Empty state - no products yet
  if (products.length === 0) {
    return (
      <div className="empty-state" style={{ paddingTop: 60 }}>
        <div className="display-italic" style={{ fontSize: 32, color: 'var(--ink)' }}>
          Ready when you are
        </div>
        <p style={{
          marginTop: 12, fontSize: 15, color: 'var(--ink-soft)',
          maxWidth: 380, marginInline: 'auto',
        }}>
          You have {locations.length} location{locations.length !== 1 ? 's' : ''} set up.
          Now add the products you keep at them.
        </p>
        <button className="btn btn-primary" onClick={onAddProduct} style={{ marginTop: 24 }}>
          <Plus size={16} /> Add your first product
        </button>
      </div>
    );
  }

  return (
    <div style={{ display: 'grid', gap: 36 }}>
      {/* Today summary */}
      <section>
        <Eyebrow>{today.toLocaleDateString(undefined, { weekday: 'long' })} · {formatDate(today)}</Eyebrow>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 20, marginTop: 12 }}>
          <div className="stat-divider" style={{ paddingTop: 10 }}>
            <div className="num" style={{ fontSize: 38, lineHeight: 1 }}>{todayLogs.length}</div>
            <div className="eyebrow" style={{ marginTop: 6 }}>Used today</div>
          </div>
          <div className="stat-divider" style={{ paddingTop: 10 }}>
            <div className="num" style={{ fontSize: 38, lineHeight: 1 }}>{grandTotal}</div>
            <div className="eyebrow" style={{ marginTop: 6 }}>Total stock</div>
          </div>
          <div className="stat-divider" style={{ paddingTop: 10 }}>
            <div className="num" style={{ fontSize: 38, lineHeight: 1 }}>{products.length}</div>
            <div className="eyebrow" style={{ marginTop: 6 }}>Products</div>
          </div>
        </div>
      </section>

      {/* Currently wearing */}
      {activeWear && (() => {
        const wp = products.find((p) => p.id === activeWear.productId);
        const loc = locations.find((l) => l.id === activeWear.locationId);
        const dur = formatDuration(Date.now() - activeWear.putOnAt) || 'a moment';
        return (
          <section>
            <Eyebrow>Right now</Eyebrow>
            <div className="card" style={{
              padding: 16,
              border: '1px solid var(--primary)',
              background: 'var(--primary-soft)',
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                {wp && (
                  <ProductThumb
                    product={wp} thumbs={thumbs} size={44}
                    onClick={() => thumbs[wp.id] && onPhotoTap(wp.id)}
                  />
                )}
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{
                    fontSize: 10, textTransform: 'uppercase', letterSpacing: '0.1em',
                    color: 'var(--primary)', fontWeight: 600,
                  }}>
                    Currently wearing
                  </div>
                  <div className="display" style={{ fontSize: 18, marginTop: 3 }}>
                    {wp ? productDisplayName(wp) : 'Unknown product'}
                  </div>
                  <div style={{
                    fontSize: 12.5, color: 'var(--ink-soft)', marginTop: 5,
                    display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap',
                  }}>
                    <Clock size={12} />
                    <span>On for {dur}</span>
                    <span>· since {formatTime(activeWear.putOnAt)}</span>
                    {activeWear.period === 'night'
                      ? <><span>·</span><Moon size={12} /></>
                      : <><span>·</span><Sun size={12} /></>}
                    {loc && <><span>·</span><LocationIcon name={loc.icon} size={12} /><span>{loc.name}</span></>}
                  </div>
                  <WettingSummary log={activeWear} compact style={{ marginTop: 6, fontSize: 12.5 }} />
                </div>
              </div>

              {/* Log a wetting on the diaper that's on right now */}
              <button
                className="btn btn-ghost"
                onClick={() => onLogWetting(activeWear)}
                style={{ width: '100%', marginTop: 14 }}
              >
                <Droplets size={15} /> Log a wetting
              </button>

              <div style={{ display: 'flex', gap: 8, marginTop: 8, flexWrap: 'wrap' }}>
                <button
                  className="btn btn-primary"
                  onClick={() => onChangeOut(activeWear)}
                  style={{ flex: '1 1 auto' }}
                >
                  <Repeat size={15} /> Change out
                </button>
                <button
                  className="btn btn-ghost"
                  onClick={() => onTakeOff(activeWear)}
                  style={{ flex: '1 1 auto' }}
                >
                  Take off
                </button>
              </div>
              <button
                onClick={() => onUndoWear(activeWear)}
                style={{
                  marginTop: 10, background: 'none', border: 'none',
                  color: 'var(--ink-mute)', fontSize: 12, cursor: 'pointer',
                  display: 'inline-flex', alignItems: 'center', gap: 4,
                  padding: 0, font: 'inherit',
                }}
              >
                <X size={12} /> Put back — I didn't wear this
              </button>
            </div>
          </section>
        );
      })()}

      {/* Stock by location summary */}
      <section>
        <SectionHeader number="01" title="Locations at a glance" />
        <div className="card" style={{ padding: 4 }}>
          {[...locations]
            .sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0))
            .map((loc) => {
              const total = products.reduce(
                (s, p) => s + (p.stock?.[loc.id] || 0),
                0
              );
              return (
                <div
                  key={loc.id}
                  className="row-divider"
                  style={{
                    padding: '12px 14px',
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
                  </div>
                  <div className="num" style={{ fontSize: 22 }}>{total}</div>
                </div>
              );
            })}
        </div>
      </section>

      {/* Quick log */}
      {!activeWear && quickProducts.length > 0 && (
        <section>
          <SectionHeader number="02" title="Quick start" />
          <p style={{
            fontSize: 12, color: 'var(--ink-mute)', marginTop: -8, marginBottom: 12, fontStyle: 'italic',
          }}>
            Tap a product to put one on. You'll pick the location next.
          </p>
          <div style={{ display: 'grid', gap: 8 }}>
            {quickProducts.map((p) => (
              <button
                key={p.id}
                onClick={() => onPutOn(p.id)}
                className="card row-hover"
                style={{
                  textAlign: 'left', padding: '14px 16px',
                  display: 'flex', alignItems: 'center', gap: 12,
                  border: '1px solid var(--line)', cursor: 'pointer',
                  font: 'inherit', color: 'inherit', width: '100%',
                }}
              >
                <ProductThumb product={p} thumbs={thumbs} size={32} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div className="display" style={{ fontSize: 15 }}>{productDisplayName(p)}</div>
                  <div style={{ fontSize: 12, color: 'var(--ink-mute)' }}>
                    {p.size} · {ABSORBENCY.find((a) => a.value === p.absorbency)?.label} · {totalStock(p)} total
                  </div>
                </div>
                <span style={{
                  fontSize: 13, color: 'var(--ink-soft)',
                  display: 'inline-flex', alignItems: 'center', gap: 4,
                }}>
                  Put on <ChevronRight size={14} />
                </span>
              </button>
            ))}
          </div>
        </section>
      )}

      {/* Low stock */}
      {(lowStock.length > 0 || outOfStock.length > 0) && (
        <section>
          <SectionHeader number={quickVisible ? '03' : '02'} title="Running low" />
          <div className="card" style={{ padding: 4 }}>
            {[...outOfStock, ...lowStock].map((p) => (
              <div
                key={p.id}
                className="row-divider"
                style={{
                  padding: '12px 14px',
                  display: 'flex', alignItems: 'center', gap: 10,
                }}
              >
                <ProductThumb
                  product={p} thumbs={thumbs} size={28}
                  onClick={() => thumbs[p.id] && onPhotoTap(p.id)}
                />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 14 }}>{productDisplayName(p)}</div>
                  <div style={{ fontSize: 12, color: 'var(--ink-mute)' }}>
                    {totalStock(p) === 0 ? 'Out of stock' : `${totalStock(p)} left across all locations`}
                  </div>
                </div>
                <button
                  className="btn btn-ghost"
                  onClick={() => onRestock(p)}
                  style={{ padding: '6px 12px', fontSize: 13 }}
                >
                  Restock
                </button>
              </div>
            ))}
          </div>
        </section>
      )}

      {/* Recent activity */}
      {recentLogs.length > 0 && (
        <section>
          <SectionHeader
            number={
              quickVisible && (lowStock.length || outOfStock.length) ? '04' :
              (quickVisible || lowStock.length || outOfStock.length) ? '03' : '02'
            }
            title="Recent activity"
          />
          <div className="card" style={{ padding: 4 }}>
            {recentLogs.map((l) => {
              const p = products.find((x) => x.id === l.productId);
              const isMove = l.type === 'move';
              const fromLoc = isMove ? locations.find((loc) => loc.id === l.fromLocationId) : null;
              const toLoc = isMove ? locations.find((loc) => loc.id === l.toLocationId) : null;
              const useLoc = !isMove ? locations.find((loc) => loc.id === l.locationId) : null;
              return (
                <div
                  key={l.id}
                  className="row-divider"
                  style={{
                    padding: '12px 14px',
                    display: 'flex', alignItems: 'center', gap: 12,
                  }}
                >
                  {p && (
                    <ProductThumb
                      product={p} thumbs={thumbs} size={28}
                      onClick={() => thumbs[p.id] && onPhotoTap(p.id)}
                    />
                  )}
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontSize: 14 }}>
                      {p ? productDisplayName(p) : <span style={{ color: 'var(--ink-mute)' }}>Removed product</span>}
                    </div>
                    <div style={{
                      fontSize: 12, color: 'var(--ink-mute)',
                      display: 'flex', alignItems: 'center', gap: 6, marginTop: 2,
                      flexWrap: 'wrap',
                    }}>
                      {isMove ? (
                        <>
                          <span>Moved {l.quantity} ·</span>
                          {fromLoc && <LocationIcon name={fromLoc.icon} size={11} />}
                          <span>{fromLoc?.name || 'Unknown'}</span>
                          <ArrowRight size={11} />
                          {toLoc && <LocationIcon name={toLoc.icon} size={11} />}
                          <span>{toLoc?.name || 'Unknown'}</span>
                        </>
                      ) : (
                        <>
                          {l.period === 'night' ? <Moon size={11} /> : <Sun size={11} />}
                          <span>
                            {isToday(l.timestamp) ? `Today, ${formatTime(l.timestamp)}` : `${formatDate(l.timestamp)}, ${formatTime(l.timestamp)}`}
                          </span>
                          {useLoc && <span>· {useLoc.name}</span>}
                          {l.putOnAt && l.takenOffAt == null && (
                            <span style={{ color: 'var(--primary)' }}>· on now</span>
                          )}
                          {wearDuration(l) != null && (
                            <span>· worn {formatDuration(wearDuration(l))}</span>
                          )}
                          <WettingSummary log={l} compact style={{ fontSize: 12 }} />
                        </>
                      )}
                    </div>
                  </div>
                  {!isMove && l.performance === 'leak' && <Pill variant="danger">Leaked</Pill>}
                  {!isMove && l.performance === 'dry' && <Pill variant="primary">Dry</Pill>}
                </div>
              );
            })}
          </div>
        </section>
      )}
    </div>
  );
}
LEDGER_EOF

mkdir -p "src/components"
cat > src/components/History.jsx << 'LEDGER_EOF'
import React, { useState, useMemo } from 'react';
import { Pencil, Trash2, Sun, Moon, ClipboardList, ArrowRight, Droplets } from 'lucide-react';
import { ProductThumb } from './Common';
import { LocationIcon } from './LocationManager';
import { WettingSummary } from './WettingForm';
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

  const filtered = useMemo(() => {
    return logs
      .filter((l) => {
        if (typeFilter === 'use' && l.type === 'move') return false;
        if (typeFilter === 'move' && l.type !== 'move') return false;
        return true;
      })
      .filter((l) => {
        if (l.type === 'move') return periodFilter === 'all';
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
          Logged uses and moves will appear here.
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
        </div>
        {typeFilter !== 'move' && (
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
          {products.map((p) => (
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
                    const p = products.find((x) => x.id === l.productId);
                    const isMove = l.type === 'move';
                    const fromLoc = isMove ? locations.find((loc) => loc.id === l.fromLocationId) : null;
                    const toLoc = isMove ? locations.find((loc) => loc.id === l.toLocationId) : null;
                    const useLoc = !isMove ? locations.find((loc) => loc.id === l.locationId) : null;
                    // Wettings attach to wear sessions (a use with a put-on time),
                    // whether that diaper is on now or was worn previously.
                    const isWearSession = !isMove && !!l.putOnAt;

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
                          <div style={{ fontSize: 14 }}>
                            {p ? productDisplayName(p) : <span style={{ color: 'var(--ink-mute)' }}>Removed product</span>}
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

mkdir -p "src/components"
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
  WETNESS, getWettings, wettingStats, wetnessLabel,
} from '../lib/wetting';

export default function Insights({ products, logs, locations, thumbs, daysRemainingMap }) {
  // Filter out moves - they're inventory transfers, not consumption
  const usageLogs = logs.filter((l) => l.type !== 'move');

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
    const withWet = sessions.filter((l) => getWettings(l).length > 0);
    const amountCounts = {};
    WETNESS.forEach((w) => { amountCounts[w.value] = 0; });
    let totalWettings = 0;
    sessions.forEach((l) => {
      getWettings(l).forEach((w) => {
        totalWettings += 1;
        if (amountCounts[w.amount] != null) amountCounts[w.amount] += 1;
      });
    });
    return {
      sessionCount: sessions.length,
      wetSessionCount: withWet.length,
      totalWettings,
      amountCounts,
      avgPerDiaper: sessions.length ? totalWettings / sessions.length : 0,
      avgPerWetDiaper: withWet.length ? totalWettings / withWet.length : 0,
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
            </>
          )}
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

git add -A
git commit -m "Add diaper wetting log + insights" || echo "Nothing new to commit - pushing current state."
git push
echo
echo "Pushed to master. Netlify will auto-deploy in ~1-2 min."
echo "Then tap Sync on the GitHub source in project knowledge."
