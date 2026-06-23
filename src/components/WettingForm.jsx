import React, { useState, useEffect } from 'react';
import { Check, X, Droplets, Droplet, Pencil, AlertTriangle, ShieldCheck } from 'lucide-react';
import { Modal } from './Common';
import {
  uid, toLocalInputValue, fromLocalInputValue,
  productDisplayName, formatTime, formatDuration, wearDuration,
} from '../lib/helpers';
import {
  WETNESS, DIAPER_FEEL, CORE_FEEL, POSTURES, getWettings, wettingStats,
  wetnessLabel, feelLabel, coreFeelLabel, postureLabel,
  capacityProfile, globalCapacity, capacityStatus,
} from '../lib/wetting';
import { TAPE_STATES, tapeLabel } from '../lib/session';

// WettingSummary — compact, reusable read-out of a wear session's wettings.
// Used on the dashboard's "currently wearing" card and in History rows.
// In compact mode it renders nothing when there are no wettings yet.
export function WettingSummary({ log, compact = false, style = {} }) {
  const { count, peakFeel, byAmount } = wettingStats(log);

  if (count === 0) {
    if (compact) return null;
    return (
      <div style={{ fontSize: 12, color: 'var(--ink-mute)', ...style }}>
        No wettings logged yet.
      </div>
    );
  }

  const breakdown = WETNESS
    .filter((w) => byAmount[w.value] > 0)
    .map((w) => `${byAmount[w.value]} ${w.label.toLowerCase()}`)
    .join(' · ');

  if (compact) {
    return (
      <span style={{
        display: 'inline-flex', alignItems: 'center', gap: 5,
        color: 'var(--accent)', ...style,
      }}>
        <Droplet size={11} />
        {count} wetting{count !== 1 ? 's' : ''}
        {peakFeel && (
          <span style={{ color: 'var(--ink-mute)' }}>· {feelLabel(peakFeel).toLowerCase()}</span>
        )}
      </span>
    );
  }

  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 8, ...style }}>
      <span style={{
        display: 'inline-flex', alignItems: 'center', gap: 5,
        fontSize: 13, color: 'var(--accent)', fontWeight: 600,
      }}>
        <Droplets size={14} /> {count} wetting{count !== 1 ? 's' : ''}
      </span>
      {breakdown && <span style={{ fontSize: 12, color: 'var(--ink-soft)' }}>{breakdown}</span>}
      {peakFeel && (
        <span style={{ fontSize: 12, color: 'var(--ink-mute)' }}>
          · felt {feelLabel(peakFeel).toLowerCase()}
        </span>
      )}
    </div>
  );
}

// CapacityMeter — shows how close this diaper's running load is to the point
// it (or similar diapers) have historically leaked. Quiet when there's no
// basis to judge yet; turns amber on approach and red once at/over the line.
function CapacityMeter({ load, status, isOn }) {
  if (status.level === 'none' || load <= 0) return null;

  const palette = {
    ok:    { bar: 'var(--primary)', fg: 'var(--ink-soft)',  Icon: ShieldCheck },
    watch: { bar: '#C9985A',        fg: '#9A6A2E',          Icon: AlertTriangle },
    over:  { bar: 'var(--danger)',  fg: 'var(--danger)',    Icon: AlertTriangle },
  }[status.level];
  const { bar, fg, Icon } = palette;

  const pct = Math.max(6, Math.min(100, Math.round((status.ratio || 0) * 100)));
  const where = status.fromProduct ? 'this diaper' : 'similar diapers';
  const ceilTxt = Number.isInteger(status.ceiling) ? status.ceiling : status.ceiling.toFixed(1);

  let msg;
  if (status.level === 'over') {
    msg = status.basis === 'leak'
      ? `At/over the load ${where} has leaked at (~${ceilTxt}).${isOn ? ' Consider changing soon.' : ''}`
      : `Past the most ${where} held dry (${ceilTxt}) — uncharted territory.`;
  } else if (status.level === 'watch') {
    msg = status.basis === 'leak'
      ? `Nearing the load ${where} has leaked at (~${ceilTxt}).`
      : `Approaching the most ${where} held dry (${ceilTxt}).`;
  } else {
    msg = status.basis === 'leak'
      ? `Comfortably under the ~${ceilTxt} load ${where} has leaked at.`
      : `Under the ${ceilTxt} load ${where} has held dry.`;
  }

  return (
    <div style={{ marginTop: 10 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, color: fg }}>
        <Icon size={13} />
        <span style={{ flex: 1 }}>{msg}</span>
        <span className="num" style={{ color: fg }}>{load}</span>
      </div>
      <div style={{
        height: 4, background: 'var(--line-soft)',
        borderRadius: 3, marginTop: 6, overflow: 'hidden',
      }}>
        <div style={{ height: '100%', width: `${pct}%`, background: bar, borderRadius: 3 }} />
      </div>
    </div>
  );
}

