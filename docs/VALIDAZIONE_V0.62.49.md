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

## Build e collaudo su iPhone reale

- Development build EAS ad hoc generata, firmata, installata e avviata su
  iPhone reale con Developer Mode attivo.
- Collegamento Metro via rete locale e caricamento del bundle: superati.
- Smoke test manuale superato per ingresso ospite, collegamento staging,
  elenco e apertura lega, squadra, rosa, giocatori, classifica, calendario e
  mercato.
- Tre account QA auto-confermati sono stati associati a una lega staging
  isolata, con una squadra ciascuno. Matrice autorizzativa verificata su iPhone:
  Presidente, Admin e Mister superati.
- Il pannello Direzione falliva per timeout: lo stato aggregato di rilascio
  richiedeva circa 12,7 secondi e produceva circa 30 KB. Il client usa ora lo
  stato interattivo di gestione, misurato in circa 0,2 secondi, lasciando i
  controlli di rilascio fuori dal percorso di navigazione. Verifica Presidente
  su iPhone reale: superata.

## Recupero password

- Redirect mobile reso deterministico tramite `leghevo://reset-password` e
  autorizzato nello staging Supabase.
- Gestiti sia il codice PKCE sia `token_hash` di recovery, con verifica OTP e
  controllo esplicito della sessione prima del cambio password.
- Apertura del link nell'app: superata.
- Cambio password finale: da ripetere dopo il ripristino del limite email del
  provider Supabase; non e' ancora certificato come superato.

## Notifiche push su iPhone reale

- Permesso iOS concesso dall'utente e dispositivo Expo registrato sul solo
  staging per l'account Mister QA, con versione app `0.62.49`.
- Preferenze push e categorie sistema/lega abilitate; nessun token e' stato
  mostrato o scritto nei file del progetto.
- Notifica QA generata tramite `create_user_notification`, accodata dal trigger
  applicativo e consegnata dalla Edge Function `send-push-notifications`.
- Esito dispatcher: una consegna inviata, zero errori e zero retry; ticket Expo
  registrato nel database.
- Ricezione visiva su iPhone, apertura dell'app tramite tocco, navigazione alla
  Home e presenza nel centro notifiche interno: superate.

## Gate ancora aperti

- Build Android interna e prova su dispositivo/emulatore.
- Recupero password end-to-end dopo il reset del rate limit email.
- Backup/restore infrastrutturale reale.

La produzione reale non e' stata interrogata, modificata o distribuita.
