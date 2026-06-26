import React, { useState, useEffect } from 'react';
import { Check, X, Droplets, Droplet, Pencil, AlertTriangle, ShieldCheck, Toilet } from 'lucide-react';
import { Modal } from './Common';
import {
  uid, toLocalInputValue, fromLocalInputValue,
  productDisplayName, formatTime, formatDuration, wearDuration,
} from '../lib/helpers';
import {
  WETNESS, DIAPER_FEEL, CORE_FEEL, POSTURES, EVENT_KINDS, CONTROL_LEVELS, TOILET_WHAT,
  getWettings, wettingStats, eventKind,
  wetnessLabel, feelLabel, coreFeelLabel, postureLabel,
  kindLabel, controlLabel, toiletWhatLabel,
  capacityProfile, globalCapacity, capacityStatus,
} from '../lib/wetting';
import { TAPE_STATES, tapeLabel } from '../lib/session';

// One-line description of a single event for the logged-so-far list.
function describeEvent(w) {
  const k = eventKind(w);
  if (k === 'toilet') {
    const what = toiletWhatLabel(w.toiletWhat);
    return `Toilet use${what ? ` · ${what.toLowerCase()}` : ''}`;
  }
  const head = k === 'bm' ? 'BM' : wetnessLabel(w.amount);
  const bits = [];
  if (w.feel) bits.push(feelLabel(w.feel).toLowerCase());
  if (w.core) bits.push(`core ${coreFeelLabel(w.core).toLowerCase()}`);
  if (w.posture) bits.push(postureLabel(w.posture).toLowerCase());
  if (w.tapes) bits.push(`tapes ${tapeLabel(w.tapes).toLowerCase()}`);
  if (w.control) bits.push(controlLabel(w.control).toLowerCase());
  if (w.asleep) bits.push('asleep');
  return head + (bits.length ? ` · ${bits.join(' · ')}` : '');
}