// WettingForm — add / edit / remove wettings on a single wear session.
// Works for the diaper currently on, or any previously worn one. Persists
// immediately via onSave(logId, wettings) so nothing is lost on close.
export default function WettingForm({ open, onClose, entry, product, onSave, logs = [] }) {
  const [list, setList] = useState([]);
  const [editingId, setEditingId] = useState(null);
  const [at, setAt] = useState(Date.now());
  const [amount, setAmount] = useState('');
  const [feel, setFeel] = useState('');
  const [core, setCore] = useState('');
  const [tapes, setTapes] = useState('');
  const [posture, setPosture] = useState('');
  const [note, setNote] = useState('');

  const defaultAt = () => {
    if (!entry) return Date.now();
    // Currently worn → now. Previously worn → the time it came off.
    return entry.takenOffAt == null ? Date.now() : entry.takenOffAt;
  };

  const resetSubForm = () => {
    setEditingId(null);
    setAt(defaultAt());
    setAmount('');
    setFeel('');
    setCore('');
    setTapes('');
    setPosture('');
    setNote('');
  };

  // Seed the working list when the modal opens for a given session.
  useEffect(() => {
    if (open && entry) {
      setList(getWettings(entry));
      resetSubForm();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, entry?.id]);

  if (!open || !entry) return null;

  const persist = (next) => {
    const sorted = [...next].sort((a, b) => (a.at || 0) - (b.at || 0));
    setList(sorted);
    onSave(entry.id, sorted);
  };

  const addOrUpdate = () => {
    if (!amount) return;
    const fields = {
      at, amount,
      feel: feel || null, core: core || null,
      tapes: tapes || null, posture: posture || null,
      note: note.trim(),
    };
    if (editingId) {
      persist(list.map((w) => (w.id === editingId ? { ...w, ...fields } : w)));
    } else {
      persist([...list, { id: uid(), ...fields }]);
    }
    resetSubForm();
  };

  const editRow = (w) => {
    setEditingId(w.id);
    setAt(w.at || Date.now());
    setAmount(w.amount || '');
    setFeel(w.feel || '');
    setCore(w.core || '');
    setTapes(w.tapes || '');
    setPosture(w.posture || '');
    setNote(w.note || '');
  };

  const removeRow = (id) => {
    persist(list.filter((w) => w.id !== id));
    if (editingId === id) resetSubForm();
  };

  const stats = wettingStats({ ...entry, wettings: list });
  const dur = wearDuration(entry);

  // Live capacity read: compare this session's running load against what this
  // product (and, as a fallback, all products) has held before. Exclude the
  // current entry so it never measures itself.
  const profile = capacityProfile(logs, entry.productId, entry.id);
  const gAll = globalCapacity(logs, entry.id);
  // Fallback compares only against the most any diaper has held dry. A global
  // leak floor would be dominated by the single weakest product and would cry
  // wolf on everything, so we deliberately drop it here.
  const fallback = { dryCeiling: gAll.dryCeiling };
  const capStatus = capacityStatus(stats.load, profile, fallback);
  const isOn = entry.takenOffAt == null;

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Wettings"
      footer={<button className="btn btn-primary" onClick={onClose}>Done</button>}
    >
      <div style={{ display: 'grid', gap: 16 }}>
        {/* Session summary — how this diaper is performing */}
        <div className="card" style={{ padding: '12px 14px' }}>
          <div style={{ fontSize: 14 }}>
            {product ? productDisplayName(product) : 'This diaper'}
          </div>
          <div style={{ fontSize: 12, color: 'var(--ink-mute)', marginTop: 3 }}>
            {entry.takenOffAt == null ? 'On now' : 'Previously worn'}
            {dur != null && ` · worn ${formatDuration(dur)}`}
            {` · ${stats.count} wetting${stats.count !== 1 ? 's' : ''}`}
            {stats.peakFeel && ` · felt ${feelLabel(stats.peakFeel).toLowerCase()}`}
          </div>
          <CapacityMeter load={stats.load} status={capStatus} isOn={isOn} />
        </div>

        {/* Existing wettings */}
        {list.length > 0 && (
          <div>
            <label className="label">Logged so far</label>
            <div className="card" style={{ padding: 4 }}>
              {list.map((w) => (
                <div
                  key={w.id}
                  className="row-divider"
                  style={{ padding: '10px 12px', display: 'flex', alignItems: 'center', gap: 10 }}
                >
                  <Droplet size={14} style={{ color: 'var(--accent)', flexShrink: 0 }} />
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontSize: 13 }}>
                      {wetnessLabel(w.amount)}
                      {w.feel && (
                        <span style={{ color: 'var(--ink-mute)' }}> · {feelLabel(w.feel).toLowerCase()}</span>
                      )}
                      {w.core && (
                        <span style={{ color: 'var(--ink-mute)' }}> · core {coreFeelLabel(w.core).toLowerCase()}</span>
                      )}
                      {w.tapes && (
                        <span style={{ color: 'var(--ink-mute)' }}> · tapes {tapeLabel(w.tapes).toLowerCase()}</span>
                      )}
                      {w.posture && (
                        <span style={{ color: 'var(--ink-mute)' }}> · {postureLabel(w.posture).toLowerCase()}</span>
                      )}
                    </div>
                    <div style={{ fontSize: 11, color: 'var(--ink-mute)', marginTop: 1 }}>
                      {formatTime(w.at)}{w.note ? ` · ${w.note}` : ''}
                    </div>
                  </div>
                  <button className="btn-icon" onClick={() => editRow(w)} aria-label="Edit wetting">
                    <Pencil size={13} />
                  </button>
                  <button className="btn-icon" onClick={() => removeRow(w.id)} aria-label="Remove wetting">
                    <X size={14} />
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}

        <hr className="hairline" />

        {/* Add / edit a single wetting */}
        <div style={{ display: 'grid', gap: 14 }}>
          <div className="eyebrow">{editingId ? 'Edit wetting' : 'Add a wetting'}</div>

          <div>
            <label className="label">When</label>
            <input
              className="input" type="datetime-local"
              value={toLocalInputValue(at)}
              onChange={(e) => setAt(fromLocalInputValue(e.target.value))}
            />
          </div>

          <div>
            <label className="label">How much?</label>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
              {WETNESS.map((w) => (
                <button
                  key={w.value} type="button"
                  className={`check-row ${amount === w.value ? 'active' : ''}`}
                  onClick={() => setAmount(w.value)}
                >
                  <span style={{ flex: 1 }}>{w.label}</span>
                  {amount === w.value && <Check size={14} />}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="label">How does it feel now? (optional)</label>
            <div style={{ display: 'grid', gap: 8 }}>
              {DIAPER_FEEL.map((f) => (
                <button
                  key={f.value} type="button"
                  className={`check-row ${feel === f.value ? 'active' : ''}`}
                  onClick={() => setFeel(feel === f.value ? '' : f.value)}
                >
                  <span style={{ flex: 1 }}>{f.label}</span>
                  {feel === f.value && <Check size={14} />}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="label">Core feel? (optional)</label>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
              {CORE_FEEL.map((c) => (
                <button
                  key={c.value} type="button"
                  className={`check-row ${core === c.value ? 'active' : ''}`}
                  onClick={() => setCore(core === c.value ? '' : c.value)}
                >
                  <span style={{ flex: 1 }}>{c.label}</span>
                  {core === c.value && <Check size={14} />}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="label">Body position? (optional)</label>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
              {POSTURES.map((p) => (
                <button
                  key={p.value} type="button"
                  className={`check-row ${posture === p.value ? 'active' : ''}`}
                  onClick={() => setPosture(posture === p.value ? '' : p.value)}
                >
                  <span style={{ flex: 1 }}>{p.label}</span>
                  {posture === p.value && <Check size={14} />}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="label">Tape trouble? (optional)</label>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
              {TAPE_STATES.map((t) => (
                <button
                  key={t.value} type="button"
                  className={`check-row ${tapes === t.value ? 'active' : ''}`}
                  onClick={() => setTapes(tapes === t.value ? '' : t.value)}
                >
                  <span style={{ flex: 1 }}>{t.label}</span>
                  {tapes === t.value && <Check size={14} />}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="label">Note (optional)</label>
            <input
              className="input"
              placeholder="e.g. after a big drink, woke up wet…"
              value={note}
              onChange={(e) => setNote(e.target.value)}
            />
          </div>

          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            <button
              className="btn btn-primary"
              onClick={addOrUpdate}
              disabled={!amount}
              style={{ flex: '1 1 auto' }}
            >
              <Droplets size={15} /> {editingId ? 'Update wetting' : 'Add wetting'}
            </button>
            {editingId && (
              <button className="btn btn-ghost" onClick={resetSubForm}>
                Cancel edit
              </button>
            )}
          </div>
        </div>
      </div>
    </Modal>
  );
}
