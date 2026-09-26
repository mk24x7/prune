// Loader and validator for the shared artifact definitions
// (Definitions/artifacts.json). The same file is consumed by the macOS app.
//
// validateDefinitions() mirrors Definitions/validate.mjs: structural checks
// that the JSON Schema expresses (required and forbidden fields per kind, no
// unknown keys, value types, enums, patterns) plus the semantic rules (unique
// ids, colors from the palette, regenerable false implies defaultEnabled false,
// non-empty project targets, nameFrom valid for the kind, no ".." segments).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

// Repo checkout: cli/lib -> ../../Definitions/artifacts.json.
// npm tarball: prepack copies the JSON next to package.json (cli/artifacts.json).
export const DEFINITIONS_CANDIDATES = [
  path.resolve(here, '../../Definitions/artifacts.json'),
  path.resolve(here, '../artifacts.json'),
];

export function definitionsPath() {
  for (const candidate of DEFINITIONS_CANDIDATES) {
    if (fs.existsSync(candidate)) return candidate;
  }
  throw new Error(`artifacts.json not found (looked in ${DEFINITIONS_CANDIDATES.join(', ')})`);
}

const TOP_KEYS = ['version', 'scan', 'colors', 'types'];
const SCAN_KEYS = ['maxDepth', 'skipUnderHome', 'skipAnywhere', 'skipPackageExtensions'];
const KINDS = ['project', 'system', 'files'];
const NAME_FROM = ['packageJson', 'cargoToml', 'packageSwift', 'gradleSettings', 'derivedData', 'dirname', 'parentDirname'];
const NAME_FROM_BY_KIND = {
  project: ['packageJson', 'cargoToml', 'packageSwift', 'gradleSettings', 'parentDirname'],
  system: ['derivedData', 'dirname'],
  files: ['dirname'],
};
const COMMON_REQUIRED = [
  'id', 'kind', 'displayName', 'description', 'nameFrom',
  'defaultEnabled', 'regenerable', 'reinstallHint', 'color', 'icon',
];
// Kind-specific keys: required, optional; every other kind-specific key is forbidden.
const KIND_KEYS = {
  project: { required: ['targets', 'siblings'], optional: [] },
  system: { required: ['path', 'expand', 'pathOverrides', 'readOnlyTree'], optional: ['isFile'] },
  files: { required: ['path', 'extensions'], optional: ['pathOverrides'] },
};
const ALL_KIND_KEYS = ['targets', 'siblings', 'path', 'pathOverrides', 'expand', 'readOnlyTree', 'isFile', 'extensions'];
const KNOWN_TYPE_KEYS = new Set([...COMMON_REQUIRED, ...ALL_KIND_KEYS]);

const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const isNonEmptyString = (v) => typeof v === 'string' && v.length > 0;
const EXT_RE = /^\.[A-Za-z0-9]+$/;
const ENV_RE = /^[A-Za-z_][A-Za-z0-9_]*$/;
const APPEND_RE = /^[^/~].*[^/]$|^[^/~]$/;

function checkNameList(value, where, errors, { minItems = 0 } = {}) {
  if (!Array.isArray(value)) {
    errors.push(`${where}: must be an array of names`);
    return;
  }
  if (value.length < minItems) errors.push(`${where}: needs at least ${minItems} item(s)`);
  const seen = new Set();
  for (const name of value) {
    if (!isNonEmptyString(name) || name.includes('/')) {
      errors.push(`${where}: invalid name ${JSON.stringify(name)}`);
      continue;
    }
    if (seen.has(name)) errors.push(`${where}: duplicate item "${name}"`);
    seen.add(name);
  }
}

function checkExtensions(value, where, errors, { minItems = 0 } = {}) {
  if (!Array.isArray(value)) {
    errors.push(`${where}: must be an array of extensions`);
    return;
  }
  if (value.length < minItems) errors.push(`${where}: needs at least ${minItems} item(s)`);
  const seen = new Set();
  for (const ext of value) {
    if (typeof ext !== 'string' || !EXT_RE.test(ext)) {
      errors.push(`${where}: invalid extension ${JSON.stringify(ext)} (expected like ".app")`);
      continue;
    }
    if (seen.has(ext)) errors.push(`${where}: duplicate item "${ext}"`);
    seen.add(ext);
  }
}

