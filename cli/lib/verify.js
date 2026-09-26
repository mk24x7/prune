// Delete-time safety checks. Every entry is re-verified immediately before it
// is trashed or removed, independent of how it was found.

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { resolveTypePath } from './definitions.js';

export class VerificationError extends Error {
  constructor(message, entryPath) {
    super(message);
    this.name = 'VerificationError';
    this.code = 'verification';
    this.path = entryPath;
  }
}

function fail(p, message) {
  throw new VerificationError(`Refusing to delete ${p}: ${message}`, p);
}

async function lexists(p) {
  try {
    await fs.lstat(p);
    return true;
  } catch {
    return false;
  }
}

/**
 * Verify one entry against its type.
 * @param {{path: string, typeId: string}} entry
 * @param {object} type artifact type from the definitions
 * @param {{scanRoot?: string, defs?: object, env?: object, home?: string}} context
 * @throws {VerificationError} with code 'verification'
 */
export async function verifyEntry(entry, type, { scanRoot, defs, env, home } = {}) {
  const raw = entry?.path;
  if (typeof raw !== 'string' || !path.isAbsolute(raw)) fail(String(raw), 'path is not absolute');
  if (!type) fail(raw, `unknown type "${entry.typeId}"`);
  if (entry.typeId !== undefined && entry.typeId !== type.id) fail(raw, `type mismatch (${entry.typeId} vs ${type.id})`);

  const effEnv = env ?? defs?.env ?? process.env;
  const effHome = path.resolve(home ?? defs?.home ?? os.homedir());
  const p = path.resolve(raw);
  if (p !== (raw.length > 1 ? raw.replace(/\/+$/, '') : raw)) fail(raw, 'path is not normalized');

  const components = p.split(path.sep).filter(Boolean);
  if (components.length <= 2) fail(p, 'path is too close to the file system root');
  if (p === '/' || p === effHome) fail(p, 'path is the file system root or the home directory');

  let st;
  try {
    st = await fs.lstat(p);
  } catch (err) {
    fail(p, `cannot stat (${err.code ?? err.message})`);
  }
  if (st.isSymbolicLink()) fail(p, 'path is a symbolic link');
  const expectsFile = type.kind === 'files' || type.isFile === true;
  if (expectsFile ? !st.isFile() : !st.isDirectory()) {
    fail(p, expectsFile ? 'expected a regular file' : 'expected a directory');
  }

  if (type.kind === 'project') {
    const base = path.basename(p);
    if (!type.targets.includes(base)) fail(p, `"${base}" is not a ${type.displayName} target`);
    if (!scanRoot) fail(p, 'no scan root to check containment');
    let realRoot;
    let realPath;
    try {
      realRoot = await fs.realpath(scanRoot);
      realPath = await fs.realpath(p);
    } catch (err) {
      fail(p, `cannot resolve real path (${err.code ?? err.message})`);
    }
    if (!realPath.startsWith(realRoot.endsWith(path.sep) ? realRoot : realRoot + path.sep)) {
      fail(p, `not inside the scan root ${scanRoot}`);
    }
    if (type.siblings.length > 0) {
      const parent = path.dirname(p);
      let any = false;
      for (const s of type.siblings) {
        if (await lexists(path.join(parent, s))) {
          any = true;
          break;
        }
      }
      if (!any) fail(p, `none of the marker files (${type.siblings.join(', ')}) exist next to it`);
    }
    return;
  }

  const resolved = (env === undefined && home === undefined && defs?.resolveSystemPath)
    ? defs.resolveSystemPath(type)
    : resolveTypePath(type, { env: effEnv, home: effHome });
  if (type.kind === 'system') {
    if (p === resolved) return;
    if (type.expand && path.dirname(p) === resolved) return;
    fail(p, `not the ${type.displayName} location (${resolved})`);
  }

  if (type.kind === 'files') {
    if (path.dirname(p) !== resolved) fail(p, `not directly inside ${resolved}`);
    const ext = path.extname(p).toLowerCase();
    if (!type.extensions.some((e) => e.toLowerCase() === ext)) fail(p, `extension "${ext}" is not one of ${type.extensions.join(', ')}`);
    return;
  }

  fail(p, `unsupported kind "${type.kind}"`);
}
