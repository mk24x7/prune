import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import fs from 'node:fs/promises';
import path from 'node:path';
import { DU_CONCURRENCY, ARTIFACT_CATEGORIES } from './constants.js';

const execFileP = promisify(execFile);

/**
 * Calculate disk size for multiple artifact directories in parallel.
 *
 * @param {Array<{path: string, categoryId: string}>} items - Artifacts to size
 * @param {object} options
 * @param {function} [options.onProgress] - Called with (completed, total)
 * @returns {Promise<Array<{path: string, sizeBytes: number, projectName: string, lastModified: Date, categoryId: string}>>}
 */
export async function calculateSizes(items, options = {}) {
  const { onProgress } = options;
  let completed = 0;

  const results = [];
  for (let i = 0; i < items.length; i += DU_CONCURRENCY) {
    const batch = items.slice(i, i + DU_CONCURRENCY);
    const batchResults = await Promise.all(
      batch.map(async (item) => {
        const result = await getDirectoryInfo(item.path, item.categoryId);
        completed++;
        if (onProgress) onProgress(completed, items.length);
        return result;
      })
    );
    results.push(...batchResults);
  }

  results.sort((a, b) => b.sizeBytes - a.sizeBytes);
  return results;
}

/**
 * Get size, project name, and last modified date for a single artifact directory.
 */
async function getDirectoryInfo(artifactPath, categoryId) {
  const [sizeBytes, projectName, lastModified] = await Promise.all([
    getDiskSize(artifactPath),
    getProjectName(artifactPath, categoryId),
    getLastModified(artifactPath),
  ]);

  return { path: artifactPath, sizeBytes, projectName, lastModified, categoryId };
}

/**
 * Get disk size in bytes using `du -sk`.
 */
async function getDiskSize(dirPath) {
  try {
    const { stdout } = await execFileP('du', ['-sk', dirPath], {
      timeout: 30000,
    });
    const sizeKB = parseInt(stdout.split('\t')[0], 10);
    return sizeKB * 1024;
  } catch {
    return 0;
  }
}

/**
 * Extract project name based on artifact category.
 */
async function getProjectName(artifactPath, categoryId) {
  const projectDir = path.dirname(artifactPath);
  const fallbackName = path.basename(projectDir);
  const def = ARTIFACT_CATEGORIES[categoryId];

  if (!def) return fallbackName;

  // System-level artifacts: use directory name or parse from path
  if (def.isSystem) {
    const dirName = path.basename(artifactPath);
    // Xcode DerivedData subdirs: "ProjectName-hashstring"
    if (categoryId === 'xcode-derived') {
      const dashIdx = dirName.lastIndexOf('-');
      if (dashIdx > 0) return dirName.substring(0, dashIdx);
    }
    return dirName;
  }

  // Project-level: read from project manifest file
  switch (categoryId) {
    case 'node':
      return readJsonName(path.join(projectDir, 'package.json'), fallbackName);

    case 'rust':
      return readTomlName(path.join(projectDir, 'Cargo.toml'), fallbackName);

    case 'swiftpm':
      return readSwiftPackageName(path.join(projectDir, 'Package.swift'), fallbackName);

    case 'gradle':
    case 'gradlecache':
      return readGradleProjectName(projectDir, fallbackName);

    default:
      return fallbackName;
  }
}

async function readJsonName(filePath, fallback) {
  try {
    const content = await fs.readFile(filePath, 'utf-8');
    const pkg = JSON.parse(content);
    return pkg.name || fallback;
  } catch {
    return fallback;
  }
}

async function readTomlName(filePath, fallback) {
  try {
    const content = await fs.readFile(filePath, 'utf-8');
    let inPackage = false;
    for (const line of content.split('\n')) {
      const trimmed = line.trim();
      if (trimmed === '[package]') {
        inPackage = true;
        continue;
      }
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        inPackage = false;
        continue;
      }
      if (inPackage && (trimmed.startsWith('name =') || trimmed.startsWith('name='))) {
        const eqIdx = trimmed.indexOf('=');
        if (eqIdx >= 0) {
          const value = trimmed.slice(eqIdx + 1).trim().replace(/^["']|["']$/g, '');
          if (value) return value;
        }
      }
    }
    return fallback;
  } catch {
    return fallback;
  }
}

async function readSwiftPackageName(filePath, fallback) {
  try {
    const content = await fs.readFile(filePath, 'utf-8');
    const match = content.match(/name:\s*"([^"]+)"/);
    return match ? match[1] : fallback;
  } catch {
    return fallback;
  }
}

async function readGradleProjectName(projectDir, fallback) {
  for (const filename of ['settings.gradle', 'settings.gradle.kts']) {
    try {
      const content = await fs.readFile(path.join(projectDir, filename), 'utf-8');
      const match = content.match(/rootProject\.name\s*=\s*['"]([^'"]+)['"]/);
      if (match) return match[1];
    } catch {
      // try next
    }
  }
  return fallback;
}

/**
 * Get the last modified time of the directory itself.
 */
async function getLastModified(dirPath) {
  try {
    const stat = await fs.stat(dirPath);
    return stat.mtime;
  } catch {
    return new Date();
  }
}
