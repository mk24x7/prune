// Measure free space per volume before and after a deletion run.

import fs from 'node:fs/promises';
import path from 'node:path';

async function nearestExisting(p) {
  let cur = path.resolve(p);
  for (;;) {
    try {
      return { path: cur, stat: await fs.stat(cur) };
    } catch {
      const parent = path.dirname(cur);
      if (parent === cur) return null;
      cur = parent;
    }
  }
}

/**
 * Available bytes for every volume that holds one of `paths`. A path that no
 * longer exists is measured through its nearest existing ancestor, so the same
 * list can be passed before and after deleting.
 * @param {string[]} paths
 * @returns {Promise<Map<number, {path: string, availableBytes: number}>>} keyed by st_dev
 */
export async function snapshot(paths) {
  const volumes = new Map();
  for (const p of paths) {
    const hit = await nearestExisting(p);
    if (!hit || volumes.has(hit.stat.dev)) continue;
    try {
      const s = await fs.statfs(hit.path);
      volumes.set(hit.stat.dev, { path: hit.path, availableBytes: Number(s.bavail) * Number(s.bsize) });
    } catch {
      // statfs unsupported for this path; skip the volume
    }
  }
  return volumes;
}

/**
 * Sum of per-volume increases in available space, each clamped at 0.
 */
export function freed(before, after) {
  let total = 0;
  for (const [dev, b] of before) {
    const a = after.get(dev);
    if (!a) continue;
    total += Math.max(0, a.availableBytes - b.availableBytes);
  }
  return total;
}
