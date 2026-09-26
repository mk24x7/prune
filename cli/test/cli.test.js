// End-to-end tests: spawn the real CLI with a fake HOME, a private log dir,
// a scrubbed environment (no npm_config_cache, GOPATH, ... from the parent
// shell) and stdin closed.

import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { makeTree, removeTree, setMtime, DAY_MS } from './fixtures.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const CLI = path.resolve(here, '../prune.js');
const pkg = createRequire(import.meta.url)('../package.json');
const MiB = 1024 * 1024;
const exists = (p) => fs.lstat(p).then(() => true, () => false);

let home;
let logDir;

function run(args, { env = {} } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [CLI, ...args], {
      env: { PATH: '/usr/bin:/bin:/usr/sbin:/sbin', HOME: home, PRUNE_LOG_DIR: logDir, NO_COLOR: '1', ...env },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d) => { stdout += d; });
    child.stderr.on('data', (d) => { stderr += d; });
    const timer = setTimeout(() => child.kill('SIGKILL'), 60_000);
    child.on('error', reject);
    child.on('close', (code, signal) => {
      clearTimeout(timer);
      resolve({ code, signal, stdout, stderr });
    });
  });
}

beforeEach(async () => {
  home = await makeTree({
    'code/app/package.json': '{"name":"big-app"}',
    'code/app/node_modules/pkg/blob.bin': { size: 2 * MiB },
    'code/small/package.json': '{"name":"small-app"}',
    'code/small/node_modules/pkg/index.js': 'module.exports = 1;\n',
    'code/rs/Cargo.toml': '[package]\nname = "crab"\n',
    'code/rs/target/debug/crab': 'bin',
    'Library/Developer/Xcode/DerivedData/Foo-abc123/Build/x': 'x',
    'Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive/x': 'x',
    'Downloads/Tool.dmg': 'dmg',
  });
  logDir = path.join(home, '.prune-logs');
});

afterEach(async () => {
  await removeTree(home);
});

test('--version prints the package.json version', async () => {
  const r = await run(['--version']);
  assert.equal(r.code, 0);
  assert.equal(r.stdout.trim(), pkg.version);
  const short = await run(['-V']);
  assert.equal(short.stdout.trim(), pkg.version);
});

test('--help and --list-categories exit 0', async () => {
  const h = await run(['--help']);
  assert.equal(h.code, 0);
  assert.match(h.stdout, /Usage:/);
  const l = await run(['--list-categories']);
  assert.equal(l.code, 0);
  assert.match(l.stdout, /xcode-derived/);
  assert.match(l.stdout, /NOT REGENERABLE/);
});

test('usage errors exit 2', async () => {
  for (const args of [['--bogus'], ['a', 'b'], ['--yes'], ['--categories', 'nope', '--dry-run'], ['--min-size', 'lots', '--dry-run'], ['--all', '--categories', 'node', '--dry-run']]) {
    const r = await run(args);
    assert.equal(r.code, 2, `${args.join(' ')}: ${r.stderr}`);
    assert.match(r.stderr, /prune: /);
  }
});

test('nonexistent root exits 2', async () => {
  const r = await run(['--dry-run', path.join(home, 'does-not-exist')]);
  assert.equal(r.code, 2);
  assert.match(r.stderr, /not an existing directory/);
});

test('without a TTY, a deleting run needs --yes or --dry-run', async () => {
  const r = await run(['--categories', 'node', home]);
  assert.equal(r.code, 2);
  assert.match(r.stderr, /not a terminal/);
  assert.equal(await exists(path.join(home, 'code/app/node_modules')), true);
});

test('--json --all --dry-run lists the expected entries as one JSON document', async () => {
  const r = await run(['--json', '--all', '--dry-run', home]);
  assert.equal(r.code, 0, r.stderr);
  const doc = JSON.parse(r.stdout);
  assert.equal(doc.version, pkg.version);
  assert.equal(doc.scanRoot, home);
  assert.equal(doc.dryRun, true);
  assert.equal(doc.mode, 'trash');
  assert.equal(doc.results, undefined);
  const got = doc.entries.map((e) => [path.relative(home, e.path), e.typeId]).sort((a, b) => a[0].localeCompare(b[0]));
  assert.deepEqual(got, [
    ['code/app/node_modules', 'node'],
    ['code/rs/target', 'rust'],
    ['code/small/node_modules', 'node'],
    ['Downloads/Tool.dmg', 'downloads-installers'],
    ['Library/Developer/Xcode/Archives/2026-01-01', 'xcode-archives'],
    ['Library/Developer/Xcode/DerivedData/Foo-abc123', 'xcode-derived'],
  ]);
  const app = doc.entries.find((e) => e.path.endsWith('code/app/node_modules'));
  assert.equal(app.projectName, 'big-app');
  assert.ok(app.sizeBytes >= 2 * MiB);
  assert.equal(doc.totals.count, 6);
  assert.equal(doc.denied.count, 0);
  // Human output went to stderr, including the non-regenerable warning for --all.
  assert.match(r.stderr, /NOT regenerable/);
  assert.equal(await exists(path.join(home, 'code/app/node_modules')), true);
});

