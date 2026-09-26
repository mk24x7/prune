#!/usr/bin/env node
// Validate Definitions/artifacts.json. Zero dependencies, Node 20+.
//
// Two layers of checks run:
//
// 1. Schema validation against Definitions/artifacts.schema.json using a small
//    hand-written JSON Schema interpreter. It implements only the draft 2020-12
//    keywords that artifacts.schema.json actually uses (type, const, enum,
//    pattern, minLength, minimum, maximum, minItems, uniqueItems, items,
//    properties, required, additionalProperties, $ref to local $defs, allOf,
//    anyOf, not, if/then). Any other keyword found in the schema is reported as
//    an error, so the schema cannot silently outgrow this validator. It is not a
//    general-purpose JSON Schema implementation.
//
// 2. Semantic rules the schema cannot express: unique ids, colors drawn from the
//    document's own palette, regenerable false implies defaultEnabled false,
//    pure-ASCII files, non-empty project targets, nameFrom strategies valid for
//    the kind, no ".." path segments, isFile/readOnlyTree only on system types,
//    and a warning for target names shared by project types with identical
//    sibling lists (the second one could never match).
//
// Usage: node Definitions/validate.mjs [path/to/artifacts.json]
// Exit code 0 on success, 1 on any error.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const dataPath = path.resolve(process.argv[2] ?? path.join(here, 'artifacts.json'));
const schemaPath = path.join(here, 'artifacts.schema.json');

const errors = [];
const warnings = [];

function readJson(file) {
  const bytes = fs.readFileSync(file);
  for (let i = 0; i < bytes.length; i++) {
    if (bytes[i] > 0x7f) {
      const line = bytes.subarray(0, i).toString('latin1').split('\n').length;
      errors.push(`${path.basename(file)}: non-ASCII byte 0x${bytes[i].toString(16)} at offset ${i} (line ${line})`);
      break;
    }
  }
  try {
    return JSON.parse(bytes.toString('utf8'));
  } catch (err) {
    errors.push(`${path.basename(file)}: invalid JSON: ${err.message}`);
    return undefined;
  }
}

// ---------------------------------------------------------------------------
// Minimal JSON Schema interpreter (subset, see header).

const SUPPORTED = new Set([
  '$schema', '$id', '$defs', '$ref', '$comment', 'title', 'description',
  'type', 'const', 'enum', 'pattern', 'minLength', 'minimum', 'maximum',
  'minItems', 'uniqueItems', 'items', 'properties', 'required',
  'additionalProperties', 'allOf', 'anyOf', 'not', 'if', 'then',
]);

function typeOf(v) {
  if (v === null) return 'null';
  if (Array.isArray(v)) return 'array';
  if (Number.isInteger(v)) return 'integer';
  return typeof v;
}

function typeMatches(expected, value) {
  const actual = typeOf(value);
  if (expected === 'number') return actual === 'number' || actual === 'integer';
  return expected === actual;
}

function resolveRef(root, ref) {
  if (!ref.startsWith('#/')) throw new Error(`unsupported $ref ${ref}`);
  let node = root;
  for (const part of ref.slice(2).split('/')) {
    node = node?.[part.replace(/~1/g, '/').replace(/~0/g, '~')];
  }
  if (node === undefined) throw new Error(`unresolvable $ref ${ref}`);
  return node;
}

