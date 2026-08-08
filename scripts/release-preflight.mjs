import { spawnSync } from 'node:child_process';
import { mkdtemp, readFile, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const databaseDir = join(root, 'database');
const migration147 = join(databaseDir, '147_final_production_readiness_and_go_live_seal.sql');
const releaseMigration = join(databaseDir, '157_ios_export_compliance_release.sql');
const standalone147 = join(root, 'LEGHEVO_SUPABASE_FINAL_PRODUCTION_READINESS_AND_GO_LIVE_SEAL_v1.sql');
const fingerprintPattern = /[a-f0-9]{64}/g;
const expectedLastMigration = 157;

function fail(message, detail) {
  console.error(`\nPRE-FLIGHT NON SUPERATO: ${message}`);
  if (detail) console.error(detail.trim());
  process.exitCode = 1;
}

function pass(label, startedAt) {
  const seconds = ((Date.now() - startedAt) / 1000).toFixed(1);
  console.log(`OK  ${label} (${seconds}s)`);
}

function run(label, command, args, { capture = false } = {}) {
  const startedAt = Date.now();
  const result = spawnSync(command, args, {
    cwd: root,
    encoding: 'utf8',
    stdio: capture ? 'pipe' : 'inherit',
    maxBuffer: 20 * 1024 * 1024,
  });

  if (result.error || result.status !== 0) {
    const detail = capture
      ? [result.stdout, result.stderr].filter(Boolean).join('\n')
      : result.error?.message;
    fail(label, detail);
    return null;
  }

  pass(label, startedAt);
  return capture ? result.stdout.trim() : true;
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function staticChecks() {
  const startedAt = Date.now();
  const [
    packageText,
    appText,
    releaseText,
    fingerprintScriptText,
    migration147Text,
    releaseMigrationText,
    standaloneText,
    entries,
  ] = await Promise.all([
      readFile(join(root, 'package.json'), 'utf8'),
      readFile(join(root, 'app.json'), 'utf8'),
      readFile(join(root, 'src/release.ts'), 'utf8'),
      readFile(join(root, 'scripts/compute-release-fingerprint.mjs'), 'utf8'),
      readFile(migration147, 'utf8'),
      readFile(releaseMigration, 'utf8'),
      readFile(standalone147, 'utf8'),
      readdir(databaseDir),
    ]);

  const packageJson = JSON.parse(packageText);
  const appJson = JSON.parse(appText);
  const releaseVersion = releaseText.match(/APP_RELEASE_VERSION\s*=\s*'([^']+)'/)?.[1];
  const releaseFingerprint = releaseText.match(/APP_BUNDLE_FINGERPRINT\s*=\s*'([a-f0-9]{64})'/)?.[1];

  assert(releaseVersion, 'Versione non leggibile in src/release.ts.');
  assert(releaseFingerprint, 'Fingerprint non leggibile in src/release.ts.');
  assert(packageJson.version === releaseVersion, 'Versione package.json non coerente.');
  assert(appJson.expo?.version === releaseVersion, 'Versione app.json non coerente.');
  assert(
    fingerprintScriptText.includes("'package-lock.json'"),
    'Il contratto fingerprint non include package-lock.json.',
  );
  assert(
    releaseMigrationText.startsWith(`-- LEGHEVO v${releaseVersion}\n`),
    'Versione della migrazione release non coerente.',
  );
  assert(migration147Text === standaloneText, 'Migrazione 147 e SQL standalone non sono identici.');

  const sqlFingerprints = new Set(releaseMigrationText.match(fingerprintPattern) ?? []);
  assert(sqlFingerprints.has(releaseFingerprint), 'Fingerprint release assente dalla migrazione release.');

  const numbered = entries
    .map((name) => ({ name, match: name.match(/^(\d{3})_.*\.sql$/) }))
    .filter((item) => item.match)
    .map((item) => ({ name: item.name, number: Number(item.match[1]) }));
  const byNumber = new Map();
  for (const item of numbered) {
    const names = byNumber.get(item.number) ?? [];
    names.push(item.name);
    byNumber.set(item.number, names);
  }

  const duplicates = [...byNumber].filter(([, names]) => names.length > 1);
  const missing = Array.from({ length: expectedLastMigration }, (_, index) => index + 1)
    .filter((number) => !byNumber.has(number));
  const unexpected = [...byNumber.keys()].filter((number) => number > expectedLastMigration);
  assert(duplicates.length === 0, `Migrazioni duplicate: ${JSON.stringify(duplicates)}.`);
  assert(missing.length === 0, `Migrazioni mancanti: ${missing.join(', ')}.`);
  assert(unexpected.length === 0, `Migrazioni oltre la ${expectedLastMigration}: ${unexpected.join(', ')}.`);
  for (const developmentNumber of [5, 57, 58]) {
    const name = byNumber.get(developmentNumber)?.[0] ?? '';
    assert(name.includes('development_'), `La migrazione ${developmentNumber} non è marcata come sviluppo.`);
  }

  const computedFingerprint = run(
    'Calcolo fingerprint applicativa',
    process.execPath,
    [join(root, 'scripts/compute-release-fingerprint.mjs')],
    { capture: true },
  );
  assert(computedFingerprint === releaseFingerprint, 'La fingerprint calcolata non coincide con src/release.ts.');
  pass(`Contratto release ${releaseVersion}, SQL e migrazioni 001-${expectedLastMigration}`, startedAt);
}

async function main() {
  console.log('LEGHEVO release preflight\n');

  try {
    await staticChecks();
  } catch (error) {
    fail('Controlli statici di release', error instanceof Error ? error.message : String(error));
    return;
  }
  if (process.exitCode) return;

  const tscCli = join(root, 'node_modules/typescript/bin/tsc');
  const expoCli = join(root, 'node_modules/expo/bin/cli');
  if (!run('Typecheck TypeScript', process.execPath, [tscCli, '--noEmit'])) return;
  if (!run('Configurazione Expo', process.execPath, [expoCli, 'config', '--type', 'public'], { capture: true })) return;

  const exportDir = await mkdtemp(join(tmpdir(), 'leghevo-release-preflight-'));
  try {
    if (!run('Export Expo Android e iOS', process.execPath, [
      expoCli,
      'export',
      '--platform',
      'android',
      '--platform',
      'ios',
      '--output-dir',
      exportDir,
    ])) return;
  } finally {
    await rm(exportDir, { recursive: true, force: true });
  }

  console.log('\nPRE-FLIGHT SUPERATO: release candidate coerente per il collaudo staging.');
  console.log('Questo controllo non autorizza il deployment o il go-live di produzione.');
}

await main();
