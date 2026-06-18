# Getting Ledger onto your phone

You have a zip file (`ledger-app.zip`). Here's the path from there to a working app on your home screen.

## What you need first

**Node.js** — a tool for running JavaScript builds. One-time install.

- Go to https://nodejs.org
- Download the LTS version for your operating system
- Run the installer with default options
- Done. You won't interact with it directly.

That's the only prerequisite.

## Build the app (one time)

1. **Unzip** `ledger-app.zip` somewhere convenient — Desktop, Documents, wherever.
2. **Open a terminal** in that folder.
   - Mac: Right-click the `ledger-app` folder → "New Terminal at Folder"
   - Windows: Open the folder, hold Shift, right-click empty space → "Open in Terminal"
3. **Run two commands.** Type each, hit enter, wait for it to finish:

   ```
   npm install
   ```
   *(takes 1–2 minutes, downloads dependencies)*

   ```
   npm run build
   ```
   *(takes 10 seconds, produces the deployable site)*

4. You now have a `dist` folder inside `ledger-app`. That folder is your app.

## Put it online

The app needs to be hosted somewhere so your phone can reach it. **Netlify Drop** is free, anonymous, and takes 30 seconds:

1. Go to https://app.netlify.com/drop
2. Drag the entire `dist` folder onto the page.
3. Wait a few seconds. Netlify gives you a URL like `https://lyrical-pony-12345.netlify.app`.
4. **Save that URL.** That's your app.

If you want to claim/customize the URL, sign up for a free Netlify account on that same page. Otherwise it'll work as-is for a few days; longer if you sign up.

## Install on your phone

Open the URL on your phone:

**iPhone (must be Safari):**
1. Tap the Share button (square with up-arrow)
2. Scroll down → "Add to Home Screen"
3. Confirm

**Android (Chrome):**
1. Tap the three-dot menu
2. "Install app" or "Add to Home screen"

Now it has its own icon and opens full-screen like a normal app. All data stays on your device.

## When you make changes later

If you (or I) update the code:

1. Replace files as needed
2. Run `npm run build` again
3. Drag the new `dist` folder to https://app.netlify.com/drop (or your account dashboard if you signed up)

## Backing up your data

In the app, tap the gear icon → "Export backup". This saves a JSON file. Keep one somewhere safe (email it to yourself, drop it in iCloud/Drive). If your phone dies or browser data gets cleared, importing that file restores everything.

I'd back up at least monthly, and definitely before changing phones.

## If something breaks

- **`npm install` fails:** Make sure Node.js is actually installed (`node --version` should print something). Try closing and reopening the terminal.
- **Site loads but looks blank:** Open it on a desktop browser first to confirm the build worked, then try the phone again. Sometimes browsers cache aggressively — try an incognito window.
- **Photos look fuzzy:** Tap them to view full-size. Lists use thumbnails for speed.

## File map (in case you need to know)

```
ledger-app/
├── src/             ← all the code
├── public/          ← icons, manifest, service worker
├── package.json     ← dependency list
├── README.md        ← technical reference
└── QUICKSTART.md    ← this file
```

After `npm run build` you'll also have:

```
ledger-app/dist/     ← what you upload to Netlify
ledger-app/node_modules/   ← downloaded dependencies (don't touch)
```
