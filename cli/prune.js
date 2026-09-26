#!/usr/bin/env node
// prune: find and remove regenerable developer artifacts on macOS.

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { loadDefinitions } from './lib/definitions.js';
import { parseCli, UsageError, HELP } from './lib/args.js';
import { createStyle, colorEnabled } from './lib/style.js';
import { createSpinner } from './lib/spinner.js';
import { scanForArtifacts, checkSystemArtifacts, DENIED_CAP } from './lib/scanner.js';
import { calculateSizes } from './lib/sizer.js';
import { deleteEntries } from './lib/deleter.js';
import { openDeletionLog } from './lib/log.js';
import { snapshot, freed } from './lib/diskspace.js';
import {
  formatBytes,
  shortenPath,
  plural,
  sumKnown,
  listCategories,
  printEntries,
  perTypeBreakdown,
  nonRegenerableWarning,
  totalsLine,
  promptCategories,
  promptSelection,
  promptYesNo,
} from './lib/ui.js';

const require = createRequire(import.meta.url);
const pkg = require('./package.json');

const EXIT = { ok: 0, error: 1, usage: 2, failed: 3 };
const DAY_MS = 24 * 60 * 60 * 1000;

// A closed pipe (prune --list-categories | head) is not an error.
for (const stream of [process.stdout, process.stderr]) {
  stream.on('error', (e) => {
    if (e.code === 'EPIPE') process.exit(process.exitCode ?? EXIT.ok);
    throw e;
  });
}

