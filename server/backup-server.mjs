#!/usr/bin/env node
// Ledger backup receiver — a tiny, dependency-free Node service.
//
// Accepts the app's backup JSON at POST /api/backup (bearer-token auth),
// stores timestamped copies on disk, keeps a rolling window, and maintains
// latest.json. Backups are USER DATA and live only in DATA_DIR on the
// server — never in this repo.
//
// This file ships in the repo so it stays versioned and arrives with the
// normal git pull, but running it is a one-time server-side setup:
//
//   1. Generate a token:      openssl rand -hex 32
//   2. Run under systemd with environment:
//        LEDGER_BACKUP_TOKEN=<token>   (required)
//        PORT=8091                     (default)
//        DATA_DIR=/var/lib/ledger-backups   (default)
//        KEEP=30                       (rolling copies to keep, default)
//   3. Caddy: route /api/* to it, e.g.
//        handle /api/* { reverse_proxy 127.0.0.1:8091 }
//
// Endpoints:
//   GET  /api/backup/health  -> 200 {"ok":true}      (no auth; reveals nothing)
//   POST /api/backup         -> 200 {"ok":true,...}  (Authorization: Bearer <token>)

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const TOKEN = process.env.LEDGER_BACKUP_TOKEN || '';
const PORT = Number(process.env.PORT) || 8091;
const DATA_DIR = process.env.DATA_DIR || '/var/lib/ledger-backups';
const KEEP = Math.max(1, Number(process.env.KEEP) || 30);
const MAX_BYTES = Math.max(1, Number(process.env.MAX_BYTES) || 100 * 1024 * 1024);

if (!TOKEN) {
  console.error('LEDGER_BACKUP_TOKEN is not set — refusing to start.');
  process.exit(1);
}

fs.mkdirSync(DATA_DIR, { recursive: true });

const sha256 = (s) => crypto.createHash('sha256').update(s, 'utf8').digest();
const tokenOk = (header) => {
  if (typeof header !== 'string' || !header.startsWith('Bearer ')) return false;
  const presented = header.slice(7).trim();
  if (!presented) return false;
  // Hash both sides so timingSafeEqual gets equal-length buffers.
  return crypto.timingSafeEqual(sha256(presented), sha256(TOKEN));
};

const send = (res, status, obj) => {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  });
  res.end(body);
};

// Rolling window: keep the newest KEEP timestamped backups, delete the rest.
const prune = () => {
  const files = fs
    .readdirSync(DATA_DIR)
    .filter((f) => /^ledger-backup-.*\.json$/.test(f))
    .sort(); // timestamped names sort chronologically
  const excess = files.length - KEEP;
  for (let i = 0; i < excess; i++) {
    try { fs.unlinkSync(path.join(DATA_DIR, files[i])); } catch { /* ignore */ }
  }
  return Math.min(files.length, KEEP);
};

const server = http.createServer((req, res) => {
  const url = (req.url || '').split('?')[0];

  if (req.method === 'GET' && url === '/api/backup/health') {
    return send(res, 200, { ok: true });
  }

  if (url !== '/api/backup') {
    return send(res, 404, { ok: false, error: 'not found' });
  }
  if (req.method !== 'POST') {
    return send(res, 405, { ok: false, error: 'method not allowed' });
  }
  if (!tokenOk(req.headers.authorization)) {
    return send(res, 401, { ok: false, error: 'unauthorized' });
  }

  const chunks = [];
  let received = 0;
  let aborted = false;

  req.on('data', (chunk) => {
    if (aborted) return;
    received += chunk.length;
    if (received > MAX_BYTES) {
      aborted = true;
      send(res, 413, { ok: false, error: 'payload too large' });
      req.destroy();
      return;
    }
    chunks.push(chunk);
  });

  req.on('end', () => {
    if (aborted) return;
    let data;
    try {
      data = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    } catch {
      return send(res, 400, { ok: false, error: 'invalid JSON' });
    }
    // Sanity check that this is actually a Ledger export.
    if (!data || data.version !== 1 || !Array.isArray(data.logs)) {
      return send(res, 400, { ok: false, error: 'unrecognized backup format' });
    }

    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    const name = `ledger-backup-${stamp}.json`;
    const body = JSON.stringify(data);
    try {
      // Write via a temp file + rename so latest.json is never half-written.
      const finalPath = path.join(DATA_DIR, name);
      const tmpPath = finalPath + '.tmp';
      fs.writeFileSync(tmpPath, body);
      fs.renameSync(tmpPath, finalPath);

      const latestTmp = path.join(DATA_DIR, 'latest.json.tmp');
      fs.writeFileSync(latestTmp, body);
      fs.renameSync(latestTmp, path.join(DATA_DIR, 'latest.json'));

      const kept = prune();
      console.log(`[${new Date().toISOString()}] stored ${name} (${received} bytes, ${kept} kept)`);
      return send(res, 200, { ok: true, savedAs: name, kept });
    } catch (e) {
      console.error('write failed:', e);
      return send(res, 500, { ok: false, error: 'could not store backup' });
    }
  });

  req.on('error', () => { aborted = true; });
});

// Localhost only — the outside world reaches this through Caddy.
server.listen(PORT, '127.0.0.1', () => {
  console.log(`Ledger backup receiver on 127.0.0.1:${PORT}, storing in ${DATA_DIR}, keeping ${KEEP}`);
});
