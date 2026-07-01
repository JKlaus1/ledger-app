// Auto-backup to the home server.
//
// Tier-1 design: IndexedDB stays the source of truth and the app remains
// fully offline-first. This module just pushes the SAME payload the manual
// "Export backup" button produces to POST /api/backup (proxied by Caddy to
// a small service on the server), so a rolling copy exists off-device.
//
// A successful auto-backup updates the shared 'lastBackupAt' kv key — the
// same one the manual export sets — so the 14-day backup nag stays quiet
// while this is working, and both paths report through one status line.
//
// Config lives in kv (on-device only, never in the repo):
//   autoBackupConfig    { enabled, token }
//   autoBackupLastError { at, message } | null

import { exportAll, kvGet, kvSet } from './storage';

const CONFIG_KEY = 'autoBackupConfig';
const ERROR_KEY = 'autoBackupLastError';
const ENDPOINT = '/api/backup';

// How often the background trigger considers a new backup "due".
export const AUTO_BACKUP_INTERVAL_MS = 24 * 3600 * 1000;

export const getAutoBackupConfig = async () => {
  try {
    const c = await kvGet(CONFIG_KEY);
    return { enabled: !!c?.enabled, token: c?.token || '' };
  } catch {
    return { enabled: false, token: '' };
  }
};

export const saveAutoBackupConfig = (cfg) =>
  kvSet(CONFIG_KEY, {
    enabled: !!cfg.enabled,
    token: (cfg.token || '').trim(),
  });

export const getAutoBackupLastError = async () => {
  try {
    return await kvGet(ERROR_KEY);
  } catch {
    return null;
  }
};

// Run a backup if configured (and due, unless forced). Never throws.
// Returns:
//   { ok: true, at }                     — uploaded
//   { ok: false, skipped: true, reason } — not enabled / not due / offline
//   { ok: false, error: { at, message }} — attempted and failed
export const runAutoBackup = async ({ force = false } = {}) => {
  const cfg = await getAutoBackupConfig();
  if (!cfg.enabled || !cfg.token) return { ok: false, skipped: true, reason: 'off' };

  if (!force) {
    let last = null;
    try { last = await kvGet('lastBackupAt'); } catch { /* ignore */ }
    if (last && Date.now() - last < AUTO_BACKUP_INTERVAL_MS) {
      return { ok: false, skipped: true, reason: 'fresh' };
    }
    if (typeof navigator !== 'undefined' && navigator.onLine === false) {
      return { ok: false, skipped: true, reason: 'offline' };
    }
  }

  try {
    const data = await exportAll();
    const res = await fetch(ENDPOINT, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + cfg.token,
      },
      body: JSON.stringify(data),
    });
    if (!res.ok) {
      throw new Error(
        res.status === 401 ? 'Server rejected the token' : `Server error (${res.status})`
      );
    }
    const at = Date.now();
    try { await kvSet('lastBackupAt', at); } catch { /* ignore */ }
    try { await kvSet(ERROR_KEY, null); } catch { /* ignore */ }
    return { ok: true, at };
  } catch (e) {
    const err = {
      at: Date.now(),
      message: (e && e.message) || 'Could not reach the backup server',
    };
    try { await kvSet(ERROR_KEY, err); } catch { /* ignore */ }
    return { ok: false, error: err };
  }
};
