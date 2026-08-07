# Validazione tecnica LEGHEVO v0.62.45

## Obiettivo

Ridurre le vulnerabilità transitive correggibili senza introdurre l'upgrade
breaking a Expo 57 e legare il nuovo lockfile a una release certificata distinta.

## Modifiche validate

- Override patch per `brace-expansion` nelle linee usate da minimatch 3, 9 e 10.
- Override patch per `js-yaml` nelle catene Expo e Istanbul compatibili.
- Audit npm ridotto da 15 segnalazioni, di cui tre alte, a 13 segnalazioni, di
  cui una alta e dodici moderate.
- Versione aggiornata in `package.json`, `package-lock.json`, `app.json` e
  `src/release.ts`.
- Fingerprint SHA-256 certificata:
  `fb8bff0bbba1f7dfdc078dac8246168b8837934e3f3d5ef69bb5981c5129a967`.
- Migrazione `153` additiva; il certificato v0.62.44 resta immutato.

## Evidenze locali

- `npm ci`: superato.
- Expo Doctor: 18/18 controlli superati.
- TypeScript, configurazione Expo ed export Hermes Android/iOS: superati.
- Preflight release con migrazioni `001`–`153`: superato.
- Simulazione completa con `ROLLBACK`: superata; stato precedente v0.62.44
  conservato.
- Applicazione persistente sul solo Supabase locale: superata.
- Riesecuzione idempotente: superata rapidamente.
- Un solo certificato release e un solo certificato readiness per v0.62.45.
- Fingerprint certificata esatta, readiness `certified` 10/10, go-live logico
  consentito e rollback count pari a zero.

## Evidenze staging

- Dry-run: proposta esclusivamente la migrazione `153`, senza seed o ruoli.
- Applicazione atomica: superata con timeout limitato alla transazione.
- Dry-run post-deploy: database remoto allineato, nessuna migrazione pendente.
- Lint SQL remoto a livello errore: zero risultati.
- La validazione interna alla migrazione ha certificato release e readiness
  v0.62.45 prima del commit.

## Verifica remota sospesa

I due smoke test pubblici post-deploy della RPC v9, con fingerprint certificata
e alterata, non sono stati avviati: il sistema di approvazione ha raggiunto il
limite d'uso e indica nuova disponibilità dal 13 agosto 2026 alle 20:12. Non è
stato tentato alcun aggiramento. Il test resta un gate esplicito da completare.

## Rischio residuo e confini

Restano 13 segnalazioni npm. La correzione proposta per PostCSS e per la catena
Expo/UUID richiede Expo 57 e deve essere trattata come upgrade breaking con una
regressione dedicata; non è stato usato `npm audit fix --force`.

Le attestazioni operative sono dati di collaudo del prototipo e non dimostrano
backup fisici, restore o traffico reali. La produzione reale non è stata
contattata né modificata e il go-live non è autorizzato da questa validazione.
