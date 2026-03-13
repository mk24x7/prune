import os from 'node:os';

// Directories to skip during scanning -- these are either known to not contain
// project node_modules or are extremely large and slow to traverse.
export const SKIP_DIRS = new Set([
  // macOS system directories
  'Library',
  '.Trash',
  'Applications',
  'Pictures',
  'Movies',
  'Music',
  '.Spotlight-V100',
  '.fseventsd',

  // Tool/runtime caches
  '.npm',
  '.cache',
  '.yarn',
  '.pnpm-store',
  '.bun',

  // Development tools (no project node_modules inside these)
  '.git',
  '.docker',
  '.ollama',
  '.conda',
  '.anaconda',
  '.cocoapods',
  '.gradle',
  '.cargo',
  '.rustup',

  // Shell/editor configs
  '.oh-my-zsh',
  '.zsh_sessions',

  // IDE extensions (huge trees, no user projects)
  '.vscode',
  '.cursor',
  '.windsurf',

  // Other
  '.local',
  '.config',
  'Wallpapers',
  'node_modules', // handled specially -- recorded but not recursed into
]);

export const DEFAULT_ROOT = os.homedir();
export const MAX_DEPTH = 8;
export const DU_CONCURRENCY = 8;
