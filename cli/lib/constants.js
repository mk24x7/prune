import os from 'node:os';
import path from 'node:path';

const HOME = os.homedir();

// -- Artifact Categories --

export const ARTIFACT_CATEGORIES = {
  // Project-level (found by scanning)
  node: {
    id: 'node',
    name: 'Node Modules',
    targetDirs: ['node_modules'],
    siblingFiles: [],
    projectNameFile: 'package.json',
    reinstallHint: 'npm install',
    isSystem: false,
  },
  swiftpm: {
    id: 'swiftpm',
    name: 'Swift PM',
    targetDirs: ['.build'],
    siblingFiles: ['Package.swift'],
    projectNameFile: 'Package.swift',
    reinstallHint: 'swift build',
    isSystem: false,
  },
  cocoapods: {
    id: 'cocoapods',
    name: 'CocoaPods',
    targetDirs: ['Pods'],
    siblingFiles: ['Podfile'],
    projectNameFile: null,
    reinstallHint: 'pod install',
    isSystem: false,
  },
  rust: {
    id: 'rust',
    name: 'Rust',
    targetDirs: ['target'],
    siblingFiles: ['Cargo.toml'],
    projectNameFile: 'Cargo.toml',
    reinstallHint: 'cargo build',
    isSystem: false,
  },
  pythonvenv: {
    id: 'pythonvenv',
    name: 'Python Venv',
    targetDirs: ['venv', '.venv'],
    siblingFiles: ['requirements.txt', 'pyproject.toml', 'setup.py', 'setup.cfg', 'Pipfile'],
    projectNameFile: null,
    reinstallHint: 'python -m venv venv',
    isSystem: false,
  },
  pycache: {
    id: 'pycache',
    name: 'Python Cache',
    targetDirs: ['__pycache__'],
    siblingFiles: [],
    projectNameFile: null,
    reinstallHint: 'auto-regenerated',
    isSystem: false,
  },
  gradle: {
    id: 'gradle',
    name: 'Gradle Build',
    targetDirs: ['build'],
    siblingFiles: ['build.gradle', 'build.gradle.kts'],
    projectNameFile: 'settings.gradle',
    reinstallHint: './gradlew build',
    isSystem: false,
  },
  gradlecache: {
    id: 'gradlecache',
    name: 'Gradle Cache',
    targetDirs: ['.gradle'],
    siblingFiles: ['build.gradle', 'build.gradle.kts', 'settings.gradle', 'settings.gradle.kts'],
    projectNameFile: null,
    reinstallHint: 'auto-regenerated',
    isSystem: false,
  },
  next: {
    id: 'next',
    name: 'Next.js Build',
    targetDirs: ['.next'],
    siblingFiles: ['next.config.js', 'next.config.mjs', 'next.config.ts', 'package.json'],
    projectNameFile: 'package.json',
    reinstallHint: 'next build',
    isSystem: false,
  },
  nuxt: {
    id: 'nuxt',
    name: 'Nuxt Build',
    targetDirs: ['.nuxt', '.output'],
    siblingFiles: ['nuxt.config.js', 'nuxt.config.ts', 'nuxt.config.mjs'],
    projectNameFile: 'package.json',
    reinstallHint: 'nuxt build',
    isSystem: false,
  },
  sveltekit: {
    id: 'sveltekit',
    name: 'SvelteKit Build',
    targetDirs: ['.svelte-kit'],
    siblingFiles: ['svelte.config.js', 'svelte.config.mjs', 'svelte.config.ts'],
    projectNameFile: 'package.json',
    reinstallHint: 'vite build',
    isSystem: false,
  },
  astro: {
    id: 'astro',
    name: 'Astro Build',
    targetDirs: ['.astro'],
    siblingFiles: ['astro.config.mjs', 'astro.config.js', 'astro.config.ts'],
    projectNameFile: 'package.json',
    reinstallHint: 'astro build',
    isSystem: false,
  },
  angular: {
    id: 'angular',
    name: 'Angular Cache',
    targetDirs: ['.angular'],
    siblingFiles: ['angular.json'],
    projectNameFile: 'angular.json',
    reinstallHint: 'ng build',
    isSystem: false,
  },
  turbo: {
    id: 'turbo',
    name: 'Turbo Cache',
    targetDirs: ['.turbo'],
    siblingFiles: ['turbo.json', 'package.json'],
    projectNameFile: 'package.json',
    reinstallHint: 'auto-regenerated on next turbo run',
    isSystem: false,
  },
  vite: {
    id: 'vite',
    name: 'Vite Cache',
    targetDirs: ['.vite'],
    siblingFiles: ['vite.config.js', 'vite.config.ts', 'vite.config.mjs', 'package.json'],
    projectNameFile: 'package.json',
    reinstallHint: 'auto-regenerated on next dev/build',
    isSystem: false,
  },
  parcel: {
    id: 'parcel',
    name: 'Parcel Cache',
    targetDirs: ['.parcel-cache'],
    siblingFiles: ['package.json'],
    projectNameFile: 'package.json',
    reinstallHint: 'auto-regenerated on next build',
    isSystem: false,
  },
  pytestcache: {
    id: 'pytestcache',
    name: 'Pytest Cache',
    targetDirs: ['.pytest_cache'],
    siblingFiles: [],
    projectNameFile: null,
    reinstallHint: 'auto-regenerated on next test run',
    isSystem: false,
  },
  mypycache: {
    id: 'mypycache',
    name: 'Mypy Cache',
    targetDirs: ['.mypy_cache'],
    siblingFiles: [],
    projectNameFile: null,
    reinstallHint: 'auto-regenerated on next mypy run',
    isSystem: false,
  },
  ruffcache: {
    id: 'ruffcache',
    name: 'Ruff Cache',
    targetDirs: ['.ruff_cache'],
    siblingFiles: [],
    projectNameFile: null,
    reinstallHint: 'auto-regenerated on next ruff run',
    isSystem: false,
  },
  tox: {
    id: 'tox',
    name: 'Tox Cache',
    targetDirs: ['.tox'],
    siblingFiles: ['tox.ini', 'pyproject.toml'],
    projectNameFile: null,
    reinstallHint: 'auto-regenerated on next tox run',
    isSystem: false,
  },

  // System-level (fixed paths)
  'xcode-derived': {
    id: 'xcode-derived',
    name: 'Xcode DerivedData',
    systemPath: path.join(HOME, 'Library/Developer/Xcode/DerivedData'),
    expandSubdirs: true,
    reinstallHint: 'Xcode rebuilds automatically',
    isSystem: true,
  },
  'xcode-archives': {
    id: 'xcode-archives',
    name: 'Xcode Archives',
    systemPath: path.join(HOME, 'Library/Developer/Xcode/Archives'),
    expandSubdirs: true,
    reinstallHint: 're-archive from Xcode',
    isSystem: true,
  },
  'xcode-device-support': {
    id: 'xcode-device-support',
    name: 'Xcode Device Support',
    systemPath: path.join(HOME, 'Library/Developer/Xcode/iOS DeviceSupport'),
    expandSubdirs: true,
    reinstallHint: 're-downloaded on device connect',
    isSystem: true,
  },
  'xcode-cache': {
    id: 'xcode-cache',
    name: 'Xcode Cache',
    systemPath: path.join(HOME, 'Library/Caches/com.apple.dt.Xcode'),
    expandSubdirs: false,
    reinstallHint: 'Xcode rebuilds cache automatically',
    isSystem: true,
  },
  'gradle-global': {
    id: 'gradle-global',
    name: 'Gradle Global Cache',
    systemPath: path.join(HOME, '.gradle/caches'),
    expandSubdirs: false,
    reinstallHint: 're-downloaded on next build',
    isSystem: true,
  },
  'homebrew-cache': {
    id: 'homebrew-cache',
    name: 'Homebrew Cache',
    systemPath: path.join(HOME, 'Library/Caches/Homebrew'),
    expandSubdirs: false,
    reinstallHint: 're-downloaded on next install',
    isSystem: true,
  },
  'npm-cache': {
    id: 'npm-cache',
    name: 'npm Cache',
    systemPath: path.join(HOME, '.npm'),
    expandSubdirs: false,
    reinstallHint: 're-downloaded on next npm install',
    isSystem: true,
  },
  'yarn-cache': {
    id: 'yarn-cache',
    name: 'Yarn Cache',
    systemPath: path.join(HOME, 'Library/Caches/Yarn'),
    expandSubdirs: false,
    reinstallHint: 're-downloaded on next yarn install',
    isSystem: true,
  },
  'pnpm-store': {
    id: 'pnpm-store',
    name: 'pnpm Store',
    systemPath: path.join(HOME, 'Library/pnpm/store'),
    expandSubdirs: false,
    reinstallHint: 're-downloaded on next pnpm install',
    isSystem: true,
  },
  'bun-cache': {
    id: 'bun-cache',
    name: 'Bun Cache',
    systemPath: path.join(HOME, '.bun/install/cache'),
    expandSubdirs: false,
    reinstallHint: 're-downloaded on next bun install',
    isSystem: true,
  },
  'pip-cache': {
    id: 'pip-cache',
    name: 'pip Cache',
    systemPath: path.join(HOME, 'Library/Caches/pip'),
    expandSubdirs: false,
    reinstallHint: 're-downloaded on next pip install',
    isSystem: true,
  },
  'cargo-registry': {
    id: 'cargo-registry',
    name: 'Cargo Registry Cache',
    systemPath: path.join(HOME, '.cargo/registry'),
    expandSubdirs: false,
    reinstallHint: 're-downloaded on next cargo build',
    isSystem: true,
  },
  'go-mod-cache': {
    id: 'go-mod-cache',
    name: 'Go Module Cache',
    systemPath: path.join(HOME, 'go/pkg/mod'),
    expandSubdirs: false,
    reinstallHint: 're-downloaded on next go build',
    isSystem: true,
  },
  'puppeteer-cache': {
    id: 'puppeteer-cache',
    name: 'Puppeteer Cache',
    systemPath: path.join(HOME, '.cache/puppeteer'),
    expandSubdirs: false,
    reinstallHint: 're-downloaded on next puppeteer run',
    isSystem: true,
  },
  'playwright-cache': {
    id: 'playwright-cache',
    name: 'Playwright Browsers',
    systemPath: path.join(HOME, 'Library/Caches/ms-playwright'),
    expandSubdirs: false,
    reinstallHint: 'npx playwright install',
    isSystem: true,
  },
  'electron-cache': {
    id: 'electron-cache',
    name: 'Electron Cache',
    systemPath: path.join(HOME, 'Library/Caches/electron'),
    expandSubdirs: false,
    reinstallHint: 're-downloaded on next electron install',
    isSystem: true,
  },
};

