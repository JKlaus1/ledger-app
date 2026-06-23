// Fluid intake — its own kind of log (type: 'drink'): a free-standing,
// timestamped record of something you drank. Kept separate from wear sessions
// because intake isn't tied to a particular diaper; the value is correlating
// it against wetting timing/volume over time. Backward compatible by
// construction (a new log type older code simply ignores as "not a use").
//
//   { id, type: 'drink', timestamp, kind, size, oz, note, createdAt, updatedAt }
//
// `size` is a rough bucket (small/medium/large). `oz` is an optional exact
// amount — when present it wins over the bucket for volume estimates. The
// ounce value behind each bucket is user-adjustable and stored in kv under
// `drinkSizePresets`; DRINK_SIZES below only supplies the defaults.

export const DRINK_KINDS = [
  { value: 'water',   label: 'Water' },
  { value: 'coffee',  label: 'Coffee' },
  { value: 'tea',     label: 'Tea' },
  { value: 'soda',    label: 'Soda' },
  { value: 'juice',   label: 'Juice' },
  { value: 'alcohol', label: 'Alcohol' },
  { value: 'other',   label: 'Other' },
];

// Rough sizes with a default nominal ounce value, so intake can be totalled
// without asking for exact volumes every time. The oz here are defaults only —
// the live values come from the user's presets (see normalizeDrinkPresets).
export const DRINK_SIZES = [
  { value: 'small',  label: 'Small',  oz: 8,  order: 1 },
  { value: 'medium', label: 'Medium', oz: 16, order: 2 },
  { value: 'large',  label: 'Large',  oz: 24, order: 3 },
];

export const DEFAULT_DRINK_PRESETS = Object.fromEntries(
  DRINK_SIZES.map((s) => [s.value, s.oz])
);

export const drinkKindLabel = (v) => DRINK_KINDS.find((d) => d.value === v)?.label || 'Drink';
export const drinkSizeLabel = (v) => DRINK_SIZES.find((d) => d.value === v)?.label || '';
export const isDrink = (l) => !!l && l.type === 'drink';

// Coerce a raw kv value into a complete, sane {small,medium,large} preset map,
// keeping any valid positive numbers and filling the rest from defaults.
export const normalizeDrinkPresets = (raw) => {
  const out = { ...DEFAULT_DRINK_PRESETS };
  if (raw && typeof raw === 'object') {
    DRINK_SIZES.forEach((s) => {
      const n = Number(raw[s.value]);
      if (Number.isFinite(n) && n > 0) out[s.value] = n;
    });
  }
  return out;
};

// Ounces for a size bucket, honouring user presets and falling back to the
// built-in default when no preset is supplied.
export const drinkSizeOz = (v, presets = null) => {
  const p = presets && presets[v];
  if (Number.isFinite(Number(p)) && Number(p) > 0) return Number(p);
  return DRINK_SIZES.find((d) => d.value === v)?.oz || 0;
};

// Best volume estimate for a logged drink: the exact amount if recorded,
// otherwise the (preset-aware) bucket nominal.
export const drinkVolumeOz = (drink, presets = null) => {
  if (!drink) return 0;
  const exact = Number(drink.oz);
  if (Number.isFinite(exact) && exact > 0) return exact;
  return drinkSizeOz(drink.size, presets);
};
