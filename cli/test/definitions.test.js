import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  loadDefinitions,
  validateDefinitions,
  definitionsPath,
  DefinitionsError,
} from '../lib/definitions.js';

const raw = JSON.parse(fs.readFileSync(definitionsPath(), 'utf8'));
const clone = () => structuredClone(raw);
const typeIndex = (doc, id) => doc.types.findIndex((t) => t.id === id);

test('bundled definitions validate and have the pinned type count', () => {
  assert.deepEqual(validateDefinitions(raw), []);
  const defs = loadDefinitions({ env: {}, home: '/Users/fixture' });
  // Pinned: guards against accidental deletions or additions.
  assert.equal(defs.types.length, 47);
  assert.equal(defs.projectTypes.length + defs.systemTypes.length + defs.filesTypes.length, 47);
  assert.equal(new Set(defs.types.map((t) => t.id)).size, 47);
  assert.equal(defs.byId.get('node').kind, 'project');
  assert.equal(defs.version, 1);
  assert.ok(defs.scan.maxDepth >= 1);
});

test('vite is gone', () => {
  const defs = loadDefinitions({ env: {} });
  assert.equal(defs.byId.has('vite'), false);
  assert.ok(!defs.types.some((t) => (t.targets ?? []).includes('.vite')));
});

test('non-regenerable user data types are off by default', () => {
  const defs = loadDefinitions({ env: {} });
  for (const id of ['xcode-archives', 'android-avd', 'ios-device-backups']) {
    const t = defs.byId.get(id);
    assert.ok(t, id);
    assert.equal(t.regenerable, false, id);
    assert.equal(t.defaultEnabled, false, id);
    assert.ok(!defs.defaultEnabledIds.includes(id), id);
  }
  assert.ok(defs.defaultEnabledIds.includes('node'));
});

test('resolveSystemPath honours GOMODCACHE, then GOPATH + pkg/mod, then default', () => {
  const home = '/Users/fixture';
  const go = (env) => loadDefinitions({ env, home }).resolveSystemPath(loadDefinitions({ env, home }).byId.get('go-mod-cache'));
  assert.equal(go({ GOMODCACHE: '/custom/mod', GOPATH: '/gp' }), '/custom/mod');
  assert.equal(go({ GOMODCACHE: '', GOPATH: '/gp' }), '/gp/pkg/mod');
  assert.equal(go({ GOPATH: '/gp' }), '/gp/pkg/mod');
  assert.equal(go({}), path.join(home, 'go/pkg/mod'));
});

test('resolveSystemPath expands ~/ for types without overrides', () => {
  const defs = loadDefinitions({ env: {}, home: '/h' });
  assert.equal(defs.resolveSystemPath(defs.byId.get('xcode-derived')), '/h/Library/Developer/Xcode/DerivedData');
  assert.equal(defs.resolveSystemPath(defs.byId.get('downloads-installers')), '/h/Downloads');
});

test('loadDefinitions throws DefinitionsError on invalid input', () => {
  const doc = clone();
  doc.types[0].color = 'magenta';
  assert.throws(() => loadDefinitions({ raw: doc }), DefinitionsError);
});

const mutations = [
  ['duplicate id', (d) => { d.types[1].id = d.types[0].id; }, /duplicate id/],
  ['color outside palette', (d) => { d.types[0].color = 'magenta'; }, /color "magenta" is not in the top-level colors palette/],
  ['regenerable false but default on', (d) => { d.types[0].regenerable = false; }, /regenerable is false so defaultEnabled must be false/],
  ['unknown type key', (d) => { d.types[0].bogus = 1; }, /unknown field "bogus"/],
  ['unknown top-level key', (d) => { d.extra = true; }, /document: unknown field "extra"/],
  ['unknown scan key', (d) => { d.scan.depth = 3; }, /scan: unknown field "depth"/],
  ['empty targets', (d) => { d.types[typeIndex(d, 'node')].targets = []; }, /project type needs non-empty targets/],
  ['missing common field', (d) => { delete d.types[0].displayName; }, /missing required field "displayName"/],
  ['project missing siblings', (d) => { delete d.types[typeIndex(d, 'node')].siblings; }, /missing required field "siblings" for kind "project"/],
  ['project with path', (d) => { d.types[typeIndex(d, 'node')].path = '~/x'; }, /field "path" is not allowed for kind "project"/],
  ['system missing expand', (d) => { delete d.types[typeIndex(d, 'npm-cache')].expand; }, /missing required field "expand" for kind "system"/],
  ['system with targets', (d) => { d.types[typeIndex(d, 'npm-cache')].targets = ['x']; }, /field "targets" is not allowed for kind "system"/],
  ['files with expand', (d) => { d.types[typeIndex(d, 'downloads-installers')].expand = true; }, /field "expand" is not allowed for kind "files"/],
  ['files missing extensions', (d) => { delete d.types[typeIndex(d, 'downloads-installers')].extensions; }, /missing required field "extensions" for kind "files"/],
  ['bad kind', (d) => { d.types[0].kind = 'weird'; }, /kind "weird" is not one of/],
  ['nameFrom invalid for kind', (d) => { d.types[typeIndex(d, 'npm-cache')].nameFrom = 'packageJson'; }, /nameFrom "packageJson" is not valid for kind "system"/],
  ['path without ~/', (d) => { d.types[typeIndex(d, 'npm-cache')].path = '/etc'; }, /path must be a string starting with "~\/"/],
  ['path with ..', (d) => { d.types[typeIndex(d, 'npm-cache')].path = '~/../etc'; }, /must not contain "\.\." segments/],
  ['override with unknown key', (d) => { d.types[typeIndex(d, 'npm-cache')].pathOverrides = [{ env: 'X', foo: 1 }]; }, /pathOverrides\[0\]: unknown field "foo"/],
  ['id pattern', (d) => { d.types[0].id = 'Node_JS'; }, /id must match/],
  ['version', (d) => { d.version = 2; }, /version: must equal 1/],
  ['isFile expanded', (d) => { d.types[typeIndex(d, 'docker-disk-image')].expand = true; }, /a file cannot be expanded/],
  ['empty types', (d) => { d.types = []; }, /types: must be a non-empty array/],
];

for (const [name, mutate, expected] of mutations) {
  test(`validateDefinitions reports: ${name}`, () => {
    const doc = clone();
    mutate(doc);
    const errors = validateDefinitions(doc);
    assert.ok(errors.some((e) => expected.test(e)), `expected ${expected} in:\n${errors.join('\n')}`);
  });
}
