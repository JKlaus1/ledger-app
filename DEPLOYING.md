# Faster deploys (no more drag-and-drop)

You have two ways to push updates without visiting the Netlify website. Both
deploy to your **existing** site, so the URL — and all your phone's data — stay
put. (Important: your data lives in the browser under that exact URL. If you
ever deploy to a *new* URL, export a backup first and import it on the new one.)

---

## Option 1 — Netlify CLI (fastest, one command)

Best for solo tweaking. No Git required.

One-time setup:

```
npm install -g netlify-cli
netlify login            # opens browser, authorize once
cd ledger-app
netlify link             # pick your existing "friendly-wisp-9ff42d" site
```

After that, every update is a single command from the project folder:

```
netlify deploy --prod
```

It builds locally and uploads `dist` to your live site in ~30–60s. Done.

---

## Option 2 — Git-connected (auto-build on every push)

Best if you also want version history and backups of the code itself.

One-time setup:

1. Put the project on GitHub (private repo is fine):
   ```
   cd ledger-app
   git init
   git add .
   git commit -m "Ledger"
   ```
   Create an empty repo on github.com, then follow its "push an existing repo"
   lines (a couple of `git remote add` / `git push` commands).

2. Link it to your existing Netlify site:
   - Netlify dashboard → your site → **Site configuration**
   - **Build & deploy → Continuous deployment → Link repository**
   - Choose the GitHub repo. Build settings come from `netlify.toml`
     (build command `npm run build`, publish dir `dist`) — just confirm.

After that, your update loop is:

```
git commit -am "what I changed"
git push
```

Netlify sees the push, runs the build, and deploys in ~1–2 min.

---

## Your day-to-day loop

While editing, run the live preview on your computer — instant, no deploy:

```
npm run dev
```

When you're happy, deploy with whichever option above you chose. Your phone
picks up the new version automatically on the next launch (the app now checks
for updates and refreshes itself — no force-close needed).
