// Append-only deletion log: ~/Library/Logs/Prune/deletions.jsonl
// (PRUNE_LOG_DIR or an explicit dir overrides). One JSON line per item plus
// one run line; the file is rotated at 5 MB by renaming with a date suffix.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const LOG_FILE_NAME = 'deletions.jsonl';
export const ROTATE_BYTES = 5 * 1024 * 1024;

export function defaultLogDir({ env = process.env, home = os.homedir() } = {}) {
  if (env.PRUNE_LOG_DIR) return path.resolve(env.PRUNE_LOG_DIR);
  return path.join(home, 'Library', 'Logs', 'Prune');
}

function rotateIfNeeded(file, now) {
  let size;
  try {
    size = fs.statSync(file).size;
  } catch {
    return;
  }
  if (size < ROTATE_BYTES) return;
  const stamp = now.toISOString().slice(0, 10);
  const base = file.replace(/\.jsonl$/, '');
  let target = `${base}-${stamp}.jsonl`;
  for (let n = 1; fs.existsSync(target); n++) target = `${base}-${stamp}-${n}.jsonl`;
  fs.renameSync(file, target);
}

/**
 * Open the deletion log. Writes are synchronous appends so a crash mid-run
 * still leaves a line for every item already processed.
 * @param {{dir?: string, version: string, mode: 'trash'|'permanent', env?: object, home?: string, now?: () => Date}} options
 */
export function openDeletionLog({ dir, version, mode, env = process.env, home = os.homedir(), now = () => new Date() }) {
  const logDir = dir ? path.resolve(dir) : defaultLogDir({ env, home });
  fs.mkdirSync(logDir, { recursive: true });
  const file = path.join(logDir, LOG_FILE_NAME);
  rotateIfNeeded(file, now());

  const write = (obj) => {
    fs.appendFileSync(file, `${JSON.stringify(obj)}\n`);
  };

  return {
    file,
    /** @param {{typeId: string, path: string, estimatedBytes: number|null, result: 'ok'|'failed', trashedTo?: string, error?: string, mode?: string}} item */
    item(item) {
      const line = {
        ts: now().toISOString(),
        tool: 'cli',
        version,
        mode: item.mode ?? mode,
        typeId: item.typeId,
        path: item.path,
        estimatedBytes: item.estimatedBytes ?? null,
        result: item.result,
      };
      if (item.trashedTo) line.trashedTo = item.trashedTo;
      if (item.error) line.error = item.error;
      write(line);
    },
    /** @param {object} summary */
    run(summary) {
      write({ ts: now().toISOString(), tool: 'cli', version, mode, event: 'run', ...summary });
    },
  };
}
