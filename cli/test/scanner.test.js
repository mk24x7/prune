import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { loadDefinitions } from '../lib/definitions.js';
import { scanForArtifacts, checkSystemArtifacts } from '../lib/scanner.js';
import { makeTree, removeTree } from './fixtures.js';

const deepDirs = Array.from({ length: 11 }, (_, i) => `d${i + 1}`).join('/');

// Fixture A: project scan. The fixture root doubles as the fake home.
const fixtureA = {
  'app1/package.json': '{"name":"app-one"}',
  'app1/node_modules/left-pad/index.js': 'module.exports = 1;',
  'app1/node_modules/left-pad/__pycache__/x.pyc': 'x',
  'app1/.next/cache/a': 'a',
  'rusty/Cargo.toml': '[package]\nname = "rusty"\n',
  'rusty/target/debug/rusty': 'bin',
  'notrust/target/inner/Cargo.toml': '[package]\nname = "inner"\n',
  'notrust/target/inner/target/debug/x': 'bin',
  'py/requirements.txt': 'requests\n',
  'py/venv/bin/python': '#!/bin/sh\n',
  'py/__pycache__/m.pyc': 'x',
  'gradleproj/build.gradle': '',
  'gradleproj/settings.gradle': "rootProject.name = 'gp'\n",
  'gradleproj/build/out.jar': 'jar',
  'gradleproj/.gradle/cache': 'x',
  linkdir: { symlink: 'app1' },
  '.hidden/package.json': '{}',
  '.hidden/node_modules/x/index.js': '',
  'Library/x/node_modules/y/index.js': '',
  'work/Library/proj/node_modules/z/index.js': '',
  [`${deepDirs}/node_modules/a/index.js`]: '',
  'Thing.app/Contents/node_modules/a/index.js': '',
  'Wallpapers/node_modules/a/index.js': '',
  '.git/modules/node_modules/a/index.js': '',
  'sys/cache/node_modules/a/index.js': '',
  'plain/target/readme.txt': 'no Cargo.toml here',
};

const expectedDefault = [
  ['app1/.next', 'next'],
  ['app1/node_modules', 'node'],
  ['gradleproj/.gradle', 'gradlecache'],
  ['gradleproj/build', 'gradle'],
  ['notrust/target/inner/target', 'rust'],
  ['py/__pycache__', 'pycache'],
  ['py/venv', 'pythonvenv'],
  ['rusty/target', 'rust'],
  ['work/Library/proj/node_modules', 'node'],
];

let rootA;
let defs;

before(async () => {
  rootA = await makeTree(fixtureA);
  defs = loadDefinitions({ env: {}, home: rootA });
});

after(async () => {
  await removeTree(rootA);
});

const rel = (root, found) => found.map((f) => [path.relative(root, f.path), f.typeId]).sort((a, b) => a[0].localeCompare(b[0]));

test('fixture A: exact (path, type) set with default options', async () => {
  const res = await scanForArtifacts(rootA, defs.projectTypes, {
    scan: defs.scan,
    home: rootA,
    extraSkipPaths: [path.join(rootA, 'sys/cache')],
  });
  assert.deepEqual(rel(rootA, res.found), expectedDefault);
  assert.equal(res.deniedCount, 0);
  assert.ok(res.scannedCount > 10);
  assert.equal(res.cancelled, false);
});

