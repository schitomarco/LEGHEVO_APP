# Validazione tecnica LEGHEVO v0.62.46

## Obiettivo

Rendere affidabile il collaudo locale della release e coerenti i dati demo
della lega, senza modificare la produzione.

## Modifiche validate

- Il launcher `node scripts/local-e2e.mjs --start` isola temporaneamente
  `.env.local`, passa a Expo solo le credenziali loopback e lo ripristina alla
  chiusura. Questo evita di usare accidentalmente lo staging nei test locali.
- La lega demo ora espone otto partecipanti, coerenti con il contatore `8/8`.
- Le card operative della lega espongono nome e ruolo accessibili; Calendario
  può essere individuato dai test senza coordinate.
- Versione aggiornata a `0.62.46` e fingerprint SHA-256 certificata:
  `61b3336cc006d8b2739696dd9d6c0f9432585bd6f3ca70eb56656a7b9196d9e6`.
- Migrazione additiva `154`; nessun certificato delle release precedenti viene
  riscritto.

## Evidenze locali

- Simulazione completa con `ROLLBACK`, applicazione persistente e riesecuzione
  idempotente della migrazione 154: superate sul solo Supabase locale.
- Readiness locale: `certified`, 10/10 controlli, release attiva `0.62.46`.
- Preflight: contratto SQL `001`–`154`, TypeScript, configurazione Expo ed
  export Android/iOS: superati.
- Simulator iOS: barriera release superata dopo il controllo; accesso ospite,
  home e apertura della lega demo verificati, inclusa intestazione `8/8`.
- Il file `.env.local` è stato ripristinato dopo il test locale.

## Evidenze staging

- Dry-run: proposta esclusivamente la migrazione `154`, senza seed o ruoli.
- La migrazione 154 risulta registrata su staging; un secondo tentativo è
  stato rifiutato correttamente dalla chiave univoca della cronologia, senza
  rieseguire istruzioni SQL.
- RPC v9 con fingerprint certificata: HTTP 200, compatibile, rollout idoneo,
  release attiva `0.62.46`, readiness `certified` 10/10.
- RPC v9 con fingerprint alterata: HTTP 200, non compatibile e non idonea al
  rollout, codice `release.bundle_not_certified`.
- Simulator iOS collegato a staging: la barriera della release 0.62.46 viene
  superata e la schermata di accesso viene mostrata correttamente.
- Smoke test ospite automatizzato su staging: superati accesso senza account,
  Home, apertura della lega demo e presenza coerente di `8/8` squadre.

## Limiti residui

La checklist funzionale multi-account, le notifiche reali, le build firmate e
le prove di backup/restore infrastrutturali restano gate separati. Non sono
stati eseguiti su produzione.

La produzione reale non è stata interrogata, modificata o distribuita.
