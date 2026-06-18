# Ledger

A personal supply tracker for managing absorbent product inventory across multiple locations. Built as a Progressive Web App (PWA) so it installs to your phone's home screen and works offline.

## Features

- **Multi-location inventory** — Track stock separately at each location (closet, dresser, work, truck, etc.). Locations are user-defined and fully editable.
- **Move stock between locations** — One-tap transfers logged in history.
- **High-quality photos** — Each product can have a photo. Thumbnails are kept for fast list rendering, full-size versions for detail viewing. Stored locally in IndexedDB.
- **Usage logging** — Day/night, performance (dry/leaked), notes, custom timestamps. Quick "use one" decrements the right location automatically.
- **Insights** — 14-day chart, day/night split, top products, leak rate per product, days remaining, usage by location.
- **Offline-first** — All data lives on your device. No account, no servers, no analytics.
- **Installable** — Add to home screen on iOS and Android for a native-app feel.

## Project structure

```
ledger-app/
├── public/
│   ├── manifest.webmanifest    # PWA manifest
│   ├── sw.js                   # Service worker for offline support
│   ├── icon-192.png            # App icon (you can replace with your own)
│   └── icon-512.png
├── src/
│   ├── lib/
│   │   ├── storage.js          # IndexedDB wrapper
│   │   ├── images.js           # Image processing
│   │   └── helpers.js          # Date/format utilities and constants
│   ├── components/
│   │   ├── Common.jsx          # Shared UI primitives (Modal, Pill, etc.)
│   │   ├── ProductForm.jsx     # Add/edit product modal
│   │   ├── LogForm.jsx         # Log a use modal
│   │   ├── MoveForm.jsx        # Transfer stock between locations modal
│   │   ├── RestockForm.jsx     # Add/adjust stock modal
│   │   ├── LocationManager.jsx # Manage locations
│   │   ├── PhotoViewer.jsx     # Tap-to-view full size photo
│   │   ├── Dashboard.jsx       # Today / home tab
│   │   ├── Inventory.jsx       # Inventory tab
│   │   ├── History.jsx         # History tab
│   │   └── Insights.jsx        # Insights tab
│   ├── App.jsx                 # Main app shell + state
│   ├── main.jsx                # Entry point
│   └── styles.css              # All styles
├── index.html
├── vite.config.js
├── package.json
└── README.md
```

## Local development

Requires Node.js 18 or newer.

```bash
npm install
npm run dev
```

This starts a dev server at http://localhost:5173. Open it in your browser to test.

## Deploying to Netlify (free, drag-and-drop)

1. Build the app:
   ```bash
   npm run build
   ```
   This creates a `dist/` folder.

2. Go to https://app.netlify.com/drop
3. Drag the `dist/` folder onto the page.
4. Netlify gives you a URL like `https://ledger-supplies-XXXX.netlify.app`. That's your app.
5. Optional: Sign up for a free Netlify account to claim/customize the URL and redeploy when you make changes.

## Installing on your phone

### iOS (Safari)
1. Open the Netlify URL in Safari (must be Safari, not Chrome).
2. Tap the Share button (square with arrow).
3. Scroll down and tap "Add to Home Screen".
4. Name it "Ledger" and tap Add.

### Android (Chrome)
1. Open the Netlify URL in Chrome.
2. Tap the three-dot menu.
3. Tap "Install app" or "Add to Home screen".

The app will now have its own icon and launch full-screen like a native app. Data is stored on the device — uninstalling the app or clearing browser data will remove your inventory and logs.

## Data privacy

Everything stays on your device. The app makes no network requests after initial load, has no analytics, no account system, and no backend. Your data is yours and yours alone.

## Backing up your data

In settings (gear icon, top right) you can export all your data as a JSON file. Save this somewhere safe periodically. You can re-import it on the same device or a new one to restore.
