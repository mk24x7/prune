// Delete verified entries, either to the Trash (default) or permanently.
// Sequential on purpose: large parallel removals thrash the disk and make
// progress reporting and the log harder to follow.

import fs from 'node:fs/promises';
import path from 'node:path';
import { verifyEntry } from './verify.js';
import { trashPaths, detectTrashImpl } from './trash.js';

const isPermissionError = (err) => err && (err.code === 'EACCES' || err.code === 'EPERM');

async function isGone(p) {
  try {
    await fs.lstat(p);
    return false;
  } catch (err) {
    return err.code === 'ENOENT' || err.code === 'ENOTDIR';
  }
}

/**
 * Give the owner enough permission to delete everything under `p`:
 * u+w on files, u+rwx on directories (needed to list and unlink entries).
 * Never follows symlinks and never touches anything outside `p`.
 */
export async function makeWritable(p) {
  let st;
  try {
    st = await fs.lstat(p);
  } catch {
    return;
  }
  if (st.isSymbolicLink()) return;
  const mode = st.mode & 0o7777;
  if (st.isDirectory()) {
    if ((mode & 0o700) !== 0o700) await fs.chmod(p, mode | 0o700).catch(() => {});
    let names = [];
    try {
      names = await fs.readdir(p);
    } catch {
      return;
    }
    for (const name of names) await makeWritable(path.join(p, name));
  } else if ((mode & 0o200) === 0) {
    await fs.chmod(p, mode | 0o200).catch(() => {});
  }
}

async function removePermanently(p) {
  try {
    await fs.rm(p, { recursive: true, force: true });
  } catch (err) {
    if (!isPermissionError(err)) throw err;
    await makeWritable(p);
    await fs.rm(p, { recursive: true, force: true });
  }
}

/**
 * @param {{path: string, typeId: string, sizeBytes?: number|null}[]} entries
 * @param {object} options
 * @param {'trash'|'permanent'} options.mode
 * @param {string} options.scanRoot root the project entries were found under
 * @param {object} options.defs loaded definitions
 * @param {object} [options.log] deletion log from openDeletionLog()
 * @param {*} [options.trashImpl] 'trash' | 'osascript' | function (tests)
 * @param {(done: number, total: number, entry: object) => void} [options.onProgress] called before each item
 * @returns {Promise<{ok: {path: string, trashedTo?: string, alreadyGone?: boolean}[], failed: {path: string, error: string, code: string}[]}>}
 */
export async function deleteEntries(entries, { mode = 'trash', scanRoot, defs, log, trashImpl, onProgress } = {}) {
  if (mode !== 'trash' && mode !== 'permanent') throw new Error(`unknown delete mode "${mode}"`);
  const impl = mode === 'trash' ? (trashImpl ?? detectTrashImpl()) : null;
  const ok = [];
  const failed = [];

  const record = (entry, outcome) => {
    if (outcome.result === 'ok') {
      const item = { path: entry.path };
      if (outcome.trashedTo) item.trashedTo = outcome.trashedTo;
      if (outcome.alreadyGone) item.alreadyGone = true;
      ok.push(item);
    } else {
      failed.push({ path: entry.path, error: outcome.error, code: outcome.code });
    }
    log?.item({
      mode,
      typeId: entry.typeId,
      path: entry.path,
      estimatedBytes: entry.sizeBytes ?? null,
      result: outcome.result,
      trashedTo: outcome.trashedTo,
      error: outcome.error,
    });
  };

  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i];
    onProgress?.(i + 1, entries.length, entry);

    // Already gone (e.g. nested inside a system cache deleted earlier): success.
    if (await isGone(entry.path)) {
      record(entry, { result: 'ok', alreadyGone: true });
      continue;
    }

    try {
      await verifyEntry(entry, defs?.byId.get(entry.typeId), { scanRoot, defs });
    } catch (err) {
      record(entry, { result: 'failed', error: err.message, code: err.code === 'verification' ? 'verification' : 'other' });
      continue;
    }

    if (mode === 'trash') {
      const res = await trashPaths([entry.path], { impl });
      if (res.trashed.length === 1) {
        record(entry, { result: 'ok', trashedTo: res.trashed[0].trashedTo });
      } else if (await isGone(entry.path)) {
        record(entry, { result: 'ok', alreadyGone: true });
      } else {
        const f = res.failed[0];
        record(entry, { result: 'failed', error: f.error, code: f.code });
      }
      continue;
    }

    try {
      await removePermanently(entry.path);
      if (await isGone(entry.path)) {
        record(entry, { result: 'ok' });
      } else {
        record(entry, { result: 'failed', error: 'path still exists after removal', code: 'other' });
      }
    } catch (err) {
      if (err.code === 'ENOENT') {
        record(entry, { result: 'ok', alreadyGone: true });
      } else {
        record(entry, {
          result: 'failed',
          error: err.message || String(err),
          code: isPermissionError(err) ? 'permission' : 'other',
        });
      }
    }
  }
  return { ok, failed };
}
