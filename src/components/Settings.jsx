import React, { useRef, useState } from 'react';
import { Download, Upload, MapPin, AlertTriangle } from 'lucide-react';
import { Modal, ConfirmDialog } from './Common';
import { exportAll, importAll, clearAll } from '../lib/storage';

export default function Settings({
  open, onClose, onOpenLocations, onDataChanged, onShowToast,
}) {
  const fileRef = useRef(null);
  const [confirmClear, setConfirmClear] = useState(false);
  const [confirmImport, setConfirmImport] = useState(null);

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