// Returns a list of error strings; empty means valid.
function check(root, schema, value, at) {
  if (schema === true) return [];
  if (schema === false) return [`${at}: not allowed`];
  const out = [];
  for (const key of Object.keys(schema)) {
    if (!SUPPORTED.has(key)) out.push(`schema keyword "${key}" is not supported by validate.mjs`);
  }
  if (schema.$ref) out.push(...check(root, resolveRef(root, schema.$ref), value, at));
  if (schema.type !== undefined) {
    const types = Array.isArray(schema.type) ? schema.type : [schema.type];
    if (!types.some((t) => typeMatches(t, value))) {
      out.push(`${at}: expected ${types.join(' or ')}, got ${typeOf(value)}`);
      return out;
    }
  }
  if ('const' in schema && JSON.stringify(schema.const) !== JSON.stringify(value)) {
    out.push(`${at}: must equal ${JSON.stringify(schema.const)}`);
  }
  if (schema.enum && !schema.enum.some((e) => JSON.stringify(e) === JSON.stringify(value))) {
    out.push(`${at}: ${JSON.stringify(value)} is not one of ${schema.enum.join(', ')}`);
  }
  if (typeof value === 'string') {
    if (schema.minLength !== undefined && value.length < schema.minLength) {
      out.push(`${at}: shorter than ${schema.minLength}`);
    }
    if (schema.pattern !== undefined && !new RegExp(schema.pattern, 'u').test(value)) {
      out.push(`${at}: ${JSON.stringify(value)} does not match /${schema.pattern}/`);
    }
  }
  if (typeof value === 'number') {
    if (schema.minimum !== undefined && value < schema.minimum) out.push(`${at}: below ${schema.minimum}`);
    if (schema.maximum !== undefined && value > schema.maximum) out.push(`${at}: above ${schema.maximum}`);
  }
  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) {
      out.push(`${at}: needs at least ${schema.minItems} item(s)`);
    }
    if (schema.uniqueItems) {
      const seen = new Set();
      for (const item of value) {
        const k = JSON.stringify(item);
        if (seen.has(k)) out.push(`${at}: duplicate item ${k}`);
        seen.add(k);
      }
    }
    if (schema.items !== undefined) {
      value.forEach((item, i) => out.push(...check(root, schema.items, item, `${at}[${i}]`)));
    }
  }
  if (typeOf(value) === 'object') {
    for (const req of schema.required ?? []) {
      if (!(req in value)) out.push(`${at}: missing required property "${req}"`);
    }
    const props = schema.properties ?? {};
    for (const [k, v] of Object.entries(value)) {
      if (k in props) out.push(...check(root, props[k], v, `${at}.${k}`));
      else if (schema.additionalProperties === false) out.push(`${at}: unknown property "${k}"`);
      else if (typeof schema.additionalProperties === 'object') {
        out.push(...check(root, schema.additionalProperties, v, `${at}.${k}`));
      }
    }
  }
  for (const sub of schema.allOf ?? []) out.push(...check(root, sub, value, at));
  if (schema.anyOf && !schema.anyOf.some((sub) => check(root, sub, value, at).length === 0)) {
    out.push(`${at}: does not match any allowed alternative`);
  }
  if (schema.not !== undefined && check(root, schema.not, value, at).length === 0) {
    out.push(`${at}: matches a forbidden shape (${describeNot(schema.not)})`);
  }
  if (schema.if !== undefined && check(root, schema.if, value, at).length === 0 && schema.then !== undefined) {
    out.push(...check(root, schema.then, value, at));
  }
  return out;
}

function describeNot(sub) {
  const alts = sub.anyOf ?? [sub];
  const keys = alts.flatMap((a) => a.required ?? []);
  return keys.length ? `must not have: ${keys.join(', ')}` : 'see schema';
}

// ---------------------------------------------------------------------------
// Semantic rules.

const PROJECT_NAME_FROM = new Set(['packageJson', 'cargoToml', 'packageSwift', 'gradleSettings', 'parentDirname']);
const SYSTEM_NAME_FROM = new Set(['derivedData', 'dirname']);
const FILES_NAME_FROM = new Set(['dirname']);

