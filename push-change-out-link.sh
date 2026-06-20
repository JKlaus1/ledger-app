#!/usr/bin/env bash
# Ledger — link direct change-outs (and auto-link within 10 min)
# Run from the repo root:
#   cp ~/storage/downloads/push-change-out-link.sh ~/ledger-app/ && cd ~/ledger-app && bash push-change-out-link.sh
set -e

if [ ! -d src/components ] || [ ! -d src/lib ]; then
  echo "!! Run this from inside ~/ledger-app (src/components / src/lib not found here)."
  exit 1
fi
echo "Writing src/lib/session.js ..."
cat > src/lib/session.js << 'LEDGER_EOF'
// Wear-session metadata — the small vocabularies for context, change
// reason, and skin check. Kept in its own module (not helpers.js) so these
// shared constants live in one place and can grow without touching helpers.
//
// All three are optional on a log and backward-compatible: older logs that
// predate these fields simply have them undefined, which every consumer
// treats as "not set".

// Where/what you were doing while wearing it. Helps explain why some
// sessions leak or run short (exercise, travel) vs. hold fine (sleep).
export const CONTEXTS = [
  { value: 'home',     label: 'At home' },
  { value: 'work',     label: 'Work' },
  { value: 'out',      label: 'Out / errands' },
  { value: 'travel',   label: 'Travel' },
  { value: 'exercise', label: 'Exercise' },
  { value: 'sleep',    label: 'Sleeping' },
];

// Why the diaper came off. Sharpens performance data: a routine change is
// very different from one forced by a leak or saturation.
export const CHANGE_REASONS = [
  { value: 'routine',       label: 'Routine change' },
  { value: 'saturated',     label: 'Full / saturated' },
  { value: 'leak',          label: 'Leaked' },
  { value: 'uncomfortable', label: 'Uncomfortable' },
  { value: 'bedtime',       label: 'Bedtime / waking up' },
  { value: 'other',         label: 'Other' },
];

// A quick skin check at change time. Ordered so we can flag the worst.
export const SKIN_STATES = [
  { value: 'fine',      label: 'Fine',          order: 1 },
  { value: 'pink',      label: 'A little pink', order: 2 },
  { value: 'irritated', label: 'Irritated',     order: 3 },
];

// Product construction — how the diaper is backed, and how the tabs fasten.
// Optional on a product; older products without them read as "not set".
export const BACKINGS = [
  { value: 'plastic', label: 'Plastic-backed' },
  { value: 'cloth',   label: 'Cloth-backed' },
];

export const TAB_TYPES = [
  { value: 'taped',    label: 'Taped' },
  { value: 'velcro',   label: 'Velcro' },
  { value: 'tearaway', label: 'Tear-away (pull-up)' },
];

// How physically active you were over the wear — recorded at take-off.
// Ordered so Insights can later relate activity to how the core held up
// (the hunch being that active + wet breaks a core down faster than rest).
export const ACTIVITY_LEVELS = [
  { value: 'rest',     label: 'Rest / sitting',        order: 1 },
  { value: 'light',    label: 'Light / around home',   order: 2 },
  { value: 'moderate', label: 'Moderate / on my feet', order: 3 },
  { value: 'vigorous', label: 'Vigorous / very active', order: 4 },
];

// How the absorbent core held together by take-off. Ordered worst-ascending
// so a future view can flag the sessions where it fell apart.
export const CORE_CONDITIONS = [
  { value: 'held',     label: 'Held its shape',    order: 1 },
  { value: 'softened', label: 'Softened',          order: 2 },
  { value: 'clumped',  label: 'Clumped / shifted', order: 3 },
  { value: 'broke',    label: 'Broke apart',       order: 4 },
];

// Did the tapes/fasteners give trouble? Distinct from a product's `tabs`
// (which is the tab TYPE — taped/velcro/tearaway); this is behavior on a
// given wear. Shared by the take-off summary and per-wetting notes, ordered
// worst-ascending so it can later be cross-tabbed against tab type.
export const TAPE_STATES = [
  { value: 'held',     label: 'Held fine',                    order: 1 },
  { value: 'loosened', label: 'Loosened / needed a re-press', order: 2 },
  { value: 'popped',   label: 'A tab popped open',            order: 3 },
  { value: 'failed',   label: 'Tab failed (tore / lost stick)', order: 4 },
];

const labelOf = (arr, v) => arr.find((x) => x.value === v)?.label || null;

export const contextLabel = (v) => labelOf(CONTEXTS, v);
export const reasonLabel = (v) => labelOf(CHANGE_REASONS, v);
export const skinLabel = (v) => labelOf(SKIN_STATES, v);
export const backingLabel = (v) => labelOf(BACKINGS, v);
export const tabsLabel = (v) => labelOf(TAB_TYPES, v);
export const activityLabel = (v) => labelOf(ACTIVITY_LEVELS, v);
export const coreLabel = (v) => labelOf(CORE_CONDITIONS, v);
export const tapeLabel = (v) => labelOf(TAPE_STATES, v);

// A put-on within this many ms after a take-off is treated as a direct
// change-out (not a fresh wear with a gap). Used both by explicit "change into"
// flows and the auto-link fallback for separate take-off + put-on actions.
export const CHANGE_OUT_WINDOW_MS = 10 * 60 * 1000;

// Per-unit cost from a product's pack cost / pack size, or null if either
// is missing. Centralized so the inventory and insights agree.
export const unitCost = (product) => {
  if (!product) return null;
  const cost = Number(product.cost);
  const pack = Number(product.packSize);
  if (!Number.isFinite(cost) || !Number.isFinite(pack) || pack <= 0) return null;
  return cost / pack;
};

// Format a number as money in the user's locale, no fixed currency symbol
// (the app never asked which currency the pack cost is in).
export const fmtMoney = (n) =>
  n == null || !Number.isFinite(n)
    ? '—'
    : n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
LEDGER_EOF

echo "Writing src/App.jsx ..."
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

echo "Writing src/components/History.jsx ..."
cat > src/components/History.jsx << 'LEDGER_EOF'
import React, { useState, useMemo } from 'react';
import { Pencil, Trash2, Sun, Moon, ClipboardList, ArrowRight, Droplets, StickyNote, Repeat } from 'lucide-react';
import { ProductThumb } from './Common';
import { LocationIcon } from './LocationManager';
import { WettingSummary } from './WettingForm';
import { contextLabel, reasonLabel } from '../lib/session';
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
        if (typeFilter === 'use') return l.type !== 'move' && l.type !== 'note';
        if (typeFilter === 'move') return l.type === 'move';
        if (typeFilter === 'note') return l.type === 'note';
        return true;
      })
      .filter((l) => {
        if (l.type === 'move' || l.type === 'note') return periodFilter === 'all';
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
        </div>
        {typeFilter !== 'move' && typeFilter !== 'note' && (
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

echo "Files written. Committing and pushing ..."
git add -A && git commit -m "Link direct change-outs (10-min auto-link); show as 'Changed into' in history" && git push
echo "Done. Netlify will auto-build from master; then tap Sync on the GitHub source in project knowledge."
