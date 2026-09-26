import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { loadDefinitions } from '../lib/definitions.js';
import { verifyEntry } from '../lib/verify.js';
import { deleteEntries, makeWritable } from '../lib/deleter.js';
import { trashPaths, classifyTrashError, detectTrashImpl } from '../lib/trash.js';
import { openDeletionLog, ROTATE_BYTES, LOG_FILE_NAME } from '../lib/log.js';
import { snapshot, freed } from '../lib/diskspace.js';
import { makeTree, removeTree } from './fixtures.js';

const MiB = 1024 * 1024;
const exists = (p) => fs.lstat(p).then(() => true, () => false);
const readLines = async (file) => (await fs.readFile(file, 'utf8')).split('\n').filter(Boolean).map((l) => JSON.parse(l));

async function withTree(spec, fn) {
  const root = await makeTree(spec);
  try {
    return await fn(root, loadDefinitions({ env: {}, home: root }));
  } finally {
    await removeTree(root);
  }
}

// ---------------------------------------------------------------------------
// Verifier

const verifierSpec = {
  'proj/package.json': '{}',
  'proj/node_modules/a/index.js': '',
  'proj/src/index.js': '',
  'sub/keep.txt': '',
  'rust2/target/debug/x': '',
  'rusty/Cargo.toml': '',
  'rusty/target/x': '',
  link: { symlink: 'proj' },
  'sub/escape': { symlink: '../proj' },
  'linkedproj/package.json': '{}',
  'linkedproj/node_modules': { symlink: '../proj/node_modules' },
  'Library/Developer/Xcode/DerivedData/Foo-abc/Build/x': '',
  '.npm/_cacache/x': '',
  'other/x': '',
  'Downloads/a.dmg': 'x',
  'Downloads/b.txt': 'x',
  'Downloads/sub/c.dmg': 'x',
  'Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw/x': '',
};

async function rejects(entry, defs, ctx, pattern) {
  await assert.rejects(
    verifyEntry(entry, defs.byId.get(entry.typeId), ctx),
    (err) => err.code === 'verification' && pattern.test(err.message),
  );
}

test('verifier accepts well-formed entries of every kind', () => withTree(verifierSpec, async (root, defs) => {
  const ctx = { scanRoot: root, defs };
  await verifyEntry({ path: path.join(root, 'proj/node_modules'), typeId: 'node' }, defs.byId.get('node'), ctx);
  await verifyEntry({ path: path.join(root, 'rusty/target'), typeId: 'rust' }, defs.byId.get('rust'), ctx);
  await verifyEntry({ path: path.join(root, 'Library/Developer/Xcode/DerivedData/Foo-abc'), typeId: 'xcode-derived' }, defs.byId.get('xcode-derived'), ctx);
  await verifyEntry({ path: path.join(root, 'Library/Developer/Xcode/DerivedData'), typeId: 'xcode-derived' }, defs.byId.get('xcode-derived'), ctx);
  await verifyEntry({ path: path.join(root, '.npm'), typeId: 'npm-cache' }, defs.byId.get('npm-cache'), ctx);
  await verifyEntry({ path: path.join(root, 'Downloads/a.dmg'), typeId: 'downloads-installers' }, defs.byId.get('downloads-installers'), ctx);
  // A symlinked scan root is compared by real path.
  await verifyEntry({ path: path.join(root, 'link/node_modules'), typeId: 'node' }, defs.byId.get('node'), { scanRoot: path.join(root, 'link'), defs });
}));