test('--json without --yes implies a dry run', async () => {
  const r = await run(['--json', '--categories', 'node', home]);
  assert.equal(r.code, 0, r.stderr);
  const doc = JSON.parse(r.stdout);
  assert.equal(doc.dryRun, true);
  assert.equal(doc.entries.length, 2);
  assert.equal(await exists(path.join(home, 'code/app/node_modules')), true);
});

test('--yes --permanent --categories node deletes, exits 0 and writes the log', async () => {
  const r = await run(['--yes', '--permanent', '--categories', 'node', home]);
  assert.equal(r.code, 0, r.stderr + r.stdout);
  assert.equal(await exists(path.join(home, 'code/app/node_modules')), false);
  assert.equal(await exists(path.join(home, 'code/small/node_modules')), false);
  assert.equal(await exists(path.join(home, 'code/app/package.json')), true);
  assert.equal(await exists(path.join(home, 'code/rs/target')), true);
  assert.match(r.stdout, /Freed .* \(measured; .* estimated\)/);

  const lines = (await fs.readFile(path.join(logDir, 'deletions.jsonl'), 'utf8')).split('\n').filter(Boolean).map((l) => JSON.parse(l));
  assert.equal(lines.length, 3);
  const items = lines.filter((l) => l.event !== 'run');
  assert.equal(items.length, 2);
  for (const l of items) {
    assert.equal(l.tool, 'cli');
    assert.equal(l.mode, 'permanent');
    assert.equal(l.typeId, 'node');
    assert.equal(l.result, 'ok');
    assert.equal(l.version, pkg.version);
  }
  const runLine = lines.find((l) => l.event === 'run');
  assert.equal(runLine.ok, 2);
  assert.equal(runLine.failed, 0);
});

test('--yes --json reports results', async () => {
  const r = await run(['--yes', '--json', '--permanent', '--categories', 'rust', home]);
  assert.equal(r.code, 0, r.stderr);
  const doc = JSON.parse(r.stdout);
  assert.equal(doc.dryRun, false);
  assert.equal(doc.mode, 'permanent');
  assert.deepEqual(doc.results.ok.map((o) => path.relative(home, o.path)), ['code/rs/target']);
  assert.deepEqual(doc.results.failed, []);
  assert.equal(await exists(path.join(home, 'code/rs/target')), false);
});

test('--min-age 30 excludes recently modified entries', async () => {
  const old = Date.now() - 60 * DAY_MS;
  const nm = path.join(home, 'code/small/node_modules');
  await setMtime(path.join(nm, 'pkg/index.js'), old);
  await setMtime(path.join(nm, 'pkg'), old);
  await setMtime(nm, old);
  const r = await run(['--json', '--categories', 'node', '--min-age', '30', home]);
  assert.equal(r.code, 0, r.stderr);
  const doc = JSON.parse(r.stdout);
  assert.deepEqual(doc.entries.map((e) => path.relative(home, e.path)), ['code/small/node_modules']);
  assert.equal(doc.totals.filteredOut, 1);
});

test('--min-size 1MB excludes small entries', async () => {
  const r = await run(['--json', '--categories', 'node', '--min-size', '1MB', home]);
  assert.equal(r.code, 0, r.stderr);
  const doc = JSON.parse(r.stdout);
  assert.deepEqual(doc.entries.map((e) => path.relative(home, e.path)), ['code/app/node_modules']);
});

test('--dry-run never prompts, uses default categories and exits 0', async () => {
  const r = await run(['--dry-run', home]);
  assert.equal(r.code, 0, r.stderr);
  assert.doesNotMatch(r.stdout, /^\? /m);
  assert.match(r.stdout, /default categories/);
  assert.match(r.stdout, /Dry run: nothing was deleted/);
  assert.match(r.stdout, /code\/app\/node_modules/);
  // xcode-archives is off by default, so it is not listed.
  assert.doesNotMatch(r.stdout, /Archives/);
  assert.equal(await exists(path.join(home, 'code/app/node_modules')), true);
  assert.equal(await exists(logDir), false);
});

test('--log-dir overrides PRUNE_LOG_DIR', async () => {
  const custom = path.join(home, 'custom-logs');
  const r = await run(['--yes', '--permanent', '--categories', 'rust', '--log-dir', custom, home]);
  assert.equal(r.code, 0, r.stderr);
  const lines = (await fs.readFile(path.join(custom, 'deletions.jsonl'), 'utf8')).split('\n').filter(Boolean);
  assert.equal(lines.length, 2);
  assert.equal(await exists(logDir), false);
});