function semanticChecks(doc) {
  if (!doc || !Array.isArray(doc.types)) return;
  const palette = new Set(Array.isArray(doc.colors) ? doc.colors : []);
  const ids = new Map();

  doc.types.forEach((t, i) => {
    const where = `types[${i}]${t?.id ? ` (${t.id})` : ''}`;
    if (!t || typeof t !== 'object') return;

    if (ids.has(t.id)) errors.push(`${where}: duplicate id, first used at types[${ids.get(t.id)}]`);
    else ids.set(t.id, i);

    if (!palette.has(t.color)) errors.push(`${where}: color "${t.color}" is not in the top-level colors palette`);

    if (t.regenerable === false && t.defaultEnabled !== false) {
      errors.push(`${where}: regenerable is false so defaultEnabled must be false`);
    }

    const allowedNameFrom = t.kind === 'project' ? PROJECT_NAME_FROM
      : t.kind === 'system' ? SYSTEM_NAME_FROM
        : FILES_NAME_FROM;
    if (!allowedNameFrom.has(t.nameFrom)) {
      errors.push(`${where}: nameFrom "${t.nameFrom}" is not valid for kind "${t.kind}"`);
    }

    if (t.kind === 'project') {
      if (!Array.isArray(t.targets) || t.targets.length === 0) errors.push(`${where}: project type needs non-empty targets`);
      for (const name of [...(t.targets ?? []), ...(t.siblings ?? [])]) {
        if (name === '.' || name === '..' || name.includes('/')) errors.push(`${where}: invalid file name "${name}"`);
      }
    } else {
      if (typeof t.path === 'string') {
        if (t.path.split('/').includes('..')) errors.push(`${where}: path must not contain ".." segments`);
        if (t.path === '~/' || t.path.endsWith('/')) errors.push(`${where}: path must name a directory or file below home without a trailing slash`);
      }
      for (const o of t.pathOverrides ?? []) {
        if (typeof o.append === 'string' && o.append.split('/').includes('..')) {
          errors.push(`${where}: pathOverrides append "${o.append}" must not contain ".." segments`);
        }
      }
    }
    if (t.kind !== 'system' && ('isFile' in t || 'readOnlyTree' in t)) {
      errors.push(`${where}: isFile and readOnlyTree are only valid on system types`);
    }
    if (t.isFile === true && t.expand === true) errors.push(`${where}: a file cannot be expanded`);
  });

  // Same target name in two project types is fine when sibling markers
  // disambiguate them; identical sibling lists mean the second never matches.
  const projects = doc.types.filter((t) => t?.kind === 'project');
  for (let a = 0; a < projects.length; a++) {
    for (let b = a + 1; b < projects.length; b++) {
      const shared = (projects[a].targets ?? []).filter((n) => (projects[b].targets ?? []).includes(n));
      const sa = JSON.stringify([...(projects[a].siblings ?? [])].sort());
      const sb = JSON.stringify([...(projects[b].siblings ?? [])].sort());
      if (shared.length && sa === sb) {
        warnings.push(`${projects[a].id} and ${projects[b].id} share target(s) ${shared.join(', ')} with identical siblings`);
      }
    }
  }
}

// ---------------------------------------------------------------------------

const schema = readJson(schemaPath);
const doc = readJson(dataPath);

if (schema && doc) {
  try {
    const schemaErrors = check(schema, schema, doc, '$');
    errors.push(...new Set(schemaErrors));
  } catch (err) {
    errors.push(`schema: ${err.message}`);
  }
  const schemaColors = schema.$defs?.color?.enum ?? [];
  if (JSON.stringify(schemaColors) !== JSON.stringify(doc.colors)) {
    errors.push('colors: top-level palette in artifacts.json differs from the schema color enum');
  }
}
semanticChecks(doc);

for (const w of warnings) console.warn(`warning: ${w}`);

if (errors.length) {
  console.error(`artifacts.json is invalid (${errors.length} error(s)):`);
  for (const e of errors) console.error(`  - ${e}`);
  process.exit(1);
}

const counts = { project: 0, system: 0, files: 0 };
for (const t of doc.types) counts[t.kind]++;
console.log(
  `artifacts.json OK: ${doc.types.length} types (${counts.project} project, ${counts.system} system, ${counts.files} files)`,
);
