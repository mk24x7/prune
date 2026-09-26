// Move paths to the user's Trash.
// macOS 15+ ships /usr/bin/trash (supports Put Back). On macOS 13/14 we fall
// back to Finder via osascript, passing the path through argv so it is never
// interpolated into AppleScript source.

import { execFile } from 'node:child_process';
import { accessSync, constants } from 'node:fs';

export const TRASH_BIN = '/usr/bin/trash';
const TIMEOUT_MS = 10 * 60 * 1000; // moving is a rename, but Finder may prompt

export function detectTrashImpl() {
  try {
    accessSync(TRASH_BIN, constants.X_OK);
    return 'trash';
  } catch {
    return 'osascript';
  }
}

function run(file, args) {
  return new Promise((resolve, reject) => {
    execFile(file, args, { timeout: TIMEOUT_MS, maxBuffer: 1024 * 1024 }, (err, stdout, stderr) => {
      if (err) {
        err.stdout = stdout;
        err.stderr = stderr;
        reject(err);
      } else {
        resolve({ stdout, stderr });
      }
    });
  });
}

// Classify a failure from /usr/bin/trash, Finder or a custom impl.
// A missing file, a permission problem, a timeout or a missing tool is
// 'other'; everything else (the volume has no Trash, Finder cannot move it)
// is 'unsupported', which the caller may offer to delete permanently instead.
export function classifyTrashError(err) {
  if (err?.code === 'unsupported') return 'unsupported';
  // String codes are Node spawn errors (e.g. ENOENT for the tool itself).
  if (typeof err?.code === 'string') return 'other';
  if (err?.killed || err?.signal) return 'other';
  const text = `${err?.stderr ?? ''} ${err?.message ?? ''}`;
  if (/Code=(4|513|257)\b|fnfErr|permission|not permitted|-5000\b|-1743\b/i.test(text)) return 'other';
  return 'unsupported';
}

function firstLine(text) {
  return String(text ?? '').split('\n').map((s) => s.trim()).find(Boolean) ?? '';
}

function describe(err) {
  const line = firstLine(err?.stderr)
    .replace(/^\S+ \S+ trash\[\d+:\d+\] /, '') // NSLog prefix
    .replace(/^# /, '')
    .replace(/ UserInfo=.*$/, '');
  return line || err?.message || String(err);
}

async function trashOneWithBin(p) {
  // -v prints: # Moved "<src>" to "<dst>"; -s makes failures exit non-zero.
  const { stdout } = await run(TRASH_BIN, ['-v', '-s', p]);
  const m = String(stdout).match(/Moved "(.*)" to "(.*)"\s*$/m);
  return { trashedTo: m ? m[2] : undefined };
}

async function trashOneWithFinder(p) {
  await run('/usr/bin/osascript', [
    '-e', 'on run argv',
    '-e', 'tell application "Finder" to delete (POSIX file (item 1 of argv) as alias)',
    '-e', 'end run',
    p,
  ]);
  return {};
}

/**
 * Move each path to the Trash (one child process per path, no shell).
 * @param {string[]} paths
 * @param {{impl?: 'trash'|'osascript'|((p: string) => Promise<{trashedTo?: string}|void>)}} [options]
 * @returns {Promise<{trashed: {path: string, trashedTo?: string}[], failed: {path: string, error: string, code: 'unsupported'|'other'}[]}>}
 */
export async function trashPaths(paths, { impl = detectTrashImpl() } = {}) {
  const one = typeof impl === 'function' ? impl : impl === 'trash' ? trashOneWithBin : trashOneWithFinder;
  const trashed = [];
  const failed = [];
  for (const p of paths) {
    try {
      const res = (await one(p)) ?? {};
      trashed.push(res.trashedTo ? { path: p, trashedTo: res.trashedTo } : { path: p });
    } catch (err) {
      failed.push({ path: p, error: describe(err), code: classifyTrashError(err) });
    }
  }
  return { trashed, failed };
}
