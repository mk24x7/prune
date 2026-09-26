#!/usr/bin/env node
// Load and validate the shared artifact definitions. Exit 1 on any error.
// Usage: node scripts/check-definitions.js [path/to/artifacts.json]

import fs from 'node:fs';
import path from 'node:path';
import { definitionsPath, validateDefinitions } from '../lib/definitions.js';

let file;
let doc;
try {
  file = process.argv[2] ? path.resolve(process.argv[2]) : definitionsPath();
  doc = JSON.parse(fs.readFileSync(file, 'utf8'));
} catch (err) {
  console.error(`check-definitions: ${err.message}`);
  process.exit(1);
}

const errors = validateDefinitions(doc);
if (errors.length) {
  console.error(`${file} is invalid (${errors.length} error(s)):`);
  for (const e of errors) console.error(`  - ${e}`);
  process.exit(1);
}

const counts = { project: 0, system: 0, files: 0 };
for (const t of doc.types) counts[t.kind]++;
console.log(`${file} OK: ${doc.types.length} types (${counts.project} project, ${counts.system} system, ${counts.files} files)`);
