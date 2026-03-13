import fs from 'node:fs/promises';
import path from 'node:path';

/**
 * Delete artifact directories sequentially with progress reporting.
 * Sequential to avoid I/O spikes from parallel large deletions.
 *
 * @param {string[]} paths - Absolute paths to delete
 * @param {object} options
 * @param {Set<string>} options.allowedNames - Allowed directory basenames (e.g. "node_modules", "Pods")
 * @param {Set<string>} options.allowedSystemPaths - Allowed full system paths
 * @param {function} [options.onProgress] - Called with (current, total, path)
 * @returns {Promise<{deleted: string[], failed: Array<{path: string, error: string}>}>}
 */
export async function deleteDirectories(paths, options = {}) {
  const { allowedNames = new Set(), allowedSystemPaths = new Set(), onProgress } = options;
  const deleted = [];
  const failed = [];

  for (let i = 0; i < paths.length; i++) {
    const dirPath = paths[i];
    const basename = path.basename(dirPath);

    const isAllowedByName = allowedNames.has(basename);
    const isAllowedByPath = allowedSystemPaths.has(dirPath);

    if (!isAllowedByName && !isAllowedByPath) {
      failed.push({
        path: dirPath,
        error: `Refusing to delete: '${basename}' is not a recognized artifact directory`,
      });
      continue;
    }

    if (onProgress) {
      onProgress(i + 1, paths.length, dirPath);
    }

    try {
      await fs.rm(dirPath, { recursive: true, force: true });
      deleted.push(dirPath);
    } catch (err) {
      failed.push({ path: dirPath, error: err.message || 'Unknown error' });
    }
  }

  return { deleted, failed };
}
