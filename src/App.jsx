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
              ledger
            </span>
            <span className="eyebrow" style={{ marginLeft: 10, fontSize: 9.5 }}>
              supplies & usage
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
