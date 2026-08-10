const platform = process.argv[2];

function fail(message) {
  console.error(`REVENUECAT STORE PRE-FLIGHT NON SUPERATO: ${message}`);
  process.exit(1);
}

if (platform !== 'ios' && platform !== 'android') {
  fail('specificare ios oppure android.');
}

if (process.env.EXPO_PUBLIC_REVENUECAT_STORE_MODE !== 'store') {
  fail('EXPO_PUBLIC_REVENUECAT_STORE_MODE deve essere store.');
}
if (process.env.EXPO_PUBLIC_REVENUECAT_PURCHASES_ENABLED !== 'true') {
  fail('gli acquisti devono essere esplicitamente abilitati.');
}
if (process.env.EXPO_PUBLIC_REVENUECAT_API_KEY?.trim()) {
  fail('la chiave generica del Test Store deve essere assente.');
}

const variableName = platform === 'ios'
  ? 'EXPO_PUBLIC_REVENUECAT_IOS_API_KEY'
  : 'EXPO_PUBLIC_REVENUECAT_ANDROID_API_KEY';
const expectedPrefix = platform === 'ios' ? 'appl_' : 'goog_';
const apiKey = process.env[variableName]?.trim();

if (!apiKey?.startsWith(expectedPrefix) || apiKey.length <= expectedPrefix.length) {
  fail(`${variableName} non è una chiave SDK pubblica valida ${expectedPrefix}…`);
}
if (apiKey.startsWith('test_')) {
  fail('una chiave Test Store non può entrare nella build store.');
}

console.log(
  `REVENUECAT STORE PRE-FLIGHT SUPERATO: ${platform}, configurazione store fail-closed.`,
);