async function main(argv) {
  const home = os.homedir();
  const defs = loadDefinitions({ env: process.env, home });

  let opts;
  try {
    opts = parseCli(argv, { knownIds: defs.types.map((t) => t.id) });
  } catch (err) {
    if (err instanceof UsageError) {
      process.stderr.write(`prune: ${err.message}\nRun "prune --help" for usage.\n`);
      return EXIT.usage;
    }
    throw err;
  }

  if (opts.help) {
    process.stdout.write(HELP);
    return EXIT.ok;
  }
  if (opts.version) {
    process.stdout.write(`${pkg.version}\n`);
    return EXIT.ok;
  }

  // Human-readable output goes to stdout, or to stderr when stdout carries JSON.
  const humanStream = opts.json ? process.stderr : process.stdout;
  const out = (line = '') => humanStream.write(`${line}\n`);
  const err = (line = '') => process.stderr.write(`${line}\n`);
  const style = createStyle(colorEnabled({ noColor: opts.noColor, env: process.env, stream: humanStream }));

  if (opts.listCategories) {
    listCategories(defs, style, out);
    return EXIT.ok;
  }

  const dryRun = opts.dryRun || (opts.json && !opts.yes);
  const interactive = !opts.yes && !dryRun;
  if (interactive && !process.stdin.isTTY) {
    err('prune: stdin is not a terminal, so there is no way to confirm a deletion.');
    err('Pass --dry-run to only list, or --yes with --categories <list> or --all to delete without prompts.');
    return EXIT.usage;
  }

  const scanRoot = path.resolve(opts.root ?? home);
  try {
    const st = await fs.stat(scanRoot);
    if (!st.isDirectory()) throw Object.assign(new Error('not a directory'), { code: 'ENOTDIR' });
  } catch (e) {
    err(`prune: ${scanRoot} is not an existing directory (${e.code ?? e.message})`);
    return EXIT.usage;
  }

  out('');
  out(`${style.bold('prune')} ${style.dim(`v${pkg.version}`)} - find and remove regenerable developer artifacts`);
  if (dryRun) out(style.dim('(dry run: nothing will be deleted)'));
  out('');

  // Which types?
  let typeIds;
  if (opts.all) {
    typeIds = defs.types.map((t) => t.id);
    const warning = nonRegenerableWarning(typeIds, defs, style);
    if (warning.length) {
      warning.forEach((l) => out(l));
      out('');
    }
  } else if (opts.categories) {
    typeIds = opts.categories;
  } else if (interactive) {
    typeIds = await promptCategories(defs, style);
    out('');
    if (typeIds.length === 0) {
      out(style.dim('No categories selected.'));
      return EXIT.ok;
    }
  } else {
    typeIds = defs.defaultEnabledIds;
    out(style.dim(`Using the ${typeIds.length} default categories; pass --categories or --all to change.`));
    out('');
  }
  const types = typeIds.map((id) => defs.byId.get(id));
  const projectTypes = types.filter((t) => t.kind === 'project');
  const fixedTypes = types.filter((t) => t.kind !== 'project');

  const spinner = createSpinner({ enabled: Boolean(process.stderr.isTTY) && !opts.json });
  const abort = new AbortController();
  process.on('SIGINT', () => {
    abort.abort();
    spinner.stop();
    process.stderr.write('\x1b[?25h\n');
    process.exit(130);
  });

  // Scan.
  const displayRoot = shortenPath(scanRoot, home);
  spinner.start(`Scanning ${displayRoot} ...`);
  let lastTick = 0;
  const scan = await scanForArtifacts(scanRoot, projectTypes, {
    scan: defs.scan,
    includeHidden: opts.includeHidden,
    home,
    extraSkipPaths: defs.systemTypes.map((t) => defs.resolveSystemPath(t)),
    maxDepth: opts.maxDepth ?? defs.scan.maxDepth,
    signal: abort.signal,
    onProgress: (dir) => {
      const now = Date.now();
      if (now - lastTick > 100) {
        spinner.update(`Scanning ${shortenPath(dir, home)}`);
        lastTick = now;
      }
    },
  });
  spinner.update('Checking system cache locations ...');
  const fixed = await checkSystemArtifacts(fixedTypes, defs);
  const found = [...scan.found, ...fixed.found];
  const deniedCount = scan.deniedCount + fixed.deniedDirectories.length;
  const deniedPaths = [...scan.deniedDirectories, ...fixed.deniedDirectories].slice(0, DENIED_CAP);

  // Size.
  spinner.update(`Found ${plural(found.length, 'item')}. Calculating sizes ...`);
  let entries = await calculateSizes(found, {
    defs,
    onProgress: (done, total) => spinner.update(`Calculating sizes (${done}/${total}) ...`),
  });
  spinner.stop();

  if (deniedCount > 0) {
    err(style.yellow(`${plural(deniedCount, 'folder')} could not be read (permission denied):`));
    for (const p of deniedPaths.slice(0, 5)) err(`  ${shortenPath(p, home)}`);
    if (deniedCount > 5) err(`  ... and ${deniedCount - 5} more`);
    err(style.dim('Grant Full Disk Access to your terminal in System Settings > Privacy & Security to include them.'));
    err('');
  }

  // Filters.
  const filteredOut = [];
  if (opts.minAgeDays > 0) {
    const cutoff = Date.now() - opts.minAgeDays * DAY_MS;
    entries = entries.filter((e) => {
      const keep = e.lastModified !== null && e.lastModified.getTime() <= cutoff;
      if (!keep) filteredOut.push(e);
      return keep;
    });
  }
  if (opts.minSizeBytes > 0) {
    entries = entries.filter((e) => {
      const keep = !e.sizeUnknown && e.sizeBytes >= opts.minSizeBytes;
      if (!keep) filteredOut.push(e);
      return keep;
    });
  }

  const report = {
    version: pkg.version,
    scanRoot,
    mode: opts.permanent ? 'permanent' : 'trash',
    dryRun,
    entries: entries.map((e) => {
      const t = defs.byId.get(e.typeId);
      return {
        path: e.path,
        typeId: e.typeId,
        kind: t.kind,
        displayName: t.displayName,
        projectName: e.projectName,
        sizeBytes: e.sizeBytes,
        sizeUnknown: e.sizeUnknown,
        lastModified: e.lastModified ? e.lastModified.toISOString() : null,
        regenerable: t.regenerable,
      };
    }),
    denied: { count: deniedCount, paths: deniedPaths },
    totals: { count: entries.length, ...(({ bytes, unknown }) => ({ sizeBytes: bytes, unknownCount: unknown }))(sumKnown(entries)), filteredOut: filteredOut.length },
  };
  const emitJson = () => {
    if (opts.json) process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  };

  if (filteredOut.length) {
    out(style.dim(`${plural(filteredOut.length, 'item')} hidden by --min-age/--min-size.`));
  }
  if (entries.length === 0) {
    out(scan.cancelled ? 'Scan cancelled.' : 'No artifacts found.');
    emitJson();
    return EXIT.ok;
  }

  out(`Found ${style.bold(totalsLine(entries))} ${style.dim('(estimated)')}`);
  out('');

  if (dryRun || opts.yes) {
    printEntries(entries, defs, style, out, home);
    out('');
  }
  if (dryRun) {
    out(style.dim('Dry run: nothing was deleted.'));
    emitJson();
    return EXIT.ok;
  }

  // Select.
  const selected = opts.yes ? entries : await promptSelection(entries, defs, style, home);
  if (selected.length === 0) {
    out(style.dim('Nothing selected.'));
    emitJson();
    return EXIT.ok;
  }

  // Confirm.
  const mode = opts.permanent ? 'permanent' : 'trash';
  const warning = nonRegenerableWarning(selected.map((e) => e.typeId), defs, style);
  out('');
  out(`Selected ${style.bold(totalsLine(selected))}:`);
  for (const row of perTypeBreakdown(selected, defs)) {
    out(`  ${row.name}: ${plural(row.count, 'item')}, ${formatBytes(row.bytes)}${row.unknown ? ` + ${row.unknown} unknown` : ''}`);
  }
  if (selected.length < entries.length) out(style.dim(`  (${entries.length - selected.length} not selected)`));
  out('');
  warning.forEach((l) => out(l));
  if (!opts.yes) {
    const verb = mode === 'trash' ? 'Move these items to the Trash?' : 'Delete these items PERMANENTLY? This cannot be undone.';
    if (!(await promptYesNo(verb, style))) {
      out(style.dim('Cancelled.'));
      return EXIT.ok;
    }
  }

  // Delete.
  let log = null;
  try {
    log = openDeletionLog({ dir: opts.logDir, version: pkg.version, mode, env: process.env, home });
  } catch (e) {
    err(style.yellow(`Warning: cannot open the deletion log (${e.message}); continuing without it.`));
  }
  const selectedPaths = selected.map((e) => e.path);
  const before = await snapshot(selectedPaths);
  const verbing = mode === 'trash' ? 'Moving to Trash' : 'Deleting';
  spinner.start(`${verbing} ...`);
  const progress = (label) => (done, total, entry) => spinner.update(`${label} [${done}/${total}] ${entry.projectName ?? path.basename(entry.path)}`);
  const first = await deleteEntries(selected, { mode, scanRoot, defs, log, onProgress: progress(verbing) });
  spinner.stop();

  const okPaths = new Map(first.ok.map((o) => [o.path, { ...o, mode }]));
  let failed = first.failed;

  const unsupported = failed.filter((f) => f.code === 'unsupported');
  if (mode === 'trash' && unsupported.length) {
    err(style.yellow(`${plural(unsupported.length, 'item')} could not be moved to the Trash (the volume may not support it):`));
    for (const f of unsupported) err(`  ${shortenPath(f.path, home)} - ${f.error}`);
    if (opts.yes) {
      err('Rerun with --permanent to delete them permanently. Nothing was escalated automatically.');
    } else if (await promptYesNo(`Delete these ${unsupported.length} items permanently?`, style)) {
      const retry = selected.filter((e) => unsupported.some((u) => u.path === e.path));
      spinner.start('Deleting ...');
      const second = await deleteEntries(retry, { mode: 'permanent', scanRoot, defs, log, onProgress: progress('Deleting') });
      spinner.stop();
      for (const o of second.ok) okPaths.set(o.path, { ...o, mode: 'permanent' });
      const retried = new Set(retry.map((e) => e.path));
      failed = [...failed.filter((f) => !retried.has(f.path)), ...second.failed];
    }
  }

  const after = await snapshot(selectedPaths);
  const measured = freed(before, after);
  const byPath = new Map(selected.map((e) => [e.path, e]));
  const okEntries = [...okPaths.keys()].map((p) => byPath.get(p));
  const trashedEntries = okEntries.filter((e) => okPaths.get(e.path).mode === 'trash');
  const removedEntries = okEntries.filter((e) => okPaths.get(e.path).mode === 'permanent');

  log?.run({
    scanRoot,
    requested: selected.length,
    ok: okEntries.length,
    failed: failed.length,
    estimatedBytes: sumKnown(okEntries).bytes,
    measuredFreedBytes: measured,
  });

  // Summary.
  out('');
  if (okEntries.length === 0) {
    out(style.red('Nothing was removed.'));
  } else if (failed.length) {
    out(style.yellow(`Removed ${okEntries.length} of ${selected.length} items.`));
  } else {
    out(style.green(`Done. Removed ${plural(okEntries.length, 'item')}.`));
  }
  if (trashedEntries.length) {
    out(`Moved to Trash: ${style.bold(formatBytes(sumKnown(trashedEntries).bytes))} (estimated). Empty the Trash to reclaim the space.`);
  }
  if (removedEntries.length) {
    out(`Freed ${style.bold(formatBytes(measured))} (measured; ${formatBytes(sumKnown(removedEntries).bytes)} estimated).`);
  }
  if (failed.length) {
    out('');
    out(style.red(`Could not remove ${plural(failed.length, 'item')}:`));
    for (const f of failed) out(`  ${shortenPath(f.path, home)} - ${f.error}`);
  }
  if (log) out(style.dim(`Log: ${shortenPath(log.file, home)}`));
  out('');

  report.results = {
    ok: [...okPaths.values()].map(({ path: p, mode: m, trashedTo, alreadyGone }) => ({ path: p, mode: m, ...(trashedTo ? { trashedTo } : {}), ...(alreadyGone ? { alreadyGone } : {}) })),
    failed,
    estimatedBytes: sumKnown(okEntries).bytes,
    measuredFreedBytes: measured,
  };
  emitJson();
  return failed.length ? EXIT.failed : EXIT.ok;
}

main(process.argv.slice(2)).then(
  (code) => {
    process.exitCode = code;
  },
  (e) => {
    if (process.stderr.isTTY) process.stderr.write('\x1b[?25h');
    if (e?.name === 'ExitPromptError') {
      process.stderr.write('Cancelled.\n');
      process.exitCode = EXIT.ok;
      return;
    }
    process.stderr.write(`prune: ${e?.message ?? e}\n`);
    process.exitCode = EXIT.error;
  },
);
