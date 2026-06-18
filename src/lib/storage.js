// IndexedDB wrapper for Ledger.
//
// We use four separate object stores so each can be loaded
// independently (photos are big; we only want to load the
// ones we actually need to display):
//
//   - kv         { key, value }  for app state (current location, prefs)
//   - products   keyed by product id
//   - locations  keyed by location id
//   - logs       keyed by log id
//   - photos     keyed by product id, value is { thumb, full }
//
// All values are JSON-serializable (data URLs for photos).

const DB_NAME = 'ledger-db';
const DB_VERSION = 1;
const STORES = ['kv', 'products', 'locations', 'logs', 'photos'];

let dbPromise = null;

const openDB = () => {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onerror = () => reject(req.error);
    req.onsuccess = () => resolve(req.result);
    req.onupgradeneeded = (e) => {
      const db = e.target.result;
      STORES.forEach((name) => {
        if (!db.objectStoreNames.contains(name)) {
          if (name === 'kv') {
            db.createObjectStore(name, { keyPath: 'key' });
          } else {
            db.createObjectStore(name, { keyPath: 'id' });
          }
        }
      });
    };
  });
  return dbPromise;
};

const tx = async (storeName, mode = 'readonly') => {
  const db = await openDB();
  const transaction = db.transaction(storeName, mode);
  return transaction.objectStore(storeName);
};

// Generic helpers
const promisifyRequest = (req) =>
  new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });

// === Generic store access ===
export const getAll = async (storeName) => {
  const store = await tx(storeName);
  return promisifyRequest(store.getAll());
};

export const getOne = async (storeName, id) => {
  const store = await tx(storeName);
  return promisifyRequest(store.get(id));
};

export const putOne = async (storeName, value) => {
  const store = await tx(storeName, 'readwrite');
  return promisifyRequest(store.put(value));
};

export const deleteOne = async (storeName, id) => {
  const store = await tx(storeName, 'readwrite');
  return promisifyRequest(store.delete(id));
};

export const clearStore = async (storeName) => {
  const store = await tx(storeName, 'readwrite');
  return promisifyRequest(store.clear());
};

// === Key-value (app state) ===
export const kvGet = async (key) => {
  const r = await getOne('kv', key);
  return r ? r.value : null;
};

export const kvSet = async (key, value) => {
  return putOne('kv', { key, value });
};

// === Product helpers (products + their photos in one logical operation) ===
export const getAllProducts = () => getAll('products');
export const getAllLocations = () => getAll('locations');
export const getAllLogs = () => getAll('logs');

export const saveProduct = (product) => putOne('products', product);
export const removeProduct = async (id) => {
  await deleteOne('products', id);
  await deleteOne('photos', id);
};

export const saveLocation = (location) => putOne('locations', location);
export const removeLocation = (id) => deleteOne('locations', id);

export const saveLog = (log) => putOne('logs', log);
export const removeLog = (id) => deleteOne('logs', id);

// === Photo helpers (kept separate so we don't load big data URLs unnecessarily) ===
// Returns { id, thumb, full } or null
export const getPhoto = (productId) => getOne('photos', productId);

export const savePhoto = (productId, { thumb, full }) =>
  putOne('photos', { id: productId, thumb, full });

export const removePhoto = (productId) => deleteOne('photos', productId);

// Get all photo thumbnails — used at app load to show product lists.
// We do NOT load full-size versions until the user taps a photo.
export const getAllThumbs = async () => {
  const photos = await getAll('photos');
  const map = {};
  photos.forEach((p) => {
    map[p.id] = p.thumb;
  });
  return map;
};

// === Export / Import (backup feature) ===
export const exportAll = async () => {
  const [products, locations, logs, photos, kv] = await Promise.all([
    getAll('products'),
    getAll('locations'),
    getAll('logs'),
    getAll('photos'),
    getAll('kv'),
  ]);
  return {
    version: 1,
    exportedAt: new Date().toISOString(),
    products,
    locations,
    logs,
    photos,
    kv,
  };
};

export const importAll = async (data) => {
  if (!data || data.version !== 1) {
    throw new Error('Unrecognized backup format');
  }
  // Clear all stores first
  await Promise.all(STORES.map(clearStore));
  // Restore each store
  const restore = async (storeName, items) => {
    if (!Array.isArray(items)) return;
    const store = await tx(storeName, 'readwrite');
    items.forEach((item) => store.put(item));
  };
  await restore('products', data.products);
  await restore('locations', data.locations);
  await restore('logs', data.logs);
  await restore('photos', data.photos);
  await restore('kv', data.kv);
};

export const clearAll = async () => {
  await Promise.all(STORES.map(clearStore));
};
