import React, { useEffect } from 'react';
import { X, Check } from 'lucide-react';

export const Pill = ({ children, variant = 'default', style = {} }) => (
  <span className={`pill${variant !== 'default' ? ` pill-${variant}` : ''}`} style={style}>
    {children}
  </span>
);

export const Eyebrow = ({ children, style = {} }) => (
  <div className="eyebrow" style={{ marginBottom: 8, ...style }}>
    {children}
  </div>
);

export const SectionHeader = ({ number, title, action }) => (
  <div style={{ display: 'flex', alignItems: 'baseline', gap: 12, marginBottom: 16 }}>
    <span className="num" style={{ fontSize: 13, color: 'var(--ink-mute)', fontStyle: 'italic' }}>
      {number}
    </span>
    <span className="display" style={{ fontSize: 22, color: 'var(--ink)', flex: 1 }}>
      {title}
    </span>
    {action}
  </div>
);

export const Modal = ({ open, onClose, title, children, footer }) => {
  // Prevent body scroll while modal open
  useEffect(() => {
    if (open) {
      const original = document.body.style.overflow;
      document.body.style.overflow = 'hidden';
      return () => { document.body.style.overflow = original; };
    }
  }, [open]);

  if (!open) return null;
  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <div style={{
          display: 'flex', alignItems: 'center',
          padding: '18px 20px', borderBottom: '1px solid var(--line)',
          position: 'sticky', top: 0, background: 'var(--bg)', zIndex: 1,
        }}>
          <span className="display" style={{ fontSize: 20, flex: 1 }}>{title}</span>
          <button className="btn-icon" onClick={onClose} aria-label="Close">
            <X size={18} />
          </button>
        </div>
        <div style={{ padding: 20 }}>{children}</div>
        {footer && (
          <div style={{
            padding: '14px 20px', borderTop: '1px solid var(--line)',
            display: 'flex', gap: 10, justifyContent: 'flex-end',
            position: 'sticky', bottom: 0, background: 'var(--bg)',
            flexWrap: 'wrap',
          }}>
            {footer}
          </div>
        )}
      </div>
    </div>
  );
};

export const Toast = ({ message, onDone }) => {
  useEffect(() => {
    if (!message) return;
    const t = setTimeout(onDone, 2200);
    return () => clearTimeout(t);
  }, [message, onDone]);
  if (!message) return null;
  return (
    <div className="toast">
      <Check size={14} /> {message}
    </div>
  );
};

export const ConfirmDialog = ({
  open, title, body, onConfirm, onCancel,
  confirmLabel = 'Delete', danger = true,
}) => (
  <Modal
    open={open}
    onClose={onCancel}
    title={title}
    footer={
      <>
        <button className="btn btn-ghost" onClick={onCancel}>Cancel</button>
        <button
          className={`btn ${danger ? 'btn-danger' : 'btn-primary'}`}
          onClick={onConfirm}
        >
          {confirmLabel}
        </button>
      </>
    }
  >
    <p style={{ color: 'var(--ink-soft)', margin: 0 }}>{body}</p>
  </Modal>
);

/* ProductThumb — shows photo if present, otherwise color swatch.
   The `thumbs` prop is a map of productId -> data URL for photos
   loaded from IndexedDB at app start. */
export const ProductThumb = ({ product, thumbs, size = 14, style = {}, onClick }) => {
  if (!product) return null;
  const photo = thumbs?.[product.id];
  const cursor = onClick ? 'pointer' : undefined;

  if (photo) {
    return (
      <img
        src={photo}
        alt=""
        onClick={onClick}
        style={{
          width: size, height: size,
          objectFit: 'cover',
          borderRadius: Math.max(3, Math.round(size * 0.18)),
          flexShrink: 0,
          border: '1px solid rgba(0,0,0,0.08)',
          display: 'block',
          cursor,
          ...style,
        }}
      />
    );
  }
  return (
    <div
      onClick={onClick}
      style={{
        width: size, height: size,
        borderRadius: '50%',
        background: product.color || '#D4DDD3',
        border: '1px solid rgba(0,0,0,0.08)',
        flexShrink: 0,
        cursor,
        ...style,
      }}
    />
  );
};
