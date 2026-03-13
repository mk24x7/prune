import fs from 'node:fs/promises';
import path from 'node:path';

/**
 * Delete node_modules directories sequentially with progress reporting.
 * Sequential to avoid I/O spikes from parallel large deletions.
 *
 * @param {string[]} paths - Absolute paths to delete
 * @param {object} options
 * @param {function} [options.onProgress] - Called with (current, total, path)
 * @returns {Promise<{deleted: string[], failed: Array<{path: string, error: string}>}>}
 */
export async function deleteDirectories(paths, options = {}) {
  const { onProgress } = options;
  const deleted = [];
  const failed = [];

  for (let i = 0; i < paths.length; i++) {
    const dirPath = paths[i];

    if (path.basename(dirPath) !== 'node_modules') {
      failed.push({ path: dirPath, error: 'Refusing to delete: path does not end in node_modules' });
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
