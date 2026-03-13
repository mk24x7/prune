import checkbox from '@inquirer/checkbox';
import confirm from '@inquirer/confirm';
import chalk from 'chalk';
import os from 'node:os';
import { ARTIFACT_CATEGORIES } from './constants.js';

const HOME = os.homedir();

/**
 * Format bytes into a human-readable string with color coding.
 * Red for >500MB, yellow for >100MB, green otherwise.
 */
export function formatSize(bytes) {
  let value, unit;

  if (bytes >= 1024 * 1024 * 1024) {
    value = (bytes / (1024 * 1024 * 1024)).toFixed(1);
    unit = 'GB';
  } else if (bytes >= 1024 * 1024) {
    value = (bytes / (1024 * 1024)).toFixed(1);
    unit = 'MB';
  } else {
    value = (bytes / 1024).toFixed(1);
    unit = 'KB';
  }

  const text = `${value} ${unit}`;

  if (bytes > 500 * 1024 * 1024) return chalk.red(text);
  if (bytes > 100 * 1024 * 1024) return chalk.yellow(text);
  return chalk.green(text);
}

/**
 * Format a raw byte count without color (for summaries).
 */
export function formatSizeRaw(bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
  } else if (bytes >= 1024 * 1024) {
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  } else {
    return `${(bytes / 1024).toFixed(1)} KB`;
  }
}

/**
 * Format a date as a relative time string.
 */
export function formatAge(date) {
  const now = Date.now();
  const diffMs = now - date.getTime();
  const diffMins = Math.floor(diffMs / (1000 * 60));
  const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
  const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));
  const diffWeeks = Math.floor(diffDays / 7);
  const diffMonths = Math.floor(diffDays / 30);
  const diffYears = Math.floor(diffDays / 365);

  if (diffYears > 0) return `${diffYears} year${diffYears > 1 ? 's' : ''} ago`;
  if (diffMonths > 0) return `${diffMonths} month${diffMonths > 1 ? 's' : ''} ago`;
  if (diffWeeks > 0) return `${diffWeeks} week${diffWeeks > 1 ? 's' : ''} ago`;
  if (diffDays > 0) return `${diffDays} day${diffDays > 1 ? 's' : ''} ago`;
  if (diffHours > 0) return `${diffHours} hour${diffHours > 1 ? 's' : ''} ago`;
  if (diffMins > 0) return `${diffMins} minute${diffMins > 1 ? 's' : ''} ago`;
  return 'just now';
}

/**
 * Shorten a path by replacing the home directory with ~.
 */
function shortenPath(fullPath) {
  if (fullPath.startsWith(HOME)) {
    return '~' + fullPath.slice(HOME.length);
  }
  return fullPath;
}

/**
 * Get a colored category label.
 */
function categoryLabel(categoryId) {
  const def = ARTIFACT_CATEGORIES[categoryId];
  const name = def ? def.name : categoryId;

  const colors = {
    node: chalk.green,
    swiftpm: chalk.hex('#F05138'),
    cocoapods: chalk.red,
    rust: chalk.hex('#DEA584'),
    pythonvenv: chalk.yellow,
    pycache: chalk.yellow,
    gradle: chalk.cyan,
    gradlecache: chalk.cyan,
    'xcode-derived': chalk.blue,
    'xcode-archives': chalk.blue,
    'xcode-device-support': chalk.blue,
    'xcode-cache': chalk.blue,
    'gradle-global': chalk.cyan,
    'homebrew-cache': chalk.magenta,
  };

  const colorFn = colors[categoryId] || chalk.white;
  return colorFn(`[${name}]`);
}

/**
 * Prompt the user to select categories to scan.
 */
export async function promptCategories() {
  const projectCats = Object.values(ARTIFACT_CATEGORIES).filter((c) => !c.isSystem);
  const systemCats = Object.values(ARTIFACT_CATEGORIES).filter((c) => c.isSystem);

  const choices = [
    { name: chalk.dim('--- Project Artifacts ---'), value: '__header_project__', disabled: '' },
    ...projectCats.map((c) => ({ name: c.name, value: c.id, checked: true })),
    { name: chalk.dim('--- System Caches ---'), value: '__header_system__', disabled: '' },
    ...systemCats.map((c) => ({ name: c.name, value: c.id, checked: true })),
  ];

  const selected = await checkbox({
    message: 'Select artifact types to scan (space=toggle, a=all, enter=confirm)',
    choices,
    pageSize: 20,
    loop: false,
  });

  return selected.filter((s) => !s.startsWith('__header'));
}

