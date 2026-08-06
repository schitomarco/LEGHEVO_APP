# Validazione proiezione runtime LEGHEVO v0.62.43

Data della verifica: 7 agosto 2026.

## Problema rilevato

Il primo smoke test iOS collegato allo staging ha ricevuto PostgreSQL `57014`
dalla RPC `get_leghevo_client_rollout_eligibility_v9`. Il percorso precedente
ricostruiva ricorsivamente il modello di integrità applicativa e non terminava
neppure con un timeout di sessione esteso a 60 secondi.

Il client ha reagito correttamente in modalità fail-closed e non ha consentito
l'accesso all'app collegata allo staging.

## Correzione

La migrazione `148_constant_time_runtime_release_projection.sql` mantiene firma,
nome e permessi dell'endpoint v9, ma legge le evidenze immutabili già prodotte
dal sigillo finale di production readiness:

- dieci check certificati e relativi snapshot;
- fingerprint di ogni check, run e certificato;
- fingerprint e revisione della testa finale;
- contratti firmati di release e rollout;
- generazioni e sequenze delle teste operative correnti.

La risposta resta fail-closed quando una fingerprint non coincide, una testa è
affected, compare una dead letter, una sequenza non è allineata, il kill switch
è attivo oppure il bundle non è certificato. La RPC non chiama più le funzioni
di introspezione globale dello schema nel percorso runtime.

## Evidenze locali

- Diagnostica `get_leghevo_runtime_release_projection_integrity_v1`: 20/20
  controlli booleani `true`.
- Esecuzione come ruolo `anon` con header attestati: `compatible=true`,
  `productionReadinessProtected=true`, `checkCount=10` e
  `productionGoLiveAllowed=true`.
- Bundle non certificato: `compatible=false` e motivo
  `release.bundle_not_certified`.
- `EXPLAIN ANALYZE`: planning 0,032 ms, esecuzione 8,555 ms.
- Seconda applicazione completa della migrazione: superata con 20/20 controlli.
- Migrazione e SQL standalone identici; SHA-256:
  `c969922f0959cf65a0b0a8929e7187e6af9ceddb16c12e3d5c79e6a4cf391258`.

## Evidenze staging

- Migrazione 148 applicata e registrata nello staging.
- Diagnostica remota: 20/20 controlli booleani `true`.
- Chiamata via PostgREST con chiave pubblicabile e header attestati: HTTP 200,
  `compatible=true`, `productionReadinessProtected=true`, `checkCount=10` e
  `productionGoLiveAllowed=true`.
- Latenza end-to-end via PostgREST: 462 ms.
- Smoke test Expo Go su Simulator iPhone 17 Pro: barriera superata e schermata
  reale di registrazione/accesso visualizzata.

Nessun database di produzione è stato coinvolto o autorizzato. Restano da
collaudare autenticazione e flussi applicativi con account staging distinti.
