// Fluid intake — its own kind of log (type: 'drink'): a free-standing,
// timestamped record of something you drank. Kept separate from wear sessions
// because intake isn't tied to a particular diaper; the value is correlating
// it against wetting timing/volume over time. Backward compatible by
// construction (a new log type older code simply ignores as "not a use").
//
//   { id, type: 'drink', timestamp, kind, size, note, createdAt, updatedAt }

export const DRINK_KINDS = [
  { value: 'water',   label: 'Water' },
  { value: 'coffee',  label: 'Coffee' },
  { value: 'tea',     label: 'Tea' },
  { value: 'soda',    label: 'Soda' },
  { value: 'juice',   label: 'Juice' },
  { value: 'alcohol', label: 'Alcohol' },
  { value: 'other',   label: 'Other' },
];

// Rough sizes with a nominal ounce value, so intake can be totalled without
// asking for exact volumes every time.
export const DRINK_SIZES = [
  { value: 'small',  label: 'Small',  oz: 8,  order: 1 },
  { value: 'medium', label: 'Medium', oz: 16, order: 2 },
  { value: 'large',  label: 'Large',  oz: 24, order: 3 },
];

export const drinkKindLabel = (v) => DRINK_KINDS.find((d) => d.value === v)?.label || 'Drink';
export const drinkSizeLabel = (v) => DRINK_SIZES.find((d) => d.value === v)?.label || '';
export const drinkSizeOz = (v) => DRINK_SIZES.find((d) => d.value === v)?.oz || 0;
export const isDrink = (l) => !!l && l.type === 'drink';
