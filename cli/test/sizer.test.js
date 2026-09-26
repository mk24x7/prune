import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { loadDefinitions } from '../lib/definitions.js';
import { calculateSizes, duBytes, lastModified, mapPool, projectName, sizeEntry } from '../lib/sizer.js';
import { makeTree, removeTree, setMtime, DAY_MS } from './fixtures.js';

const defs = loadDefinitions({ env: {}, home: '/nonexistent-home' });
const MiB = 1024 * 1024;

test('2 MiB of files sizes to at least 2 MiB', async () => {
  const root = await makeTree({
    'node_modules/a.bin': { size: MiB },
    'node_modules/sub/b.bin': { size: MiB },
  });
  try {
    const [entry] = await calculateSizes([{ path: path.join(root, 'node_modules'), typeId: 'node' }], { defs });
    assert.equal(entry.sizeUnknown, false);
    assert.ok(entry.sizeBytes >= 2 * MiB, `got ${entry.sizeBytes}`);
  } finally {
    await removeTree(root);
  }
});

test('unreadable subdirectory still yields a non-zero size', { skip: process.getuid?.() === 0 ? 'running as root' : false }, async () => {
  const root = await makeTree({
    'target/readable.bin': { size: 256 * 1024 },
    'target/locked/secret.bin': { size: 1024 },
  });
  try {
    await fs.chmod(path.join(root, 'target/locked'), 0o000);
    const bytes = await duBytes(path.join(root, 'target'));
    assert.ok(bytes !== null && bytes >= 256 * 1024, `got ${bytes}`);
  } finally {
    await removeTree(root);
  }
});

test('du failure modes: spawn failure and timeout are unknown, non-zero exit parses stdout', async () => {
  const root = await makeTree({
    'bin/slow-du': { content: '#!/bin/sh\nsleep 5\n', mode: 0o755 },
    'bin/partial-du': { content: '#!/bin/sh\nprintf "8\\t%s\\n" "$2"\necho "du: denied" >&2\nexit 1\n', mode: 0o755 },
    'dir/x': 'x',
  });
  try {
    const dir = path.join(root, 'dir');
    assert.equal(await duBytes(dir, { duPath: path.join(root, 'bin/missing-du') }), null);
    assert.equal(await duBytes(dir, { duPath: path.join(root, 'bin/slow-du'), timeout: 200 }), null);
    assert.equal(await duBytes(dir, { duPath: path.join(root, 'bin/partial-du') }), 8 * 1024);

    const entry = await sizeEntry({ path: dir, typeId: 'node' }, defs.byId.get('node'), { duPath: path.join(root, 'bin/missing-du') });
    assert.equal(entry.sizeBytes, null);
    assert.equal(entry.sizeUnknown, true);
  } finally {
    await removeTree(root);
  }
});

test('file entries use allocated size from stat', async () => {
  const root = await makeTree({ 'Downloads/x.dmg': { size: 300 * 1024 } });
  try {
    const entry = await sizeEntry({ path: path.join(root, 'Downloads/x.dmg'), typeId: 'downloads-installers' }, defs.byId.get('downloads-installers'));
    assert.ok(entry.sizeBytes >= 300 * 1024);
    assert.equal(entry.projectName, 'x.dmg');
  } finally {
    await removeTree(root);
  }
});