function checkScan(scan, errors) {
  if (!isObject(scan)) {
    errors.push('scan: must be an object');
    return;
  }
  for (const key of SCAN_KEYS) {
    if (!(key in scan)) errors.push(`scan: missing required field "${key}"`);
  }
  for (const key of Object.keys(scan)) {
    if (!SCAN_KEYS.includes(key)) errors.push(`scan: unknown field "${key}"`);
  }
  if ('maxDepth' in scan && !(Number.isInteger(scan.maxDepth) && scan.maxDepth >= 1 && scan.maxDepth <= 64)) {
    errors.push('scan.maxDepth: must be an integer between 1 and 64');
  }
  if ('skipUnderHome' in scan) checkNameList(scan.skipUnderHome, 'scan.skipUnderHome', errors);
  if ('skipAnywhere' in scan) checkNameList(scan.skipAnywhere, 'scan.skipAnywhere', errors);
  if ('skipPackageExtensions' in scan) checkExtensions(scan.skipPackageExtensions, 'scan.skipPackageExtensions', errors);
}

function checkType(t, i, palette, ids, errors) {
  if (!isObject(t)) {
    errors.push(`types[${i}]: must be an object`);
    return;
  }
  const where = `types[${i}]${typeof t.id === 'string' ? ` (${t.id})` : ''}`;

  for (const key of Object.keys(t)) {
    if (!KNOWN_TYPE_KEYS.has(key)) errors.push(`${where}: unknown field "${key}"`);
  }
  for (const key of COMMON_REQUIRED) {
    if (!(key in t)) errors.push(`${where}: missing required field "${key}"`);
  }

  if ('id' in t) {
    if (typeof t.id !== 'string' || !/^[a-z0-9-]+$/.test(t.id)) {
      errors.push(`${where}: id must match ^[a-z0-9-]+$`);
    } else if (ids.has(t.id)) {
      errors.push(`${where}: duplicate id, first used at types[${ids.get(t.id)}]`);
    } else {
      ids.set(t.id, i);
    }
  }
  for (const key of ['displayName', 'description', 'reinstallHint', 'icon']) {
    if (key in t && !isNonEmptyString(t[key])) errors.push(`${where}: ${key} must be a non-empty string`);
  }
  for (const key of ['defaultEnabled', 'regenerable', 'expand', 'readOnlyTree', 'isFile']) {
    if (key in t && typeof t[key] !== 'boolean') errors.push(`${where}: ${key} must be a boolean`);
  }
  if ('color' in t && !palette.has(t.color)) {
    errors.push(`${where}: color "${t.color}" is not in the top-level colors palette`);
  }
  if (t.regenerable === false && t.defaultEnabled !== false) {
    errors.push(`${where}: regenerable is false so defaultEnabled must be false`);
  }

  if ('nameFrom' in t && !NAME_FROM.includes(t.nameFrom)) {
    errors.push(`${where}: nameFrom "${t.nameFrom}" is not one of ${NAME_FROM.join(', ')}`);
  }

  if (!KINDS.includes(t.kind)) {
    if ('kind' in t) errors.push(`${where}: kind "${t.kind}" is not one of ${KINDS.join(', ')}`);
    return;
  }

  if (NAME_FROM.includes(t.nameFrom) && !NAME_FROM_BY_KIND[t.kind].includes(t.nameFrom)) {
    errors.push(`${where}: nameFrom "${t.nameFrom}" is not valid for kind "${t.kind}"`);
  }

  const spec = KIND_KEYS[t.kind];
  for (const key of spec.required) {
    if (!(key in t)) errors.push(`${where}: missing required field "${key}" for kind "${t.kind}"`);
  }
  for (const key of ALL_KIND_KEYS) {
    if (key in t && !spec.required.includes(key) && !spec.optional.includes(key)) {
      errors.push(`${where}: field "${key}" is not allowed for kind "${t.kind}"`);
    }
  }

  if (t.kind === 'project') {
    if ('targets' in t) {
      if (Array.isArray(t.targets) && t.targets.length === 0) {
        errors.push(`${where}: project type needs non-empty targets`);
      } else {
        checkNameList(t.targets, `${where}.targets`, errors);
      }
    }
    if ('siblings' in t) checkNameList(t.siblings, `${where}.siblings`, errors);
    for (const name of [...(Array.isArray(t.targets) ? t.targets : []), ...(Array.isArray(t.siblings) ? t.siblings : [])]) {
      if (name === '.' || name === '..') errors.push(`${where}: invalid file name "${name}"`);
    }
    return;
  }

  // system and files
  if ('path' in t) {
    if (typeof t.path !== 'string' || !t.path.startsWith('~/')) {
      errors.push(`${where}: path must be a string starting with "~/"`);
    } else {
      if (t.path.split('/').includes('..')) errors.push(`${where}: path must not contain ".." segments`);
      if (t.path === '~/' || t.path.endsWith('/')) {
        errors.push(`${where}: path must name a directory or file below home without a trailing slash`);
      }
    }
  }
  if ('pathOverrides' in t) {
    if (!Array.isArray(t.pathOverrides)) {
      errors.push(`${where}: pathOverrides must be an array`);
    } else {
      t.pathOverrides.forEach((o, j) => {
        const ow = `${where}.pathOverrides[${j}]`;
        if (!isObject(o)) {
          errors.push(`${ow}: must be an object`);
          return;
        }
        for (const key of Object.keys(o)) {
          if (key !== 'env' && key !== 'append') errors.push(`${ow}: unknown field "${key}"`);
        }
        if (typeof o.env !== 'string' || !ENV_RE.test(o.env)) errors.push(`${ow}: env must be an environment variable name`);
        if ('append' in o) {
          if (typeof o.append !== 'string' || !APPEND_RE.test(o.append)) {
            errors.push(`${ow}: append must be a relative path without leading or trailing slash`);
          } else if (o.append.split('/').includes('..')) {
            errors.push(`${where}: pathOverrides append "${o.append}" must not contain ".." segments`);
          }
        }
      });
    }
  }
  if (t.kind === 'files' && 'extensions' in t) checkExtensions(t.extensions, `${where}.extensions`, errors, { minItems: 1 });
  if (t.isFile === true && t.expand === true) errors.push(`${where}: a file cannot be expanded`);
}

