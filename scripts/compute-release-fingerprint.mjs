import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import { extname, join, relative } from 'node:path';

const root = new URL('../', import.meta.url);
const includedRoots = ['App.tsx', 'index.ts', 'package.json', 'app.json', 'src', 'scripts'];
const excluded = new Set([
  'src/release.ts',
  'scripts/compute-release-fingerprint.mjs',
  // Release tooling does not ship in the mobile bundle and must not change an
  // already certified application fingerprint.
  'scripts/release-preflight.mjs',
  'scripts/local-e2e.mjs',
]);

async function collect(path) {
  const absolute = new URL(path, root);
  const entries = await readdir(absolute, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const child = join(path, entry.name).replaceAll('\\', '/');
    if (entry.isDirectory()) {
      files.push(...(await collect(`${child}/`)));
      continue;
    }
    if (entry.isFile() && ['.ts', '.tsx', '.json'].includes(extname(entry.name))) {
      files.push(child);
    }
  }
  return files;
}

const files = [];
for (const item of includedRoots) {
  if (item === 'src' || item === 'scripts') {
    files.push(...(await collect(`${item}/`)));
  } else {
    files.push(item);
  }
}

const hash = createHash('sha256');
for (const path of [...new Set(files)].filter((item) => !excluded.has(item)).sort()) {
  const bytes = await readFile(new URL(path, root));
  hash.update(path);
  hash.update('\0');
  hash.update(bytes);
  hash.update('\0');
}

console.log(hash.digest('hex'));