test('every nameFrom strategy, well-formed and malformed', async () => {
  const root = await makeTree({
    'js/package.json': '{"name":"@scope/js-app"}',
    'js/node_modules/': null,
    'badjs/package.json': '{not json',
    'badjs/node_modules/': null,
    'rs/Cargo.toml': '[dependencies]\nname = "wrong"\n\n[package]\nname = "rs-crate" # comment\nversion = "0.1.0"\n',
    'rs/target/': null,
    'badrs/Cargo.toml': '[package\nname=',
    'badrs/target/': null,
    'sw/Package.swift': '// swift-tools-version:5.9\nlet package = Package(\n    name: "SwiftThing",\n    targets: []\n)\n',
    'sw/.build/': null,
    'badsw/Package.swift': 'let package = Package()',
    'badsw/.build/': null,
    'gr/settings.gradle.kts': 'rootProject.name = "gradle-kts"\n',
    'gr/build/': null,
    'badgr/settings.gradle': 'include ":app"\n',
    'badgr/build/': null,
    'DerivedData/MyApp-abcdefghijkl/': null,
    'DerivedData/plain/': null,
    'Pods-parent/Pods/': null,
  });
  try {
    const cases = [
      ['js/node_modules', 'node', '@scope/js-app'],
      ['badjs/node_modules', 'node', 'badjs'],
      ['rs/target', 'rust', 'rs-crate'],
      ['badrs/target', 'rust', 'badrs'],
      ['sw/.build', 'swiftpm', 'SwiftThing'],
      ['badsw/.build', 'swiftpm', 'badsw'],
      ['gr/build', 'gradle', 'gradle-kts'],
      ['badgr/build', 'gradle', 'badgr'],
      ['DerivedData/MyApp-abcdefghijkl', 'xcode-derived', 'MyApp'],
      ['DerivedData/plain', 'xcode-derived', 'plain'],
      ['DerivedData/plain', 'xcode-device-support', 'plain'],
      ['Pods-parent/Pods', 'cocoapods', 'Pods-parent'],
      ['missing/node_modules', 'node', 'missing'],
    ];
    for (const [rel, typeId, expected] of cases) {
      const type = defs.byId.get(typeId);
      assert.equal(await projectName(path.join(root, rel), type), expected, `${rel} via ${type.nameFrom}`);
    }
  } finally {
    await removeTree(root);
  }
});

test('lastModified reflects a touched direct child', async () => {
  const old = Date.now() - 100 * DAY_MS;
  const root = await makeTree({
    'node_modules/a/x.js': { content: 'x', mtime: old },
    'node_modules/b.js': { content: 'y', mtime: old },
  });
  try {
    const nm = path.join(root, 'node_modules');
    await setMtime(path.join(nm, 'a'), old);
    await setMtime(nm, old);
    const before = await lastModified(nm);
    assert.ok(Math.abs(before.getTime() - old) < 2000, 'all old');

    const recent = Date.now() - DAY_MS;
    await setMtime(path.join(nm, 'b.js'), recent);
    const after = await lastModified(nm);
    assert.ok(Math.abs(after.getTime() - recent) < 2000, `expected ~${new Date(recent).toISOString()} got ${after.toISOString()}`);

    assert.equal(await lastModified(path.join(root, 'nope')), null);
    const fileTime = await lastModified(path.join(nm, 'b.js'));
    assert.ok(Math.abs(fileTime.getTime() - recent) < 2000);
  } finally {
    await removeTree(root);
  }
});

test('mapPool keeps order and never exceeds the limit', async () => {
  let inFlight = 0;
  let peak = 0;
  const out = await mapPool(Array.from({ length: 30 }, (_, i) => i), 8, async (n) => {
    inFlight++;
    peak = Math.max(peak, inFlight);
    await new Promise((r) => setTimeout(r, (n % 5) * 3));
    inFlight--;
    return n * 2;
  });
  assert.deepEqual(out, Array.from({ length: 30 }, (_, i) => i * 2));
  assert.ok(peak <= 8 && peak > 1, `peak ${peak}`);
  assert.deepEqual(await mapPool([], 8, async () => 1), []);
});

test('calculateSizes sorts largest first with unknown sizes last and reports progress', async () => {
  const root = await makeTree({
    'small/node_modules/a': { size: 4096 },
    'big/node_modules/a': { size: 512 * 1024 },
  });
  try {
    const calls = [];
    const entries = await calculateSizes([
      { path: path.join(root, 'small/node_modules'), typeId: 'node' },
      { path: path.join(root, 'gone/node_modules'), typeId: 'node' },
      { path: path.join(root, 'big/node_modules'), typeId: 'node' },
    ], { defs, onProgress: (d, t) => calls.push([d, t]) });
    assert.deepEqual(entries.map((e) => path.relative(root, e.path)), ['big/node_modules', 'small/node_modules', 'gone/node_modules']);
    assert.equal(entries[2].sizeUnknown, true);
    assert.deepEqual(calls.map((c) => c[1]), [3, 3, 3]);
    assert.deepEqual(calls.map((c) => c[0]).sort(), [1, 2, 3]);
  } finally {
    await removeTree(root);
  }
});