test('fixture A: symlinks, package contents and skip lists are never reported', async () => {
  const res = await scanForArtifacts(rootA, defs.projectTypes, {
    scan: defs.scan,
    home: rootA,
    includeHidden: true,
    maxDepth: 30,
  });
  const paths = rel(rootA, res.found).map(([p]) => p);
  assert.ok(!paths.some((p) => p.startsWith('linkdir')), 'symlinked project must not be followed');
  assert.ok(!paths.some((p) => p.includes('Thing.app')), '.app contents must be skipped');
  assert.ok(!paths.some((p) => p.startsWith('Library/')), 'home Library must be skipped');
  assert.ok(!paths.some((p) => p.startsWith('Wallpapers')), 'skipAnywhere must apply');
  assert.ok(!paths.some((p) => p.startsWith('.git')), '.git must be skipped even with hidden on');
  assert.ok(!paths.some((p) => p.includes('node_modules/left-pad')), 'matched artifacts are not recursed');
  assert.ok(!paths.includes('plain/target'), 'target without Cargo.toml is not rust');
  assert.ok(!paths.includes('notrust/target'), 'outer target without Cargo.toml is not rust');
  assert.ok(paths.includes('sys/cache/node_modules'), 'without extraSkipPaths the dir is scanned');
});

test('fixture A: hidden toggle', async () => {
  const off = await scanForArtifacts(rootA, defs.projectTypes, { scan: defs.scan, home: rootA });
  assert.ok(!off.found.some((f) => f.path.includes('.hidden')));
  const on = await scanForArtifacts(rootA, defs.projectTypes, { scan: defs.scan, home: rootA, includeHidden: true });
  assert.ok(on.found.some((f) => f.path === path.join(rootA, '.hidden/node_modules') && f.typeId === 'node'));
});

test('fixture A: depth toggle', async () => {
  const deep = path.join(rootA, deepDirs, 'node_modules');
  const def = await scanForArtifacts(rootA, defs.projectTypes, { scan: defs.scan, home: rootA });
  assert.ok(!def.found.some((f) => f.path === deep), 'depth 12 is beyond the default maxDepth');
  const at12 = await scanForArtifacts(rootA, defs.projectTypes, { scan: defs.scan, home: rootA, maxDepth: 12 });
  assert.ok(at12.found.some((f) => f.path === deep));
  const at11 = await scanForArtifacts(rootA, defs.projectTypes, { scan: defs.scan, home: rootA, maxDepth: 11 });
  assert.ok(!at11.found.some((f) => f.path === deep));
});

test('fixture A: skipUnderHome only applies directly under home', async () => {
  // Scanning with a different home: Library at the root is no longer special.
  const res = await scanForArtifacts(rootA, defs.projectTypes, { scan: defs.scan, home: '/nonexistent-home' });
  assert.ok(res.found.some((f) => f.path === path.join(rootA, 'Library/x/node_modules')));
});

test('fixture A: only selected types are matched', async () => {
  const res = await scanForArtifacts(rootA, [defs.byId.get('rust')], { scan: defs.scan, home: rootA });
  assert.deepEqual(rel(rootA, res.found), [
    ['notrust/target/inner/target', 'rust'],
    ['rusty/target', 'rust'],
  ]);
});

test('onFound, onProgress and cancellation', async () => {
  const seen = [];
  let progress = 0;
  const res = await scanForArtifacts(rootA, defs.projectTypes, {
    scan: defs.scan,
    home: rootA,
    onFound: (f, n) => seen.push([f.path, n]),
    onProgress: () => progress++,
  });
  assert.equal(seen.length, res.found.length);
  assert.equal(progress, res.scannedCount);

  const ac = new AbortController();
  ac.abort();
  const cancelled = await scanForArtifacts(rootA, defs.projectTypes, { scan: defs.scan, home: rootA, signal: ac.signal });
  assert.equal(cancelled.cancelled, true);
  assert.equal(cancelled.found.length, 0);
});

test('unreadable directory is counted as denied', { skip: process.getuid?.() === 0 ? 'running as root' : false }, async () => {
  const root = await makeTree({ 'ok/package.json': '{}', 'ok/node_modules/a': '', 'locked/node_modules/a': '' });
  try {
    await fs.chmod(path.join(root, 'locked'), 0o000);
    const d = loadDefinitions({ env: {}, home: root });
    const res = await scanForArtifacts(root, d.projectTypes, { scan: d.scan, home: root });
    assert.equal(res.deniedCount, 1);
    assert.deepEqual(res.deniedDirectories, [path.join(root, 'locked')]);
    assert.deepEqual(rel(root, res.found), [['ok/node_modules', 'node']]);
  } finally {
    await removeTree(root);
  }
});

