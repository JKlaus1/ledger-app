// Constants and utility functions

export const TYPES = [
  { value: 'brief',   label: 'Tab brief',     short: 'Brief'   },
  { value: 'pullup',  label: 'Pull-up',       short: 'Pull-up' },
  { value: 'pad',     label: 'Pad / liner',   short: 'Pad'     },
  { value: 'booster', label: 'Booster pad',   short: 'Booster' },
];

export const ABSORBENCY = [
  { value: 'light',     label: 'Light',     order: 1 },
  { value: 'moderate',  label: 'Moderate',  order: 2 },
  { value: 'heavy',     label: 'Heavy',     order: 3 },
  { value: 'overnight', label: 'Overnight / Maximum', order: 4 },
];

export const SIZES = ['XS', 'S', 'M', 'L', 'XL', '2XL', '3XL'];

export const PERFORMANCE = [
  { value: 'dry',  label: 'Stayed dry / minimal use' },
  { value: 'used', label: 'Used as expected' },
  { value: 'leak', label: 'Leaked' },
];

export const COLORS = [
  { name: 'Sage',  hex: '#A8B89E' },
  { name: 'Sand',  hex: '#D4C19E' },
  { name: 'Slate', hex: '#8A95A0' },
  { name: 'Plum',  hex: '#9C7891' },
  { name: 'Rose',  hex: '#C99B96' },
  { name: 'Sky',   hex: '#9DB4C5' },
  { name: 'Olive', hex: '#9A9760' },
  { name: 'Rust',  hex: '#B8806A' },
  { name: 'Cream', hex: '#E8DCC0' },
];

export const LOCATION_ICONS = [
  'home', 'closet', 'dresser', 'truck', 'car', 'bag',
  'briefcase', 'building', 'gym', 'bed', 'box', 'star',
];

export const uid = () =>
  Math.random().toString(36).slice(2, 9) + Date.now().toString(36).slice(-4);

export const formatDate = (ts, opts = {}) => {
  const d = new Date(ts);
  return d.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: opts.year ? 'numeric' : undefined,
  });
};

export const formatTime = (ts) => {
  const d = new Date(ts);
  return d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
};

export const dayKey = (ts) => {
  const d = new Date(ts);
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
};

export const isToday = (ts) => dayKey(ts) === dayKey(Date.now());

// datetime-local input needs YYYY-MM-DDTHH:MM in local time
export const toLocalInputValue = (ts) => {
  const d = new Date(ts);
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

export const fromLocalInputValue = (s) => new Date(s).getTime();

export const guessPeriod = (ts) => {
  const h = new Date(ts).getHours();
  return (h >= 21 || h < 7) ? 'night' : 'day';
};

export const productDisplayName = (p, opts = {}) => {
  if (!p) return 'Unknown';
  let base;
  if (p.brand && p.name) base = `${p.brand} ${p.name}`;
  else base = p.brand || p.name || 'Untitled';
  // Append the color / print descriptor if present (part of the product identity)
  if (opts.withPrint !== false && p.print && p.print.trim()) {
    base += ` · ${p.print.trim()}`;
  }
  return base;
};

// Sum stock across all locations for a product
export const totalStock = (product) => {
  if (!product?.stock) return 0;
  return Object.values(product.stock).reduce((s, n) => s + (Number(n) || 0), 0);
};

// Get stock at a specific location
export const stockAt = (product, locationId) => {
  if (!product?.stock || !locationId) return 0;
  return Number(product.stock[locationId]) || 0;
};

// === Wear-session helpers ===

// A log is an "active wear" (currently on) if it's a use with a put-on
// time but no take-off time yet.
export const isWornNow = (log) =>
  !!log && log.type !== 'move' && !!log.putOnAt && log.takenOffAt == null;

// Duration worn in ms, or null if not a completed wear session
export const wearDuration = (log) => {
  if (!log || !log.putOnAt || log.takenOffAt == null) return null;
  const d = log.takenOffAt - log.putOnAt;
  return d >= 0 ? d : null;
};

// Format a millisecond duration as "2d 3h", "7h 30m", "45m"
export const formatDuration = (ms) => {
  if (ms == null || ms < 0) return '';
  const totalMin = Math.round(ms / 60000);
  if (totalMin < 1) return 'under a minute';
  const d = Math.floor(totalMin / 1440);
  const h = Math.floor((totalMin % 1440) / 60);
  const m = totalMin % 60;
  const parts = [];
  if (d) parts.push(`${d}d`);
  if (h) parts.push(`${h}h`);
  if (m && !d) parts.push(`${m}m`); // drop minutes once we're past a day
  return parts.join(' ') || '0m';
};
