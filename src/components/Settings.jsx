import React, { useRef, useState, useEffect } from 'react';
import { Download, Upload, MapPin, AlertTriangle, GlassWater, CloudUpload, Check } from 'lucide-react';
import { Modal, ConfirmDialog } from './Common';
import { exportAll, importAll, clearAll, kvSet } from '../lib/storage';
import { formatDate } from '../lib/helpers';
import { DRINK_SIZES, normalizeDrinkPresets } from '../lib/intake';
import {
  getAutoBackupConfig, saveAutoBackupConfig,
  getAutoBackupLastError, runAutoBackup,
} from '../lib/autobackup';

export default function Settings({
  open, onClose, onOpenLocations, onDataChanged, onShowToast,
  lastBackupAt, onBackedUp, drinkPresets, onSaveDrinkPresets,
}) {
  const fileRef = useRef(null);
  const [confirmClear, setConfirmClear] = useState(false);
  const [confirmImport, setConfirmImport] = useState(null);

  // Editable copy of the per-bucket drink ounces, seeded from the live presets.
  const [sizeDraft, setSizeDraft] = useState(() => normalizeDrinkPresets(drinkPresets));
  useEffect(() => {
    if (open) setSizeDraft(normalizeDrinkPresets(drinkPresets));
  }, [open, drinkPresets]);

  // Auto-backup to the home server. Config (enabled + token) lives in kv on
  // this device only. The token never goes anywhere near the repo.
  const [autoCfg, setAutoCfg] = useState({ enabled: false, token: '' });
  const [autoErr, setAutoErr] = useState(null);
  const [autoBusy, setAutoBusy] = useState(false);
  useEffect(() => {
    if (!open) return;
    (async () => {
      setAutoCfg(await getAutoBackupConfig());
      setAutoErr(await getAutoBackupLastError());
    })();
  }, [open]);

  const saveAuto = async (next) => {
    setAutoCfg(next);
    try {
      await saveAutoBackupConfig(next);
    } catch {
      onShowToast?.('Could not save auto-backup settings');
    }
  };

  const backupNow = async () => {
    setAutoBusy(true);
    // Persist whatever's typed in the token field before trying it.
    try { await saveAutoBackupConfig(autoCfg); } catch { /* ignore */ }
    const res = await runAutoBackup({ force: true });
    setAutoBusy(false);
    if (res.ok) {
      setAutoErr(null);
      onBackedUp?.(res.at);
      onShowToast?.('Backed up to server');
    } else if (res.skipped) {
      onShowToast?.('Turn it on and enter the token first');
    } else {
      setAutoErr(res.error);
      onShowToast?.(res.error?.message || 'Backup failed');
    }
  };

  const saveSizes = async () => {
    const next = normalizeDrinkPresets(sizeDraft);
    try {
      await kvSet('drinkSizePresets', next);
      onSaveDrinkPresets?.(next);
      onShowToast?.('Drink sizes saved');
    } catch {
      onShowToast?.('Could not save drink sizes');
    }
  };

  const handleExport = async () => {
    try {
      const data = await exportAll();
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      const date = new Date().toISOString().slice(0, 10);
      a.href = url;
      a.download = `ledger-backup-${date}.json`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      const now = Date.now();
      try { await kvSet('lastBackupAt', now); } catch {}
      onBackedUp?.(now);
      onShowToast?.('Backup downloaded');
    } catch (e) {
      onShowToast?.('Export failed');
    }
  };

  const handleImportFile = (file) => {
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (e) => {
      try {
        const data = JSON.parse(e.target.result);
        if (data?.version !== 1) throw new Error('bad version');
        setConfirmImport(data);
      } catch {
        onShowToast?.('Could not read that file');
      }
    };
    reader.onerror = () => onShowToast?.('Could not read that file');
    reader.readAsText(file);
  };

  const doImport = async () => {
    try {
      await importAll(confirmImport);
      setConfirmImport(null);
      onShowToast?.('Restored from backup');
      onDataChanged?.();
      onClose();
    } catch (e) {
      onShowToast?.('Import failed');
      setConfirmImport(null);
    }
  };

  const doClear = async () => {
    try {
      await clearAll();
      setConfirmClear(false);
      onShowToast?.('All data cleared');
      onDataChanged?.();
      onClose();
    } catch {
      onShowToast?.('Could not clear data');
      setConfirmClear(false);
    }
  };

  return (
    <>
      <Modal open={open} onClose={onClose} title="Settings"
        footer={<button className="btn btn-ghost" onClick={onClose}>Done</button>}
      >
        <div style={{ display: 'grid', gap: 14 }}>
          <div style={{
            textAlign: 'center', fontSize: 12, color: 'var(--ink-mute)',
            padding: '2px 0 4px',
          }}>
            Ledger · build 2026-07-01
          </div>

          <button
            className="btn btn-ghost"
            style={{ justifyContent: 'flex-start', width: '100%', padding: 14 }}
            onClick={() => { onClose(); onOpenLocations(); }}
          >
            <MapPin size={16} />
            <span style={{ flex: 1, textAlign: 'left' }}>Manage locations</span>
          </button>

          <hr className="hairline" />

          <div className="eyebrow">Backup</div>
          <p style={{ fontSize: 13, color: 'var(--ink-soft)', margin: 0 }}>
            Export your data as a JSON file. Save it somewhere safe in case your phone dies or browser data gets cleared. Re-import to restore.
          </p>
          <div style={{ fontSize: 12, color: lastBackupAt ? 'var(--ink-mute)' : 'var(--accent)', fontStyle: 'italic' }}>
            {lastBackupAt
              ? `Last backed up ${formatDate(lastBackupAt, { year: true })}.`
              : 'No backup yet on this device.'}
          </div>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            <button className="btn btn-ghost" onClick={handleExport}>
              <Download size={14} /> Export backup
            </button>
            <button className="btn btn-ghost" onClick={() => fileRef.current?.click()}>
              <Upload size={14} /> Restore from file
            </button>
            <input
              ref={fileRef}
              type="file"
              accept="application/json,.json"
              style={{ display: 'none' }}
              onChange={(e) => {
                const f = e.target.files?.[0];
                if (f) handleImportFile(f);
                e.target.value = '';
              }}
            />
          </div>

          <hr className="hairline" />

          <div className="eyebrow">Auto-backup to home server</div>
          <p style={{ fontSize: 13, color: 'var(--ink-soft)', margin: 0 }}>
            When turned on, the app quietly uploads a full backup to your server about once a day (and keeps a rolling set there). Your data still lives on this phone — this is just a safety net.
          </p>
          <button
            type="button"
            className={`check-row ${autoCfg.enabled ? 'active' : ''}`}
            onClick={() => saveAuto({ ...autoCfg, enabled: !autoCfg.enabled })}
          >
            <span style={{ flex: 1 }}>
              {autoCfg.enabled ? 'Auto-backup is on' : 'Auto-backup is off'}
            </span>
            {autoCfg.enabled && <Check size={14} />}
          </button>
          {autoCfg.enabled && (
            <>
              <div>
                <label className="label">Backup token</label>
                <input
                  className="input"
                  type="password"
                  autoComplete="off"
                  placeholder="Paste the token from your server setup"
                  value={autoCfg.token}
                  onChange={(e) => setAutoCfg((c) => ({ ...c, token: e.target.value }))}
                  onBlur={() => saveAuto(autoCfg)}
                />
                <div style={{ fontSize: 11, color: 'var(--ink-mute)', marginTop: 6, fontStyle: 'italic' }}>
                  Stored only on this device. The same token you set on the server.
                </div>
              </div>
              {autoErr?.message && (
                <div style={{ fontSize: 12, color: 'var(--danger)', fontStyle: 'italic' }}>
                  Last attempt failed: {autoErr.message}
                </div>
              )}
              <div>
                <button className="btn btn-ghost" onClick={backupNow} disabled={autoBusy}>
                  <CloudUpload size={14} /> {autoBusy ? 'Uploading…' : 'Back up to server now'}
                </button>
              </div>
            </>
          )}

          <hr className="hairline" />

          <div className="eyebrow">Drink sizes</div>
          <p style={{ fontSize: 13, color: 'var(--ink-soft)', margin: 0 }}>
            Ounces behind each size bucket, used to estimate daily intake. Set these to your usual cups and bottles. A logged drink's exact amount, when given, overrides these.
          </p>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8 }}>
            {DRINK_SIZES.map((sz) => (
              <div key={sz.value}>
                <label className="label">{sz.label}</label>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <input
                    className="input"
                    type="number" inputMode="decimal" min="1" step="1"
                    value={sizeDraft[sz.value]}
                    onChange={(e) => setSizeDraft((d) => ({ ...d, [sz.value]: e.target.value }))}
                  />
                  <span style={{ fontSize: 12, color: 'var(--ink-mute)' }}>oz</span>
                </div>
              </div>
            ))}
          </div>
          <div>
            <button className="btn btn-ghost" onClick={saveSizes}>
              <GlassWater size={14} /> Save drink sizes
            </button>
          </div>

          <hr className="hairline" />

          <div className="eyebrow" style={{ color: 'var(--danger)' }}>Danger zone</div>
          <button className="btn btn-danger" onClick={() => setConfirmClear(true)}>
            <AlertTriangle size={14} /> Erase all data
          </button>
        </div>
      </Modal>

      <ConfirmDialog
        open={confirmClear}
        title="Erase all data?"
        body="This deletes every product, location, log, and photo. The action can't be undone unless you have a backup file."
        confirmLabel="Erase everything"
        onCancel={() => setConfirmClear(false)}
        onConfirm={doClear}
      />

      <ConfirmDialog
        open={!!confirmImport}
        title="Restore from backup?"
        body="This replaces all your current data with the contents of the backup file."
        confirmLabel="Restore"
        danger={false}
        onCancel={() => setConfirmImport(null)}
        onConfirm={doImport}
      />
    </>
  );
}
