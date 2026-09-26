// Sizes found artifacts and works out their display name and last-modified time.

import { execFile } from 'node:child_process';
import { existsSync } from 'node:fs';
import fs from 'node:fs/promises';
import path from 'node:path';

export const DU_TIMEOUT_MS = 120_000;
export const DEFAULT_CONCURRENCY = 8;
const DU = existsSync('/usr/bin/du') ? '/usr/bin/du' : 'du';

function parseDuKilobytes(stdout) {
  if (typeof stdout !== 'string') return null;
  // Output is "<kb>\t<path>\n"; take the last non-empty line.
  const lines = stdout.split('\n').filter(Boolean);
  if (lines.length === 0) return null;
  const kb = Number.parseInt(lines[lines.length - 1].split('\t')[0], 10);
  return Number.isFinite(kb) && kb >= 0 ? kb : null;
}

/**
 * Disk usage of a directory via `du -sk`.
 * Non-zero exit (e.g. an unreadable subdirectory) still yields the partial
 * total that du printed. Timeout, kill or spawn failure yields null: unknown,
 * never 0.
 * @returns {Promise<number|null>} bytes, or null when unknown
 */
export function duBytes(dirPath, { timeout = DU_TIMEOUT_MS, duPath = DU } = {}) {
  return new Promise((resolve) => {
    execFile(duPath, ['-sk', dirPath], { timeout, maxBuffer: 1024 * 1024 }, (err, stdout) => {
      if (!err) {
        const kb = parseDuKilobytes(stdout);
        resolve(kb === null ? null : kb * 1024);
        return;
      }
      if (err.killed || err.signal || typeof err.code !== 'number') {
        resolve(null); // timed out, killed, or could not be spawned
        return;
      }
      const kb = parseDuKilobytes(err.stdout ?? stdout);
      resolve(kb === null ? null : kb * 1024);
    });
  });
}

// ---------------------------------------------------------------------------
// Project names

async function readText(file) {
  try {
    return await fs.readFile(file, 'utf8');
  } catch {
    return null;
  }
}

async function nameFromPackageJson(dir) {
  const text = await readText(path.join(dir, 'package.json'));
  if (text === null) return null;
  try {
    const pkg = JSON.parse(text);
    return typeof pkg?.name === 'string' && pkg.name.trim() ? pkg.name.trim() : null;
  } catch {
    return null;
  }
}

async function nameFromCargoToml(dir) {
  const text = await readText(path.join(dir, 'Cargo.toml'));
  if (text === null) return null;
  let section = '';
  for (const raw of text.split('\n')) {
    const line = raw.replace(/#.*$/, '').trim();
    const header = line.match(/^\[([^\]]+)\]$/);
    if (header) {
      section = header[1].trim();
      continue;
    }
    if (section === 'package' || section === 'workspace.package') {
      const m = line.match(/^name\s*=\s*["']([^"']+)["']$/);
      if (m) return m[1];
    }
  }
  return null;
}

