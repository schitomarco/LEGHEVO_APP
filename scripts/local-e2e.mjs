import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const mode = process.argv[2] ?? '--check';

function abort(message) {
  console.error(`LOCAL E2E NON DISPONIBILE: ${message}`);
  process.exit(1);
}

function readLocalSupabaseEnvironment() {
  const result = spawnSync(
    'npx',
    ['--yes', 'supabase@2.111.0', 'status', '-o', 'env'],
    { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
  );
  if (result.error || result.status !== 0) {
    abort('avvia prima lo stack con `npx --yes supabase@2.111.0 start`.');
  }

  const values = {};
  for (const line of result.stdout.split(/\r?\n/)) {
    const match = line.match(/^([A-Z][A-Z0-9_]*)=(.*)$/);
    if (!match) continue;
    values[match[1]] = match[2].replace(/^['"]|['"]$/g, '');
  }
  return values;
}

function assertLoopback(rawUrl) {
  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    abort('URL Supabase locale assente o non valida.');
  }
  if (!['127.0.0.1', 'localhost', '::1'].includes(url.hostname)) {
    abort('il launcher rifiuta URL non locali per proteggere staging e produzione.');
  }
  return url.origin;
}

async function probe(label, url, key) {
  let response;
  try {
    response = await fetch(url, {
      headers: { apikey: key, Authorization: `Bearer ${key}` },
      signal: AbortSignal.timeout(10_000),
    });
  } catch (error) {
    abort(`${label} non raggiungibile (${error instanceof Error ? error.message : String(error)}).`);
  }
  if (!response.ok) abort(`${label} ha risposto HTTP ${response.status}.`);
  console.log(`OK  ${label} (HTTP ${response.status})`);
}

const local = readLocalSupabaseEnvironment();
const apiUrl = assertLoopback(local.API_URL);
const publishableKey = local.PUBLISHABLE_KEY || local.ANON_KEY;
if (!publishableKey) abort('chiave pubblicabile locale non disponibile.');

if (mode === '--check') {
  console.log('LEGHEVO local E2E smoke test\n');
  await probe('Supabase Auth', `${apiUrl}/auth/v1/settings`, publishableKey);
  await probe('Supabase REST', `${apiUrl}/rest/v1/`, publishableKey);
  console.log('\nLOCAL E2E PRONTO: servizi raggiungibili senza file .env.');
} else if (mode === '--start') {
  const expoCli = join(root, 'node_modules/expo/bin/cli');
  console.log('Avvio Expo collegato esclusivamente al Supabase locale...');
  const result = spawnSync(process.execPath, [expoCli, 'start'], {
    cwd: root,
    stdio: 'inherit',
    env: {
      ...process.env,
      EXPO_PUBLIC_SUPABASE_URL: apiUrl,
      EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY: publishableKey,
    },
  });
  process.exit(result.status ?? 1);
} else {
  abort('usa `--check` oppure `--start`.');
}
