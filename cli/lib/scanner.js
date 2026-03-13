import fs from 'node:fs/promises';
import path from 'node:path';
import { SKIP_DIRS, MAX_DEPTH } from './constants.js';

/**
 * Scan a directory tree for node_modules directories.
 * Uses iterative DFS with fs.opendir for memory efficiency.
 * Skips known non-project directories and does not recurse into found node_modules.
 *
 * @param {string} root - Root directory to scan
 * @param {object} options
 * @param {function} [options.onProgress] - Called with current directory path
 * @param {function} [options.onFound] - Called with (path, totalFound) when a node_modules is found
 * @param {boolean} [options.includeHidden] - Also scan hidden dirs not in SKIP_DIRS
 * @param {object} [options.signal] - Object with { cancelled: boolean } to abort the scan
 * @returns {Promise<string[]>} - Array of absolute paths to node_modules directories
 */
export async function scanForNodeModules(root, options = {}) {
  const { onProgress, onFound, includeHidden = false, signal } = options;
  const results = [];

  // Stack entries: [absolutePath, depth]
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
      // Permission denied, not a directory, etc. -- skip silently
      continue;
    }

    try {
      for await (const entry of dir) {
        const name = entry.name;

        // Found a node_modules -- record it but do NOT recurse into it
        if (name === 'node_modules') {
          const fullPath = path.join(dirPath, name);
          // Verify it's actually a directory (not a file or broken symlink)
          try {
            const stat = await fs.lstat(fullPath);
            if (stat.isDirectory() && !stat.isSymbolicLink()) {
              results.push(fullPath);
              if (onFound) onFound(fullPath, results.length);
            }
          } catch {
            // Can't stat -- skip
          }
          continue;
        }

        // Skip non-directories
        if (!entry.isDirectory()) continue;

        // Skip symlinks to avoid infinite loops and double-counting
        if (entry.isSymbolicLink()) continue;

        // Skip directories in the skip list
        if (SKIP_DIRS.has(name)) continue;

        // Skip hidden directories (starting with .) unless opted in
        if (!includeHidden && name.startsWith('.')) continue;

        stack.push([path.join(dirPath, name), depth + 1]);
      }
    } catch {
      // Error reading directory entries -- skip
    }
  }

  return results;
}
