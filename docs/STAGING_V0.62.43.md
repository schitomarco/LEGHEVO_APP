# Staging remoto LEGHEVO v0.62.43

Data della verifica: 6 agosto 2026.

## Esito

L'ambiente Supabase `LEGHEVO Staging`, ospitato nella regione europea
`eu-central-1`, è attivo e contiene la sequenza database approvata per la
v0.62.43. L'ambiente è separato dalla produzione; durante questa attività non
sono stati modificati altri progetti Supabase.

Questa verifica certifica la preparazione tecnica dello staging, non autorizza
il go-live di produzione e non sostituisce i collaudi funzionali end-to-end.

## Database

- Piano Supabase: Free, adeguato alla fase di sviluppo e collaudo iniziale.
- Migrazioni applicate: 143 file della sequenza `001`–`147`.
- Esclusioni intenzionali: `004`, `005`, `057` e `058`.
- `004_automatic_provider_sync.sql` è esclusa perché abilita sincronizzazioni
  pianificate che richiedono il piano Pro di API-Football e consumano quota.
- `005`, `057` e `058` sono seed riservati allo sviluppo.
- L'estensione `pg_cron` non è abilitata: nello staging non partono richieste
  automatiche verso API-Football.
- La migrazione 138 ha richiesto un timeout di sessione più ampio; la procedura
  è poi ripartita dalla prima migrazione non applicata e ha completato `138`–`147`.
- Diagnostica finale: 20 controlli su 20 `true`.
- Modello finale `production`: protetto, sano e fresco; stato `certified`, dieci
  controlli richiesti e superati, go-live tecnicamente consentito e versione
  attiva `0.62.43`.

La password del database è conservata nel Portachiavi di macOS con servizio
`supabase-leghevo-staging-db`; non è presente nel repository.

## Edge Function e segreti

- `sync-football-data`: distribuita e `ACTIVE`.
- `send-push-notifications`: distribuita e `ACTIVE`.
- Entrambe hanno `verify_jwt = false` perché usano l'autenticazione applicativa
  condivisa tramite il segreto server-side `automations`.
- Una richiesta senza `automations` è stata rifiutata da entrambe con `HTTP 401`.
- Una richiesta autenticata `GET`, scelta per non produrre effetti, ha raggiunto
  entrambe le funzioni ed è stata rifiutata dal relativo handler con l'atteso
  `HTTP 405`; questo conferma il riconoscimento della chiave.
- Il segreto `API_FOOTBALL_KEY` è configurato nello staging.
- Il segreto `automations` è configurato nello staging.
- Il valore locale di `automations` è conservato nel Portachiavi di macOS con
  servizio `supabase-leghevo-staging-automations`.
- Nessun valore segreto, token o identificativo del progetto è registrato in
  questo documento o nei file versionati.

## Limiti operativi attuali

L'account API-Football attuale è sul piano gratuito. Le sincronizzazioni restano
quindi manuali e controllate: prima di effettuare una richiesta reale occorre
scegliere un test minimo compatibile con la quota disponibile. Le automazioni
cron resteranno disattivate fino all'eventuale passaggio a un piano adeguato e a
un'esplicita approvazione operativa.

## Prossimi controlli

1. Eseguire una sincronizzazione API-Football minima e verificare persistenza,
   telemetria e consumo quota.
2. Collaudare `send-push-notifications` con credenziali e dispositivo di test.
3. Eseguire la checklist `docs/CHECKLIST_COLLAUDO_E2E.md` con account distinti.
4. Completare build e test iOS/Android su simulatori e dispositivi target.
5. Mantenere la produzione separata finché backup, restore rehearsal, rollout e
   rollback non saranno stati verificati e approvati esplicitamente.