async function nameFromPackageSwift(dir) {
  const text = await readText(path.join(dir, 'Package.swift'));
  if (text === null) return null;
  const m = text.match(/Package\s*\(\s*name\s*:\s*"([^"]+)"/) ?? text.match(/name\s*:\s*"([^"]+)"/);
  return m ? m[1] : null;
}

async function nameFromGradleSettings(dir) {
  for (const file of ['settings.gradle', 'settings.gradle.kts']) {
    const text = await readText(path.join(dir, file));
    if (text === null) continue;
    const m = text.match(/rootProject\.name\s*=\s*['"]([^'"]+)['"]/);
    if (m) return m[1];
  }
  return null;
}

function nameFromDerivedData(p) {
  // "MyApp-abcdefghijklmnop" -> "MyApp"
  const base = path.basename(p);
  const idx = base.lastIndexOf('-');
  return idx > 0 ? base.slice(0, idx) : base;
}

/**
 * Display name for an artifact according to its type's nameFrom strategy.
 * Manifest strategies read from the artifact's parent directory and fall back
 * to the parent directory name when the manifest is missing or malformed.
 */
export async function projectName(artifactPath, type) {
  const parent = path.dirname(artifactPath);
  const parentName = path.basename(parent);
  switch (type?.nameFrom) {
    case 'packageJson':
      return (await nameFromPackageJson(parent)) ?? parentName;
    case 'cargoToml':
      return (await nameFromCargoToml(parent)) ?? parentName;
    case 'packageSwift':
      return (await nameFromPackageSwift(parent)) ?? parentName;
    case 'gradleSettings':
      return (await nameFromGradleSettings(parent)) ?? parentName;
    case 'derivedData':
      return nameFromDerivedData(artifactPath);
    case 'dirname':
      return path.basename(artifactPath);
    case 'parentDirname':
      return parentName;
    default:
      return type?.kind === 'project' ? parentName : path.basename(artifactPath);
  }
}

/**
 * max(mtime of the path, mtimes of its direct children). For a file, its mtime.
 * @returns {Promise<Date|null>} null when the path cannot be read
 */
export async function lastModified(p) {
  let st;
  try {
    st = await fs.lstat(p);
  } catch {
    return null;
  }
  let latest = st.mtimeMs;
  if (st.isDirectory()) {
    let names = [];
    try {
      names = await fs.readdir(p);
    } catch {
      names = [];
    }
    for (const name of names) {
      try {
        const c = await fs.lstat(path.join(p, name));
        if (c.mtimeMs > latest) latest = c.mtimeMs;
      } catch {
        // vanished or unreadable; ignore
      }
    }
  }
  return new Date(latest);
}

/**
 * Size one found item.
 * @returns {Promise<{path, typeId, sizeBytes: number|null, sizeUnknown: boolean, projectName: string, lastModified: Date|null}>}
 */
export async function sizeEntry(item, type, { duPath } = {}) {
  let sizeBytes = null;
  let st = null;
  try {
    st = await fs.lstat(item.path);
  } catch {
    st = null;
  }
  if (st?.isFile()) {
    // Allocated bytes, like du; Docker.raw is sparse so st.size would overstate it.
    sizeBytes = typeof st.blocks === 'number' ? st.blocks * 512 : st.size;
  } else if (st?.isDirectory()) {
    sizeBytes = await duBytes(item.path, duPath ? { duPath } : {});
  }
  const [name, modified] = await Promise.all([projectName(item.path, type), lastModified(item.path)]);
  return {
    path: item.path,
    typeId: item.typeId,
    sizeBytes,
    sizeUnknown: sizeBytes === null,
    projectName: name,
    lastModified: modified,
  };
}

/**
 * Run `worker` over `items` with at most `limit` in flight. Results keep input order.
 */
export async function mapPool(items, limit, worker) {
  const results = new Array(items.length);
  let next = 0;
  const run = async () => {
    while (next < items.length) {
      const i = next++;
      results[i] = await worker(items[i], i);
    }
  };
  await Promise.all(Array.from({ length: Math.min(Math.max(1, limit), items.length) }, run));
  return results;
}

/**
 * Size all found items with a worker pool. Result is sorted by size, largest
 * first, unknown sizes last.
 * @param {{path: string, typeId: string}[]} items
 * @param {{defs: object, concurrency?: number, onProgress?: (done: number, total: number, entry: object) => void, duPath?: string}} options
 */
export async function calculateSizes(items, { defs, concurrency = DEFAULT_CONCURRENCY, onProgress, duPath } = {}) {
  let done = 0;
  const entries = await mapPool(items, concurrency, async (item) => {
    const entry = await sizeEntry(item, defs?.byId.get(item.typeId), { duPath });
    done++;
    onProgress?.(done, items.length, entry);
    return entry;
  });
  entries.sort((a, b) => {
    if (a.sizeUnknown !== b.sizeUnknown) return a.sizeUnknown ? 1 : -1;
    return (b.sizeBytes ?? 0) - (a.sizeBytes ?? 0);
  });
  return entries;
}
