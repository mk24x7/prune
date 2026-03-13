import checkbox from '@inquirer/checkbox';
import confirm from '@inquirer/confirm';
import chalk from 'chalk';
import os from 'node:os';

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
 * Format a date as a relative time string (e.g., "3 days ago", "2 months ago").
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
 * Prompt the user to select node_modules directories for deletion.
 *
 * @param {Array<{path: string, sizeBytes: number, projectName: string, lastModified: Date}>} entries
 * @returns {Promise<string[]>} - Array of selected paths
 */
export async function promptSelection(entries) {
  const choices = entries.map((entry) => {
    const size = formatSize(entry.sizeBytes);
    const age = chalk.dim(formatAge(entry.lastModified));
    const shortPath = chalk.dim(shortenPath(entry.path));

    return {
      name: `${entry.projectName} (${size}) - ${age}\n    ${shortPath}`,
      value: entry.path,
    };
  });

  const selected = await checkbox({
    message: 'Select directories to delete (space=toggle, a=all, enter=confirm)',
    choices,
    pageSize: 15,
    loop: false,
  });

  return selected;
}

/**
 * Prompt the user to confirm deletion.
 *
 * @param {string[]} selectedPaths - Paths selected for deletion
 * @param {Array<{path: string, sizeBytes: number}>} entries - All entries (for size lookup)
 * @returns {Promise<boolean>}
 */
export async function promptConfirm(selectedPaths, entries) {
  const entryMap = new Map(entries.map((e) => [e.path, e]));
  const totalBytes = selectedPaths.reduce(
    (sum, p) => sum + (entryMap.get(p)?.sizeBytes || 0),
    0
  );

  console.log(
    `\nSelected ${chalk.bold(selectedPaths.length)} director${selectedPaths.length === 1 ? 'y' : 'ies'} totaling ${chalk.bold.red(formatSizeRaw(totalBytes))}\n`
  );

  return confirm({
    message: 'Delete these directories?',
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
      `\n${chalk.green('Done!')} Freed ${chalk.bold(formatSizeRaw(freedBytes))} across ${deleted.length} director${deleted.length === 1 ? 'y' : 'ies'}.`
    );
  }

  if (failed.length > 0) {
    console.log(
      `\n${chalk.red('Failed')} to delete ${failed.length} director${failed.length === 1 ? 'y' : 'ies'}:`
    );
    for (const { path: p, error } of failed) {
      console.log(`  ${shortenPath(p)} - ${error}`);
    }
  }
}
