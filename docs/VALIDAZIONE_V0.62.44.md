# Validazione tecnica LEGHEVO v0.62.44

## Obiettivo

Chiudere il rischio rilevato durante il QA della v0.62.43: una modifica del
lockfile poteva produrre bundle Hermes differenti senza cambiare la fingerprint
applicativa.

## Modifiche validate

- `package-lock.json` fa parte degli input ordinati della fingerprint SHA-256.
- Versione applicativa aggiornata in modo coerente in `package.json`,
  `package-lock.json`, `app.json` e `src/release.ts`.
- La migrazione `152` registra in un audit immutabile la ricertificazione dei
  modelli interessati dalle hotfix, quindi certifica release e rollout v0.62.44.
- La precedente release v0.62.43 rimane un certificato distinto e non viene
  modificata.

## Evidenze locali

- Simulazione completa terminata con `ROLLBACK`: superata.
- Applicazione persistente sul solo Supabase locale: superata.
- Riesecuzione idempotente: superata.
- Certificati v0.62.44: uno release e uno production readiness.
- Eventi di ricertificazione della migrazione 152: tre.
- Production readiness: `protected=true`, `healthy=true`, `fresh=true`,
  `status=certified`, `checkCount=10`, `failedCheckCount=0`,
  `goLiveAllowed=true`.
- TypeScript, configurazione Expo ed export Hermes Android/iOS: superati.

## Evidenze staging

- Dry-run: proposta esclusivamente la migrazione `152`.
- Primo e secondo tentativo: rollback automatico per `statement_timeout`, senza
  stato parziale persistente.
- Applicazione atomica con timeout limitato alla transazione: superata.
- Cronologia remota allineata fino alla migrazione `152`.
- Lint SQL remoto: zero errori.
- Test pubblico con versione e fingerprint certificate: `compatible=true`,
  `rolloutEligible=true`, readiness protetta, sana, fresca e `certified`.
- Test pubblico con fingerprint errata: `compatible=false`,
  `rolloutEligible=false`, motivo `release.bundle_not_certified`.

## Confini della validazione

Le attestazioni operative create dalla migrazione sono dati di collaudo del
prototipo e non dimostrano l'esistenza di backup fisici o restore reali. La
produzione reale non è stata contattata né modificata. Prima del go-live restano
obbligatori backup/restore esterno, build firmate, telemetria reale e checklist
operativa.
