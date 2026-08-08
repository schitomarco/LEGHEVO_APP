# Validazione tecnica LEGHEVO v0.62.47

## Obiettivo

Preparare una release candidata affidabile verso la futura versione pubblica
`1.0.0`, aggiornando Expo in modo incrementale fino a SDK 57. La produzione
non viene modificata.

## Modifiche validate

- Aggiornamento incrementale Expo SDK 54 -> 55 -> 56 -> 57, con le dipendenze
  React Native compatibili con SDK 57.
- Configurazione della schermata di avvio trasferita al plugin
  `expo-splash-screen`, richiesto dalle versioni Expo più recenti.
- Gestione difensiva dei dati opzionali delle notifiche push.
- Versione applicativa candidata `0.62.47` e migrazione additiva `155` con
  fingerprint SHA-256 certificata:
  `95e900f04bca008e1753d1e2fdf438ca361e833719e2dd363d88a13acdc5ac25`.

## Evidenze locali

- `expo-doctor`: 20/20 controlli superati.
- TypeScript, configurazione Expo ed export statico Android/iOS: superati.
- Preflight release: contratto SQL `001`-`155`, fingerprint e configurazione
  superati.
- Migrazione 155: simulazione con rollback, applicazione persistente e
  riesecuzione idempotente superate sul solo Supabase locale.
- Readiness locale: `certified`, 10/10 controlli, release attiva `0.62.47`.

## Evidenze staging

- Dry-run: proposta esclusivamente la migrazione `155`, senza seed o ruoli.
- Compatibilita' con fingerprint certificata: HTTP 200, compatibile, rollout
  idoneo, release attiva `0.62.47`, readiness `certified` e 10/10 controlli.
- Controllo con fingerprint alterata: HTTP 200, non compatibile e non idoneo
  al rollout, codice `release.bundle_not_certified`.
- Simulator iOS con Expo Go SDK 57: smoke test ospite automatizzato superato:
  ingresso senza account, Home, apertura della lega demo, intestazione `8/8`
  e presenza della squadra demo.

## Limiti e gate verso 1.0.0

- I test completi con ruoli reali (presidente, amministratore e mister) sono
  rinviati finche' il limite temporaneo di invio e-mail di Supabase staging non
  consente di completare le credenziali QA. Nessun account reale e' stato
  modificato per aggirarlo.
- Expo Go non supporta completamente le notifiche push remote Android: per
  quel collaudo servira' una development build o una build firmata.
- `npm audit` segnala dipendenze transitive Expo/Metro: 20 vulnerabilita'
  residue (9 moderate, 11 high, nessuna critical). La sola correzione proposta
  con `--force` declasserebbe Expo in modo incompatibile, quindi non e' stata
  applicata.
- Restano gate separati: build firmate, test su dispositivo reale, notifiche
  push reali, backup/restore infrastrutturale e checklist multi-account.

La produzione reale non e' stata interrogata, modificata o distribuita.