test('verifier rejections', () => withTree(verifierSpec, async (root, defs) => {
  const ctx = { scanRoot: root, defs };
  await rejects({ path: path.join(root, 'proj/node_modules'), typeId: 'node' }, defs, { scanRoot: path.join(root, 'sub'), defs }, /not inside the scan root/);
  await rejects({ path: path.join(root, 'linkedproj/node_modules'), typeId: 'node' }, defs, ctx, /symbolic link/);
  await rejects({ path: path.join(root, 'sub/escape/node_modules'), typeId: 'node' }, defs, { scanRoot: path.join(root, 'sub'), defs }, /not inside the scan root/);
  await rejects({ path: path.join(root, 'rust2/target'), typeId: 'rust' }, defs, ctx, /marker files/);
  await rejects({ path: path.join(root, 'proj/src'), typeId: 'node' }, defs, ctx, /not a Node Modules target|is not a .* target/);
  await rejects({ path: path.join(root, 'other'), typeId: 'npm-cache' }, defs, ctx, /not the .* location/);
  await rejects({ path: path.join(root, 'Library/Developer/Xcode/DerivedData/Foo-abc/Build'), typeId: 'xcode-derived' }, defs, ctx, /not the .* location/);
  await rejects({ path: path.join(root, '.npm/_cacache'), typeId: 'npm-cache' }, defs, ctx, /not the .* location/);
  await rejects({ path: root, typeId: 'npm-cache' }, defs, { scanRoot: root, defs, env: { npm_config_cache: root }, home: root }, /home directory/);
  await rejects({ path: '/Users', typeId: 'npm-cache' }, defs, ctx, /too close to the file system root/);
  await rejects({ path: '/', typeId: 'npm-cache' }, defs, ctx, /too close/);
  await rejects({ path: path.join(root, 'Downloads/b.txt'), typeId: 'downloads-installers' }, defs, ctx, /extension/);
  await rejects({ path: path.join(root, 'Downloads/sub/c.dmg'), typeId: 'downloads-installers' }, defs, ctx, /not directly inside/);
  await rejects({ path: path.join(root, 'Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw'), typeId: 'docker-disk-image' }, defs, ctx, /expected a regular file/);
  await rejects({ path: path.join(root, 'proj/package.json'), typeId: 'node' }, defs, ctx, /expected a directory/);
  await rejects({ path: `${root}/proj/../proj/node_modules`, typeId: 'node' }, defs, ctx, /not normalized/);
  await rejects({ path: 'relative/node_modules', typeId: 'node' }, defs, ctx, /not absolute/);
  await rejects({ path: path.join(root, 'nope/node_modules'), typeId: 'node' }, defs, ctx, /cannot stat/);
  await assert.rejects(verifyEntry({ path: path.join(root, 'proj/node_modules'), typeId: 'bogus' }, undefined, ctx), /unknown type/);
}));

// ---------------------------------------------------------------------------
// Deleter

test('permanent mode removes a normal tree and a read-only (0555) tree', () => withTree({
  'a/package.json': '{}',
  'a/node_modules/x/index.js': 'x',
  'b/package.json': '{}',
  'b/node_modules/pkg/file.js': { content: 'y', mode: 0o444 },
  'b/node_modules/pkg/': { dir: true, mode: 0o555 },
  'b/node_modules/': { dir: true, mode: 0o555 },
}, async (root, defs) => {
  const entries = [
    { path: path.join(root, 'a/node_modules'), typeId: 'node', sizeBytes: 10 },
    { path: path.join(root, 'b/node_modules'), typeId: 'node', sizeBytes: 20 },
  ];
  const progress = [];
  const res = await deleteEntries(entries, { mode: 'permanent', scanRoot: root, defs, onProgress: (d, t) => progress.push(`${d}/${t}`) });
  assert.deepEqual(res.failed, []);
  assert.equal(res.ok.length, 2);
  assert.deepEqual(progress, ['1/2', '2/2']);
  assert.equal(await exists(path.join(root, 'a/node_modules')), false);
  assert.equal(await exists(path.join(root, 'b/node_modules')), false);
  assert.equal(await exists(path.join(root, 'b/package.json')), true);
}));

test('makeWritable restores access under a 000 directory', { skip: process.getuid?.() === 0 ? 'running as root' : false }, () => withTree({
  'x/locked/f': 'f',
  'x/locked/': { dir: true, mode: 0o000 },
}, async (root) => {
  await makeWritable(path.join(root, 'x'));
  assert.deepEqual(await fs.readdir(path.join(root, 'x/locked')), ['f']);
}));

test('ENOENT counts as success in both modes', () => withTree({}, async (root, defs) => {
  const entry = { path: path.join(root, 'gone/node_modules'), typeId: 'node' };
  for (const mode of ['trash', 'permanent']) {
    const res = await deleteEntries([entry], { mode, scanRoot: root, defs, trashImpl: async () => { throw new Error('must not be called'); } });
    assert.deepEqual(res.failed, []);
    assert.deepEqual(res.ok, [{ path: entry.path, alreadyGone: true }]);
  }
}));

