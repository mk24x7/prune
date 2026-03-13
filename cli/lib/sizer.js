import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import fs from 'node:fs/promises';
import path from 'node:path';
import { DU_CONCURRENCY } from './constants.js';

const execFileP = promisify(execFile);

/**
 * Calculate disk size for multiple node_modules directories in parallel.
 *
 * @param {string[]} paths - Absolute paths to node_modules directories
 * @param {object} options
 * @param {function} [options.onProgress] - Called with (completed, total)
 * @returns {Promise<Array<{path: string, sizeBytes: number, projectName: string, lastModified: Date}>>}
 */
export async function calculateSizes(paths, options = {}) {
  const { onProgress } = options;
  let completed = 0;

  // Process paths in batches to limit concurrency
  const results = [];
  for (let i = 0; i < paths.length; i += DU_CONCURRENCY) {
    const batch = paths.slice(i, i + DU_CONCURRENCY);
    const batchResults = await Promise.all(
      batch.map(async (nmPath) => {
        const result = await getDirectoryInfo(nmPath);
        completed++;
        if (onProgress) onProgress(completed, paths.length);
        return result;
      })
    );
    results.push(...batchResults);
  }

  // Sort by size descending
  results.sort((a, b) => b.sizeBytes - a.sizeBytes);

  return results;
}

/**
 * Get size, project name, and last modified date for a single node_modules directory.
 */
async function getDirectoryInfo(nmPath) {
  const [sizeBytes, projectName, lastModified] = await Promise.all([
    getDiskSize(nmPath),
    getProjectName(nmPath),
    getLastModified(nmPath),
  ]);

  return { path: nmPath, sizeBytes, projectName, lastModified };
}

/**
 * Get disk size in bytes using `du -sk`.
 * Uses execFile (not exec) so paths with spaces are handled safely.
 */
async function getDiskSize(dirPath) {
  try {
    const { stdout } = await execFileP('du', ['-sk', dirPath], {
      timeout: 30000,
    });
    // Output format: "12345\t/path/to/dir\n"
    const sizeKB = parseInt(stdout.split('\t')[0], 10);
    return sizeKB * 1024;
  } catch {
    return 0;
  }
}

/**
 * Extract project name from the parent directory's package.json,
 * falling back to the parent directory basename.
 */
async function getProjectName(nmPath) {
  const projectDir = path.dirname(nmPath);
  const fallbackName = path.basename(projectDir);

  try {
    const pkgPath = path.join(projectDir, 'package.json');
    const content = await fs.readFile(pkgPath, 'utf-8');
    const pkg = JSON.parse(content);
    return pkg.name || fallbackName;
  } catch {
    return fallbackName;
  }
}

/**
 * Get the last modified time of the node_modules directory itself.
 */
async function getLastModified(nmPath) {
  try {
    const stat = await fs.stat(nmPath);
    return stat.mtime;
  } catch {
    return new Date();
  }
}
