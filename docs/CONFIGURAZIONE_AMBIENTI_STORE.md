# Ambienti LEGHEVO per gli store

## Regola vincolante

- `testflight` e `play-testing` usano esclusivamente **LEGHEVO Staging**.
- `production` usa esclusivamente un progetto **LEGHEVO Production** dedicato.
- **PADEL CORE non deve mai essere collegato a LEGHEVO.**

Il controllo e applicato da `app.config.js` durante la valutazione della
configurazione Expo. Una build store viene interrotta prima del bundle quando:

- mancano URL o publishable key Supabase;
- una build di test non punta a LEGHEVO Staging;
- una build production punta a LEGHEVO Staging;
- il tipo di ambiente non corrisponde al profilo EAS;
- RevenueCat non e in modalita store o usa chiavi del tipo sbagliato.

## Variabili EAS

Ambiente `preview`:

- `EXPO_PUBLIC_SUPABASE_URL`: URL di LEGHEVO Staging;
- `EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY`: publishable key di staging;
- chiavi SDK pubbliche RevenueCat Apple e Google;
- acquisti abilitati e modalita `store`.

Ambiente `production`:

- `EXPO_PUBLIC_SUPABASE_URL`: URL del progetto LEGHEVO Production;
- `EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY`: publishable key di produzione;
- chiavi SDK pubbliche RevenueCat Apple e Google;
- acquisti abilitati e modalita `store`.

`EXPO_PUBLIC_APP_ENV` viene impostata direttamente dai profili in `eas.json` e
non contiene segreti.

## Stato al 13 agosto 2026

- `LEGHEVO Production` e separato da staging e usa il project ref
  `cnkfruanqggnprkaujan`;
- le migrazioni sono applicate e allineate fino alla `170_public_v1_release.sql`;
- la release applicativa `1.0.0` e certificata e attiva al 100%;
- le Edge Function di produzione risultano attive;
- l'ambiente EAS `production` punta al progetto Supabase di produzione e usa
  le chiavi SDK RevenueCat native Apple e Google.

I secret server-side dei provider non devono mai essere copiati in Git o nelle
variabili `EXPO_PUBLIC_*`. La rotazione e la verifica di tali secret restano un
controllo operativo separato dalla certificazione dello schema.