test('trash mode with a fake implementation records trashedTo', () => withTree({
  'p/package.json': '{}',
  'p/node_modules/x': 'x',
}, async (root, defs) => {
  const bin = path.join(root, 'fake-trash');
  await fs.mkdir(bin);
  const calls = [];
  const impl = async (p) => {
    calls.push(p);
    const dest = path.join(bin, path.basename(p));
    await fs.rename(p, dest);
    return { trashedTo: dest };
  };
  const src = path.join(root, 'p/node_modules');
  const res = await deleteEntries([{ path: src, typeId: 'node', sizeBytes: 1 }], { mode: 'trash', scanRoot: root, defs, trashImpl: impl });
  assert.deepEqual(calls, [src]);
  assert.deepEqual(res.ok, [{ path: src, trashedTo: path.join(bin, 'node_modules') }]);
  assert.equal(await exists(src), false);
  assert.equal(await exists(path.join(bin, 'node_modules/x')), true);
}));

test('trash unsupported leaves the directory and reports the code', () => withTree({
  'p/package.json': '{}',
  'p/node_modules/x': 'x',
}, async (root, defs) => {
  const src = path.join(root, 'p/node_modules');
  const impl = async () => { throw Object.assign(new Error('volume has no Trash'), { code: 'unsupported' }); };
  const res = await deleteEntries([{ path: src, typeId: 'node' }], { mode: 'trash', scanRoot: root, defs, trashImpl: impl });
  assert.deepEqual(res.ok, []);
  assert.equal(res.failed.length, 1);
  assert.equal(res.failed[0].code, 'unsupported');
  assert.match(res.failed[0].error, /no Trash/);
  assert.equal(await exists(path.join(src, 'x')), true);
}));

test('verification failures are reported, logged and nothing is deleted', () => withTree({
  'p/src/x': 'x',
}, async (root, defs) => {
  const logDir = path.join(root, 'logs');
  const log = openDeletionLog({ dir: logDir, version: '9.9.9', mode: 'permanent' });
  const src = path.join(root, 'p/src');
  const res = await deleteEntries([{ path: src, typeId: 'node', sizeBytes: 5 }], { mode: 'permanent', scanRoot: root, defs, log });
  assert.equal(res.failed[0].code, 'verification');
  assert.equal(await exists(path.join(src, 'x')), true);
  const [line] = await readLines(log.file);
  assert.equal(line.result, 'failed');
  assert.match(line.error, /Refusing to delete/);
}));

test('trashPaths classifies failures and accepts function impls', async () => {
  const res = await trashPaths(['/a/x', '/a/y', '/a/z'], {
    impl: async (p) => {
      if (p === '/a/y') throw Object.assign(new Error('boom'), { stderr: 'Error Domain=NSCocoaErrorDomain Code=513 "no permission"' });
      if (p === '/a/z') throw Object.assign(new Error('Command failed'), { code: 5, stderr: 'Error Domain=NSCocoaErrorDomain Code=3328 "not supported"' });
      return { trashedTo: `/T/${path.basename(p)}` };
    },
  });
  assert.deepEqual(res.trashed, [{ path: '/a/x', trashedTo: '/T/x' }]);
  assert.deepEqual(res.failed.map((f) => [f.path, f.code]), [['/a/y', 'other'], ['/a/z', 'unsupported']]);
  assert.equal(classifyTrashError(Object.assign(new Error('spawn'), { code: 'ENOENT' })), 'other');
  assert.equal(classifyTrashError(Object.assign(new Error('t'), { killed: true, signal: 'SIGTERM' })), 'other');
  assert.ok(['trash', 'osascript'].includes(detectTrashImpl()));
});

// ---------------------------------------------------------------------------
// Log

