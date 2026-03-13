#!/usr/bin/env node

import path from 'node:path';
import os from 'node:os';
import chalk from 'chalk';
import ora from 'ora';
import { DEFAULT_ROOT, ARTIFACT_CATEGORIES } from './lib/constants.js';
import { scanForArtifacts, checkSystemArtifacts } from './lib/scanner.js';
import { calculateSizes } from './lib/sizer.js';
import {
  formatSizeRaw,
  promptCategories,
  promptSelection,
  promptConfirm,
  printSummary,
  listCategories,
} from './lib/ui.js';
import { deleteDirectories } from './lib/deleter.js';

// -- Parse CLI arguments --

const args = process.argv.slice(2);

// Parse args into flags, positional args, and flag values
const flags = new Set();
const positional = [];
let categoriesArg = null;

for (let i = 0; i < args.length; i++) {
  const arg = args[i];
  if (arg === '-h') {
    flags.add('-h');
  } else if (arg.startsWith('--categories=')) {
    categoriesArg = arg.split('=').slice(1).join('=');
  } else if (arg === '--categories') {
    if (i + 1 >= args.length || args[i + 1].startsWith('--')) {
      console.error('Error: --categories requires a value (e.g. --categories node,rust)');
      process.exit(1);
    }
    categoriesArg = args[++i];
  } else if (arg.startsWith('--')) {
    flags.add(arg);
  } else {
    positional.push(arg);
  }
}

if (flags.has('--help') || flags.has('-h')) {
  console.log(`
${chalk.bold('prune')} - Find and remove developer build artifacts to free disk space

${chalk.dim('Usage:')}
  prune [path] [options]

${chalk.dim('Options:')}
  [path]                   Directory to scan (default: home directory)
  --categories <list>      Comma-separated category IDs (e.g. node,rust,xcode-derived)
  --all                    Scan all artifact categories
  --list-categories        Show available categories
  --dry-run                Scan and display only, do not delete
  --include-hidden         Also scan hidden directories
  --help, -h               Show this help message

${chalk.dim('Examples:')}
  prune                              Interactive category selection
  prune ~/projects                   Scan specific directory
  prune --categories node,rust       Scan Node.js and Rust artifacts
  prune --all                        Scan all categories
  prune --all --dry-run              Preview all without deleting
  prune --list-categories            Show available category IDs
`);
  process.exit(0);
}

if (flags.has('--list-categories')) {
  listCategories();
  process.exit(0);
}

const dryRun = flags.has('--dry-run');
const includeHidden = flags.has('--include-hidden');
const scanAll = flags.has('--all');
const root = positional[0] ? path.resolve(positional[0]) : DEFAULT_ROOT;

// -- Ensure clean exit on Ctrl+C --

process.on('SIGINT', () => {
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

  console.log(`\n${chalk.bold('prune')} - Find and remove developer build artifacts\n`);

  if (dryRun) {
    console.log(chalk.dim('(dry-run mode -- no items will be deleted)\n'));
  }

  // Determine categories to scan
  let categoryIds;
  if (scanAll) {
    categoryIds = Object.keys(ARTIFACT_CATEGORIES);
  } else if (categoriesArg) {
    categoryIds = categoriesArg.split(',').map((s) => s.trim());
    // Validate
    for (const id of categoryIds) {
      if (!ARTIFACT_CATEGORIES[id]) {
        console.error(chalk.red(`Unknown category: ${id}`));
        console.log(chalk.dim('Use --list-categories to see available categories'));
        process.exit(1);
      }
    }
  } else {
    // Interactive category selection
    categoryIds = await promptCategories();
    if (categoryIds.length === 0) {
      console.log(chalk.dim('\nNo categories selected.'));
      process.exit(0);
    }
    console.log('');
  }

  const projectCats = categoryIds.filter((id) => !ARTIFACT_CATEGORIES[id]?.isSystem);
  const systemCats = categoryIds.filter((id) => ARTIFACT_CATEGORIES[id]?.isSystem);

  // Phase 1: Scan for artifacts
  const spinner = ora({
    text: `Scanning ${chalk.cyan(displayRoot)} for artifacts...`,
    spinner: 'dots',
  }).start();

  let allItems = [];

  // Scan project-level artifacts
  if (projectCats.length > 0) {
    let lastUpdate = 0;
    const projectItems = await scanForArtifacts(root, projectCats, {
      includeHidden,
      onProgress: (dir) => {
        const now = Date.now();
        if (now - lastUpdate > 100) {
          const shortDir = dir.startsWith(home) ? '~' + dir.slice(home.length) : dir;
          const maxLen = process.stdout.columns ? process.stdout.columns - 20 : 60;
          const display = shortDir.length > maxLen
            ? '...' + shortDir.slice(shortDir.length - maxLen + 3)
            : shortDir;
          spinner.text = `Scanning ${chalk.dim(display)}`;
          lastUpdate = now;
        }
      },
    });
    allItems.push(...projectItems);
  }

  // Check system-level artifacts
  if (systemCats.length > 0) {
    spinner.text = 'Checking system artifact locations...';
    const systemItems = await checkSystemArtifacts(systemCats);
    allItems.push(...systemItems);
  }

  if (allItems.length === 0) {
    spinner.succeed('No artifacts found.');
    process.exit(0);
  }

  spinner.text = `Found ${allItems.length} item${allItems.length === 1 ? '' : 's'}. Calculating sizes...`;

  // Phase 2: Calculate sizes
  const entries = await calculateSizes(allItems, {
    onProgress: (completed, total) => {
      spinner.text = `Calculating sizes... (${completed}/${total})`;
    },
  });

  const totalBytes = entries.reduce((sum, e) => sum + e.sizeBytes, 0);
  spinner.succeed(
    `Found ${chalk.bold(entries.length)} item${entries.length === 1 ? '' : 's'} (total: ${chalk.bold(formatSizeRaw(totalBytes))})\n`
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

  // Build allowed sets for safety
  const allowedNames = new Set();
  const allowedSystemPaths = new Set();
  for (const id of categoryIds) {
    const def = ARTIFACT_CATEGORIES[id];
    if (!def) continue;
    if (def.isSystem) {
      allowedSystemPaths.add(def.systemPath);
      // If expanded, allow subdirectories too
      if (def.expandSubdirs) {
        for (const entry of entries) {
          if (entry.categoryId === id) {
            allowedSystemPaths.add(entry.path);
          }
        }
      }
    } else if (def.targetDirs) {
      for (const d of def.targetDirs) {
        allowedNames.add(d);
      }
    }
  }

  const entryMap = new Map(entries.map((e) => [e.path, e]));
  const { deleted, failed } = await deleteDirectories(selected, {
    allowedNames,
    allowedSystemPaths,
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
  if (err.name === 'ExitPromptError') {
    process.stdout.write('\x1B[?25h');
    console.log(chalk.dim('\nCancelled.'));
    process.exit(0);
  }
  console.error(chalk.red('Error:'), err.message);
  process.exit(1);
});