/**
 * Prompt the user to select artifact directories for deletion.
 */
export async function promptSelection(entries) {
  const choices = entries.map((entry) => {
    const size = formatSize(entry.sizeBytes);
    const age = chalk.dim(formatAge(entry.lastModified));
    const shortPath = chalk.dim(shortenPath(entry.path));
    const catLabel = categoryLabel(entry.categoryId);

    return {
      name: `${catLabel} ${entry.projectName} (${size}) - ${age}\n    ${shortPath}`,
      value: entry.path,
    };
  });

  const selected = await checkbox({
    message: 'Select items to delete (space=toggle, a=all, enter=confirm)',
    choices,
    pageSize: 15,
    loop: false,
  });

  return selected;
}

/**
 * Prompt the user to confirm deletion.
 */
export async function promptConfirm(selectedPaths, entries) {
  const entryMap = new Map(entries.map((e) => [e.path, e]));
  const totalBytes = selectedPaths.reduce(
    (sum, p) => sum + (entryMap.get(p)?.sizeBytes || 0),
    0
  );

  // Show per-category breakdown
  const catBytes = {};
  for (const p of selectedPaths) {
    const entry = entryMap.get(p);
    if (entry) {
      const catId = entry.categoryId;
      catBytes[catId] = (catBytes[catId] || 0) + entry.sizeBytes;
    }
  }

  console.log(
    `\nSelected ${chalk.bold(selectedPaths.length)} item${selectedPaths.length === 1 ? '' : 's'} totaling ${chalk.bold.red(formatSizeRaw(totalBytes))}`
  );

  for (const [catId, bytes] of Object.entries(catBytes).sort((a, b) => b[1] - a[1])) {
    const def = ARTIFACT_CATEGORIES[catId];
    console.log(`  ${def ? def.name : catId}: ${formatSizeRaw(bytes)}`);
  }

  console.log('');

  return confirm({
    message: 'Delete these items?',
    default: false,
  });
}

/**
 * Print the final summary after deletion.
 */
export function printSummary(deleted, failed, entries) {
  const entryMap = new Map(entries.map((e) => [e.path, e]));
  const freedBytes = deleted.reduce(
    (sum, p) => sum + (entryMap.get(p)?.sizeBytes || 0),
    0
  );

  if (deleted.length > 0) {
    console.log(
      `\n${chalk.green('Done!')} Freed ${chalk.bold(formatSizeRaw(freedBytes))} across ${deleted.length} item${deleted.length === 1 ? '' : 's'}.`
    );

    // Per-category breakdown
    const catBytes = {};
    for (const p of deleted) {
      const entry = entryMap.get(p);
      if (entry) {
        const catId = entry.categoryId;
        catBytes[catId] = (catBytes[catId] || 0) + entry.sizeBytes;
      }
    }
    if (Object.keys(catBytes).length > 1) {
      for (const [catId, bytes] of Object.entries(catBytes).sort((a, b) => b[1] - a[1])) {
        const def = ARTIFACT_CATEGORIES[catId];
        console.log(`  ${def ? def.name : catId}: ${formatSizeRaw(bytes)}`);
      }
    }
  }

  if (failed.length > 0) {
    console.log(
      `\n${chalk.red('Failed')} to delete ${failed.length} item${failed.length === 1 ? '' : 's'}:`
    );
    for (const { path: p, error } of failed) {
      console.log(`  ${shortenPath(p)} - ${error}`);
    }
  }
}

/**
 * List available categories.
 */
export function listCategories() {
  console.log(chalk.bold('\nAvailable artifact categories:\n'));

  console.log(chalk.dim('  Project Artifacts (found by scanning):'));
  for (const cat of Object.values(ARTIFACT_CATEGORIES).filter((c) => !c.isSystem)) {
    console.log(`    ${chalk.bold(cat.id.padEnd(14))} ${cat.name}`);
  }

  console.log(chalk.dim('\n  System Caches (fixed locations):'));
  for (const cat of Object.values(ARTIFACT_CATEGORIES).filter((c) => c.isSystem)) {
    console.log(`    ${chalk.bold(cat.id.padEnd(22))} ${cat.name}`);
  }

  console.log(chalk.dim('\n  Use: prune --categories node,rust,xcode-derived'));
  console.log(chalk.dim('  Or:  prune --all'));
  console.log('');
}
