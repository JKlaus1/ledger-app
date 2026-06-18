import React, { useEffect, useState } from 'react';
import { X } from 'lucide-react';
import { getPhoto } from '../lib/storage';

/* Loads the full-size version of a product's photo from IndexedDB
   on demand and displays it as an overlay. Tap anywhere to dismiss.
   We don't preload full-size photos at app start to save memory;
   they're only fetched when actually viewed. */
export default function PhotoViewer({ productId, onClose }) {
  const [src, setSrc] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  useEffect(() => {
    if (!productId) return;
    let cancelled = false;
    setLoading(true);
    setError(false);

    getPhoto(productId)
      .then((photo) => {
        if (cancelled) return;
        if (photo?.full) {
          setSrc(photo.full);
        } else if (photo?.thumb) {
          // Fall back to thumbnail if no full version exists
          setSrc(photo.thumb);
        } else {
          setError(true);
        }
        setLoading(false);
      })
      .catch(() => {
        if (cancelled) return;
        setError(true);
        setLoading(false);
      });

    return () => { cancelled = true; };
  }, [productId]);

  // Close on escape key
  useEffect(() => {
    const handler = (e) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [onClose]);

  if (!productId) return null;

  return (
    <div className="photo-viewer" onClick={onClose}>
      <button
        className="photo-viewer-close"
        onClick={onClose}
        aria-label="Close"
      >
        <X size={20} />
      </button>
      {loading && (
        <div style={{ color: 'var(--bg)', fontStyle: 'italic', opacity: 0.7 }}>
          Loading…
        </div>
      )}
      {error && (
        <div style={{ color: 'var(--bg)', fontStyle: 'italic', opacity: 0.7 }}>
          Photo unavailable
        </div>
      )}
      {src && <img src={src} alt="Product" onClick={(e) => e.stopPropagation()} />}
    </div>
  );
}
