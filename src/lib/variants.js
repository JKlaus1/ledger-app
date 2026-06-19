// Variant grouping for Ledger.
//
// Different colors / prints of the same diaper are separate product
// records (each carries its own stock, photo, and cost), but for the
// purposes of inventory display and — later — performance stats, they
// should be understood as variants of ONE product.
//
// How a product joins a group:
//   - explicit `product.groupId` wins when set
//       * a normal key string  -> joined to that group
//       * a "solo:..." key      -> deliberately standalone, never merges
//   - otherwise we derive a key from the normalized brand + model, so
//     same-brand/model items group automatically with no migration and
//     no manual tagging. Normalizing also collapses casing differences
//     (e.g. "InControl" vs "Incontrol") into a single group.

import { productDisplayName, totalStock } from './helpers';

const norm = (s) => (s || '').toLowerCase().replace(/\s+/g, ' ').trim();

// The effective grouping key for a product.
export const groupKeyOf = (p) => {
  if (!p) return '';
  const explicit = p.groupId == null ? '' : String(p.groupId).trim();
  if (explicit) return explicit;
  return 'name:' + norm(`${p.brand || ''} ${p.name || ''}`);
};

// Cluster products into groups.
// Returns: [{ key, products, rep, label, total, isMulti }]
//   rep    -> representative product (first variant, stable order)
//   label  -> brand + model, without the per-variant print
//   total  -> combined stock across all variants
//   isMulti-> true when the group holds more than one variant
export const groupProducts = (products, { sort = true } = {}) => {
  const map = new Map();
  for (const p of products) {
    const k = groupKeyOf(p);
    if (!map.has(k)) map.set(k, []);
    map.get(k).push(p);
  }

  let groups = [...map.entries()].map(([key, items]) => {
    const sorted = [...items].sort(
      (a, b) =>
        (a.print || '').localeCompare(b.print || '') ||
        productDisplayName(a).localeCompare(productDisplayName(b))
    );
    const rep = sorted[0];
    return {
      key,
      products: sorted,
      rep,
      label: productDisplayName(rep, { withPrint: false }),
      total: items.reduce((s, p) => s + totalStock(p), 0),
      isMulti: sorted.length > 1,
    };
  });

  if (sort) groups.sort((a, b) => a.label.localeCompare(b.label));
  return groups;
};

// Existing groups offered as "group with" choices in the product form.
// Excludes the product currently being edited.
// Returns: [{ key, label, count }]
export const groupOptions = (products, excludeId) =>
  groupProducts((products || []).filter((p) => p.id !== excludeId)).map((g) => ({
    key: g.key,
    label: g.label,
    count: g.products.length,
  }));
