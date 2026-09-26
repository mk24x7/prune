// Test fixture builder: turns a spec map into a real directory tree under a
// fresh fs.mkdtemp directory.
//
// Spec keys are paths relative to the root. Values:
//   'text' or Buffer        regular file with that content
//   null or {}              directory (a key ending in "/" also means directory)
//   { symlink: 'target' }   symbolic link (target used verbatim)
//   { size: n }             file with n random bytes
//   { content, mode, mtime } file with optional chmod and mtime (Date or ms)
//   { dir: true, mode, mtime } directory with optional chmod and mtime
// Parent directories are created automatically. Modes and mtimes are applied
// after everything is created (deepest first) so they are not disturbed.

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';

export async function makeTree(spec = {}, { prefix = 'prune-test-' } = {}) {
  const root = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), prefix)));
  await addToTree(root, spec);
  return root;
}

export async function addToTree(root, spec) {
  const deferred = [];
  for (const [rel, value] of Object.entries(spec)) {
    const full = path.join(root, rel);
    const isDir = rel.endsWith('/') || value === null || (typeof value === 'object' && !Buffer.isBuffer(value)
      && (value.dir === true || Object.keys(value).length === 0));
    if (isDir) {
      await fs.mkdir(full, { recursive: true });
    } else if (value && typeof value === 'object' && !Buffer.isBuffer(value) && 'symlink' in value) {
      await fs.mkdir(path.dirname(full), { recursive: true });
      await fs.symlink(value.symlink, full);
      continue;
    } else {
      await fs.mkdir(path.dirname(full), { recursive: true });
      let content = value;
      if (value && typeof value === 'object' && !Buffer.isBuffer(value)) {
        content = 'size' in value ? crypto.randomBytes(value.size) : (value.content ?? '');
      }
      await fs.writeFile(full, content);
    }
    if (value && typeof value === 'object' && !Buffer.isBuffer(value) && ('mode' in value || 'mtime' in value)) {
      deferred.push({ full, mode: value.mode, mtime: value.mtime });
    }
  }
  deferred.sort((a, b) => b.full.length - a.full.length);
  for (const { full, mtime } of deferred) {
    if (mtime !== undefined) await fs.utimes(full, new Date(mtime), new Date(mtime));
  }
  for (const { full, mode } of deferred) {
    if (mode !== undefined) await fs.chmod(full, mode);
  }
  return root;
}

// Remove a fixture, restoring permissions first so 000/0555 trees go away.
export async function removeTree(root) {
  if (!root) return;
  await makeOwnerAccessible(root);
  await fs.rm(root, { recursive: true, force: true });
}

async function makeOwnerAccessible(p) {
  let st;
  try {
    st = await fs.lstat(p);
  } catch {
    return;
  }
  if (st.isSymbolicLink()) return;
  if (st.isDirectory()) {
    await fs.chmod(p, (st.mode & 0o7777) | 0o700).catch(() => {});
    const names = await fs.readdir(p).catch(() => []);
    for (const name of names) await makeOwnerAccessible(path.join(p, name));
  } else {
    await fs.chmod(p, (st.mode & 0o7777) | 0o600).catch(() => {});
  }
}

// Set mtime on a path (Date or ms), without touching atime semantics.
export async function setMtime(p, when) {
  const d = new Date(when);
  await fs.utimes(p, d, d);
}

export const DAY_MS = 24 * 60 * 60 * 1000;
