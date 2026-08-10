# Validazione fondazione multi-provider LEGHEVO

Data: 10 agosto 2026.

## Ambito

Intervento successivo alla release applicativa `0.62.49`. La produzione è
rimasta esclusa. Il progetto Supabase coinvolto è esclusivamente lo staging
collegato al repository.

## Database locale

- Migrazione `159_multi_provider_identity_cache_and_quota.sql`: applicata.
- Seconda applicazione idempotente: superata.
- Migrazione `160_provider_free_budget_scheduler.sql`: applicata.
- Diagnostica multi-provider: `23/23` controlli booleani superati.
- Test budget transazionale:
  - 80 richieste ordinarie acquisite;
  - richiesta ordinaria successiva respinta nella prova originaria P0-only;
  - riserva critical acquisita;
  - nessun dato di prova conservato grazie al rollback.
- Test cache/telemetria transazionale:
  - cache write/read superato;
  - cache hit registrato come chiamata esterna evitata;
  - retry, fallback e previsione mensile presenti;
  - rollback finale superato.
- Trigger identità: giocatore e club di prova canonicalizzati automaticamente,
  poi rimossi dal rollback.

La policy finale consente l'accesso alle 20 unità riservate sia a P0 sia a P1,
come previsto dal contratto HIGH/CRITICAL.

## Applicazione ed Edge Function

- TypeScript: superato.
- Export Expo iOS: superato.
- Export Expo Android: superato.
- Bundle Edge locale: compilato e servito correttamente.
- Richiesta priva di credenziali: respinta con HTTP 401, confermando il gate
  server-side preesistente.

## Staging remoto

- Dry-run: proposte esclusivamente le migrazioni 159 e 160.
- Seed proposti: nessuno.
- Ruoli proposti: nessuno.
- Migrazioni 159 e 160 applicate con successo.
- Cronologia remota allineata fino alla 160.
- `sync-football-data`: deploy accettato, stato `ACTIVE`, versione 6.
- Nessun nuovo secret scritto o mostrato.

## Fase 2: percorso football-data.org

- Migrazione `161`: applicata e verificata prima in locale.
- Test transazionale del run provider-aware: lease e fencing acquisiti, poi
  rollback completo.
- Test negativo: giocatori via `football-data` respinti; il provider è
  autorizzato soltanto per `sync-fixtures`.
- Gateway con cache-first, quota manager, ledger e TTL calendario di 6 ore.
- Validazione fail-closed di ID, giornata, data UTC, squadre, punteggio e stato.
- Export Expo iOS/Android e typecheck: superati nuovamente.
- Dry-run staging: proposta esclusivamente la migrazione 161; nessun seed e
  nessun ruolo.
- Cronologia staging allineata fino alla 161.
- `sync-football-data`: stato `ACTIVE`, versione 11.
- Secret `FOOTBALL_DATA_API_KEY`: configurato sul solo staging; durante la
  verifica sono stati letti soltanto nome e digest.
- Smoke diretto provider: HTTP 200, competizione `SA`, 10 partite e campi
  contratto attesi.
- Migrazione `162`: ingresso atomico ristretto alle sole fixture
  `football-data`; dry-run con una sola migrazione, nessun seed/ruolo.
- Smoke end-to-end staging del 24 maggio 2026:
  - run `66de5af7-9d20-4eb5-9815-1e3c3e3d9e8a` completato;
  - 7 fixture finali pubblicate in un unico commit;
  - lifecycle `applied`, nessuna pubblicazione superseded;
  - 7/7 fixture collegate a un'identità canonica;
  - cache hit certificata, zero unità quota e chiamata esterna evitata.
- Nessun cron del nuovo provider è stato attivato.

## Fase 3: recovery provider-aware

- Migrazione `163`: il provider viene conservato nel payload immutabile dei
  nuovi run football-data e riutilizzato dalla coda recovery.
- Il worker arricchisce la richiesta recovery dal registro server-side, senza
  fidarsi di parametri aggiunti dal client.
- Test staging football-data del 23 maggio 2026: HTTP 200, 2 fixture,
  lifecycle applicato e `provider: football-data` presente nel run concluso.
- Regressione API-Football: HTTP 200 e run completato sulla finestra gratuita
  ammessa, senza fixture inventate.
- Test locali, seconda applicazione idempotente e dry-run della sola 163:
  superati; nessun seed e nessun ruolo.

## Fase 4: identità club verificata fra provider

- Catalogo API-Football Serie A 2024 letto con HTTP 200: 20 club ufficiali.
- Confronto con le identità football-data già osservate sullo staging: 12
  corrispondenze esatte verificate, senza deduzioni basate sul solo nome.
- Migrazione `164`: registro esplicito `verified_club_provider_links` e
  riconciliazione service-role-only verso le identità canoniche LEGHEVO.
- Test locale di convergenza: i due ID provider vengono collegati allo stesso
  UUID canonico.
- Test locale negativo: un mapping preesistente incompatibile viene messo in
  quarantena e apre un conflitto, senza fusione automatica.
- Seconda applicazione locale idempotente e dry-run staging della sola 164:
  superati; nessun seed applicativo e nessun ruolo.
- Verifica protetta sullo staging: 12/12 link `confirmed`, zero `pending`, zero
  conflitti e 12 UUID canonici condivisi fra i due provider.
- Nessun cron del nuovo provider è stato attivato.

## Fase 5: estensione catalogo club corrente

- Sincronizzazione football-data del 17 maggio 2026: HTTP 200, 10 fixture,
  lifecycle `applied` e 20 club della giornata canonicalizzati sullo staging.
- Migrazione `165`: aggiunte le cinque coppie ufficiali Atalanta, Bologna,
  Fiorentina, Inter e Lazio dal confronto football-data 2025/API-Football 2024.
- Applicazione locale ripetuta due volte senza duplicazioni o conflitti.
- Dry-run staging: proposta esclusivamente la migrazione 165; nessun seed,
  nessun ruolo e migrazione legacy dei cron 004 intenzionalmente esclusa.
- Verifica protetta finale: 17/17 link `confirmed`, zero `pending`, zero
  conflitti e 17 UUID canonici condivisi fra i provider.
- Restano fuori dal registro Pisa, Cremonese e Sassuolo: gli ID API-Football
  devono essere verificati sul catalogo corrente e non verranno dedotti dal
  solo nome.

## Fase 6: completamento mapping 20/20

- Tre ricerche live minime su API-Football, tutte HTTP 200 e senza errori:
  Pisa `801` (`PIS`), Cremonese `520` (`CRE`) e Sassuolo `488` (`SAS`).
- I risultati prima squadra sono stati distinti esplicitamente da omonimi,
  formazioni U18/U19/U20 e squadra femminile tramite paese e codice ufficiale.
- Migrazione `166`: collegate le tre coppie agli ID football-data già
  canonicalizzati, senza modificare il contratto fail-closed.
- Seconda applicazione locale idempotente superata.
- Dry-run staging: proposta esclusivamente la migrazione 166; nessun seed e
  nessun ruolo.
- Verifica protetta finale: 20/20 link `confirmed`, zero `pending`, zero
  conflitti nel registro, zero conflitti club aperti e 20 UUID canonici
  condivisi fra i provider.
- Nessun cron del nuovo provider è stato attivato.

## Gate ancora aperti

- Collaudo del Centro Operativo su una build collegata allo staging.
- Nuovo contratto release e nuova fingerprint: il preflight `0.62.49` resta
  intenzionalmente chiuso perché non deve essere modificato retroattivamente.
- Produzione e release finale `1.0.0`: non autorizzate da questo intervento.
