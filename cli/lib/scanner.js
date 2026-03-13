import fs from 'node:fs/promises';
import path from 'node:path';
import { ARTIFACT_CATEGORIES, MAX_DEPTH, getSkipDirs } from './constants.js';

/**
 * Build lookup structures from selected category IDs.
 */
function buildTargetMap(categoryIds) {
  const targetMap = new Map(); // dirName -> [categoryDef, ...]
  const allTargetDirs = new Set();

  for (const id of categoryIds) {
    const def = ARTIFACT_CATEGORIES[id];
    if (!def || def.isSystem) continue;

    for (const dirName of def.targetDirs) {
      allTargetDirs.add(dirName);
      if (!targetMap.has(dirName)) {
        targetMap.set(dirName, []);
      }
      targetMap.get(dirName).push(def);
    }
  }

  return { targetMap, allTargetDirs };
}

/**
 * Check if a directory name matches an artifact definition, including sibling file detection.
 */
async function matchDefinition(dirName, parentPath, targetMap) {
  const defs = targetMap.get(dirName);
  if (!defs) return null;

  for (const def of defs) {
    if (def.siblingFiles.length === 0) {
      return def;
    }
    for (const sibling of def.siblingFiles) {
      try {
        await fs.access(path.join(parentPath, sibling));
        return def;
      } catch {
        // sibling not found, try next
      }
    }
  }
  return null;
}

/**
 * Scan a directory tree for artifact directories matching selected categories.
 * Uses iterative DFS with fs.opendir for memory efficiency.
 *
 * @param {string} root - Root directory to scan
 * @param {string[]} categoryIds - Array of category IDs to scan for
 * @param {object} options
 * @param {function} [options.onProgress] - Called with current directory path
 * @param {function} [options.onFound] - Called with (path, categoryId, totalFound)
 * @param {boolean} [options.includeHidden] - Also scan hidden dirs not in skip list
 * @param {object} [options.signal] - Object with { cancelled: boolean } to abort
 * @returns {Promise<Array<{path: string, categoryId: string}>>}
 */
export async function scanForArtifacts(root, categoryIds, options = {}) {
  const { onProgress, onFound, includeHidden = false, signal } = options;
  const results = [];

  const { targetMap, allTargetDirs } = buildTargetMap(categoryIds);
  if (allTargetDirs.size === 0) return results;

  // Build skip dirs, removing any that are scan targets for selected categories
  const skipDirs = getSkipDirs(categoryIds);

  const stack = [[path.resolve(root), 0]];

  while (stack.length > 0) {
    if (signal?.cancelled) return results;

    const [dirPath, depth] = stack.pop();
    if (depth > MAX_DEPTH) continue;

    if (onProgress) {
      onProgress(dirPath);
    }

    let dir;
    try {
      dir = await fs.opendir(dirPath);
    } catch {
      continue;
    }

    try {
      for await (const entry of dir) {
        const name = entry.name;

        // Check if this is a target directory
        if (allTargetDirs.has(name)) {
          const fullPath = path.join(dirPath, name);
          try {
            const stat = await fs.lstat(fullPath);
            if (stat.isDirectory() && !stat.isSymbolicLink()) {
              const def = await matchDefinition(name, dirPath, targetMap);
              if (def) {
                results.push({ path: fullPath, categoryId: def.id });
                if (onFound) onFound(fullPath, def.id, results.length);
              }
            }
          } catch {
            // Can't stat -- skip
          }
          continue; // Don't recurse into matched dirs
        }

        if (!entry.isDirectory()) continue;
        if (entry.isSymbolicLink()) continue;
        if (skipDirs.has(name)) continue;
        if (!includeHidden && name.startsWith('.') && !allTargetDirs.has(name)) continue;

        stack.push([path.join(dirPath, name), depth + 1]);
      }
    } catch {
      // Error reading directory entries
    }
  }

  return results;
}

/**
 * Check system-level artifact paths.
 * @param {string[]} categoryIds - Array of category IDs to check
 * @returns {Promise<Array<{path: string, categoryId: string}>>}
 */
export async function checkSystemArtifacts(categoryIds) {
  const results = [];

  for (const id of categoryIds) {
    const def = ARTIFACT_CATEGORIES[id];
    if (!def || !def.isSystem) continue;

    try {
      const stat = await fs.stat(def.systemPath);
      if (!stat.isDirectory()) continue;
    } catch {
      continue; // Path doesn't exist or not accessible
    }

    if (def.expandSubdirs) {
      try {
        const entries = await fs.readdir(def.systemPath, { withFileTypes: true });
        for (const entry of entries) {
          if (entry.isDirectory()) {
            results.push({
              path: path.join(def.systemPath, entry.name),
              categoryId: id,
            });
          }
        }
      } catch {
        // If we can't list subdirs, add the whole directory
        results.push({ path: def.systemPath, categoryId: id });
      }
    } else {
      results.push({ path: def.systemPath, categoryId: id });
    }
  }

  return results;
}