/**
 * Validate a parsed artifacts.json document.
 * @param {unknown} raw
 * @returns {string[]} error messages; empty when valid
 */
export function validateDefinitions(raw) {
  const errors = [];
  if (!isObject(raw)) return ['document: must be a JSON object'];

  for (const key of TOP_KEYS) {
    if (!(key in raw)) errors.push(`document: missing required field "${key}"`);
  }
  for (const key of Object.keys(raw)) {
    if (!TOP_KEYS.includes(key)) errors.push(`document: unknown field "${key}"`);
  }
  if ('version' in raw && raw.version !== 1) errors.push('version: must equal 1');
  if ('scan' in raw) checkScan(raw.scan, errors);

  let palette = new Set();
  if ('colors' in raw) {
    if (!Array.isArray(raw.colors) || raw.colors.length === 0) {
      errors.push('colors: must be a non-empty array');
    } else {
      palette = new Set(raw.colors);
      if (palette.size !== raw.colors.length) errors.push('colors: duplicate palette entry');
    }
  }

  if ('types' in raw) {
    if (!Array.isArray(raw.types) || raw.types.length === 0) {
      errors.push('types: must be a non-empty array');
    } else {
      const ids = new Map();
      raw.types.forEach((t, i) => checkType(t, i, palette, ids, errors));
    }
  }
  return errors;
}

export class DefinitionsError extends Error {
  constructor(file, errors) {
    super(`${file} is invalid:\n  - ${errors.join('\n  - ')}`);
    this.name = 'DefinitionsError';
    this.errors = errors;
  }
}

/**
 * Resolve a system or files type path.
 * The first pathOverrides entry whose env var is set and non-empty wins
 * (append joined if present); otherwise the leading "~/" becomes home.
 */
export function resolveTypePath(type, { env = process.env, home = os.homedir() } = {}) {
  for (const o of type.pathOverrides ?? []) {
    const value = env[o.env];
    if (typeof value === 'string' && value !== '') {
      return path.resolve(o.append ? path.join(value, o.append) : value);
    }
  }
  return path.join(home, type.path.slice(2));
}

/**
 * Load and validate the shared definitions.
 * @param {{env?: object, home?: string, raw?: object, file?: string}} [options]
 */
export function loadDefinitions({ env = process.env, home = os.homedir(), raw, file } = {}) {
  let source = file;
  let doc = raw;
  if (doc === undefined) {
    source = file ?? definitionsPath();
    doc = JSON.parse(fs.readFileSync(source, 'utf8'));
  }
  const errors = validateDefinitions(doc);
  if (errors.length) throw new DefinitionsError(source ?? 'artifacts.json', errors);

  const types = doc.types;
  const byId = new Map(types.map((t) => [t.id, t]));
  return {
    version: doc.version,
    scan: doc.scan,
    colors: doc.colors,
    types,
    byId,
    projectTypes: types.filter((t) => t.kind === 'project'),
    systemTypes: types.filter((t) => t.kind === 'system'),
    filesTypes: types.filter((t) => t.kind === 'files'),
    defaultEnabledIds: types.filter((t) => t.defaultEnabled).map((t) => t.id),
    home,
    env,
    resolveSystemPath: (type) => resolveTypePath(type, { env, home }),
  };
}
