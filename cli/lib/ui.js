// Human-facing output and interactive prompts. Everything is ASCII; the
// inquirer prompts get an ASCII theme instead of their default glyphs.

import checkbox, { Separator } from '@inquirer/checkbox';
import confirm from '@inquirer/confirm';

const KB = 1024;
const MB = KB * 1024;
const GB = MB * 1024;

export function formatBytes(bytes) {
  if (bytes === null || bytes === undefined) return '?';
  if (bytes >= GB) return `${(bytes / GB).toFixed(1)} GB`;
  if (bytes >= MB) return `${(bytes / MB).toFixed(1)} MB`;
  return `${(bytes / KB).toFixed(1)} KB`;
}

export function colorSize(bytes, style) {
  const text = formatBytes(bytes);
  if (bytes === null || bytes === undefined) return style.dim(text);
  if (bytes > 500 * MB) return style.red(text);
  if (bytes > 100 * MB) return style.yellow(text);
  return style.green(text);
}

export function formatAge(date, now = Date.now()) {
  if (!date) return 'age unknown';
  const mins = Math.floor((now - date.getTime()) / 60000);
  const units = [
    [365 * 24 * 60, 'year'],
    [30 * 24 * 60, 'month'],
    [7 * 24 * 60, 'week'],
    [24 * 60, 'day'],
    [60, 'hour'],
    [1, 'minute'],
  ];
  for (const [size, name] of units) {
    const n = Math.floor(mins / size);
    if (n > 0) return `${n} ${name}${n > 1 ? 's' : ''} ago`;
  }
  return 'just now';
}

export function shortenPath(p, home) {
  if (home && (p === home || p.startsWith(home.endsWith('/') ? home : `${home}/`))) return `~${p.slice(home.length)}`;
  return p;
}

export const plural = (n, word, many = `${word}s`) => `${n} ${n === 1 ? word : many}`;

export function sumKnown(entries) {
  let bytes = 0;
  let unknown = 0;
  for (const e of entries) {
    if (e.sizeUnknown || e.sizeBytes === null) unknown++;
    else bytes += e.sizeBytes;
  }
  return { bytes, unknown };
}

function totalText(entries) {
  const { bytes, unknown } = sumKnown(entries);
  return unknown ? `${formatBytes(bytes)} + ${unknown} of unknown size` : formatBytes(bytes);
}

// ---------------------------------------------------------------------------
// Listings

export function typeLabel(type, style) {
  return style.palette(type?.color, `[${type?.displayName ?? '?'}]`);
}

export function listCategories(defs, style, out) {
  const section = (title, types, describe) => {
    out(style.bold(title));
    const width = Math.max(...types.map((t) => t.id.length)) + 2;
    for (const t of types) {
      const flags = [t.defaultEnabled ? 'default' : 'off by default', t.regenerable ? null : 'NOT REGENERABLE']
        .filter(Boolean).join(', ');
      out(`  ${style.bold(t.id.padEnd(width))}${t.displayName} ${style.dim(`(${flags})`)}`);
      out(`  ${' '.repeat(width)}${style.dim(describe(t))}`);
    }
    out('');
  };
  out('');
  section('Project artifacts (found by scanning the path):', defs.projectTypes, (t) => `${t.targets.join(', ')}${t.siblings.length ? ` next to ${t.siblings.join(' | ')}` : ''}`);
  section('System caches (fixed locations):', defs.systemTypes, (t) => shortenPath(defs.resolveSystemPath(t), defs.home));
  if (defs.filesTypes.length) {
    section('Other:', defs.filesTypes, (t) => `${t.extensions.join(', ')} in ${shortenPath(defs.resolveSystemPath(t), defs.home)}`);
  }
  out(style.dim('Use: prune --categories node,rust,xcode-derived   or   prune --all'));
  out('');
}

export function printEntries(entries, defs, style, out, home) {
  for (const e of entries) {
    const type = defs.byId.get(e.typeId);
    out(`  ${typeLabel(type, style)} ${e.projectName} (${colorSize(e.sizeBytes, style)}) ${style.dim(`- ${formatAge(e.lastModified)}`)}`);
    out(`      ${style.dim(shortenPath(e.path, home))}`);
  }
}

