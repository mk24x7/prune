#!/usr/bin/env node

import path from 'node:path';
import os from 'node:os';
import chalk from 'chalk';
import ora from 'ora';
import { DEFAULT_ROOT } from '../lib/constants.js';
import { scanForNodeModules } from '../lib/scanner.js';
import { calculateSizes } from '../lib/sizer.js';
import {
  formatSizeRaw,
  promptSelection,
  promptConfirm,
  printSummary,
} from '../lib/ui.js';
import { deleteDirectories } from '../lib/deleter.js';

// -- Parse CLI arguments --

const args = process.argv.slice(2);
const flags = new Set(args.filter((a) => a.startsWith('--')));
const positional = args.filter((a) => !a.startsWith('--'));

if (flags.has('--help') || flags.has('-h')) {
  console.log(`
${chalk.bold('node-cleanup')} - Find and remove node_modules directories

${chalk.dim('Usage:')}
  node-cleanup [path] [options]

${chalk.dim('Options:')}
  [path]             Directory to scan (default: home directory)
  --dry-run          Scan and display only, do not delete
  --include-hidden   Also scan hidden directories
  --help, -h         Show this help message

${chalk.dim('Examples:')}
  node-cleanup                    Scan home directory
  node-cleanup ~/projects         Scan specific directory
  node-cleanup --dry-run          Preview without deleting
`);
  process.exit(0);
}

const dryRun = flags.has('--dry-run');
const includeHidden = flags.has('--include-hidden');
const root = positional[0] ? path.resolve(positional[0]) : DEFAULT_ROOT;

// -- Ensure clean exit on Ctrl+C --

process.on('SIGINT', () => {
  // Restore cursor in case ora hid it
  process.stdout.write('\x1B[?25h');
  console.log('\n');
  process.exit(0);
});

// -- Main --

async function main() {
  const home = os.homedir();
  const displayRoot = root.startsWith(home)
    ? '~' + root.slice(home.length)
    : root;

  console.log(`\n${chalk.bold('node-cleanup')} - Find and remove node_modules directories\n`);

  if (dryRun) {
    console.log(chalk.dim('(dry-run mode -- no directories will be deleted)\n'));
  }

  // Phase 1: Scan for node_modules
  const spinner = ora({
    text: `Scanning ${chalk.cyan(displayRoot)} for node_modules...`,
    spinner: 'dots',
  }).start();

  let lastUpdate = 0;
  const paths = await scanForNodeModules(root, {
    includeHidden,
    onProgress: (dir) => {
      // Throttle spinner updates to avoid flickering
      const now = Date.now();
      if (now - lastUpdate > 100) {
        const shortDir = dir.startsWith(home) ? '~' + dir.slice(home.length) : dir;
        // Truncate long paths
        const maxLen = process.stdout.columns ? process.stdout.columns - 20 : 60;
        const display = shortDir.length > maxLen
          ? '...' + shortDir.slice(shortDir.length - maxLen + 3)
          : shortDir;
        spinner.text = `Scanning ${chalk.dim(display)}`;
        lastUpdate = now;
      }
    },
  });

  if (paths.length === 0) {
    spinner.succeed('No node_modules directories found.');
    process.exit(0);
  }

  spinner.text = `Found ${paths.length} node_modules director${paths.length === 1 ? 'y' : 'ies'}. Calculating sizes...`;

  // Phase 2: Calculate sizes
  const entries = await calculateSizes(paths, {
    onProgress: (completed, total) => {
      spinner.text = `Calculating sizes... (${completed}/${total})`;
    },
  });

  const totalBytes = entries.reduce((sum, e) => sum + e.sizeBytes, 0);
  spinner.succeed(
    `Found ${chalk.bold(entries.length)} node_modules director${entries.length === 1 ? 'y' : 'ies'} (total: ${chalk.bold(formatSizeRaw(totalBytes))})\n`
  );

  // Phase 3: Interactive selection
  const selected = await promptSelection(entries);

  if (selected.length === 0) {
    console.log(chalk.dim('\nNothing selected.'));
    process.exit(0);
  }

  // Phase 4: Confirm
  const confirmed = await promptConfirm(selected, entries);

  if (!confirmed) {
    console.log(chalk.dim('\nCancelled.'));
    process.exit(0);
  }

  // Phase 5: Delete
  if (dryRun) {
    console.log(chalk.dim('\n(dry-run mode -- skipping deletion)'));
    process.exit(0);
  }

  console.log('');
  const deleteSpinner = ora({ spinner: 'dots' }).start();

  const entryMap = new Map(entries.map((e) => [e.path, e]));
  const { deleted, failed } = await deleteDirectories(selected, {
    onProgress: (current, total, dirPath) => {
      const entry = entryMap.get(dirPath);
      const name = entry?.projectName || path.basename(path.dirname(dirPath));
      const size = entry ? formatSizeRaw(entry.sizeBytes) : '';
      deleteSpinner.text = `Deleting [${current}/${total}] ${name} (${size})...`;
    },
  });

  deleteSpinner.stop();

  // Phase 6: Summary
  printSummary(deleted, failed, entries);
  console.log('');
}

main().catch((err) => {
  // Handle user cancellation (Ctrl+C during inquirer prompts)
  if (err.name === 'ExitPromptError') {
    process.stdout.write('\x1B[?25h');
    console.log(chalk.dim('\nCancelled.'));
    process.exit(0);
  }
  console.error(chalk.red('Error:'), err.message);
  process.exit(1);
});
