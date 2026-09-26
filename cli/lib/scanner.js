// Finds artifacts: a depth-first walk for project types, and fixed-path checks
// for system and files types. All rules come from the shared definitions.

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

export const DENIED_CAP = 50;

const isDeniedError = (err) => err && (err.code === 'EACCES' || err.code === 'EPERM');

function buildTargetMap(types) {
  const targetMap = new Map(); // dir name -> [type, ...] in definition order
  for (const t of types) {
    if (t.kind !== 'project') continue;
    for (const name of t.targets) {
      if (!targetMap.has(name)) targetMap.set(name, []);
      targetMap.get(name).push(t);
    }
  }
  return targetMap;
}

async function exists(p) {
  try {
    await fs.lstat(p);
    return true;
  } catch {
    return false;
  }
}

// First type (definition order) whose sibling requirement is met.
async function matchType(candidates, parentDir) {
  for (const t of candidates) {
    if (t.siblings.length === 0) return t;
    for (const sibling of t.siblings) {
      if (await exists(path.join(parentDir, sibling))) return t;
    }
  }
  return null;
}

/**
 * Walk `root` looking for project artifacts.
 *
 * Depth: root is depth 0, its children depth 1. Directories are listed while
 * their depth is below maxDepth, so an artifact can be found at depth <= maxDepth.
 *
 * @param {string} root
 * @param {object[]} types artifact types (non-project kinds are ignored)
 * @param {object} options
 * @param {object} options.scan scan rules from the definitions
 * @param {boolean} [options.includeHidden]
 * @param {string} [options.home]
 * @param {Iterable<string>} [options.extraSkipPaths] absolute paths never entered or matched
 * @param {number} [options.maxDepth]
 * @param {(dir: string, scannedCount: number) => void} [options.onProgress]
 * @param {(found: {path: string, typeId: string}, count: number) => void} [options.onFound]
 * @param {AbortSignal} [options.signal]
 */
export async function scanForArtifacts(root, types, options = {}) {
  const {
    scan,
    includeHidden = false,
    home = os.homedir(),
    extraSkipPaths = [],
    maxDepth = scan.maxDepth,
    onProgress,
    onFound,
    signal,
  } = options;

  const result = { found: [], deniedDirectories: [], deniedCount: 0, scannedCount: 0, cancelled: false };
  const targetMap = buildTargetMap(types);
  if (targetMap.size === 0) return result;

  const homeDir = path.resolve(home);
  const skipUnderHome = new Set(scan.skipUnderHome);
  const skipAnywhere = new Set(scan.skipAnywhere);
  const packageSuffixes = scan.skipPackageExtensions.map((e) => e.toLowerCase());
  const skipPaths = new Set([...extraSkipPaths].map((p) => path.resolve(p)));

  const noteDenied = (dir) => {
    result.deniedCount++;
    if (result.deniedDirectories.length < DENIED_CAP) result.deniedDirectories.push(dir);
  };

  const stack = [[path.resolve(root), 0]];
  while (stack.length > 0) {
    if (signal?.aborted) {
      result.cancelled = true;
      break;
    }
    const [dirPath, depth] = stack.pop();

    let dir;
    try {
      dir = await fs.opendir(dirPath);
    } catch (err) {
      if (isDeniedError(err)) noteDenied(dirPath);
      continue;
    }
    result.scannedCount++;
    onProgress?.(dirPath, result.scannedCount);

    const children = [];
    try {
      for await (const entry of dir) {
        const name = entry.name;
        const full = path.join(dirPath, name);
        if (skipPaths.has(full)) continue;

        const candidates = targetMap.get(name);
        if (candidates) {
          let st;
          try {
            st = await fs.lstat(full);
          } catch {
            continue;
          }
          if (!st.isDirectory() || st.isSymbolicLink()) continue;
          const type = await matchType(candidates, dirPath);
          if (type) {
            const found = { path: full, typeId: type.id };
            result.found.push(found);
            onFound?.(found, result.found.length);
            continue; // never recurse into a matched artifact
          }
          // No sibling match: fall through and treat it as an ordinary directory.
        } else {
          let isDir = entry.isDirectory();
          if (!isDir && !entry.isFile() && !entry.isSymbolicLink()) {
            // Unknown dirent type on some file systems: ask lstat.
            try {
              const st = await fs.lstat(full);
              isDir = st.isDirectory() && !st.isSymbolicLink();
            } catch {
              isDir = false;
            }
          }
          if (!isDir) continue;
        }

        if (skipAnywhere.has(name)) continue;
        if (dirPath === homeDir && skipUnderHome.has(name)) continue;
        const lower = name.toLowerCase();
        if (packageSuffixes.some((s) => lower.endsWith(s))) continue;
        if (!includeHidden && name.startsWith('.') && !candidates) continue;
        if (depth + 1 >= maxDepth) continue;
        children.push(full);
      }
    } catch (err) {
      if (isDeniedError(err)) noteDenied(dirPath);
    }
    // Reverse so the walk visits children in directory order.
    for (let i = children.length - 1; i >= 0; i--) stack.push([children[i], depth + 1]);
  }
  return result;
}

/**
 * Check fixed-path system and files types.
 * System: the resolved path must exist as a real directory (or regular file
 * when isFile); expand lists every real subdirectory, hidden ones included.
 * Files: regular files directly inside the path whose extension matches.
 * Symlinked paths are ignored because the verifier would refuse them.
 *
 * @returns {Promise<{found: {path: string, typeId: string}[], deniedDirectories: string[]}>}
 */
export async function checkSystemArtifacts(types, defs) {
  const found = [];
  const deniedDirectories = [];

  for (const t of types) {
    if (t.kind !== 'system' && t.kind !== 'files') continue;
    const resolved = defs.resolveSystemPath(t);

    let st;
    try {
      st = await fs.lstat(resolved);
    } catch (err) {
      if (isDeniedError(err)) deniedDirectories.push(resolved);
      continue;
    }
    if (st.isSymbolicLink()) continue;

    if (t.kind === 'system') {
      if (t.isFile) {
        if (st.isFile()) found.push({ path: resolved, typeId: t.id });
        continue;
      }
      if (!st.isDirectory()) continue;
      if (!t.expand) {
        found.push({ path: resolved, typeId: t.id });
        continue;
      }
      try {
        const entries = await fs.readdir(resolved, { withFileTypes: true });
        for (const e of entries.sort((a, b) => a.name.localeCompare(b.name))) {
          if (e.isDirectory() && !e.isSymbolicLink()) found.push({ path: path.join(resolved, e.name), typeId: t.id });
        }
      } catch (err) {
        if (isDeniedError(err)) deniedDirectories.push(resolved);
      }
      continue;
    }

    // files kind
    if (!st.isDirectory()) continue;
    const exts = new Set(t.extensions.map((e) => e.toLowerCase()));
    try {
      const entries = await fs.readdir(resolved, { withFileTypes: true });
      for (const e of entries.sort((a, b) => a.name.localeCompare(b.name))) {
        if (e.isFile() && exts.has(path.extname(e.name).toLowerCase())) {
          found.push({ path: path.join(resolved, e.name), typeId: t.id });
        }
      }
    } catch (err) {
      if (isDeniedError(err)) deniedDirectories.push(resolved);
    }
  }
  return { found, deniedDirectories };
}