// WettingSummary — compact, reusable read-out of a wear session's events.
export function WettingSummary({ log, compact = false, style = {} }) {
  const { count, peakFeel, byAmount, bmCount, toiletCount } = wettingStats(log);
  const extras = [];
  if (bmCount > 0) extras.push(`${bmCount} BM`);
  if (toiletCount > 0) extras.push(`${toiletCount} toilet`);

  if (count === 0 && extras.length === 0) {
    if (compact) return null;
    return (
      <div style={{ fontSize: 12, color: 'var(--ink-mute)', ...style }}>
        No events logged yet.
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
        color: 'var(--accent)', flexWrap: 'wrap', ...style,
      }}>
        <Droplet size={11} />
        {count} wetting{count !== 1 ? 's' : ''}
        {peakFeel && (
          <span style={{ color: 'var(--ink-mute)' }}>· {feelLabel(peakFeel).toLowerCase()}</span>
        )}
        {extras.length > 0 && (
          <span style={{ color: 'var(--ink-mute)' }}>· {extras.join(' · ')}</span>
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
      {extras.length > 0 && (
        <span style={{ fontSize: 12, color: 'var(--ink-mute)' }}>· {extras.join(' · ')}</span>
      )}
    </div>
  );
}

// CapacityMeter — how close this diaper's running load is to where it (or
// similar diapers) have historically leaked. Quiet when there's no basis yet.
function CapacityMeter({ load, status, isOn }) {
  if (status.level === 'none' || load <= 0) return null;

  const palette = {
    ok:    { bar: 'var(--primary)', fg: 'var(--ink-soft)', Icon: ShieldCheck },
    watch: { bar: '#C9985A',        fg: '#9A6A2E',         Icon: AlertTriangle },
    over:  { bar: 'var(--danger)',  fg: 'var(--danger)',   Icon: AlertTriangle },
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

// A small selectable grid of options.
function OptionGrid({ options, value, onPick, cols = 2 }) {
  return (
    <div style={{ display: 'grid', gridTemplateColumns: `repeat(${cols}, 1fr)`, gap: 8 }}>
      {options.map((o) => (
        <button
          key={o.value} type="button"
          className={`check-row ${value === o.value ? 'active' : ''}`}
          onClick={() => onPick(value === o.value ? '' : o.value)}
        >
          <span style={{ flex: 1 }}>{o.label}</span>
          {value === o.value && <Check size={14} />}
        </button>
      ))}
    </div>
  );
}

// WettingForm — add / edit / remove events on a single wear session.
export default function WettingForm({ open, onClose, entry, product, onSave, logs = [] }) {
  const [list, setList] = useState([]);
  const [editingId, setEditingId] = useState(null);
  const [kind, setKind] = useState('wet');
  const [at, setAt] = useState(Date.now());
  const [amount, setAmount] = useState('');
  const [feel, setFeel] = useState('');
  const [core, setCore] = useState('');
  const [tapes, setTapes] = useState('');
  const [posture, setPosture] = useState('');
  const [control, setControl] = useState('');
  const [asleep, setAsleep] = useState(false);
  const [toiletWhat, setToiletWhat] = useState('');
  const [note, setNote] = useState('');

  const defaultAt = () => {
    if (!entry) return Date.now();
    return entry.takenOffAt == null ? Date.now() : entry.takenOffAt;
  };

  const resetSubForm = () => {
    setEditingId(null);
    setKind('wet');
    setAt(defaultAt());
    setAmount('');
    setFeel('');
    setCore('');
    setTapes('');
    setPosture('');
    setControl('');
    setAsleep(false);
    setToiletWhat('');
    setNote('');
  };

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

  const canAdd =
    (kind === 'wet' && !!amount) ||
    (kind === 'bm') ||
    (kind === 'toilet' && !!toiletWhat);

  const addOrUpdate = () => {
    if (!canAdd) return;
    const base = { at, kind, note: note.trim() };
    let fields;
    if (kind === 'toilet') {
      fields = { ...base, toiletWhat: toiletWhat || null,
        amount: null, feel: null, core: null, tapes: null, posture: null, control: null, asleep: false };
    } else {
      fields = { ...base,
        amount: kind === 'wet' ? amount : null,
        feel: feel || null, core: core || null, tapes: tapes || null,
        posture: posture || null, control: control || null, toiletWhat: null, asleep: !!asleep };
    }
    if (editingId) {
      persist(list.map((w) => (w.id === editingId ? { ...w, ...fields } : w)));
    } else {
      persist([...list, { id: uid(), ...fields }]);
    }
    resetSubForm();
  };

  const editRow = (w) => {
    setEditingId(w.id);
    setKind(eventKind(w));
    setAt(w.at || Date.now());
    setAmount(w.amount || '');
    setFeel(w.feel || '');
    setCore(w.core || '');
    setTapes(w.tapes || '');
    setPosture(w.posture || '');
    setControl(w.control || '');
    setAsleep(!!w.asleep);
    setToiletWhat(w.toiletWhat || '');
    setNote(w.note || '');
  };

  const removeRow = (id) => {
    persist(list.filter((w) => w.id !== id));
    if (editingId === id) resetSubForm();
  };

  const stats = wettingStats({ ...entry, wettings: list });
  const dur = wearDuration(entry);

  // Live capacity read against this product's (and all products') history.
  const profile = capacityProfile(logs, entry.productId, entry.id);
  const gAll = globalCapacity(logs, entry.id);
  const fallback = { dryCeiling: gAll.dryCeiling };
  const capStatus = capacityStatus(stats.load, profile, fallback);
  const isOn = entry.takenOffAt == null;

  const isToilet = kind === 'toilet';
  const isBM = kind === 'bm';

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Diaper log"
      footer={<button className="btn btn-primary" onClick={onClose}>Done</button>}
    >
      <div style={{ display: 'grid', gap: 16 }}>
        {/* Session summary */}
        <div className="card" style={{ padding: '12px 14px' }}>
          <div style={{ fontSize: 14 }}>
            {product ? productDisplayName(product) : 'This diaper'}
          </div>
          <div style={{ fontSize: 12, color: 'var(--ink-mute)', marginTop: 3 }}>
            {entry.takenOffAt == null ? 'On now' : 'Previously worn'}
            {dur != null && ` · worn ${formatDuration(dur)}`}
            {` · ${stats.count} wetting${stats.count !== 1 ? 's' : ''}`}
            {stats.bmCount > 0 && ` · ${stats.bmCount} BM`}
            {stats.toiletCount > 0 && ` · ${stats.toiletCount} toilet`}
          </div>
          <CapacityMeter load={stats.load} status={capStatus} isOn={isOn} />
        </div>

        {/* Existing events */}
        {list.length > 0 && (
          <div>
            <label className="label">Logged so far</label>
            <div className="card" style={{ padding: 4 }}>
              {list.map((w) => {
                const k = eventKind(w);
                const Icon = k === 'toilet' ? Toilet : Droplet;
                const tint = k === 'toilet' ? 'var(--primary)' : 'var(--accent)';
                return (
                  <div
                    key={w.id}
                    className="row-divider"
                    style={{ padding: '10px 12px', display: 'flex', alignItems: 'center', gap: 10 }}
                  >
                    <Icon size={14} style={{ color: tint, flexShrink: 0 }} />
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontSize: 13 }}>{describeEvent(w)}</div>
                      <div style={{ fontSize: 11, color: 'var(--ink-mute)', marginTop: 1 }}>
                        {formatTime(w.at)}{w.note ? ` · ${w.note}` : ''}
                      </div>
                    </div>
                    <button className="btn-icon" onClick={() => editRow(w)} aria-label="Edit event">
                      <Pencil size={13} />
                    </button>
                    <button className="btn-icon" onClick={() => removeRow(w.id)} aria-label="Remove event">
                      <X size={14} />
                    </button>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        <hr className="hairline" />

        {/* Add / edit a single event */}
        <div style={{ display: 'grid', gap: 14 }}>
          <div className="eyebrow">{editingId ? 'Edit entry' : 'Add an entry'}</div>

          <div>
            <label className="label">What happened?</label>
            <OptionGrid options={EVENT_KINDS} value={kind} onPick={(v) => setKind(v || 'wet')} cols={3} />
          </div>

          <div>
            <label className="label">When</label>
            <input
              className="input" type="datetime-local"
              value={toLocalInputValue(at)}
              onChange={(e) => setAt(fromLocalInputValue(e.target.value))}
            />
          </div>

          {isToilet ? (
            <div>
              <label className="label">What did you do?</label>
              <OptionGrid options={TOILET_WHAT} value={toiletWhat} onPick={setToiletWhat} cols={3} />
              <p style={{ fontSize: 11, color: 'var(--ink-mute)', marginTop: 6, fontStyle: 'italic' }}>
                Toilet uses don't count toward the diaper's capacity.
              </p>
            </div>
          ) : (
            <>
              {!isBM && (
                <div>
                  <label className="label">How much?</label>
                  <OptionGrid options={WETNESS} value={amount} onPick={setAmount} cols={2} />
                </div>
              )}

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
                <label className="label">Was it…? (optional)</label>
                <OptionGrid options={CONTROL_LEVELS} value={control} onPick={setControl} cols={3} />
              </div>

              <div>
                <label className="label">Were you asleep?</label>
                <button
                  type="button"
                  className={`check-row ${asleep ? 'active' : ''}`}
                  onClick={() => setAsleep(!asleep)}
                >
                  <span style={{ flex: 1 }}>{asleep ? 'Yes — happened while asleep' : 'No — awake'}</span>
                  {asleep && <Check size={14} />}
                </button>
              </div>

              <div>
                <label className="label">Core feel? (optional)</label>
                <OptionGrid options={CORE_FEEL} value={core} onPick={setCore} cols={2} />
              </div>

              <div>
                <label className="label">Body position? (optional)</label>
                <OptionGrid options={POSTURES} value={posture} onPick={setPosture} cols={2} />
              </div>

              <div>
                <label className="label">Tape trouble? (optional)</label>
                <OptionGrid options={TAPE_STATES} value={tapes} onPick={setTapes} cols={2} />
              </div>
            </>
          )}

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
              disabled={!canAdd}
              style={{ flex: '1 1 auto' }}
            >
              <Droplets size={15} /> {editingId ? 'Update entry' : 'Add entry'}
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
