// Command-line parsing with util.parseArgs (strict). Every usage problem is a
// UsageError, which the entry point turns into exit code 2.

import { parseArgs } from 'node:util';

export class UsageError extends Error {
  constructor(message) {
    super(message);
    this.name = 'UsageError';
    this.exitCode = 2;
  }
}

const OPTIONS = {
  help: { type: 'boolean', short: 'h' },
  version: { type: 'boolean', short: 'V' },
  categories: { type: 'string' },
  all: { type: 'boolean' },
  'list-categories': { type: 'boolean' },
  'dry-run': { type: 'boolean' },
  'include-hidden': { type: 'boolean' },
  yes: { type: 'boolean', short: 'y' },
  'non-interactive': { type: 'boolean' },
  json: { type: 'boolean' },
  permanent: { type: 'boolean' },
  'min-age': { type: 'string' },
  'min-size': { type: 'string' },
  'max-depth': { type: 'string' },
  'no-color': { type: 'boolean' },
  'log-dir': { type: 'string' },
};

const SIZE_UNITS = { B: 1, K: 1024, KB: 1024, M: 1024 ** 2, MB: 1024 ** 2, G: 1024 ** 3, GB: 1024 ** 3 };

/** "500KB", "1.5GB", "2048" (bytes) -> bytes. Units are powers of 1024. */
export function parseSize(text) {
  const m = String(text).trim().match(/^(\d+(?:\.\d+)?)\s*([KMG]?B?)$/i);
  if (!m) return null;
  const unit = (m[2] || 'B').toUpperCase();
  const factor = SIZE_UNITS[unit];
  if (!factor) return null;
  return Math.round(Number(m[1]) * factor);
}

export const HELP = `prune - find and remove regenerable developer artifacts

Usage:
  prune [path] [options]

Arguments:
  path                    Directory to scan for project artifacts (default: home)

Selection:
  --categories <list>     Comma-separated type ids (see --list-categories)
  --all                   Every type, including ones that are not regenerable
  --list-categories       Show all type ids and exit
  --include-hidden        Also descend into hidden directories
  --max-depth <n>         Maximum directory depth below path (default from definitions)
  --min-age <days>        Only items not modified in the last <days> days
  --min-size <n[KB|MB|GB]> Only items at least this large

Deletion:
  --dry-run               Scan and list only; never prompts, never deletes
  --permanent             Delete permanently instead of moving to the Trash
  -y, --yes               Select every item found and skip prompts
                          (requires --categories or --all; alias --non-interactive)

Output:
  --json                  Print one JSON document to stdout (human output goes
                          to stderr); implies --dry-run unless --yes is given
  --no-color              Disable colors (NO_COLOR is also honoured)
  --log-dir <path>        Deletion log directory (default ~/Library/Logs/Prune)
  -h, --help              Show this help
  -V, --version           Show the version

Exit codes:
  0 success, 1 runtime error, 2 usage error, 3 some items could not be removed

Examples:
  prune                               Pick categories and items interactively
  prune ~/code --categories node,rust Scan one folder for two types
  prune --all --dry-run               Preview everything without deleting
  prune --categories node --min-age 90 --yes
                                      Trash node_modules untouched for 90 days
  prune --all --json > report.json    Machine-readable preview
`;

/**
 * @param {string[]} argv arguments after the script name
 * @param {{knownIds?: string[]}} [context]
 */
export function parseCli(argv, { knownIds } = {}) {
  let parsed;
  try {
    parsed = parseArgs({ args: argv, options: OPTIONS, strict: true, allowPositionals: true });
  } catch (err) {
    throw new UsageError(err.message);
  }
  const { values: v, positionals } = parsed;
  if (positionals.length > 1) {
    throw new UsageError(`expected at most one path, got ${positionals.length}: ${positionals.join(' ')}`);
  }

  const opts = {
    help: Boolean(v.help),
    version: Boolean(v.version),
    listCategories: Boolean(v['list-categories']),
    all: Boolean(v.all),
    categories: null,
    dryRun: Boolean(v['dry-run']),
    includeHidden: Boolean(v['include-hidden']),
    yes: Boolean(v.yes || v['non-interactive']),
    json: Boolean(v.json),
    permanent: Boolean(v.permanent),
    minAgeDays: 0,
    minSizeBytes: 0,
    maxDepth: undefined,
    noColor: Boolean(v['no-color']),
    logDir: v['log-dir'],
    root: positionals[0],
  };
  if (opts.help || opts.version) return opts;

  if (v.categories !== undefined) {
    const ids = v.categories.split(',').map((s) => s.trim()).filter(Boolean);
    if (ids.length === 0) throw new UsageError('--categories needs at least one type id');
    if (knownIds) {
      const unknown = ids.filter((id) => !knownIds.includes(id));
      if (unknown.length) {
        throw new UsageError(`unknown categor${unknown.length === 1 ? 'y' : 'ies'}: ${unknown.join(', ')} (see --list-categories)`);
      }
    }
    opts.categories = [...new Set(ids)];
  }
  if (opts.all && opts.categories) throw new UsageError('use either --all or --categories, not both');
  if (opts.yes && !opts.all && !opts.categories && !opts.listCategories) {
    throw new UsageError('--yes requires --categories <list> or --all so the selection is explicit');
  }

  if (v['min-age'] !== undefined) {
    if (!/^\d+(\.\d+)?$/.test(v['min-age'])) throw new UsageError(`--min-age expects a number of days, got "${v['min-age']}"`);
    opts.minAgeDays = Number(v['min-age']);
  }
  if (v['min-size'] !== undefined) {
    const bytes = parseSize(v['min-size']);
    if (bytes === null) throw new UsageError(`--min-size expects a size like 500KB, 100MB or 1GB, got "${v['min-size']}"`);
    opts.minSizeBytes = bytes;
  }
  if (v['max-depth'] !== undefined) {
    if (!/^\d+$/.test(v['max-depth']) || Number(v['max-depth']) < 1 || Number(v['max-depth']) > 64) {
      throw new UsageError(`--max-depth expects an integer from 1 to 64, got "${v['max-depth']}"`);
    }
    opts.maxDepth = Number(v['max-depth']);
  }
  if (opts.logDir !== undefined && opts.logDir.trim() === '') throw new UsageError('--log-dir needs a path');
  return opts;
}
