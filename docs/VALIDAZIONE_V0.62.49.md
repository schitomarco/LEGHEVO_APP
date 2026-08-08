# Validazione tecnica LEGHEVO v0.62.49

## Obiettivo

Preparare e collaudare una development build iOS generata da EAS, mantenendo
la produzione esclusa e riservando il numero `1.0.0` alla release finale.

## Configurazione iOS ed EAS

- `ios.config.usesNonExemptEncryption` impostato a `false`: il client non
  contiene implementazioni crittografiche proprietarie e usa i normali canali
  HTTPS delle librerie di rete.
- Aggiunto il profilo EAS `development-simulator`, separato dai profili per
  dispositivo e produzione.
- Nell'ambiente EAS `development` sono configurati soltanto URL staging e
  chiave pubblicabile Supabase. Password database, credenziali provider e
  segreti locali non sono stati caricati.
- `.env.local` resta escluso dal repository e dall'archivio di build.

## Evidenze tecniche

- Preflight release `0.62.49`: superato.
- Expo Doctor: 20/20 controlli superati.
- TypeScript ed export statico Android/iOS: superati.
- Migrazione 157 sul Supabase locale: simulazione con rollback, applicazione
  persistente e riesecuzione idempotente superate.
- Readiness locale: release `0.62.49`, stato `certified`, 10/10 controlli.

## Evidenze staging

- Dry-run iniziale: proposta esclusivamente la migrazione 157, senza seed o
  ruoli.
- Cronologia remota finale: allineata, nessuna migrazione pendente.
- RPC v9 con fingerprint certificata: HTTP 200, compatibile, rollout idoneo,
  release attiva `0.62.49`, readiness `certified` 10/10.
- RPC v9 con fingerprint alterata: HTTP 200, non compatibile, rollout negato,
  codice `release.bundle_not_certified`.

## Build e collaudo Simulator

- Development build EAS iOS Simulator completata con SDK Expo 57 e versione
  applicativa `0.62.49`.
- Artefatto installato correttamente su iPhone 17 Pro Simulator, iOS 27.0.
- Smoke test automatizzato superato: avvio app nativa, ingresso ospite, Home,
  apertura della lega demo, intestazione `8/8` e presenza della squadra demo.

## Gate ancora aperti

- Build iOS per dispositivo fisico con registrazione UDID e credenziali Apple.
- Build Android interna e prova su dispositivo/emulatore.
- Notifiche push reali su dispositivo fisico.
- Checklist multi-account e backup/restore infrastrutturale reale.

La produzione reale non e' stata interrogata, modificata o distribuita.