test('log writes one line per item plus a run line', () => withTree({
  'p/package.json': '{}',
  'p/node_modules/x': 'x',
  'q/package.json': '{}',
  'q/node_modules/y': 'y',
}, async (root, defs) => {
  const logDir = path.join(root, 'logs');
  const log = openDeletionLog({ dir: logDir, version: '4.0.0', mode: 'permanent' });
  const entries = [
    { path: path.join(root, 'p/node_modules'), typeId: 'node', sizeBytes: 100 },
    { path: path.join(root, 'q/node_modules'), typeId: 'node', sizeBytes: 200 },
    { path: path.join(root, 'r/node_modules'), typeId: 'node', sizeBytes: null },
  ];
  const res = await deleteEntries(entries, { mode: 'permanent', scanRoot: root, defs, log });
  log.run({ scanRoot: root, requested: 3, ok: res.ok.length, failed: res.failed.length });
  const lines = await readLines(path.join(logDir, LOG_FILE_NAME));
  assert.equal(lines.length, 4);
  assert.deepEqual(lines.slice(0, 3).map((l) => [l.tool, l.version, l.mode, l.typeId, l.result, l.estimatedBytes]), [
    ['cli', '4.0.0', 'permanent', 'node', 'ok', 100],
    ['cli', '4.0.0', 'permanent', 'node', 'ok', 200],
    ['cli', '4.0.0', 'permanent', 'node', 'ok', null],
  ]);
  for (const l of lines) assert.ok(!Number.isNaN(Date.parse(l.ts)));
  assert.equal(lines[3].event, 'run');
  assert.equal(lines[3].ok, 3);
}));

test('log honours PRUNE_LOG_DIR and rotates at 5 MB', () => withTree({}, async (root) => {
  const dir = path.join(root, 'envlogs');
  const now = () => new Date('2026-09-26T10:00:00Z');
  await fs.mkdir(dir, { recursive: true });
  await fs.writeFile(path.join(dir, LOG_FILE_NAME), Buffer.alloc(ROTATE_BYTES, 0x20));
  const log = openDeletionLog({ version: '4.0.0', mode: 'trash', env: { PRUNE_LOG_DIR: dir }, home: '/nonexistent', now });
  assert.equal(log.file, path.join(dir, LOG_FILE_NAME));
  assert.equal(await exists(path.join(dir, 'deletions-2026-09-26.jsonl')), true);
  assert.equal(await exists(log.file), false);
  log.item({ typeId: 'node', path: '/x/y/node_modules', estimatedBytes: 1, result: 'ok' });
  assert.equal((await readLines(log.file)).length, 1);
}));

// ---------------------------------------------------------------------------
// Disk space

test('measured freed space >= 10 MiB after permanently deleting a 20 MiB fixture', () => withTree({
  'big/package.json': '{}',
  'big/node_modules/a.bin': { size: 10 * MiB },
  'big/node_modules/b.bin': { size: 10 * MiB },
}, async (root, defs) => {
  const target = path.join(root, 'big/node_modules');
  const before = await snapshot([target]);
  assert.equal(before.size, 1);
  const res = await deleteEntries([{ path: target, typeId: 'node' }], { mode: 'permanent', scanRoot: root, defs });
  assert.equal(res.ok.length, 1);
  const after = await snapshot([target]);
  const bytes = freed(before, after);
  assert.ok(bytes >= 10 * MiB, `measured ${bytes}`);
}));

test('freed clamps negative deltas and ignores unknown volumes', () => {
  const before = new Map([[1, { path: '/a', availableBytes: 100 }], [2, { path: '/b', availableBytes: 100 }]]);
  const after = new Map([[1, { path: '/a', availableBytes: 50 }], [2, { path: '/b', availableBytes: 180 }], [3, { path: '/c', availableBytes: 999 }]]);
  assert.equal(freed(before, after), 80);
});

// ---------------------------------------------------------------------------
// Real Trash (opt-in: it puts a folder in your Trash)

test('real /usr/bin/trash moves a folder to the Trash', { skip: process.env.PRUNE_TEST_REAL_TRASH === '1' ? false : 'set PRUNE_TEST_REAL_TRASH=1 to run' }, () => withTree({
  'realtrash/package.json': '{}',
  'realtrash/node_modules/x': 'x',
}, async (root, defs) => {
  const src = path.join(root, 'realtrash/node_modules');
  const res = await deleteEntries([{ path: src, typeId: 'node' }], { mode: 'trash', scanRoot: root, defs, trashImpl: detectTrashImpl() });
  assert.deepEqual(res.failed, []);
  assert.equal(await exists(src), false);
  if (res.ok[0].trashedTo) assert.match(res.ok[0].trashedTo, /\.Trash/);
}));