// Fixture B: system and files kinds against a fake home.
test('fixture B: expand lists every subdirectory including hidden ones', async () => {
  const home = await makeTree({
    'Library/Developer/Xcode/DerivedData/Foo-abc/Build/x': '',
    'Library/Developer/Xcode/DerivedData/Bar-def/Index/y': '',
    'Library/Developer/Xcode/DerivedData/.hiddenproj-123/z': '',
    'Library/Developer/Xcode/DerivedData/stray-file': 'not a dir',
    'Library/Developer/Xcode/DerivedData/linked': { symlink: '/tmp' },
    'go/pkg/mod/cache/x': '',
  });
  try {
    const d = loadDefinitions({ env: {}, home });
    const { found } = await checkSystemArtifacts([d.byId.get('xcode-derived'), d.byId.get('go-mod-cache')], d);
    assert.deepEqual(found.map((f) => [path.relative(home, f.path), f.typeId]), [
      ['Library/Developer/Xcode/DerivedData/.hiddenproj-123', 'xcode-derived'],
      ['Library/Developer/Xcode/DerivedData/Bar-def', 'xcode-derived'],
      ['Library/Developer/Xcode/DerivedData/Foo-abc', 'xcode-derived'],
      ['go/pkg/mod', 'go-mod-cache'],
    ]);
  } finally {
    await removeTree(home);
  }
});

test('fixture B: GOMODCACHE and GOPATH resolution, missing path yields nothing', async () => {
  const home = await makeTree({ 'go/pkg/mod/x': '', 'custommod/y': '', 'gp/pkg/mod/z': '' });
  try {
    const go = async (env) => {
      const d = loadDefinitions({ env, home });
      return (await checkSystemArtifacts([d.byId.get('go-mod-cache')], d)).found.map((f) => f.path);
    };
    assert.deepEqual(await go({ GOMODCACHE: path.join(home, 'custommod') }), [path.join(home, 'custommod')]);
    assert.deepEqual(await go({ GOPATH: path.join(home, 'gp') }), [path.join(home, 'gp/pkg/mod')]);
    assert.deepEqual(await go({}), [path.join(home, 'go/pkg/mod')]);
    assert.deepEqual(await go({ GOMODCACHE: path.join(home, 'missing') }), []);
    const d = loadDefinitions({ env: {}, home });
    assert.deepEqual((await checkSystemArtifacts([d.byId.get('xcode-derived'), d.byId.get('npm-cache')], d)).found, []);
  } finally {
    await removeTree(home);
  }
});

test('fixture B: isFile system type and files kind', async () => {
  const home = await makeTree({
    'Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw': 'raw',
    'Downloads/a.dmg': 'x',
    'Downloads/B.PKG': 'x',
    'Downloads/c.txt': 'x',
    'Downloads/folder.dmg/inner': 'x',
    'Downloads/link.pkg': { symlink: 'a.dmg' },
  });
  try {
    const d = loadDefinitions({ env: {}, home });
    const { found } = await checkSystemArtifacts([d.byId.get('docker-disk-image'), d.byId.get('downloads-installers')], d);
    assert.deepEqual(found.map((f) => [path.relative(home, f.path), f.typeId]), [
      ['Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw', 'docker-disk-image'],
      ['Downloads/a.dmg', 'downloads-installers'],
      ['Downloads/B.PKG', 'downloads-installers'],
    ]);
  } finally {
    await removeTree(home);
  }
});

test('fixture B: isFile type ignores a directory at the path', async () => {
  const home = await makeTree({ 'Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw/x': '' });
  try {
    const d = loadDefinitions({ env: {}, home });
    assert.deepEqual((await checkSystemArtifacts([d.byId.get('docker-disk-image')], d)).found, []);
  } finally {
    await removeTree(home);
  }
});
