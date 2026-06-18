// Service worker for Ledger.
//
// Update strategy (so new deploys appear without a force-close):
//   - Navigations / HTML  -> network-first. Every launch fetches the freshest
//                            index.html when online, falling back to cache when
//                            offline. Fresh HTML references the newest hashed
//                            asset filenames, which then get fetched + cached.
//   - Hashed build assets -> cache-first / stale-while-revalidate. Filenames
//                            change on every build, so cached copies are always
//                            valid; new ones are fetched once and kept.
//
// Bumping CACHE_NAME purges older caches on activate.

const CACHE_NAME = 'ledger-v2';
const APP_SHELL = ['./', './index.html', './manifest.webmanifest'];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)).catch(() => {})
  );
  // Note: we intentionally do NOT skipWaiting() here. The page decides when to
  // promote a new worker (see the SKIP_WAITING message below), which avoids an
  // unnecessary reload on the very first install.
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// The page posts this when it detects an updated worker is ready.
self.addEventListener('message', (e) => {
  if (e.data === 'SKIP_WAITING') self.skipWaiting();
});

const isNavigation = (req) =>
  req.mode === 'navigate' ||
  (req.method === 'GET' && (req.headers.get('accept') || '').includes('text/html'));

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  // Network-first for the app shell (HTML), with a timeout fallback to cache.
  if (isNavigation(req)) {
    e.respondWith(
      Promise.race([
        fetch(req).then((res) => {
          const clone = res.clone();
          caches.open(CACHE_NAME).then((c) => c.put('./index.html', clone)).catch(() => {});
          return res;
        }),
        new Promise((resolve) =>
          setTimeout(() => resolve(caches.match('./index.html')), 4000)
        ),
      ]).catch(() => caches.match('./index.html'))
    );
    return;
  }

  // Stale-while-revalidate for assets and other same-origin GETs.
  e.respondWith(
    caches.match(req).then((cached) => {
      const network = fetch(req)
        .then((res) => {
          if (res && res.ok) {
            const clone = res.clone();
            caches.open(CACHE_NAME).then((c) => c.put(req, clone)).catch(() => {});
          }
          return res;
        })
        .catch(() => cached);
      return cached || network;
    })
  );
});