// Directories to skip during scanning -- these are either known to not contain
// project artifacts or are extremely large and slow to traverse.
// NOTE: Some entries may be dynamically removed if they are scan targets.
export const BASE_SKIP_DIRS = new Set([
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

  // Development tools (no project artifacts inside these)
  '.git',
  '.docker',
  '.ollama',
  '.conda',
  '.anaconda',
  '.cocoapods',
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
]);

/**
 * Build the effective skip dirs set, removing any that are scan targets
 * for the selected categories.
 */
export function getSkipDirs(categories) {
  const targetDirs = new Set();
  for (const cat of categories) {
    const def = ARTIFACT_CATEGORIES[cat];
    if (def && !def.isSystem && def.targetDirs) {
      for (const d of def.targetDirs) {
        targetDirs.add(d);
      }
    }
  }

  const skipDirs = new Set(BASE_SKIP_DIRS);
  for (const t of targetDirs) {
    skipDirs.delete(t);
  }
  // Always add matched target dirs to prevent recursing into them
  // (they are handled specially by the scanner)
  for (const t of targetDirs) {
    skipDirs.add(t);
  }
  return skipDirs;
}

export const DEFAULT_ROOT = HOME;
export const MAX_DEPTH = 8;
export const DU_CONCURRENCY = 8;
