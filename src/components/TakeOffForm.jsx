import React, { useState, useEffect } from 'react';
import { Check, ArrowRight } from 'lucide-react';
import { Modal } from './Common';
import {
  PERFORMANCE, toLocalInputValue, fromLocalInputValue,
  productDisplayName, formatDuration,
} from '../lib/helpers';
import {
  CHANGE_REASONS, SKIN_STATES, ACTIVITY_LEVELS, CORE_CONDITIONS, TAPE_STATES,
  LEAK_ESCAPE, LEAK_SEVERITY, CLEANUP_METHODS,
} from '../lib/session';

// TakeOffForm — ends the active wear session. Records take-off time, how it
// performed, optional take-off detail, and (when it leaked) where/how badly it
// leaked, plus the cleanup/skin routine. A "then" choice lets the user go
// without or immediately put a fresh one on (change-out).
export default function TakeOffForm({
  open, onClose, onConfirm, entry, product, defaultThen,
}) {
  const [takenOffAt, setTakenOffAt] = useState(Date.now());
  const [performance, setPerformance] = useState('used');
  const [activity, setActivity] = useState('');
  const [core, setCore] = useState('');
  const [tapes, setTapes] = useState('');
  const [changeReason, setChangeReason] = useState('');
  const [skin, setSkin] = useState('');
  const [cream, setCream] = useState(false);
  const [creamProduct, setCreamProduct] = useState('');
  const [leakEscape, setLeakEscape] = useState('');
  const [leakSeverity, setLeakSeverity] = useState('');
  const [cleanup, setCleanup] = useState([]);
  const [notes, setNotes] = useState('');
  const [then, setThen] = useState('none'); // 'none' | 'replace'

  useEffect(() => {
    if (open) {
      setTakenOffAt(Date.now());
      setPerformance('used');
      setActivity('');
      setCore('');
      setTapes('');
      setChangeReason('');
      setSkin('');
      setCream(false);
      setCreamProduct('');
      setLeakEscape('');
      setLeakSeverity('');
      setCleanup([]);
      setNotes('');
      setThen(defaultThen === 'replace' ? 'replace' : 'none');
    }
  }, [open, defaultThen]);

  if (!open || !entry) return null;

  const putOnAt = entry.putOnAt;
  const effectiveOff = Math.max(takenOffAt, putOnAt);
  const duration = effectiveOff - putOnAt;
  const isLeak = performance === 'leak';

  const toggleCleanup = (v) =>
    setCleanup((prev) => (prev.includes(v) ? prev.filter((x) => x !== v) : [...prev, v]));

  const submit = () => {
    const merged = entry.notes
      ? (notes.trim() ? `${entry.notes}\n${notes.trim()}` : entry.notes)
      : notes.trim();
    onConfirm(
      {
        ...entry,
        takenOffAt: effectiveOff,
        performance,
        activity: activity || null,
        core: core || null,
        tapes: tapes || null,
        changeReason: changeReason || null,
        skin: skin || null,
        cream: !!cream,
        creamProduct: cream ? (creamProduct.trim() || null) : null,
        leakEscape: isLeak ? (leakEscape || null) : null,
        leakSeverity: isLeak ? (leakSeverity || null) : null,
        cleanup: cleanup.length ? cleanup : null,
        notes: merged,
      },
      then === 'replace'
    );
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Take it off"
      footer={
        <>
          <button className="btn btn-ghost" onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" onClick={submit}>
            {then === 'replace' ? 'Take off & put on new' : 'Take off'}
          </button>
        </>
      }
    >
      <div style={{ display: 'grid', gap: 16 }}>
        <div className="card" style={{ padding: '12px 14px' }}>
          <div style={{ fontSize: 14 }}>
            {product ? productDisplayName(product) : 'This item'}
          </div>
          <div style={{ fontSize: 12, color: 'var(--ink-mute)', marginTop: 3 }}>
            Worn for {formatDuration(duration) || 'under a minute'}
          </div>
        </div>

        <div>
          <label className="label">When did you take it off?</label>
          <input
            className="input" type="datetime-local"
            value={toLocalInputValue(effectiveOff)}
            onChange={(e) => setTakenOffAt(fromLocalInputValue(e.target.value))}
          />
        </div>

        <div>
          <label className="label">How did it perform?</label>
          <div style={{ display: 'grid', gap: 8 }}>
            {PERFORMANCE.map((p) => (
              <button
                key={p.value} type="button"
                className={`check-row ${performance === p.value ? 'active' : ''}`}
                onClick={() => setPerformance(p.value)}
              >
                <span style={{ flex: 1 }}>{p.label}</span>
                {performance === p.value && <Check size={14} />}
              </button>
            ))}
          </div>
        </div>

        {isLeak && (
          <>
            <div>
              <label className="label">Where did it leak?</label>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
                {LEAK_ESCAPE.map((e) => (
                  <button
                    key={e.value} type="button"
                    className={`check-row ${leakEscape === e.value ? 'active' : ''}`}
                    onClick={() => setLeakEscape(leakEscape === e.value ? '' : e.value)}
                  >
                    <span style={{ flex: 1 }}>{e.label}</span>
                    {leakEscape === e.value && <Check size={14} />}
                  </button>
                ))}
              </div>
            </div>
            <div>
              <label className="label">How bad?</label>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
                {LEAK_SEVERITY.map((s) => (
                  <button
                    key={s.value} type="button"
                    className={`check-row ${leakSeverity === s.value ? 'active' : ''}`}
                    onClick={() => setLeakSeverity(leakSeverity === s.value ? '' : s.value)}
                  >
                    <span style={{ flex: 1 }}>{s.label}</span>
                    {leakSeverity === s.value && <Check size={14} />}
                  </button>
                ))}
              </div>
            </div>
          </>
        )}

        <div>
          <label className="label">How active were you? (optional)</label>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
            {ACTIVITY_LEVELS.map((a) => (
              <button
                key={a.value} type="button"
                className={`check-row ${activity === a.value ? 'active' : ''}`}
                onClick={() => setActivity(activity === a.value ? '' : a.value)}
              >
                <span style={{ flex: 1 }}>{a.label}</span>
                {activity === a.value && <Check size={14} />}
              </button>
            ))}
          </div>
        </div>

        <div>
          <label className="label">How did the padding hold up? (optional)</label>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
            {CORE_CONDITIONS.map((c) => (
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
          <label className="label">Any tape trouble? (optional)</label>
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
          <label className="label">Why the change? (optional)</label>
          <select
            className="select"
            value={changeReason}
            onChange={(e) => setChangeReason(e.target.value)}
          >
            <option value="">Not set</option>
            {CHANGE_REASONS.map((r) => (
              <option key={r.value} value={r.value}>{r.label}</option>
            ))}
          </select>
        </div>

        <div>
          <label className="label">Skin check (optional)</label>
          <div className="seg" style={{ width: '100%' }}>
            {SKIN_STATES.map((s) => (
              <button
                key={s.value}
                type="button" style={{ flex: 1 }}
                className={`seg-btn ${skin === s.value ? 'active' : ''}`}
                onClick={() => setSkin(skin === s.value ? '' : s.value)}
              >
                {s.label}
              </button>
            ))}
          </div>
        </div>

        <div>
          <label className="label">Cleanup (optional)</label>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
            {CLEANUP_METHODS.map((m) => (
              <button
                key={m.value} type="button"
                className={`check-row ${cleanup.includes(m.value) ? 'active' : ''}`}
                onClick={() => toggleCleanup(m.value)}
              >
                <span style={{ flex: 1 }}>{m.label}</span>
                {cleanup.includes(m.value) && <Check size={14} />}
              </button>
            ))}
          </div>
        </div>

        <div>
          <label className="label">Barrier cream applied?</label>
          <button
            type="button"
            className={`check-row ${cream ? 'active' : ''}`}
            onClick={() => setCream(!cream)}
          >
            <span style={{ flex: 1 }}>{cream ? 'Yes — applied' : 'No'}</span>
            {cream && <Check size={14} />}
          </button>
          {cream && (
            <input
              className="input"
              style={{ marginTop: 8 }}
              placeholder="Which cream? (optional) — e.g. Desitin Max"
              value={creamProduct}
              onChange={(e) => setCreamProduct(e.target.value)}
            />
          )}
        </div>

        <div>
          <label className="label">Notes (optional)</label>
          <textarea
            className="textarea"
            placeholder="Time worn, comfort, leaks…"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
          />
        </div>

        <div>
          <label className="label">Then what?</label>
          <div className="seg" style={{ width: '100%' }}>
            <button
              type="button" style={{ flex: 1 }}
              className={`seg-btn ${then === 'none' ? 'active' : ''}`}
              onClick={() => setThen('none')}
            >
              Go without
            </button>
            <button
              type="button" style={{ flex: 1 }}
              className={`seg-btn ${then === 'replace' ? 'active' : ''}`}
              onClick={() => setThen('replace')}
            >
              Put on a new one <ArrowRight size={13} />
            </button>
          </div>
        </div>
      </div>
    </Modal>
  );
}
