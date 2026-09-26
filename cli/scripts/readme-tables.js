#!/usr/bin/env node
// Print the README artifact tables generated from Definitions/artifacts.json,
// so the README can be regenerated (and checked in CI) instead of hand-edited.
// Usage: node scripts/readme-tables.js [path/to/artifacts.json]

import path from 'node:path';
import { loadDefinitions } from '../lib/definitions.js';

const defs = loadDefinitions(process.argv[2] ? { file: path.resolve(process.argv[2]) } : {});

const cell = (s) => String(s).replace(/\|/g, '\\|').replace(/\n/g, ' ');
const code = (s) => `\`${s}\``;
const row = (cells) => `| ${cells.map(cell).join(' | ')} |`;
const lines = [];

lines.push('### Project-level', '');
lines.push(row(['Category', 'What it finds', 'How it detects']));
lines.push(row(['---', '---', '---']));
for (const t of defs.projectTypes) {
  const detect = t.siblings.length ? `next to any of ${t.siblings.map(code).join(', ')}` : 'always';
  lines.push(row([`${t.displayName} (${code(t.id)})`, t.targets.map(code).join(', '), detect]));
}
lines.push('');

lines.push('### System-level', '');
lines.push(row(['Category', 'Path', 'Default', 'Regenerable']));
lines.push(row(['---', '---', '---', '---']));
for (const t of defs.systemTypes) {
  const env = t.pathOverrides.map((o) => code(o.append ? `$${o.env}/${o.append}` : `$${o.env}`));
  const where = `${code(t.path)}${t.expand ? ' (each subfolder)' : ''}${env.length ? `, or ${env.join(', ')}` : ''}`;
  lines.push(row([`${t.displayName} (${code(t.id)})`, where, t.defaultEnabled ? 'on' : 'off', t.regenerable ? 'yes' : 'no']));
}
lines.push('');

if (defs.filesTypes.length) {
  lines.push('### Other', '');
  lines.push(row(['Category', 'What it finds', 'Default', 'Regenerable']));
  lines.push(row(['---', '---', '---', '---']));
  for (const t of defs.filesTypes) {
    lines.push(row([`${t.displayName} (${code(t.id)})`, `${t.extensions.map(code).join(', ')} files in ${code(t.path)}`, t.defaultEnabled ? 'on' : 'off', t.regenerable ? 'yes' : 'no']));
  }
  lines.push('');
}

process.stdout.write(lines.join('\n'));