export function perTypeBreakdown(entries, defs) {
  const byType = new Map();
  for (const e of entries) {
    const cur = byType.get(e.typeId) ?? { count: 0, bytes: 0, unknown: 0 };
    cur.count++;
    if (e.sizeUnknown || e.sizeBytes === null) cur.unknown++;
    else cur.bytes += e.sizeBytes;
    byType.set(e.typeId, cur);
  }
  return [...byType.entries()]
    .sort((a, b) => b[1].bytes - a[1].bytes)
    .map(([id, v]) => ({ id, name: defs.byId.get(id)?.displayName ?? id, ...v }));
}

/** Warning lines for any non-regenerable types in `typeIds` (empty when none). */
export function nonRegenerableWarning(typeIds, defs, style) {
  const types = [...new Set(typeIds)].map((id) => defs.byId.get(id)).filter((t) => t && !t.regenerable);
  if (types.length === 0) return [];
  return [
    style.yellow(style.bold('Warning: the following types are NOT regenerable; deleting them loses data:')),
    ...types.map((t) => style.yellow(`  - ${t.displayName} (${t.id}): ${t.reinstallHint}`)),
  ];
}

export function totalsLine(entries) {
  return `${plural(entries.length, 'item')}, ${totalText(entries)}`;
}

// ---------------------------------------------------------------------------
// Prompts

const NON_ASCII = /[^\x20-\x7e]/;

function asciiTheme(style) {
  return {
    prefix: { idle: style.cyan('?'), done: style.green('>') },
    spinner: { interval: 80, frames: ['-', '\\', '|', '/'] },
    icon: {
      checked: style.green('[x]'),
      unchecked: '[ ]',
      cursor: '>',
      disabledChecked: '[x]',
      disabledUnchecked: '[-]',
    },
    style: {
      renderSelectedChoices: (selected) => (selected.length <= 3
        ? selected.map((c) => c.short).join(', ')
        : `${selected.length} selected`),
      keysHelpTip: (keys) => keys
        .map(([key, action]) => {
          let k = key;
          if (NON_ASCII.test(key)) k = action === 'navigate' ? 'up/down' : action === 'submit' ? 'enter' : '';
          return `${style.bold(k)} ${style.dim(action)}`;
        })
        .join(style.dim(', ')),
    },
  };
}

export async function promptCategories(defs, style) {
  const choice = (t) => ({
    name: `${t.displayName}${t.regenerable ? '' : style.yellow(' (not regenerable)')}`,
    short: t.id,
    value: t.id,
    checked: t.defaultEnabled,
  });
  const choices = [
    new Separator(style.dim('-- Project artifacts --')),
    ...defs.projectTypes.map(choice),
    new Separator(style.dim('-- System caches --')),
    ...defs.systemTypes.map(choice),
  ];
  if (defs.filesTypes.length) {
    choices.push(new Separator(style.dim('-- Other --')), ...defs.filesTypes.map(choice));
  }
  return checkbox({
    message: 'Select artifact types to scan',
    choices,
    pageSize: 20,
    loop: false,
    theme: asciiTheme(style),
  });
}

export async function promptSelection(entries, defs, style, home) {
  const choices = entries.map((e) => ({
    name: `${typeLabel(defs.byId.get(e.typeId), style)} ${e.projectName} (${colorSize(e.sizeBytes, style)}) ${style.dim(`- ${formatAge(e.lastModified)}`)}\n      ${style.dim(shortenPath(e.path, home))}`,
    short: e.projectName,
    value: e.path,
  }));
  const picked = new Set(await checkbox({
    message: 'Select items to remove',
    choices,
    pageSize: 15,
    loop: false,
    theme: asciiTheme(style),
  }));
  return entries.filter((e) => picked.has(e.path));
}

export async function promptYesNo(message, style) {
  return confirm({ message, default: false, theme: asciiTheme(style) });
}
