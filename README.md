# LEGHEVO

**Versione corrente: 0.62.43 — Sviluppo 10 concluso; avanzamento tecnico 100%.**

Prototipo mobile iOS e Android di **LEGHEVO**, il fantasy football con
identità minimal premium e tono ironico da spogliatoio.



## Sviluppo 10 · Go-live, resilienza e chiusura al 100%

Obiettivo del macro-sviluppo: **100%**. Dopo la chiusura certificata della catena
operativa, LEGHEVO protegge la ripartenza dopo incidenti gravi tramite checkpoint
immutabili, prove di ripristino e piani di riavvio causale dei worker.

La v0.62.43 ha superato la validazione tecnica in un ambiente Supabase locale
isolato: sequenza di produzione `001`–`147`, diagnostica finale `20/20`, seconda
applicazione idempotente della migrazione 147, typecheck, configurazione Expo ed
export Android/iOS. Questo chiude lo sviluppo tecnico al 100%, ma non equivale a
un deployment o a un'autorizzazione al go-live sul database di produzione.

Il collaudo iOS sullo staging ha inoltre prodotto la migrazione operativa `148`:
la RPC pubblica di compatibilità legge ora il certificato finale e le teste
operative in tempo costante, senza ricostruire l'intero schema a ogni avvio. Il
bundle mobile e la versione `0.62.43` restano invariati.

Il successivo collaudo Auth ha prodotto la migrazione correttiva `149`: il
trigger di registrazione valorizza ora la fingerprint obbligatoria del nuovo
profilo. Sono stati verificati sullo staging login, rinnovo sessione, centro
account e centro privacy con un account QA isolato.

Il collaudo della Direzione Lega ha prodotto anche la migrazione `150`: gli
endpoint che possono chiudere offerte scadute dichiarano ora correttamente un
contratto `VOLATILE`, evitando transazioni PostgREST read-only. Il bundle mobile
certificato continua a usare lo stato gestionale v28, ora nuovamente operativo.

### Hotfix Direzione Lega · Contratto di scrittura coerente

- Migrazione: `database/150_management_state_write_contract.sql`.
- Correzione dell'errore PostgreSQL `25006` sulla catena gestionale v8–v31.
- Test staging: mercato, readiness e gestione v28/v31 tutti raggiungibili.
- Test ruoli: escalation manager bloccata, promozione proprietario valida,
  revisione obsoleta respinta e ripristino finale verificato.

### Hotfix Auth · Profilo atomico alla registrazione

- Migrazione: `database/149_auth_registration_profile_fingerprint.sql`.
- Correzione dell'incompatibilità tra il vincolo introdotto dalla migrazione 098
  e il trigger legale ridefinito dalla migrazione 099.
- Fingerprint iniziale coerente con nome, avatar assente, piano `free` e stato
  `active`.
- Test transazionali locale e staging: profilo, fingerprint, privacy e
  certificazione dell'accettazione tutti validi.
- Test staging con chiave pubblicabile: login, identità, refresh, account center
  e privacy center protetti.

### Hardening runtime · Proiezione di rilascio a costo costante

- Migrazione: `database/148_constant_time_runtime_release_projection.sql`.
- Script standalone: `LEGHEVO_SUPABASE_CONSTANT_TIME_RUNTIME_RELEASE_PROJECTION_v1.sql`.
- Riutilizzo dell'endpoint v9 esistente, senza modifica del contratto client.
- Verifica di fingerprint di run, check, certificato, testa, release e rollout.
- Confronto fail-closed con le teste correnti di telemetria, outbox, consumer,
  audit, disaster recovery, backup e ritorno in servizio.
- Diagnostica dedicata con esattamente 20 controlli booleani.
- Test locale anonimo: bundle certificato ammesso, bundle errato rifiutato.
- Latenza locale misurata: 8,555 ms contro il timeout oltre 60 secondi del
  percorso precedente.
- Latenza staging via PostgREST: 462 ms; smoke test iOS collegato allo staging
  arrivato correttamente alla schermata di registrazione e accesso.
- Evidenze: `docs/VALIDAZIONE_RUNTIME_PROJECTION_V0.62.43.md`.

### v0.62.43 · Sigillo finale di production readiness e go-live controllato

La disponibilità delle singole protezioni non è più sufficiente per autorizzare
il go-live. LEGHEVO certifica nello stesso punto dieci capacità terminali e
mantiene il client in modalità fail-closed se una dipendenza diventa incoerente.

- Migrazione: `database/147_final_production_readiness_and_go_live_seal.sql`.
- Script standalone: `LEGHEVO_SUPABASE_FINAL_PRODUCTION_READINESS_AND_GO_LIVE_SEAL_v1.sql`.
- Dieci controlli server-side: integrità applicativa, release, rollout, telemetria, outbox, consumer, audit, disaster recovery, backup fisico e ritorno in servizio.
- Run, controlli, certificati ed eventi immutabili con fingerprint SHA-256 separate.
- Testa `active`/`affected` protetta da trigger `ENABLE ALWAYS` e advisory lock comune.
- Go-live autorizzato soltanto con 10/10 controlli superati e release corrente coerente.
- Riconciliazione automatica sulle sette dipendenze operative terminali, senza riscrivere certificati già emessi.
- Promozione rollout v9 e client eligibility v9 fail-closed senza readiness certificata.
- Provider health v42, season state v21 e management state v31.
- Release v0.62.43 certificata con nuova telemetria, audit, checkpoint, backup, restore rehearsal e ritorno in servizio.
- Migrazione e SQL standalone identici, con 20 controlli diagnostici finali.
- Validazione locale isolata completata con 20/20 controlli: Sviluppo 10 concluso e avanzamento tecnico al 100%.
- Evidenze e limiti della verifica: `docs/VALIDAZIONE_V0.62.43.md`.
- Stato e configurazione dello staging remoto: `docs/STAGING_V0.62.43.md`.
- Preflight ripetibile: `node scripts/release-preflight.mjs`.
- Collaudo staging: `docs/CHECKLIST_COLLAUDO_E2E.md`.
- Smoke test Supabase locale senza file `.env`: `node scripts/local-e2e.mjs --check`.

### v0.62.42 · Riapertura controllata post-restore

Il restore non rende automaticamente sicuro il ritorno in produzione. LEGHEVO
entra in recovery mode, congela worker e traffico e riapre il servizio soltanto
dopo una certificazione completa della continuità applicativa e causale.

- Migrazione: `database/146_controlled_post_restore_service_return.sql`.
- Script standalone: `LEGHEVO_SUPABASE_CONTROLLED_POST_RESTORE_SERVICE_RETURN_v3.sql`.
- Revisione v2 pre-validazione: la sequenza di custodia puo ripartire da 1 solo quando aumenta la generazione del backup; resta monotona nella stessa generazione.
- Revisione v3 pre-validazione: le fingerprint di applicazione, release e rollout vengono normalizzate in SHA-256; se un modello terminale non espone una fingerprint valida, viene usato l'hash canonico del JSON del modello.
- Run recovery immutabili collegati all'ultimo artefatto, restore rehearsal e checkpoint certificati.
- Otto controlli obbligatori su integrità app, release, rollout, telemetria, outbox, consumer, audit e backup.
- Fingerprint SHA-256 separate per run, controlli, certificato ed eventi.
- Testa `recovery` fail-closed: scritture e worker disabilitati, traffico a zero.
- Riapertura atomica soltanto con 8/8 controlli `passed` e snapshot ancora corrente.
- Riconciliazione automatica `affected` quando cambiano release o catena backup.
- Promozione rollout v8 e client eligibility v8 bloccati senza certificato corrente.
- Provider health v41, season state v20 e management state v30.
- Release v0.62.42 certificata con nuovo backup, restore rehearsal e ritorno in servizio al 100%.
- Migrazione e SQL standalone identici, con 20 controlli diagnostici finali.
- L'avanzamento ufficiale resta al 95% fino alla conclusione dell'intero Sviluppo 10.

### v0.62.41 · Backup fisico certificato e restore rehearsal esterno

Il checkpoint logico non viene più considerato sufficiente da solo: la catena di
recovery registra anche un artefatto di backup esterno, ne verifica checksum e
dimensione, conserva una catena di custodia immutabile e certifica una prova di
restore su un target isolato.

- Migrazione: `database/145_certified_physical_backup_and_external_restore_rehearsal.sql`.
- Script standalone: `LEGHEVO_SUPABASE_CERTIFIED_PHYSICAL_BACKUP_AND_EXTERNAL_RESTORE_REHEARSAL_v1.sql`.
- Registro immutabile degli artefatti con generazione monotona, request ID idempotente e fingerprint SHA-256.
- Provider, locator di storage, target esterno e riferimento della chiave di cifratura conservati soltanto come hash.
- Verifica obbligatoria di checksum SHA-256, dimensione, cifratura a riposo e collegamento al checkpoint disaster recovery corrente.
- Catena di custodia append-only con sequenza monotona, collegamento crittografico all'evento precedente e trigger `ENABLE ALWAYS`.
- Restore rehearsal esterno con controllo checksum/dimensione, almeno 20 verifiche schema, 7 verifiche dati, zero mismatch e zero scritture distruttive.
- Promozione rollout v7 e client eligibility v7 fail-closed se backup, custodia o restore non sono certificati e freschi.
- Provider health v40, season state v19 e management state v29.
- Release v0.62.41 certificata con rollout iniziale al 100%, telemetria autorevole, nuovo checkpoint/drill e prova backup controllata.
- Il seed rappresenta una attestazione controllata del prototipo: la creazione materiale del backup e il restore reale restano operazioni del provider/worker esterno autorizzato.
- Migrazione e SQL standalone identici, con 20 controlli diagnostici finali.
- L'avanzamento ufficiale resta al 95% fino alla conclusione dell'intero Sviluppo 10.

### v0.62.40 · Checkpoint immutabile e prova di ripristino certificata

La release non può essere promossa usando soltanto telemetria e audit di
consegna: ogni generazione deve possedere anche un checkpoint disaster recovery
integro e un drill riuscito sulla stessa fotografia operativa.

- Migrazione: `database/144_certified_disaster_recovery_checkpoint_and_drill.sql`.
- Script standalone: `LEGHEVO_SUPABASE_CERTIFIED_DISASTER_RECOVERY_CHECKPOINT_AND_DRILL_v1.sql`.
- Checkpoint immutabili di release, rollout, telemetria, outbox, inbox, audit e sigillo applicativo.
- Sette componenti separati con fingerprint SHA-256 e radice del checkpoint certificata.
- Drill idempotenti con confronto di componenti, generazioni e sequenze anti-regressione.
- Piano di recovery conservato nel drill: ripresa telemetria, outbox, consumer e audit.
- Teste protette `ENABLE ALWAYS`, storico append-only e stati `certified`, `affected`, `revalidated`.
- Promozione rollout v6 e client eligibility v6 bloccati quando checkpoint o drill non sono aggiornati.
- Provider health v39, season state v18 e management state v28.
- Release v0.62.40 portata 10 → 35 → 60 → 85 → 100 con checkpoint e drill prima di ogni promozione.
- Migrazione e SQL standalone identici, con 20 controlli diagnostici finali.
- L'avanzamento ufficiale resta al 95% fino alla conclusione dell'intero Sviluppo 10.

## Sviluppo 9 · Integrità globale e preparazione al rilascio

Obiettivo del macro-sviluppo: **95%**. Dopo il sigillo applicativo globale, la
catena viene estesa alla distribuzione mobile: ogni bundle deve appartenere a
una release certificata e compatibile con lo schema attivo.


### v0.62.39 · Audit continuo end-to-end e chiusura certificata della catena operativa

La consegna e l'ack non vengono più considerati affidabili soltanto nel momento
in cui avvengono. Una nuova attestazione immutabile ricontrolla nel tempo
messaggi, teste di consegna, ricevute, sequenze, fingerprint e dead-letter per
entrambe le destinazioni operative.

- Migrazione: `database/143_continuous_end_to_end_delivery_audit_and_closure.sql`.
- Script standalone Supabase: `LEGHEVO_SUPABASE_CONTINUOUS_END_TO_END_DELIVERY_AUDIT_AND_CLOSURE_v2.sql`.
- Run di audit immutabili con generazione monotona e fingerprint SHA-256.
- Due attestazioni per ogni audit: Centro Operativo e dispatcher notifiche.
- Verifica continua di sequenze, conteggi, teste causali, ricevute, fingerprint e dead-letter.
- Teste audit separate, protette da trigger `ENABLE ALWAYS`, con stati `certified` e `affected`.
- Remediation append-only controllata: replay review, quarantena o indagine manuale, senza riscrivere ricevute o consegne.
- Promozione rollout v5 ammessa soltanto con audit protetto, sano e aggiornato all'ultima sequenza.
- Compatibilità client v5 fail-closed se compaiono nuovi eventi non attestati o divergenze end-to-end.
- Provider health v38, season state v17 e management state v27.
- Release v0.62.39 certificata e portata al 100% attraverso audit reali prima di ogni promozione.
- Lo script e la migrazione sono identici e terminano con esattamente 20 controlli booleani.
- Dopo la validazione 20/20, lo Sviluppo 9 potrà essere dichiarato concluso e l'avanzamento ufficiale passerà al 95%.

### v0.62.38 · Inbox autorevole e ack end-to-end

> **Correzione pre-validazione v2.** La diagnostica finale riconosce esattamente i quattro controlli legacy della v0.62.37 che diventano intenzionalmente falsi dopo la revoca dei vecchi bypass e l’attivazione della v0.62.38; nessun altro falso viene tollerato.

La consegna outbox non basta più a considerare applicato un evento. Ogni
consumatore deve essere certificato con generazione e fencing, applicare i
messaggi nella sequenza esatta e produrre una ricevuta immutabile collegata al
messaggio, alla destinazione e alla fingerprint dell'operazione eseguita.

- Migrazione: `database/142_authoritative_consumer_inbox_and_end_to_end_ack_safety.sql`.
- Script standalone Supabase: `LEGHEVO_SUPABASE_AUTHORITATIVE_CONSUMER_INBOX_AND_END_TO_END_ACK_v2.sql`.
- Certificati consumatore immutabili per Centro Operativo e dispatcher notifiche, con token conservato soltanto come hash.
- Claim consumer-aware strettamente vincolato alla prossima sequenza applicabile.
- Ack atomico: ricevuta applicativa, avanzamento monotono della testa e completamento outbox avvengono nella stessa transazione.
- Ricevute con firma SHA-256, fingerprint immutabile, application key e application fingerprint.
- Adozione esplicita e tracciata delle consegne storiche già completate dalla v0.62.37.
- Replay controllato soltanto su messaggi già applicati e con ricevuta autorevole, senza creare un secondo ack.
- Promozione rollout v4 bloccata se mancano ricevute, esistono gap o le fingerprint non coincidono.
- Revoca dei bypass diretti su claim v1, completion v1 e promozione rollout v3.
- Compatibilità client v4 e nuove RPC provider health v37, season state v16 e management state v26.
- Centro Operativo aggiornato con ricevute, consumatori certificati, gap e coerenza end-to-end.
- La release v0.62.38 viene certificata e portata al 100% esercitando realmente claim e ack end-to-end.
- Lo script standalone e la migrazione sono identici e terminano con esattamente 20 controlli booleani.
- L'avanzamento ufficiale resta al 90% fino al completamento e alla validazione dell'intero Sviluppo 9.

### v0.62.37 · Outbox operativa transazionale e dead-letter queue

Gli eventi critici di release, rollout e telemetria non vengono più considerati
consegnati soltanto perché registrati nel database. Un trigger transazionale
`ENABLE ALWAYS` li acquisisce nella nuova outbox con sequenza monotona,
deduplicazione per evento sorgente e due destinazioni certificate.

- Migrazione: `database/141_transactional_operational_outbox_and_dead_letter_safety.sql`.
- Script standalone Supabase: `LEGHEVO_SUPABASE_TRANSACTIONAL_OPERATIONAL_OUTBOX_AND_DEAD_LETTER_v1.sql`.
- Messaggi outbox immutabili con fingerprint, payload versionato e sequenza globale per ambiente.
- Cattura atomica degli eventi release, rollout e telemetria tramite trigger `ENABLE ALWAYS`.
- Deduplicazione su tabella ed ID dell'evento sorgente, senza doppie notifiche in caso di retry.
- Due destinazioni certificate: Centro Operativo e dispatcher notifiche.
- Claim concorrente con `FOR UPDATE SKIP LOCKED`, lease a scadenza, generazione worker e fencing token conservato soltanto come hash.
- Completamento idempotente, tentativi append-only, backoff e limite massimo di cinque tentativi.
- Nuova promozione rollout v3: una dead-letter o una cattura non protetta bloccano le promozioni successive; la precedente v2 non è più invocabile direttamente dal worker.
- Dead-letter queue immutabile per le consegne non recuperabili, leggibile integralmente soltanto dal backend; l'app riceve un riepilogo sanificato.
- Nuova compatibilità client v3 e nuove RPC provider health v36, season state v15 e management state v25.
- Il Centro Operativo mostra consegne, backlog, retry, lease scadute e dead-letter.
- La release v0.62.37 viene certificata, portata al 100% e tutti gli eventi seed vengono consegnati su entrambe le destinazioni.
- Lo script standalone e la migrazione sono identici e terminano con esattamente 20 controlli booleani.
- L'avanzamento ufficiale resta al 90% fino al completamento e alla validazione dell'intero Sviluppo 9.

### v0.62.36 · Telemetria operativa autorevole e rollback automatico

Il rollout progressivo non può più essere promosso usando un report generico o
fuori sequenza. Ogni finestra operativa viene legata a una sorgente certificata,
a una generazione di fencing, alla release attiva e alla generazione esatta del
rollout. Le finestre sono monotone, non sovrapponibili e immutabili.

- Migrazione: `database/140_authoritative_operational_telemetry_and_automatic_rollback_safety.sql`.
- Script standalone Supabase: `LEGHEVO_SUPABASE_AUTHORITATIVE_OPERATIONAL_TELEMETRY_AND_AUTOMATIC_ROLLBACK_v1.sql`.
- Sorgenti telemetriche certificate con token di fencing memorizzato solo come impronta e tabella sorgenti non leggibile direttamente dai client.
- Osservazioni append-only legate a release, piano rollout, generazione e percentuale esposta.
- Sequenze strettamente monotone, finestre non sovrapponibili e limite temporale anti-replay.
- Promozione `v2` ammessa soltanto con osservazione autorevole `healthy` della generazione corrente.
- Le vecchie RPC per report e promozione diretti non sono più eseguibili dal `service_role`.
- Stato `degraded`: pausa automatica e kill switch; stato `critical`: arresto e rollback automatico verso la release precedente certificata.
- Riconciliazione `affected`/`revalidated` senza riscrivere sorgenti, osservazioni o eventi.
- Nuove RPC provider health v35, season state v14 e management state v24.
- Il Centro Operativo mostra sorgente, sequenza, error rate, latenza p95 e stato del rollback automatico.
- La v0.62.36 viene portata 10 → 35 → 60 → 85 → 100 usando cinque finestre autorevoli `healthy`.
- Lo script standalone e la migrazione sono identici e terminano con esattamente 20 controlli booleani.
- L’avanzamento ufficiale resta al 90% fino al completamento e alla validazione dell’intero Sviluppo 9.

### v0.62.35 · Rollout progressivo certificato e kill switch

La compatibilità della release non basta per pubblicarla a tutti nello stesso
momento. Il nuovo contratto divide la distribuzione in scaglioni monotoni,
richiede un report di salute certificato prima di ogni promozione e attiva un
kill switch quando errori o crash superano le soglie del piano.

- Migrazione: `database/139_application_progressive_rollout_and_kill_switch_safety.sql`.
- Script standalone Supabase: `LEGHEVO_SUPABASE_APPLICATION_PROGRESSIVE_ROLLOUT_AND_KILL_SWITCH_v2.sql`.
- Piano rollout immutabile, testa protetta, eventi append-only e report salute append-only.
- Promozioni massime di 25 punti percentuali e report `healthy` obbligatorio per la generazione corrente.
- Pausa o arresto automatico quando error rate o crash superano le soglie certificate.
- Kill switch fail-closed lato client e coorte stabile per installazione.
- Vecchia release compatibile sempre ammessa durante il rollout; la nuova release rispetta la percentuale esposta.
- La v0.62.35 viene certificata e portata 10 → 35 → 60 → 85 → 100 nello stesso script, con quattro finestre di salute `healthy`.
- Nuove RPC provider health v34, season state v13 e management state v23.
- Il Centro Operativo mostra fase, percentuale, generazione e stato del kill switch.
- Lo script standalone e la migrazione sono identici e terminano con esattamente 20 controlli booleani.
- L’avanzamento ufficiale resta al 90% fino al completamento e alla validazione dell’intero Sviluppo 9.

### v0.62.34 · Contratto di rilascio compatibile e rollback certificato

Il database registra una testa atomica della release di produzione, certifica
versione, fingerprint del bundle e intervallo client ammesso, e permette il
rollback soltanto verso una release precedente già certificata sullo stesso
sigillo applicativo. Il client invia versione e fingerprint in ogni richiesta e
si blocca prima dell'accesso quando il contratto attivo non lo ammette.

- Migrazione: `database/138_application_release_compatibility_and_rollback_safety.sql`.
- Script standalone Supabase: `LEGHEVO_SUPABASE_APPLICATION_RELEASE_COMPATIBILITY_AND_ROLLBACK_v1.sql`.
- Lo script standalone e la migrazione sono identici e terminano con esattamente 20 controlli booleani.
- Nuovi registri `leghevo_application_release_certificates`, `leghevo_application_release_heads` e `leghevo_application_release_events`.
- Certificati ed eventi sono immutabili; la testa è modificabile solo dalle RPC protette sotto advisory lock e trigger `ENABLE ALWAYS`.
- La v0.62.33 viene certificata come target di rollback additivo e la v0.62.34 come release attiva di produzione.
- Le RPC `certify_leghevo_application_release_v1`, `activate_leghevo_application_release_v1`, `rollback_leghevo_application_release_v1` e `reconcile_leghevo_application_release_v1` sono riservate al `service_role`.
- Un'attivazione ordinaria non può retrocedere di versione: ogni downgrade passa obbligatoriamente dal rollback certificato; una testa `affected` deve prima essere riconciliata.
- La riconciliazione conserva lo stato sicuro precedente, registra eventi append-only `affected`/`revalidated` e non riscrive i certificati.
- La RPC pubblica `get_leghevo_client_compatibility_v1` verifica SemVer, fingerprint del bundle, intervallo supportato e attestazione delle intestazioni del client.
- Nuove RPC terminali provider health v33, season state v12 e management state v22.
- L'app aggiunge la barriera di avvio, la schermata di aggiornamento richiesto e un fingerprint riproducibile tramite `npm run release:fingerprint`.
- Dopo l'installazione del contratto, un errore di verifica blocca l'avvio in modalità fail-closed e permette soltanto di riprovare; il fallback legacy resta attivo esclusivamente quando la RPC non è ancora installata.
- L'avanzamento ufficiale resta al 90% fino al completamento e alla validazione di tutto lo Sviluppo 9.

### v0.62.33 · Sigillo globale di integrità applicativa

La singola certificazione dei moduli non basta per una release: ruoli, mercato,
competizione, giornate, competizioni speciali, account e provider devono essere
presenti contemporaneamente, con contratti trasversali, RLS, audit e Realtime
ancora coerenti. La nuova certificazione `application_integrity_v1` congela
questa fotografia senza modificare dati sportivi o account esistenti.

- Migrazione: `database/137_application_integrity_global_seal.sql`.
- Script standalone Supabase: `LEGHEVO_SUPABASE_APPLICATION_INTEGRITY_GLOBAL_SEAL_v2.sql`.
- Lo script standalone e la migrazione sono identici e terminano con esattamente 20 controlli booleani.
- Le sette aree funzionali e tredici contratti trasversali vengono aggregate in 20 capacità strutturali.
- La fingerprint include certificazioni precedenti, funzioni terminali, trigger `ENABLE ALWAYS`, policy RLS e ACL critiche.
- Il sigillo è registrato in `leghevo_model_certifications` con chiave `application_integrity_v1` e non modifica le certificazioni precedenti.
- Nuove RPC `get_leghevo_application_integrity_model_v1`, `get_league_provider_sync_health_v32`, `get_league_season_state_v11` e `get_league_management_state_v21`.
- Il Centro Operativo mostra lo stato globale 20/20 separatamente dal modello provider e segnala immediatamente una variazione strutturale.
- La v0.62.33 è stata validata in Supabase con 20/20 controlli `true`; l’avanzamento resta al 90% perché lo Sviluppo 9 prosegue.


## Sviluppo 8 · Dati ufficiali, rinvii e affidabilità operativa

Obiettivo del macro-sviluppo: **90%**, raggiunto con la validazione della v0.62.32. La v0.62.1 ha aperto il blocco mettendo
in sicurezza le decisioni eccezionali legate a partite rinviate, sospese o
cancellate.


### v0.62.32 · Chiusura certificata del modello di affidabilità provider

Lo Sviluppo 8 riceve un unico sigillo strutturale che verifica e collega tutte
le protezioni introdotte dai rinvii fino all’avvio certificato della stagione
successiva. Il certificato globale resta immutabile e rende immediatamente
visibile qualsiasi variazione successiva di funzioni, trigger, policy o schema.

- Migrazione: `database/136_provider_reliability_model_closure.sql`.
- Script standalone Supabase: `LEGHEVO_SUPABASE_PROVIDER_RELIABILITY_MODEL_CLOSURE_v2.sql`.
- Lo script standalone e la migrazione sono identici e terminano con esattamente 20 controlli booleani.
- Trenta diagnostiche provider già validate vengono raggruppate in 20 capacità indipendenti.
- Il sigillo viene registrato in `leghevo_model_certifications` con chiave `provider_reliability_v1` e impronta MD5 dello schema protetto.
- La certificazione è immutabile: una variazione successiva non la riscrive, ma rende il modello `affected` o in attenzione.
- Nuove RPC `get_league_provider_reliability_model_v1`, `get_league_provider_sync_health_v31`, `get_league_season_state_v10` e `get_league_management_state_v20`.
- Il Centro Operativo espone il numero di capacità certificate e distingue sigillo strutturale e salute operativa corrente.
- La v0.62.32 è stata validata in Supabase con 20/20 controlli `true`: lo Sviluppo 8 è concluso e l’avanzamento ufficiale è al 90%.

### v0.62.31 · Barriera causale certificata dell’avvio competizione provider

L’avvio della competizione viene ora eseguito soltanto quando il bootstrap
provider della nuova stagione, l’impronta del calendario fantasy e la giornata
inaugurale appartengono alla stessa catena certificata. La fotografia dell’avvio
resta immutabile durante l’avanzamento normale delle giornate.

- Migrazione: `database/135_provider_competition_start_causal_barrier_safety.sql`.
- Script standalone Supabase: `LEGHEVO_SUPABASE_PROVIDER_COMPETITION_START_CAUSAL_BARRIER_v1.sql`.
- Lo script standalone e la migrazione sono identici e terminano con esattamente 20 controlli booleani.
- Nuovi registri `provider_competition_start_certificates`, `provider_competition_start_heads` e `provider_competition_start_events`.
- La RPC `start_league_competition_guarded_v4` acquisisce i lock di rollover, bootstrap, competizione e certificazione prima dell’avvio.
- Un trigger `ENABLE ALWAYS` impedisce alle RPC precedenti e agli aggiornamenti diretti di impostare `competition_started_at` fuori dal contesto certificato.
- Il certificato lega bootstrap, fingerprint provider, fingerprint del calendario, giornata inaugurale, numero di squadre e conteggi della competizione.
- L’avanzamento dalla prima alle giornate successive non modifica il certificato; una regressione reale viene marcata `affected` senza riaprire la stagione.
- Stato stagione v9, management state v19 e provider health v30 espongono certificazione e anomalie alla Direzione.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.30 · Bootstrap provider certificato della nuova stagione

La stagione rinnovata non può più aprire il mercato usando il catalogo
calciatori dell'anno precedente né generare il calendario su un insieme di
partite provider incompleto o fuori scope. Catalogo e copertura della Serie A
vengono verificati rispetto alla stagione della nuova lega e alla continuità
anti-fork certificata.

- Migrazione: `database/134_provider_new_season_bootstrap_barrier_safety.sql`.
- Script standalone Supabase: `LEGHEVO_SUPABASE_PROVIDER_NEW_SEASON_BOOTSTRAP_BARRIER_v1.sql`.
- Lo script standalone e la migrazione sono identici e terminano con esattamente 20 controlli booleani.
- Nuovi registri `provider_season_bootstrap_certificates`, `provider_season_bootstrap_heads` e `provider_season_bootstrap_events`.
- Mercato e asta richiedono il catalogo autorevole della nuova stagione; il calendario richiede anche 20 squadre, 38 giornate e 380 partite provider certificate.
- I trigger critici su rose, nomine d'asta e calendario sono `ENABLE ALWAYS` e impediscono aggiramenti da RPC precedenti o scritture dirette.
- La RPC `renew_league_season_guarded_v3` collega il rinnovo al bootstrap e conserva la compatibilità con `renew_league_season`.
- Una variazione successiva di generazione, catalogo o scope partite marca il bootstrap `affected` senza cancellare rose o calendario già presenti.
- Stato stagione v8, management state v18 e provider health v29 espongono disponibilità del catalogo, copertura partite e certificato.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.29 · Rinnovo stagione certificato anti-fork

La creazione della stagione successiva è vincolata allo snapshot ufficiale
integro della stagione conclusa. Il rinnovo avviene sotto i lock causali comuni,
con request ID idempotente, copia atomica di partecipanti e squadre e certificato
immutabile della continuità tra le due leghe.

- Migrazione: `database/133_league_season_rollover_lineage_safety.sql`.
- Script standalone Supabase: `LEGHEVO_SUPABASE_SEASON_ROLLOVER_LINEAGE_BARRIER_v1.sql`.
- Lo script standalone e la migrazione sono identici e terminano con esattamente 20 controlli booleani.
- Nuovi registri `league_season_rollover_certificates`, `league_season_rollover_heads` e `league_season_rollover_events`.
- La RPC `renew_league_season_guarded_v2` impedisce rinnovi senza snapshot ufficiale, fork concorrenti e copie non coerenti.
- Anche la RPC storica `renew_league_season` passa obbligatoriamente dalla barriera certificata.
- I rinnovi già esistenti vengono adottati senza cancellare o riaprire stagioni; le incoerenze restano `affected` e visibili alla Direzione.
- Stato stagione v7, management state v17 e provider health v28 espongono certificazione e anomalie.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.28 · Snapshot ufficiale immutabile della stagione

La proclamazione del campione produce ora una fotografia definitiva e
immutabile di classifica, podio, campione, criteri di spareggio e riferimenti
causali provider. Lo snapshot viene creato nella stessa transazione del commit
di chiusura, sotto lo stesso advisory lock della catena provider.

- Migrazione: `database/132_league_season_official_snapshot_safety.sql`.
- Script standalone Supabase: `LEGHEVO_SUPABASE_LEAGUE_SEASON_OFFICIAL_SNAPSHOT_v1.sql`.
- Lo script standalone e la migrazione sono identici e terminano con esattamente 20 controlli booleani.
- Nuovi registri `league_season_official_snapshots`, `league_season_official_snapshot_heads` e `league_season_official_snapshot_events`.
- La fotografia ufficiale è immutabile; soltanto la testa può diventare `affected`, con storico append-only e senza riaprire o riscrivere la stagione.
- La RPC `complete_league_season_guarded_v3` collega atomicamente chiusura certificata e snapshot ufficiale.
- Stato stagione v6, management state v16 e provider health v27 espongono lo snapshot e l’eventuale avviso alla Direzione.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.27 · Barriera causale certificata della chiusura stagione provider

La chiusura della stagione è ora vincolata all’intera catena delle progressioni
giornata certificate. Il server impedisce il commit se una giornata è bloccata,
affected, priva di gate o collegata a una generazione di progressione diversa.
Le stagioni già concluse non vengono riaperte automaticamente: un’eventuale
regressione successiva viene tracciata e segnalata alla Direzione.

- Migrazione: `database/131_provider_season_completion_causal_barrier_safety.sql`.
- Script standalone Supabase: `LEGHEVO_SUPABASE_PROVIDER_SEASON_COMPLETION_CAUSAL_BARRIER_v1.sql`.
- Lo script standalone e la migrazione sono identici e terminano con esattamente 20 controlli booleani.
- Il lock causale comune copre riconciliazione, inserimento e aggiornamento delle progressioni e commit finale della stagione.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.26 · Barriera causale certificata della progressione giornata provider

- Migrazione: `database/130_provider_matchday_progression_causal_barrier_safety.sql`.
- Ogni giornata interamente ufficializzata riceve una testa causale con stato `clear`, `blocked` o `affected`.
- La progressione richiede impatto `clear`, lineage `certified` e chiusura certificata di ogni eventuale remediation per tutte le partite fantasy.
- Un trigger `ENABLE ALWAYS` blocca l'inserimento di `matchday_progression_runs` se l'officialization run è cambiata o la catena causale precedente non è più affidabile.
- Le progressioni già registrate non vengono annullate: diventano `affected` e vengono segnalate senza arretrare calendario, classifica o risultati.
- Nuovi registri `provider_matchday_progression_gate_heads` e `provider_matchday_progression_gate_events`, con RLS, guard protetto e storico immutabile.
- Nuove RPC `compute_provider_matchday_progression_gate_v1`, `reconcile_provider_matchday_progression_gate_v1`, `get_league_provider_matchday_progression_gate_v1` e `get_league_provider_sync_health_v25`.
- Centro Operativo aggiornato con indicatore `PROGRESSIONE GIORNATA PROTETTA`.
- Diagnostica `get_provider_matchday_progression_gate_integrity_v1` con esattamente 20 controlli.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.25 · Chiusura causale certificata della remediation provider

- Migrazione: `database/129_provider_official_result_remediation_completion_safety.sql`.
- Una remediation può diventare `resolved` soltanto quando l’impatto è tornato `clear` e la lineage ufficiale risulta certificata.
- Le correzioni manuali devono provare che lo stesso `result_correction_run` è presente tra le sorgenti della nuova officialization run.
- I recuperi spontanei del provider sono distinti e certificati come `auto_recovered`.
- Nuovi registri `provider_official_result_remediation_completion_heads` e `provider_official_result_remediation_completion_events`, con guard `ENABLE ALWAYS`, RLS e storico immutabile.
- Nuove RPC `compute_provider_official_result_remediation_completion_v1`, `reconcile_provider_official_result_remediation_completion_v1`, `get_league_provider_official_result_remediation_completion_v1` e `get_league_provider_sync_health_v24`.
- Centro Operativo aggiornato con indicatore `CHIUSURA REMEDIATION CERTIFICATA`.
- Diagnostica `get_provider_official_result_remediation_completion_integrity_v1` con esattamente 20 controlli.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.24 · Barriera di commit della lineage ufficiale provider

- Migrazione: `database/128_provider_official_result_lineage_commit_barrier_safety.sql`.
- La nuova lineage certifica il collegamento tra risultato ufficiale, proiezione, officialization run e correzione causale.
- Lo stato `assembling` sospende la valutazione d’impatto durante i due UPDATE atomici dell’ufficializzazione, evitando falsi allarmi e remediation non necessarie.
- Il trigger ascolta anche `officialization_run_id` e `correction_run_id`; una lineage completa ma incoerente viene classificata `invalid` senza modificare risultato o classifica.
- Nuove RPC `compute_provider_official_result_lineage_v1`, `reconcile_provider_official_result_lineage_v1`, `get_league_provider_official_result_lineage_v1` e `get_league_provider_sync_health_v23`.
- Diagnostica `get_provider_official_result_lineage_integrity_v1` con esattamente 20 controlli.

### v0.62.23 · Remediation causale dei risultati ufficiali provider

- Migrazione: `database/127_provider_official_result_remediation_safety.sql`.
- Ogni risultato `affected` entra in una coda causale con generazione d’impatto, stato e storico immutabile.
- La nuova RPC `start_provider_official_result_remediation_v1` acquisisce i lock nello stesso ordine del motore risultati e blocca la riapertura se la valutazione mostrata è stata nel frattempo sostituita.
- La correzione viene collegata al `result_correction_run` realmente creato e certificata come presa in carico causale.
- Un guard `ENABLE ALWAYS` rende obbligatorio il percorso causale per ogni risultato ancora `affected`; soltanto le correzioni già aperte prima dell’installazione possono risultare non certificate e restano evidenziate per audit.
- Il Centro Risultati usa automaticamente il percorso race-safe per le partite provider da correggere.
- Nuove RPC `get_league_provider_official_result_remediation_v1` e `get_league_provider_sync_health_v22`.
- Centro Operativo aggiornato con indicatore `REMEDIATION RISULTATI PROTETTA`.
- Diagnostica `get_provider_official_result_remediation_integrity_v1` con esattamente 20 controlli.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.22 · Impatto causale certificato sui risultati ufficiali

- Migrazione: `database/126_provider_official_result_impact_safety.sql`.
- Ogni risultato ufficiale viene collegato alla proiezione e alle due risoluzioni di formazione realmente utilizzate.
- Gli hash correnti delle risoluzioni vengono confrontati con quelli dell’ufficializzazione senza modificare risultato o classifica.
- Una variazione di voti, sostituzioni o disponibilità resa effettiva dal gate provider produce uno stato `affected` preciso per la singola partita fantasy.
- Le partite riaperte passano a `in_correction`; una nuova ufficializzazione coerente torna automaticamente `clear`.
- Teste protette ed eventi immutabili conservano generazione, motivo e impronta del rischio senza payload o credenziali.
- Nuove RPC `get_league_provider_official_result_impact_v1` e `get_league_provider_sync_health_v21`.
- Centro Operativo aggiornato con indicatore `IMPATTO RISULTATI CERTIFICATO`.
- Diagnostica `get_provider_official_result_impact_integrity_v1` con esattamente 20 controlli.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.21 · Gate certificato di consumo dei voti provider

- Migrazione: `database/125_provider_score_consumption_gate_safety.sql`.
- I valori provider restano immutati nello storico, ma soltanto le fotografie correnti e causalmente allineate possono essere utilizzate dal motore sportivo.
- La vista server-side `provider_match_score_consumption_v1` certifica stato, motivo e consumabilità di ogni voto.
- Le fotografie `stale`, mancanti o superate non possono attivare sostituzioni né entrare in proiezioni e nuove ufficializzazioni.
- Una giornata reale non risulta risolta finché ogni partita finale non possiede una fotografia voti finale e allineata.
- Le variazioni del gate aggiornano automaticamente le proiezioni non ufficializzate; i risultati già ufficiali restano stabili e vengono segnalati per verifica.
- Nuove RPC `get_league_provider_score_consumption_gate_v1` e `get_league_provider_sync_health_v20`.
- Centro Operativo aggiornato con indicatore `CONSUMO VOTI CERTIFICATO`.
- Diagnostica `get_provider_score_consumption_gate_integrity_v1` con esattamente 20 controlli.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.20 · Coerenza causale tra ciclo partita e fotografia voti

- Migrazione: `database/124_provider_fixture_score_causal_coherence_safety.sql`.
- Ogni fotografia voti conserva la revisione tecnica e la generazione causale della partita osservate al momento della certificazione.
- Le semplici riletture `refreshed` non invalidano i voti; soltanto creazione, avanzamento o correzione finale fanno avanzare la generazione causale.
- Un guard monotono impedisce salti o regressioni della revisione tecnica della partita.
- Se il calendario avanza o corregge semanticamente la partita, la fotografia precedente viene marcata `stale` senza cancellare o alterare voti e storico.
- Una nuova fotografia allineata alla generazione corrente ripristina automaticamente lo stato `aligned`.
- Le variazioni concorrenti tra acquisizione dei voti e pubblicazione vengono rilevate e certificate.
- Eventi immutabili registrano soltanto impronte anonime, generazioni e motivazioni sintetiche.
- Nuova RPC `finish_provider_sync_run_guarded_v10`, con instradamento server-side dalla v9.
- Nuove RPC `get_league_provider_fixture_score_coherence_center_v1` e `get_league_provider_sync_health_v19`.
- Centro Operativo aggiornato con indicatore `COERENZA PARTITA/VOTI PROTETTA`.
- Diagnostica `get_provider_fixture_score_coherence_integrity_v1` con esattamente 20 controlli.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.19 · Ciclo di vita monotono delle partite provider

- Migrazione: `database/123_provider_fixture_lifecycle_monotonic_safety.sql`.
- Ogni run calendario certifica gli stati delle partite prima del commit atomico.
- Gli stati API-Football vengono ricondotti a `scheduled`, `live`, `interrupted`, `cancelled` o `final`.
- Una partita finale non può tornare provvisoria, perdere i gol o cambiare squadre, giornata o data già consolidate.
- Le correzioni finali legittime restano consentite e incrementano la generazione del relativo head.
- Un guard `ENABLE ALWAYS` impedisce cancellazioni fisiche e scritture fuori riconciliazione.
- Nuova RPC `finish_provider_sync_run_guarded_v9`, con instradamento server-side dalla v8.
- Nuove RPC `get_league_provider_fixture_lifecycle_center_v1` e `get_league_provider_sync_health_v18`.
- Centro Operativo aggiornato con indicatore `CICLO PARTITE PROTETTO`.
- Diagnostica `get_provider_fixture_lifecycle_integrity_v1` con esattamente 20 controlli.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.18 · Fotografia autorevole dei voti partita provider

- Migrazione: `database/122_provider_fixture_score_reconciliation_safety.sql`.
- Ogni sincronizzazione dei voti crea una fotografia immutabile dei calciatori consegnati per la singola partita.
- La fotografia finale richiede copertura di entrambe le squadre e non può tornare provvisoria.
- I voti assenti da una nuova fotografia finale vengono ritirati logicamente impostando voto e fantavoto a `null`, senza cancellare payload o storico.
- I voti ritirati che ricompaiono vengono ripristinati nello stesso commit atomico.
- Un guard `ENABLE ALWAYS` impedisce scritture successive fuori dal percorso di riconciliazione certificato.
- Nuova RPC `finish_provider_sync_run_guarded_v8`, con instradamento server-side dalla v7 e dalle versioni precedenti.
- Nuove RPC `get_league_provider_fixture_score_center_v1` e `get_league_provider_sync_health_v17`.
- Centro Operativo aggiornato con indicatore `VOTI PARTITA RICONCILIATI`.
- Diagnostica `get_provider_fixture_score_reconciliation_integrity_v1` con esattamente 20 controlli.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.17 · Riconciliazione autorevole del catalogo calciatori provider

- Migrazione: `database/121_provider_player_catalog_reconciliation_safety.sql`.
- Ogni sincronizzazione stagionale completa produce una fotografia autorevole del catalogo calciatori e dei ruoli classic/mantra.
- Le stagioni storiche vengono certificate e scartate senza sostituire il catalogo corrente.
- I calciatori assenti dalla fotografia più recente vengono resi inattivi senza cancellare anagrafiche, rose o storico.
- I ruoli superati dei calciatori presenti vengono rimossi e sostituiti esattamente con quelli certificati dal provider.
- Guard permanenti impediscono ai flussi voti/partite successivi di riattivare calciatori ritirati o reinserire ruoli diversi dalla fotografia corrente.
- Le riconciliazioni vengono applicate nella stessa transazione della pubblicazione atomica e sono protette da lease, fencing, scope e watermark.
- I recuperi relativi a cataloghi storici vengono certificati `superseded` senza aprire retry inutili.
- Nuova RPC `finish_provider_sync_run_guarded_v7`, con instradamento server-side dalle versioni precedenti.
- Nuove RPC `get_league_provider_player_catalog_center_v1` e `get_league_provider_sync_health_v16`.
- Centro Operativo aggiornato con indicatore `CATALOGO CALCIATORI RICONCILIATO`.
- Diagnostica `get_provider_player_catalog_reconciliation_integrity_v1` con esattamente 20 controlli.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.16 · Watermark monotono anti-regressione provider

- Migrazione: `database/120_provider_monotonic_publication_watermark_safety.sql`.
- Ogni scope provider conserva l'ultima pubblicazione accettata in un watermark monotono.
- Un run iniziato prima non può sovrascrivere dati già pubblicati da un run iniziato più recentemente sullo stesso scope.
- Il confronto viene serializzato con lock transazionale per provider, tipo di sync e impronta dello scope.
- Le consegne superate vengono certificate, scartate dallo staging e chiuse senza aprire incidenti o retry inutili.
- Nuovi registri `provider_sync_scope_watermarks` e `provider_sync_scope_watermark_events`, privi di payload e credenziali.
- La nuova RPC `finish_provider_sync_run_guarded_v6` protegge sia i worker aggiornati sia le chiamate legacy v5/v4.
- Il completion guard consente lo stato `completed` senza pubblicazione soltanto in presenza di un evento immutabile `watermark.stale_run`.
- Nuove RPC `get_league_provider_scope_watermark_center_v1`, `get_league_provider_atomic_publication_center_v2` e `get_league_provider_sync_health_v15`.
- Centro Operativo aggiornato con indicatore `ORDINE TEMPORALE PROTETTO`.
- Diagnostica `get_provider_monotonic_publication_integrity_v1` con esattamente 20 controlli.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.15 · Scope semantico e write-set provider vincolato

- Migrazione: `database/119_provider_semantic_scope_safety.sql`.
- Ogni run può usare esclusivamente le operazioni previste dal proprio tipo di sincronizzazione.
- Le rose stagionali possono pubblicare soltanto atleti e ruoli; il calendario soltanto giornate e partite; i voti partita soltanto atleti, ruoli e punteggi.
- Stagione, data e partita richieste vengono confrontate con le righe normalizzate nello staging.
- Le relazioni tra ruoli e atleti, partite e giornate, voti e partita richiesta vengono certificate prima del commit.
- Nuovi registri `provider_sync_scope_certificates` e `provider_sync_scope_events`, senza payload, token o credenziali.
- La nuova RPC `finish_provider_sync_run_guarded_v5` certifica lo scope e poi usa la pubblicazione atomica v4.
- La pubblicazione legacy viene respinta se manca il certificato semantico.
- Gli errori di scope sono classificati come non recuperabili dalla policy retry.
- Nuove RPC `get_league_provider_semantic_scope_center_v1` e `get_league_provider_sync_health_v14`.
- Centro Operativo aggiornato con indicatore `SCOPE PROVIDER VINCOLATO`.
- Diagnostica `get_provider_semantic_scope_integrity_v1` con esattamente 20 controlli.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.14 · Staging isolato e pubblicazione atomica provider

- Migrazione: `database/118_provider_atomic_publication_safety.sql`.
- Atleti, ruoli, giornate, partite e voti vengono normalizzati in tabelle di staging non leggibili dagli utenti.
- La Edge Function usa `stage_provider_sync_write_guarded_v1` al posto degli upsert diretti nelle tabelle operative.
- La nuova RPC `finish_provider_sync_run_guarded_v4` certifica la consegna e pubblica tutti i dati in una sola transazione.
- Se il run fallisce o la consegna è incompleta, lo staging viene scartato e nessuna scrittura parziale raggiunge i dati live.
- Gli identificativi provvisori di atleti e giornate vengono riallineati agli ID live durante il commit, proteggendo anche pubblicazioni concorrenti.
- Il payload temporaneo viene eliminato dallo staging dopo pubblicazione o scarto; resta soltanto il manifest sintetico con conteggi e stato.
- Nuove RPC `get_league_provider_atomic_publication_center_v1` e `get_league_provider_sync_health_v13`.
- Centro Operativo aggiornato con indicatore `PUBBLICAZIONE ATOMICA ATTIVA`.
- Diagnostica `get_provider_atomic_publication_integrity_v1` con esattamente 20 controlli.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.13 · Completezza e coerenza delle consegne provider

- Migrazione: `database/117_provider_delivery_completeness_safety.sql`.
- Verifica semantica di `results`, pagina corrente, totale pagine e unicità delle entità ricevute.
- Controllo della stabilità del totale pagine durante la sincronizzazione delle rose stagionali.
- Certificati `provider_sync_delivery_certificates` con unità e impronte entità conservate esclusivamente lato server.
- Nessun identificativo provider grezzo, payload, token o chiave viene salvato nel registro di completezza.
- Nuova RPC `record_provider_sync_delivery_unit_v1` per certificare ogni pagina o risposta nella stessa lease del worker.
- Nuova RPC `finish_provider_sync_run_guarded_v3`: un run non può chiudersi come `completed` senza tutte le unità attese e conteggi coerenti.
- Le consegne incomplete vengono respinte con errore recuperabile e proseguono nel retry/backoff già validato.
- Nuove RPC di lettura `get_league_provider_delivery_center_v1` e `get_league_provider_sync_health_v12`.
- Centro Operativo aggiornato con indicatore `CONSEGNA PROVIDER CERTIFICATA`.
- Diagnostica `get_provider_delivery_completeness_integrity_v1` con esattamente 20 controlli.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.12 · Contratti runtime e quarantena dei payload provider

- Migrazione: `database/116_provider_payload_contract_quarantine_safety.sql`.
- Validazione runtime dell'envelope e delle risposte API-Football per rose, calendario e voti.
- Secondo controllo nel database tramite `apply_provider_sync_write_guarded_v2`, nella stessa transazione del fencing e dell'upsert.
- I payload fuori contratto vengono respinti prima della scrittura e il run viene chiuso come fallito.
- Registro immutabile `provider_payload_contract_violations` con impronta SHA-256, dimensione e motivo sintetico; il payload grezzo non viene salvato.
- Gli errori di contratto usano il messaggio protetto `Payload provider non valido` e vengono classificati come non recuperabili dalla policy retry esistente.
- Nuove RPC `record_provider_payload_contract_violation_v1`, `get_league_provider_payload_contract_center_v1` e `get_league_provider_sync_health_v11`.
- Edge Function e file standalone di deploy aggiornati con lo stesso contratto `api-football-v3/leghevo-contract-v1`.
- Centro Operativo aggiornato con indicatore `CONTRATTI PAYLOAD ATTIVI` e conteggio delle quarantene nelle ultime 24 ore.
- Diagnostica `get_provider_payload_contract_quarantine_integrity_v1` con esattamente 20 controlli.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.11 · Lease e fencing protetto del worker provider

- Migrazione: `database/115_provider_worker_lease_fencing_safety.sql`.
- Lease esclusiva associata a ogni run provider tramite token non riutilizzabile e contatore di epoca.
- Rinnovo obbligatorio della lease durante ogni heartbeat del worker.
- Verifica server-side del token e scrittura sportiva eseguite nella stessa transazione tramite `apply_provider_sync_write_guarded_v1`.
- Un worker scaduto, revocato o sostituito non può più aggiornare dati né concludere l'esecuzione precedente.
- Scadenza automatica delle lease inattive con chiusura del run attraverso il percorso certificato già esistente.
- Registro immutabile `provider_sync_worker_lease_events`, privo di token, payload e credenziali.
- Nuove RPC `start_provider_sync_run_guarded_v2`, `apply_provider_sync_write_guarded_v1`, `heartbeat_provider_sync_run_guarded_v2`, `finish_provider_sync_run_guarded_v2`, `claim_provider_recovery_request_v3`, `claim_next_provider_recovery_request_v4`, `get_league_provider_recovery_center_v7` e `get_league_provider_sync_health_v10`.
- Edge Function predisposta ad acquisire, rinnovare e verificare la lease; deploy definitivo rimandato alla fase finale dell'ambiente.
- Centro Operativo aggiornato con indicatore `FENCING WORKER ATTIVO` e conteggi delle lease attive o scadute.
- Diagnostica `get_provider_worker_lease_fencing_integrity_v1` con esattamente 20 controlli.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.10 · Verifica protetta dell'efficacia dei recuperi provider

- Migrazione: `database/114_provider_recovery_outcome_verification_safety.sql`.
- Certificazione automatica di ogni recupero `completed` rispetto allo stato reale dell'incidente collegato.
- Distinzione tra esecuzione tecnica riuscita e recupero realmente efficace dei dati provider.
- Nuovo registro immutabile `provider_recovery_outcome_certificates`, protetto da RLS e pubblicato in Realtime.
- Se l'incidente resta aperto, il recupero prosegue automaticamente nel backoff già validato senza consentire cicli manuali paralleli.
- Gli esiti storici già superati da attività successive sono certificati come `superseded` senza creare retry duplicati.
- Quando i tentativi risultano esauriti, viene riutilizzato il circuit breaker v0.62.9 senza introdurre un secondo blocco concorrente.
- Nuove RPC `get_league_provider_outcome_verification_center_v1`, `get_league_provider_retry_center_v3`, `get_league_provider_recovery_center_v6` e `get_league_provider_sync_health_v9`.
- Centro Operativo aggiornato con indicatore `VERIFICA EFFICACIA ATTIVA` e conteggi dei recuperi verificati, da riprovare ed esauriti.
- Diagnostica `get_provider_recovery_outcome_verification_integrity_v1` con esattamente 20 controlli.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.9 · Circuit breaker protetto dei recuperi provider

- Migrazione: `database/113_provider_recovery_circuit_breaker_safety.sql`.
- Apertura automatica di un circuit breaker quando i retry protetti risultano esauriti o non recuperabili.
- Blocco server-side delle nuove richieste manuali, senza modificare la firma della RPC storica.
- Rilascio revisionato e idempotente riservato a Presidente/Admin tramite `release_provider_recovery_circuit_breaker_guarded_v1`.
- Registri `provider_recovery_circuit_breakers` e `provider_recovery_circuit_breaker_events`, con RLS e storico immutabile.
- Nuove RPC di lettura `get_league_provider_circuit_breaker_center_v1`, `get_league_provider_retry_center_v2`, `get_league_provider_recovery_center_v5` e `get_league_provider_sync_health_v8`.
- Centro Operativo aggiornato con stato del blocco e comando esplicito di riapertura.
- Diagnostica `get_provider_recovery_circuit_breaker_integrity_v1` con esattamente 20 controlli.
- Avanzamento ufficiale invariato all’85%: lo Sviluppo 8 resta in corso.

### v0.62.8 · Retry automatico e backoff protetto del provider

- Migrazione: `database/112_provider_recovery_retry_backoff_safety.sql`.
- Classificazione deterministica dei fallimenti provider in rate limit, timeout, rete, provider, configurazione, richiesta o causa sconosciuta.
- Pianificazione automatica di massimo tre retry con backoff crescente e protezione dai duplicati.
- Registri `provider_recovery_retry_schedules` e `provider_recovery_retry_events`, con storico immutabile e RLS.
- Nuove RPC server-side `dispatch_due_provider_recovery_retry_v1` e `claim_next_provider_recovery_request_v3`.
- Nuove RPC di lettura `get_league_provider_retry_center_v1`, `get_league_provider_recovery_center_v4` e `get_league_provider_sync_health_v7`.
- Edge Function aggiornata per servire prima i retry automatici maturati e poi la coda manuale.
- Centro Operativo aggiornato con indicatore `RETRY AUTOMATICO ATTIVO`, tentativi programmati, esauriti e prossimo orario utile.
- Diagnostica `get_provider_recovery_retry_backoff_integrity_v1` con 20 controlli.

### v0.62.7 · Heartbeat e avanzamento protetto del worker provider

- Migrazione: `database/111_provider_worker_heartbeat_and_progress_safety.sql`.
- Heartbeat revisionato durante le sincronizzazioni e i recuperi API-Football.
- Fase, avanzamento, totale previsto e record elaborati salvati nel run certificato.
- Storico Realtime esteso con il progresso associato a ogni revisione.
- Nuova RPC server-side `heartbeat_provider_sync_run_guarded_v1` protetta dal controllo ottimistico della revisione.
- Nuove RPC di lettura `get_league_provider_recovery_center_v3` e `get_league_provider_sync_health_v6`.
- Edge Function aggiornata per inviare heartbeat dopo ogni pagina, giornata o squadra elaborata.
- Centro Operativo aggiornato con indicatore `HEARTBEAT WORKER ATTIVO` e progresso del recupero.
- Diagnostica `get_provider_worker_heartbeat_integrity_v1` con 20 controlli.

### v0.62.6 · Watchdog protetto dei recuperi provider

- Migrazione: `database/110_provider_recovery_watchdog_safety.sql`.
- Rilevamento dei recuperi rimasti in esecuzione senza aggiornamenti del worker.
- Timeout distinti: 15 minuti per i voti partita, 20 minuti per il calendario e 60 minuti per le rose stagionali.
- Chiusura atomica dei run realmente scaduti e riapertura della possibilità di accodare un nuovo recupero.
- Registro immutabile `provider_recovery_watchdog_events`, protetto da RLS e pubblicato in Realtime.
- Nuove RPC server-side `expire_stale_provider_recovery_requests_v1`, `claim_provider_recovery_request_v2` e `claim_next_provider_recovery_request_v2`.
- Nuove RPC di lettura `get_league_provider_recovery_center_v2` e `get_league_provider_sync_health_v5`.
- Edge Function predisposta a eseguire il watchdog prima della presa in carico della coda; deploy e pianificazione restano nella configurazione finale dell'ambiente.
- Centro Operativo aggiornato con stato watchdog, recuperi scaduti e run bloccati.
- Diagnostica `get_provider_recovery_watchdog_integrity_v1` con 20 controlli.

### v0.62.5 · Recupero operativo provider protetto

- Migrazione: `database/109_provider_recovery_queue_safety.sql`.
- Coda atomica e idempotente delle richieste di recupero legate agli incidenti provider aperti.
- Registro revisionato `provider_recovery_requests` e storico immutabile `provider_recovery_request_events`.
- Un solo recupero attivo per incidente, con protezione da doppi tocchi e richieste concorrenti.
- Un recupero crea un nuovo tentativo reale e non riutilizza un run già concluso; può condividere soltanto un run ancora in corso.
- Nuove RPC `request_provider_recovery_guarded_v1`, `claim_provider_recovery_request_v1` e `get_league_provider_recovery_center_v1`.
- Collegamento automatico tra richiesta, nuovo run provider e relativo esito conclusivo.
- Edge Function `sync-football-data` predisposta per eseguire le richieste accodate dal worker server. La distribuzione e l’attivazione periodica del worker restano nella fase finale di configurazione dell’ambiente.
- Centro Operativo aggiornato con coda, recuperi in corso e pulsante `ACCODA RECUPERO PROVIDER`.
- Nuova RPC `get_league_provider_sync_health_v4` e diagnostica `get_provider_recovery_queue_integrity_v1` con 20 controlli.

### v0.62.4 · Incidenti operativi provider protetti

- Migrazione: `database/108_provider_operational_incident_safety.sql`.
- Apertura automatica degli incidenti dopo sincronizzazioni fallite o fotografie qualità in attenzione.
- Aggiornamento revisionato dello stesso incidente senza duplicazioni.
- Risoluzione automatica dopo un nuovo sync completato o il ripristino della qualità dati.
- Registri `provider_operational_incidents` e `provider_operational_incident_events` protetti da RLS.
- Nuove RPC `get_league_provider_incident_center_v1` e `get_league_provider_sync_health_v3`.
- Centro Operativo aggiornato con incidenti attivi, criticità e risoluzioni delle ultime 24 ore.
- Diagnostica `get_provider_operational_incident_integrity_v1` e tabella finale di 20 controlli.

### v0.62.3 · Freschezza e copertura dei dati provider

- Migrazione: `database/107_provider_data_freshness_and_coverage_safety.sql`.
- Fotografia immutabile della qualità dopo ogni sincronizzazione completata.
- Controllo di partite non collegate, risultati finali privi di gol, voti fuori intervallo e copertura incompleta.
- Rilevamento di calendario o rating live non aggiornati entro le finestre operative previste.
- Nuove RPC `get_league_provider_data_quality_v1` e `get_league_provider_sync_health_v2`.
- Centro Operativo aggiornato con anomalie, partite definitive, voti definitivi e stato di freschezza.
- Registro `provider_data_quality_snapshots` pubblicato in Realtime senza payload sensibili.
- Diagnostica `get_provider_data_freshness_integrity_v1` e tabella finale di 20 controlli.

### v0.62.2 · Sincronizzazione provider protetta

- Migrazione: `database/106_provider_sync_safety.sql`.
- Richieste API-Football normalizzate e idempotenti per finestra temporale.
- Lock transazionale e riuso dei run già in corso o completati per evitare doppie elaborazioni.
- Revisioni, tentativi e impronte aggiunti a `provider_sync_runs` senza modificare lo storico.
- Nuovo registro immutabile `provider_sync_run_events`, privo di payload e pubblicato in Realtime.
- Nuove RPC server-side `start_provider_sync_run_guarded_v1` e `finish_provider_sync_run_guarded_v1`.
- Edge Function `sync-football-data` instradata sul registro protetto.
- Nuova RPC `get_league_provider_sync_health_v1` e monitor `PIPELINE DATI PROTETTO` nel Centro Operativo.
- Diagnostica `get_provider_sync_safety_integrity_v1` e tabella finale di 20 controlli.

### v0.62.1 · Gestione protetta di rinvii e sospensioni

- Migrazione: `database/105_postponed_fixture_resolution_safety.sql`.
- Applicazione e revoca del voto d'ufficio atomiche, idempotenti e protette da lock transazionale.
- Revisione ottimistica contro modifiche concorrenti da più dispositivi.
- Registro immutabile `fixture_resolution_action_runs` e impronta dello stato di ogni decisione.
- Continuità con il risultato definitivo del provider e con i ricalcoli non ufficiali della giornata.
- Nuove RPC `apply_league_fixture_political_score_guarded_v1`, `revoke_league_fixture_political_score_guarded_v1` e `get_league_postponement_center_v2`.
- Diagnostica `get_league_postponement_resolution_integrity_v1` e tabella finale di 20 controlli.
- Centro Rinvii aggiornato con indicatore `GESTIONE PROTETTA · ANTI-DOPPIO TOCCO` e revisione certificata.

## Sviluppo 7 · Account, privacy e servizi di rilascio

Obiettivo del macro-sviluppo: **85%**. La v0.62.0 chiude e certifica il
modello account, privacy, assistenza e notifiche.

### v0.62.0 · Chiusura certificata dello Sviluppo 7

- Correzione compatibilità PostgreSQL: riepilogo diagnostico basato su `jsonb_each`, senza `jsonb_object_length`.
- Migrazione: `database/104_account_services_model_closure.sql`.
- Certificazione globale `account_services_v1` nel registro immutabile dei modelli LEGHEVO.
- Verifica unificata di 20 capacità e riuso delle nove diagnostiche validate dalla v0.61.1 alla v0.61.9.
- Impronta stabile di tabelle, funzioni, trigger, policy e permessi.
- Nuove RPC `get_my_account_services_model_closure_integrity_v1` e `get_my_account_center_v5`.
- Centro Account con indicatore `MODELLO CERTIFICATO`.
- Lo Sviluppo 7 porta l'avanzamento ufficiale del progetto all'85% dopo la validazione dei 20 controlli.

### v0.61.9 · Centro unificato dei servizi account

- Migrazione: `database/103_account_services_integrity_hub.sql`.
- Stato revisionato `account_service_states` e registro immutabile `account_service_events`.
- Collegamento automatico degli otto registri certificati di account, privacy, assistenza e notifiche.
- Backfill non distruttivo delle azioni già presenti e impronta SHA-256 dello stato unificato.
- Nuove RPC `get_my_account_service_hub_v1` e `get_my_account_center_v4`.
- Realtime unificato e indicatore mobile `CENTRO SERVIZI ACCOUNT · CERTIFICATO`.
- Diagnostica `get_account_services_integrity_hub_v1` con 20 controlli.

### v0.61.8 · Esportazione dati personali protetta

- Migrazione: `database/102_personal_data_export_safety.sql`.
- Registro personale immutabile `personal_data_export_runs`.
- Esportazione JSON idempotente con lock transazionale per account.
- Impronta SHA-256, revisione progressiva e certificato incluso nel file esportato.
- RPC storiche di esportazione bloccate agli account e riutilizzate soltanto dal wrapper protetto.
- Centro Privacy v4, sincronizzazione Realtime e indicatore mobile `ESPORTAZIONE PROTETTA`.
- Diagnostica `get_personal_data_export_safety_integrity_v1` con 20 controlli.

### v0.61.7 · Sicurezza credenziali e cambio password certificato

- Migrazione: `database/101_account_credential_security_safety.sql`.
- Stato revisionato `account_security_states` e registro immutabile `account_security_events`.
- Trigger automatici su `auth.users` per certificare cambio password, cambio email e conferma email.
- Nessuna password, hash o token viene copiato nelle tabelle applicative.
- Centro Account v3, sincronizzazione Realtime e indicatore mobile `CREDENZIALI PROTETTE`.
- Diagnostica `get_account_credential_security_integrity_v1` con 20 controlli.

### v0.61.6 · Centro Notifiche protetto

- Migrazione: `database/100_notification_center_safety.sql`.
- Registro immutabile `notification_action_runs`.
- Lettura singola e massiva idempotenti con lock transazionale.
- Revisione e impronta SHA-256 dello stato di ogni notifica.
- Centro Notifiche v2, compatibilità delle RPC storiche e scritture dirette bloccate.
- Sincronizzazione Realtime e indicatore mobile `INBOX PROTETTA`.
- Diagnostica `get_notification_center_safety_integrity_v1` con 20 controlli.

### v0.61.5 · Accettazione documenti legali protetta

- Migrazione: `database/099_legal_acceptance_and_age_gate_safety.sql`.
- Registro immutabile `legal_acceptance_action_runs`.
- Accettazione idempotente con revisione ottimistica e lock per account.
- Collegamento certificato alla release italiana pubblicata e al requisito minimo di età.
- Impronta SHA-256 dello stato accettato e compatibilità della registrazione Auth.
- Centro Privacy v3, sincronizzazione Realtime e indicatore mobile `ACCETTAZIONE PROTETTA`.
- Diagnostica `get_legal_acceptance_safety_integrity_v1` con 20 controlli.

### v0.61.4 · Profilo e cancellazione account protetti

- Migrazione: `database/098_account_profile_and_deletion_safety.sql`.
- Registro immutabile `account_action_runs`.
- Aggiornamento nome atomico tra profilo pubblico e metadata Auth.
- Idempotenza e revisione ottimistica contro azioni concorrenti da più dispositivi.
- Cancellazione protetta con trasferimento delle leghe, anonimizzazione storica e rimozione dei token push.
- Centro account v2, Realtime e indicatore mobile `GESTIONE PROTETTA`.
- Diagnostica `get_account_profile_safety_integrity_v1` con 20 controlli.

### v0.61.3 · Preferenze e dispositivi push protetti

- Migrazione: `database/097_push_preferences_and_device_safety.sql`.
- Registro immutabile `push_preference_action_runs`.
- Salvataggio preferenze idempotente con revisione ottimistica.
- Registrazione, disattivazione e rilascio del dispositivo protetti da lock transazionale.
- Blocco del trasferimento silenzioso di token attivi tra account differenti.
- Centro preferenze v2, sincronizzazione Realtime e indicatore mobile `GESTIONE PROTETTA`.
- Diagnostica `get_push_preference_safety_integrity_v1` con 20 controlli.

### v0.61.2 · Centro Assistenza protetto e revisionato

- Migrazione: `database/096_support_request_safety.sql`.
- Registro immutabile `support_request_action_runs`.
- Apertura, risposta e chiusura idempotenti con lock transazionale.
- Revisione ottimistica contro sessioni o dispositivi non aggiornati.
- Lavorazione service-role revisionata e compatibilità delle RPC storiche.
- Centro Assistenza v2, Realtime completo e indicatore mobile `GESTIONE PROTETTA`.
- Diagnostica `get_support_request_safety_integrity_v1` con 20 controlli.

### v0.61.1 · Richieste privacy protette e revisionate

- Migrazione: `database/095_data_rights_request_safety.sql`.
- Registro immutabile `data_rights_request_action_runs`.
- Invio e annullamento idempotenti con lock transazionale.
- Revisione ottimistica contro operazioni concorrenti o sessioni non aggiornate.
- Lavorazione service-role revisionata e compatibilità delle RPC storiche.
- Centro Privacy v2 e indicatore mobile `GESTIONE PROTETTA`.
- Diagnostica `get_data_rights_request_safety_integrity_v1` con 20 controlli.

## Certificazione Sviluppo 5

- Migrazione finale: `database/084_matchday_model_closure.sql`.
- La revisione correttiva ripristina in modo idempotente le RPC di correzione
  mancanti rilevate dalla diagnostica reale e completa la pubblicazione Realtime.
- La versione è definitiva soltanto dopo la comparsa dei 20 valori `true` nel
  controllo conclusivo Supabase.



## Certificazione Sviluppo 6

- Migrazione finale: `database/094_special_competitions_model_closure.sql`.
- Il modello certifica insieme Coppa di Lega, Supercoppa e Playoff Scudetto.
- Il preflight elenca in modo esplicito eventuali dipendenze mancanti prima di qualsiasi modifica.
- La versione diventa definitiva soltanto dopo la comparsa dei 20 valori `true` nel controllo conclusivo Supabase.


## Sviluppo 6 · Competizioni speciali e operatività avanzata

Obiettivo del macro-sviluppo: **80%**. La v0.60.1 apre il blocco senza
modificare l'avanzamento ufficiale, che resta al 75% fino alla sua chiusura.



### v0.61.0 · Chiusura certificata dello Sviluppo 6

- Migrazione: `database/094_special_competitions_model_closure.sql`.
- Certificazione globale `special_competitions_v1` nel registro immutabile dei modelli LEGHEVO.
- Diagnostica strutturale `get_special_competitions_schema_readiness_v1` con 20 capacità verificate.
- Impronta stabile di tabelle, funzioni e trigger di Coppa, Supercoppa e Playoff.
- Controllo per lega `get_league_special_competitions_model_closure_integrity_v1`.
- Direzione Lega `get_league_management_state_v14` con indicatore delle competizioni speciali certificate.
- Pubblicazione Realtime idempotente di tutti i registri dello Sviluppo 6.
- La chiusura diventa definitiva e porta il progetto all’80% solo dopo i 20 valori `true` nel controllo conclusivo Supabase.

### v0.60.9 · Certificazione della conclusione Playoff

- Migrazione: `database/093_league_playoff_completion_certification.sql`.
- Registro immutabile `league_playoff_completion_certificates`.
- Certificazione automatica dopo l’ufficializzazione protetta della finale.
- Impronta SHA-256 di podio, finale, tabellone e qualificate.
- Backfill non distruttivo dei Playoff già conclusi e validati.
- Stato `get_league_playoff_state_v5` e diagnostica `get_league_playoff_completion_integrity_v1`.
- Sincronizzazione Realtime e indicatore mobile dell’esito finale certificato.
- Diagnostica finale con 20 controlli Supabase.

### v0.60.8 · Ufficializzazione protetta dei turni Playoff

- Migrazione: `database/092_league_playoff_round_finalization_safety.sql`.
- Registro immutabile `league_playoff_round_finalization_runs`.
- Richiesta idempotente e lock transazionale dedicato alla lega.
- Collegamento obbligatorio all’avvio certificato v0.60.7 e alla giornata ufficializzata.
- Certificazione SHA-256 di punteggi, vincitori, avanzamento e podio finale.
- Stato `get_league_playoff_state_v4` e diagnostica `get_league_playoff_round_integrity_v1`.
- Endpoint storico instradato sul percorso protetto, backfill non distruttivo e Realtime.
- Diagnostica finale con 20 controlli Supabase.

### v0.60.7 · Avvio protetto dei Playoff Scudetto

- Migrazione: `database/091_league_playoff_start_safety.sql`.
- Registro immutabile `league_playoff_start_runs`.
- Richiesta idempotente e lock transazionale dedicato alla lega.
- Collegamento obbligatorio alla configurazione certificata v0.60.6.
- Verifica dei risultati ufficiali e delle progressioni della stagione regolare.
- Congelamento di qualificate, seed, giornate e struttura iniziale del tabellone.
- Stato `get_league_playoff_state_v3` e diagnostica `get_league_playoff_start_integrity_v1`.
- Backfill non distruttivo, Realtime e indicatore mobile dell’avvio certificato.
- Diagnostica finale con 20 controlli Supabase.

### v0.60.6 · Configurazione protetta dei Playoff Scudetto

- Migrazione: `database/090_league_playoff_configuration_safety.sql`.
- Registro immutabile `league_playoff_configuration_runs`.
- Configurazione Top 4 o Top 8 atomica, idempotente e protetta da lock di lega.
- Congelamento del formato prima dell'avvio del campionato.
- Certificazione non distruttiva delle configurazioni Playoff già esistenti.
- Stato `get_league_playoff_state_v2` e diagnostica dedicata.
- Sincronizzazione Realtime e indicatore mobile anti-doppio tocco.
- Diagnostica finale con 20 controlli Supabase.

### v0.60.5 · Ufficializzazione protetta della Supercoppa

- Migrazione: `database/089_league_super_cup_finalization_safety.sql`.
- Registro immutabile `league_super_cup_finalization_runs`.
- Richiesta idempotente, lock transazionale e blocco delle doppie chiusure.
- Collegamento alla programmazione certificata, alla giornata ufficializzata e alle due risoluzioni formazione.
- Verdetto deterministico per gol, fantapunti e priorità del campione di Lega.
- Stato `get_league_super_cup_state_v3`, diagnostica dedicata e Realtime.
- Indicatore mobile del verdetto ufficiale certificato.
- Diagnostica finale con 20 controlli Supabase.

### v0.60.4 · Programmazione protetta della Supercoppa

- Migrazione: `database/088_league_super_cup_schedule_safety.sql`.
- Registro immutabile `league_super_cup_schedule_runs`.
- Richiesta idempotente e lock transazionale per lega.
- Continuità certificata tra campione, vincitore/finalista di Coppa e nuova stagione.
- Collegamento obbligatorio al certificato conclusivo della Coppa precedente.
- Stato `get_league_super_cup_state_v2` e diagnostica dedicata.
- Sincronizzazione Realtime e indicatore mobile anti-doppio tocco.
- Diagnostica finale con 20 controlli Supabase.

### v0.60.3 · Certificazione protetta della conclusione

- Migrazione: `database/087_league_cup_completion_certification.sql`.
- Registro immutabile `league_cup_completion_certificates`.
- Certificazione automatica dopo l'ufficializzazione della finale.
- Impronta SHA-256 di finale, podio, tabellone e partecipanti.
- Backfill non distruttivo delle Coppe concluse già validate.
- Stato `get_league_cup_state_v4` e diagnostica dedicata.
- Sincronizzazione Realtime e indicatore mobile dell'esito certificato.
- Diagnostica finale con 20 controlli Supabase.

### v0.60.2 · Ufficializzazione protetta dei turni

- Migrazione: `database/086_league_cup_round_finalization_safety.sql`.
- Revisione correttiva: helper SHA-256 compatibile con lo schema reale di `pgcrypto` su Supabase e ripristino del sorteggio v0.60.1.
- Registro immutabile `league_cup_round_finalization_runs`.
- Collegamento obbligatorio alla giornata di campionato ufficializzata.
- Calcolo tramite formazioni e sostituzioni certificate dello Sviluppo 5.
- Avanzamento atomico del tabellone e proclamazione protetta del campione.
- Blocco delle doppie elaborazioni tramite turno atteso, richiesta e lock di lega.
- Diagnostica finale con 20 controlli Supabase.

### v0.60.1 · Coppa di Lega protetta

- Migrazione: `database/085_league_cup_draw_safety.sql`.
- Sorteggio atomico, deterministico e idempotente.
- Registro immutabile `league_cup_draw_runs`.
- Certificazione di partecipanti, giornate consecutive e tabellone.
- Blocco delle doppie richieste e delle elaborazioni concorrenti.
- Diagnostica finale con 20 controlli Supabase.

## Installazione dipendenze

Il progetto include una configurazione `.npmrc` locale che forza il registry
pubblico ufficiale e applica ritentativi controllati. Questo evita i `404`
causati da proxy o registry aziendali incompleti senza cambiare le versioni
delle dipendenze Expo.

```bash
npm run doctor
npm run install:clean
```

Il comando di verifica completo, dopo l'installazione, è:

```bash
npm run verify
```

## Stato della versione 0.55.4

- Mercato: il tap su avatar, nome o informazioni apre la scheda del calciatore; il pulsante crediti resta dedicato all’acquisto.

Questa versione usa Expo SDK 54 ed è compatibile con Expo Go 54 su iPhone.

- navigazione tra Home, Lega, Live, Asta e Profilo;
- dashboard personale collegata alla partita reale della prima lega;
- prossima sfida con avversario, giornata, data e scadenza formazione;
- stato automatico della partita: da schierare, Live, in calcolo o finale;
- accesso diretto dalla Home a formazione, Live o risultato;
- registrazione e accesso email/password con Supabase Auth;
- sessione persistente, logout e modalità demo;
- creazione di una lega Classic o Mantra con impostazioni personalizzate;
- creazione automatica della squadra del presidente;
- ingresso degli altri utenti tramite codice invito;
- elenco delle leghe e conteggio realtime dei partecipanti;
- aggiornamento automatico di partecipanti e squadre su tutti i dispositivi;
- riallineamento dei dati quando l'app torna in primo piano;
- elenco dei partecipanti con squadra, presidente e posti disponibili;
- condivisione nativa del codice invito su iPhone e Android;
- generazione automatica del calendario round-robin;
- formula solo andata oppure andata e ritorno;
- abbinamenti casa/trasferta senza duplicati per leghe da 2 a 20 squadre;
- schermata calendario con giornate, partite, risultati e fantapunti;
- stato pre-sorteggio con partecipanti, squadre e rose complete;
- proiezione immediata di giornate, partite e turno conclusivo;
- sorteggio casuale tracciato e realmente riservato al Presidente;
- blocco server-side finché spogliatoio e tutte le rose non sono completi;
- pubblicazione realtime del calendario su tutti i dispositivi;
- annullamento protetto e nuovo sorteggio soltanto prima dell'avvio;
- notifiche personali per pubblicazione e annullamento del calendario;
- stanza asta reale collegata alla lega selezionata;
- apertura e nomina dei calciatori riservate al presidente;
- rilanci sincronizzati in tempo reale tra tutti i partecipanti;
- timer, assegnazione automatica della rosa e aggiornamento dei crediti;
- asta realtime con rilanci atomici;
- configurazione del timer e del rilancio minimo da parte del Presidente;
- pausa e ripresa del timer senza perdere i secondi residui;
- annullamento sicuro del lotto e chiusura definitiva della sessione;
- protezione automatica dei crediti necessari a completare la rosa;
- rosa reale alimentata automaticamente dagli acquisti dell'asta;
- apertura della scheda completa del calciatore direttamente dalla rosa;
- riepilogo crediti spesi, crediti residui e calciatori per ruolo;
- quote di rosa configurabili per portieri, difensori, centrocampisti e
  attaccanti;
- raggruppamento coerente dei ruoli sia in modalità Classic sia Mantra;
- blocco automatico di asta, mercato e scambi quando un reparto è completo;
- contatori occupati/massimi per ogni reparto nella schermata Rosa;
- scelta del modulo Classic o Mantra;
- selezione guidata degli 11 titolari e formazione automatica;
- avviso immediato se rosa o ruoli non consentono la formazione automatica;
- controllo server-side degli slot compatibili per ogni modulo Mantra;
- campo da calcio visuale con disposizione dinamica per ogni modulo;
- indicatori nominativi per tutti i titolari e spazi liberi evidenziati;
- aggiornamento immediato della lavagna quando cambia il modulo;
- anteprima tattica disponibile anche prima della generazione del calendario;
- consegna ufficiale disabilitata in anteprima senza scritture sul database;
- rimozione diretta di un titolare toccandolo sul campo;
- supporto alle linee di difesa, centrocampo, trequarti e attacco Mantra;
- panchina, consegna atomica della distinta e blocco alla scadenza;
- revisione progressiva e chiave idempotente contro sovrascritture o doppie consegne;
- impronta e audit della distinta con scritture dirette bloccate;
- panchina ordinabile con priorità esplicita delle sostituzioni;
- obbligo di includere in distinta tutti i calciatori non titolari;
- consegna riservata esclusivamente al manager della squadra;
- sincronizzazione realtime della distinta tra i dispositivi;
- anteprima automatica dell'ultima formazione valida prima della scadenza;
- recupero e blocco della distinta precedente quando il manager non consegna;
- origine manuale o automatica della formazione visibile nel Live;
- prima giornata senza distinta calcolata a zero senza bloccare la lega;
- chiusura corretta anche quando alcuni titolari restano senza voto;
- notifiche personali per formazione recuperata o assente;
- sostituzioni automatiche con il primo panchinaro compatibile per ruolo;
- limite delle sostituzioni configurabile dal Presidente da 0 a 11;
- priorità della panchina rispettata in modo deterministico;
- compatibilità dei cambi distinta tra modalità Classic e Mantra;
- sostituzioni applicate soltanto dopo la conclusione del turno reale;
- riepilogo Live di cambi usati e titolari rimasti senza voto;
- motivo del mancato cambio visibile quando manca una riserva compatibile o
  viene raggiunto il limite;
- modificatore difesa attivabile dal Presidente nelle leghe Classic;
- requisito configurabile di quattro o cinque difensori schierati;
- media calcolata sul portiere e sui tre migliori difensori effettivamente a
  voto, dopo le sostituzioni;
- fasce standard del modificatore da +1 a +6 fantapunti;
- dettaglio separato di punteggio base, modificatore e bonus casa nel Live;
- componenti del punteggio conservate nei risultati provvisori e ufficiali;
- regola facoltativa dello scarto minimo quando le squadre restano nella stessa
  fascia gol;
- soglia dello scarto configurabile dal Presidente da 1 a 20 fantapunti;
- gol aggiuntivo tracciato separatamente e spiegato nel Live e nei risultati;
- giornate ufficiali protette dalle successive modifiche alla regola;
- fasce gol personalizzabili dal Presidente con sei soglie indipendenti;
- continuazione automatica oltre il sesto gol usando l'ultimo intervallo;
- regolamento gol effettivo visibile nel Live e nel centro risultati;
- fallback alla progressione standard quando le fasce personalizzate sono
  disattivate;
- criterio di spareggio della classifica configurabile dal Presidente;
- scelta tra differenza reti, fantapunti totali e scontri diretti;
- mini-classifica degli scontri diretti applicata solo con confronti reciproci
  omogenei;
- fallback automatico su differenza reti durante un calendario incompleto;
- criterio effettivo e dettaglio dello spareggio visibili nella classifica;
- cruscotto personale allineato allo stesso ordinamento;
- calcolo automatico di fantapunti e gol, con soglie configurabili;
- conteggio persistente dei giocatori valutati e dello stato dei tabellini;
- risultati provvisori separati dai risultati acquisiti in classifica;
- chiusura della giornata consentita soltanto con tutti i voti definitivi;
- ufficializzazione atomica riservata al Presidente dopo la fine del turno;
- riapertura protetta del singolo risultato per correzioni del provider;
- motivazione obbligatoria e revisione numerata di ogni correzione;
- storico immutabile dei punteggi ufficializzati e riaperti;
- permanenza in classifica delle altre partite già ufficiali;
- nuova ufficializzazione limitata ai risultati corretti;
- fotografia revisionata della classifica collegata a ogni giornata ufficiale;
- avanzamento atomico alla giornata successiva senza salti o doppie elaborazioni;
- riufficializzazioni storiche che aggiornano la classifica senza arretrare il calendario;
- notifiche dei risultati ufficiali e delle correzioni puntuali;
- chiusura della stagione riservata al Presidente;
- controllo obbligatorio di tutte le partite ufficializzate;
- fotografia immutabile della classifica finale;
- proclamazione del campione e albo della lega;
- mercato, risultati e revisioni congelati dopo la chiusura;
- notifica del campione a tutti i partecipanti;
- progresso della stagione visibile nella Direzione;
- campione e podio evidenziati nella Lega e nella Classifica;
- rinnovo della lega riservato al Presidente dopo la chiusura;
- nuova stagione collegata alla precedente senza cancellare lo storico;
- partecipanti, ruoli di direzione, nomi squadra e regolamento copiati;
- crediti ripristinati al budget iniziale, con rose e calendario vuoti;
- nuovo codice invito e mercato chiuso nella stagione appena creata;
- stagione precedente archiviata e sempre consultabile nell’albo;
- notifica automatica a tutti i manager trasferiti;
- archivio storico unico per tutte le stagioni collegate della lega;
- stagioni ordinate dalla più recente con accesso diretto a ogni annata;
- campione e podio congelati visibili per ciascuna stagione conclusa;
- avanzamento dei risultati ufficiali per la stagione corrente;
- graduatoria dei manager per numero di titoli conquistati;
- accesso allo storico riservato ai partecipanti della lega;
- record stagionali per punti, fantapunti, vittorie, gol e differenza reti;
- record di singola partita per punteggio, scarto e gol complessivi;
- statistiche carriera aggregate sulle sole stagioni concluse;
- classifica storica dei manager per titoli, punti, vittorie e fantapunti;
- percentuale di vittorie, podi e miglior piazzamento di ogni manager;
- record deterministici e protetti, ricavati esclusivamente da snapshot e
  risultati già congelati;
- Coppa di Lega a eliminazione diretta separata dalla classifica;
- sorteggio casuale tracciato e riservato al Presidente;
- tabellone automatico da 2 a 20 squadre con preliminari e bye;
- turni collegati alle giornate reali ancora disponibili;
- stessa formazione valida per campionato e coppa;
- risultati calcolati con il regolamento della lega ma senza bonus casa;
- spareggio su fantapunti e, in perfetta parità, sulla testa di serie;
- avanzamento automatico dei vincitori e proclamazione del campione;
- blocco della chiusura stagione finché la coppa non è conclusa;
- notifiche dedicate e aggiornamento realtime del tabellone;
- albo pluriennale della Coppa con campione e finalista di ogni stagione;
- classifica dei manager per titoli, finali e rendimento in eliminazione
  diretta;
- record della Coppa per punteggio, scarto e gol complessivi;
- esclusione automatica delle Coppe ancora aperte dai record definitivi;
- accesso diretto dall'albo della Coppa alla stagione corrispondente;
- Supercoppa collegata alla stagione precedente dopo il rinnovo della lega;
- finale tra campione del campionato e vincitore della Coppa;
- accesso del finalista di Coppa quando lo stesso manager realizza il double;
- programmazione su una giornata reale futura da parte del Presidente;
- stessa formazione valida per campionato, Coppa e Supercoppa;
- risultato separato, senza bonus casa, deciso da gol e fantapunti;
- priorità al campione del campionato in caso di parità perfetta;
- ufficializzazione protetta e blocco della chiusura se il trofeo è aperto;
- notifiche realtime per programmazione e assegnazione del titolo;
- albo pluriennale della Supercoppa e classifica dei manager per trofei;
- bacheca unificata di campionato, Coppa e Supercoppa;
- ranking assoluto dei manager per numero e tipo di trofei conquistati;
- podi, finali e double riuniti nello stesso palmarès;
- cronologia dei titoli ufficiali con accesso diretto alla stagione;
- esclusione automatica delle competizioni ancora aperte dalla bacheca;
- lettura protetta del palmarès riservata ai partecipanti;
- Playoff Scudetto opzionali configurabili prima dell'avvio;
- formato top 4 o top 8 congelato per l'intera stagione;
- teste di serie ricavate dalla classifica regolare definitiva;
- tabellone su due o tre giornate reali successive al campionato;
- formazione dedicata alle giornate Playoff con continuità automatica;
- spareggio tramite fantapunti e migliore testa di serie;
- vincitore dei Playoff proclamato Campione ufficiale della lega;
- chiusura stagione bloccata finché la fase finale non è conclusa;
- albo, storico, Supercoppa e Bacheca alimentati dal verdetto Playoff;
- archivio pluriennale dei Playoff con campione, finalista e prima classificata
  della regular season;
- testa di serie e posizione regolare conservate per ogni finalista;
- classifica carriera dei manager nelle sole fasi finali concluse;
- record Playoff di punteggio, scarto e gol complessivi;
- titoli conquistati da una testa di serie inferiore evidenziati come rimonte;
- Playoff configurati o ancora aperti esclusi dai record definitivi;
- distinzione visiva tra campione della regular season e campione via Playoff;
- centro risultati con navigazione tra giornate e stato di ogni partita;
- classifica a scontri diretti con punti, vittorie, pareggi, sconfitte e gol;
- aggiornamento realtime di calendario, risultati e classifica;
- allineamento automatico delle giornate fantasy alle date reali di Serie A;
- scadenza formazione fissata al primo calcio d'inizio reale;
- termine giornata calcolato sull'ultima partita del turno;
- indicazione chiara delle date Serie A e delle date ancora stimate;
- stato di copertura del provider e conteggio delle partite concluse;
- riallineamento realtime in caso di variazioni o rinvii;
- centro partita Live collegato alla lega e alla giornata selezionate;
- canali Live indipendenti per Home e schermata partita, senza conflitti tra
  sottoscrizioni Realtime;
- risultato, fantapunti e numero di voti aggiornati in tempo reale;
- dettaglio degli undici effettivi con bonus, malus e stato della partita;
- sostituzioni automatiche visibili anche nel Live;
- stati prepartita, in corso, in calcolo e risultato finale;
- mercato degli svincolati con acquisto atomico e prezzo minimo;
- svincoli con rimborso percentuale configurabile;
- proposte di scambio uno contro uno con eventuali crediti;
- accettazione, rifiuto, annullamento e scadenza delle trattative;
- aggiornamento realtime di rose, crediti e proposte;
- controlli automatici su proprietà, crediti e capienza delle rose;
- pannello del Presidente accessibile soltanto agli amministratori;
- apertura e chiusura immediata del mercato;
- configurazione del prezzo minimo e del rimborso per gli svincoli;
- configurazione della soglia del primo gol e delle fasce successive;
- bonus casa configurabile con anteprima delle fasce gol;
- bonus personalizzabili per gol, assist e rigore parato;
- malus personalizzabili per ammonizione, espulsione, rigore sbagliato e gol
  subito dal portiere;
- fantavoto calcolato per ogni lega dal rating e dalle statistiche grezze del
  provider;
- ricalcolo automatico dei risultati quando il Presidente modifica le regole;
- gestione dei partecipanti dal Pannello del Presidente;
- nomina e revoca degli amministratori della lega;
- rimozione sicura dei partecipanti prima dell'avvio della competizione;
- pulizia atomica di offerte, rosa, scambi e calendario della squadra rimossa;
- protezione dei dati di chi ha già partecipato alla competizione;
- rigenerazione del codice invito con invalidazione immediata del precedente;
- schermata Direzione lega separata dalle regole di punteggio;
- apertura e chiusura degli inviti da parte del Presidente;
- blocco automatico degli ingressi dopo l'avvio della competizione;
- trasferimento protetto della presidenza a un partecipante attivo;
- permanenza del vecchio Presidente nella direzione come amministratore;
- checklist server-side per partecipanti, squadre, rose e calendario;
- avvio ufficiale consentito soltanto quando tutti i controlli sono superati;
- chiusura automatica degli inviti e blocco delle rimozioni dopo il via;
- azioni su ruoli e partecipanti realmente riservate al Presidente;
- Centro Operativo riservato alla Direzione con quadro unico della giornata;
- consegne formazione mostrate come stato senza rivelare i calciatori schierati;
- conteggio di formazioni consegnate, bozze, mancanti e recuperate;
- scadenza formazione, copertura del provider e risultati da ufficializzare
  riuniti nella stessa schermata;
- priorità settimanali ordinate per urgenza con accesso diretto all'azione;
- promemoria manuali ai manager in ritardo, inviabili una sola volta per
  giornata e protetti da duplicazioni;
- schermata personale Squadra e partecipazione;
- cambio del nome squadra sincronizzato in tempo reale prima del campionato;
- blocco server-side del cambio nome dopo l'avvio della competizione;
- uscita autonoma e protetta dei manager durante il pre-campionato;
- obbligo per il Presidente di trasferire prima la presidenza;
- pulizia atomica di rosa, offerte, scambi e calendario quando un manager esce;
- notifica immediata alla Direzione e riapertura del posto disponibile;
- cruscotto personale collegato ai dati reali della squadra;
- posizione, punti, andamento, fantapunti, rosa e crediti sempre aggiornati;
- stato dello spogliatoio, completamento della rosa e calendario in un'unica
  scheda;
- prossima partita e ultimo risultato ricavati dal calendario della lega;
- Centro Sfida dedicato alla partita corrente o successiva;
- confronto tra posizione, punti, fantapunti, gol e forma recente;
- serie senza sconfitte calcolata sui soli risultati ufficiali;
- precedenti diretti della stagione e di tutte le annate collegate;
- bilancio storico tra manager anche quando cambia il nome della squadra;
- ultime cinque sfide con risultato, fantapunti e accesso alla stagione;
- stato di consegna dell’avversario senza modulo o calciatori prima del blocco;
- collegamento diretto a formazione e Live dal prepartita;
- ultimi movimenti di asta, mercato, svincolo e scambio;
- aggiornamento realtime del cruscotto dopo acquisti, crediti e risultati;
- database protetto con Row Level Security;
- leghe Classic e Mantra, rose, calendario, formazioni e risultati;
- integrazione server-side con API-Football;
- sincronizzazione automatica di rose e calendario Serie A;
- rating 0–10, bonus, malus e fantavoto aggiornati durante le partite;
- tracciamento degli errori e delle sincronizzazioni del provider;
- dataset dimostrativo server-side per sviluppare senza piano dati a pagamento;
- schermata Live collegata ai voti demo Supabase con fallback locale;
- blocco di sicurezza dei cron finché il provider non è sul piano Pro;
- base grafica del piano Premium;
- centro notifiche personale con contatore dei messaggi non letti;
- aggiornamenti realtime per offerte di scambio, asta e risultati;
- apertura diretta della schermata interessata dalla notifica;
- conferma di lettura singola o di tutte le notifiche;
- notifiche dimostrative complete disponibili nella modalità demo.
- archivio calciatori collegato a ogni lega;
- ricerca per nome, club e ruolo con filtri Classic e Mantra;
- filtri per svincolati e giocatori della propria rosa;
- scheda con fantamedia, voto base, presenze, bonus e disciplina;
- ultime cinque prestazioni e indicatore sintetico dello stato di forma;
- proprietà fantasy e prezzo di acquisto visibili nella scheda;
- anteprima della futura analisi statistica LEGHEVO Premium;
- recupero password tramite link email e collegamento diretto all'app;
- modifica protetta del nome visualizzato;
- cambio password dall'area Account e sicurezza;
- eliminazione definitiva dell'accesso con anonimizzazione dei risultati storici;
- trasferimento automatico delle leghe del Presidente prima della cancellazione;
- protezione del livello Premium da modifiche effettuate dal client.
- informativa privacy e Termini consultabili prima della registrazione e dal
  Profilo;
- presa visione dell'informativa separata dall'accettazione dei Termini;
- comunicazioni limitate a email di servizio e notifiche tecniche o di gioco;
- registrazione di versione, data, ora, finalità e fonte di ogni scelta;
- requisito minimo di 14 anni con dichiarazione separata e autorizzazione
  genitoriale richiesta tra 14 e 17 anni;
- storico dei consensi protetto da modifiche dirette del client;
- aggiornamento obbligatorio dei documenti per gli account già esistenti;
- esportazione personale in JSON di profilo, consensi, leghe, squadre,
  formazioni e notifiche;
- condivisione nativa del file dati su iPhone e Android;
- eliminazione dell'account con cancellazione automatica delle preferenze
  privacy e anonimizzazione dei risultati storici;
- Informativa privacy e Termini pubblicati per il rilascio italiano;
- titolare e sviluppatore identificati in Marco Schito;
- pagina Informazioni con dati legali, contatti, fornitori e versioni;
- tempi di conservazione definiti per account, backup, sicurezza, assistenza,
  chat facoltativa e acquisti;
- funzioni e permessi futuri descritti ma dichiarati disattivati finché non
  vengono realmente implementati;
- Centro Diritti Privacy con richieste tracciate per accesso, rettifica,
  portabilità, limitazione, opposizione e cancellazione;
- termine indicativo di 30 giorni e stato sempre visibile all'utente;
- cronologia immutabile degli aggiornamenti e risposta finale conservata;
- blocco automatico delle richieste duplicate dello stesso tipo ancora aperte;
- annullamento protetto delle richieste non ancora concluse;
- lavorazione riservata al backend, senza chiavi privilegiate nell'app;
- richieste e relativa cronologia incluse nell’esportazione personale JSON v2.
- centro rinvii condiviso con partite rinviate, sospese, interrotte,
  cancellate o con data da definire;
- attesa del recupero mantenuta come comportamento predefinito;
- voto d’ufficio da 0 a 10 assegnabile esclusivamente dal Presidente;
- motivazione obbligatoria e decisione visibile a tutti i manager;
- voto applicato soltanto ai calciatori dei club realmente coinvolti;
- isolamento della decisione tra leghe che usano la stessa giornata reale;
- ricalcolo immediato di campionato, Coppa, Playoff e Supercoppa;
- origine del voto d’ufficio evidenziata nel Live;
- revoca protetta finché i risultati non sono ufficiali;
- blocco delle modifiche dopo l’ufficializzazione della giornata;
- cronologia immutabile di applicazioni e revoche;
- ritorno automatico ai voti reali quando il provider chiude la partita;
- sincronizzazione futura rafforzata tramite identificativo provider del club;
- installazione neutra, senza voti o decisioni creati automaticamente.
- notifiche push native tramite Expo per iOS e Android;
- attivazione esclusivamente dopo scelta esplicita dell’utente;
- preferenze separate per formazione, asta e mercato, risultati, lega e
  comunicazioni tecniche;
- registrazione protetta di più dispositivi sullo stesso account;
- apertura diretta della lega e della schermata collegate all’avviso;
- token del dispositivo revocato al logout;
- token non più validi disabilitati automaticamente dopo la risposta Expo;
- coda server-side con ticket, errori e ritentativi tracciati;
- token Expo mai leggibili dal client;
- Centro notifiche interno sempre disponibile anche con le push disattivate;
- esportazione personale JSON v3 comprensiva di preferenze e consegne push;
- installazione neutra, senza permessi richiesti, dispositivi registrati o
  notifiche inviate.
- Centro Assistenza collegato alla voce Profilo prima inattiva;
- risposte rapide sui flussi più comuni di formazione, risultati e inviti;
- pratiche categorizzate e collegabili facoltativamente a una lega;
- stato distinto tra inviata, in lavorazione, in attesa dell’utente, risolta e
  chiusa;
- conversazione cronologica tra utente e assistenza;
- risposta dell’utente e chiusura volontaria protette server-side;
- massimo di tre pratiche contemporaneamente aperte per account;
- isolamento completo delle pratiche tra utenti tramite Row Level Security;
- lavorazione e risposte dell’assistenza riservate al backend;
- notifica interna e push facoltativa quando la pratica viene aggiornata;
- apertura diretta del Centro Assistenza dalla notifica;
- richieste, messaggi e cronologia inclusi nell’esportazione personale JSON v4;
- cancellazione automatica delle pratiche eliminando l’account;
- installazione neutra, senza richieste o messaggi creati automaticamente.
- regolamento della lega leggibile da tutti i membri;
- riepilogo unico di mercato, rosa, formazione, bonus, malus, fasce gol,
  classifica e modificatore difesa;
- cronologia immutabile delle modifiche con revisione, autore e data;
- motivazione obbligatoria per ogni aggiornamento del Presidente;
- elenco preciso delle regole cambiate in ogni revisione;
- notifica ai manager con apertura diretta del regolamento;
- vecchie funzioni di modifica non più richiamabili direttamente dal client;
- aggiornamento realtime del regolamento su tutti i dispositivi;
- revisioni firmate dall’utente incluse nell’esportazione personale JSON v5;
- installazione neutra, senza regole modificate o revisioni retroattive.

## Avvio immediato in modalità demo

```bash
npm install
npm start
```

Senza variabili d’ambiente comparirà il pulsante **Entra nella demo**.

## Collegamento a Supabase

1. Crea un progetto Supabase.
2. Esegui nell’SQL Editor, in ordine:
   - `database/001_initial_schema.sql`
   - `database/002_security_and_functions.sql`
   - `database/003_api_football_ingestion.sql`
   - `database/005_development_demo_data.sql`
   - `database/006_league_onboarding.sql`
   - `database/007_head_to_head_calendar.sql`
   - `database/008_live_auction_room.sql`
   - `database/009_roster_and_lineup.sql`
   - `database/010_results_and_standings.sql`
   - `database/011_transfer_market.sql`
   - `database/012_president_settings.sql`
   - `database/013_member_management.sql`
   - `database/014_custom_bonus_malus.sql`
   - `database/015_auction_direction.sql`
   - `database/016_roster_role_quotas.sql`
   - `database/017_live_match_center.sql`
   - `database/018_notification_center.sql`
   - `database/019_player_directory.sql`
   - `database/020_account_management.sql`
   - `database/021_membership_realtime.sql`
   - `database/022_privacy_and_data_rights.sql`
   - `database/023_league_direction.sql`
   - `database/024_safe_member_removal.sql`
   - `database/025_team_identity_and_membership.sql`
   - `database/026_leave_league_notification_fix.sql`
   - `database/027_team_dashboard.sql`
   - `database/028_calendar_matchdays_and_pairings.sql`
   - `database/029_lineup_and_bench.sql`
   - `database/030_matchday_results_and_standings.sql`
   - `database/031_real_matchday_schedule.sql`
   - `database/032_lineup_continuity.sql`
   - `database/033_automatic_substitutions.sql`
   - `database/034_defense_modifier_and_score_breakdown.sql`
   - `database/035_goal_margin_rule.sql`
   - `database/036_custom_goal_bands.sql`
   - `database/037_standings_tiebreakers.sql`
   - `database/038_result_corrections_and_audit.sql`
   - `database/039_season_closure_and_honours.sql`
   - `database/040_season_renewal.sql`
   - `database/041_league_history_and_hall_of_fame.sql`
   - `database/042_league_records_and_manager_careers.sql`
   - `database/043_league_cup_knockout.sql`
   - `database/044_league_cup_history_and_records.sql`
   - `database/045_league_super_cup.sql`
   - `database/046_unified_trophy_cabinet.sql`
   - `database/047_league_championship_playoffs.sql`
   - `database/048_league_playoff_history_and_records.sql`
   - `database/049_league_operations_center.sql`
   - `database/050_data_rights_request_center.sql`
   - `database/051_published_legal_documents_and_age_gate.sql`
   - `database/052_postponed_fixture_resolution.sql`
   - `database/053_push_notifications_and_preferences.sql`
   - `database/054_matchup_center.sql`
   - `database/055_support_center.sql`
   - `database/056_shared_rulebook_and_revisions.sql`
   - `database/057_development_player_pool.sql` *(solo ambiente di sviluppo)*
   - `database/058_development_pippolandia_roster.sql` *(solo ambiente di sviluppo)*
   - `database/059_onboarding_hardening.sql`
   - `database/060_invite_preview.sql`
   - `database/061_role_permissions_and_audit.sql`
   - `database/062_role_integrity_and_diagnostics.sql`
   - `database/063_role_session_sync.sql`
   - `database/064_role_action_concurrency.sql`
   - `database/065_role_model_closure.sql`
   - `database/066_market_roster_integrity.sql`
   - `database/067_trade_offer_safety.sql`
   - `database/068_live_auction_safety.sql`
3. Copia `.env.example` in `.env`.
4. Inserisci Project URL e publishable key.
5. Riavvia Expo.

```dotenv
EXPO_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_your_key
EXPO_PUBLIC_EAS_PROJECT_ID=uuid-del-progetto-eas
```

Non inserire mai nell’app la `service_role` key o la chiave API-Football.

Per i link di recupero password aggiungi in Supabase Auth, tra i Redirect URLs:

```text
leghevo://**
exp://**
```

Durante i test con Expo Go può essere necessario aggiungere anche l'indirizzo
esatto mostrato da Metro, seguito da `/--/reset-password`.

## Notifiche push

La migrazione `053_push_notifications_and_preferences.sql` crea preferenze,
dispositivi e coda protetta, ma non registra token e non invia messaggi.

Per attivare la consegna reale:

1. collega il progetto a EAS e configura le credenziali FCM/APNs;
2. abilita la sicurezza avanzata delle push nel pannello Expo;
3. salva `EXPO_ACCESS_TOKEN` tra i segreti Supabase;
4. distribuisci `supabase/functions/send-push-notifications`;
5. crea un Database Webhook sugli inserimenti della tabella
   `notification_push_deliveries`, diretto alla stessa Edge Function.

Il webhook non riceve token dall’app: la Edge Function preleva dal database
soltanto le consegne autorizzate e registra ticket ed eventuali errori. Le push
remote Android richiedono una development build o una build di produzione:
Expo Go continua a mostrare il Centro notifiche, ma non può ricevere push
remote.

## Provider dati

La scelta iniziale è **API-Football**. Il connettore si trova nella Edge
Function `supabase/functions/sync-football-data` e gestisce tre operazioni:

- `sync-season-players`;
- `sync-fixtures`;
- `sync-fixture-players`.

Configurazione, frequenze e formula del fantavoto sono documentate in
`docs/DATA_PROVIDER.md`. Dopo aver configurato i segreti server, il file
`database/004_automatic_provider_sync.sql` attiva i lavori programmati soltanto
quando nel Vault è presente `leghevo_provider_plan=pro`.

## Controlli di sviluppo

```bash
npm run typecheck
npx expo config --type public
```

## Struttura

- `App.tsx`: sessione e navigazione;
- `src/hooks/useAuth.ts`: autenticazione e profilo demo;
- `src/hooks/useLeagues.ts`: caricamento e aggiornamento delle leghe;
- `src/hooks/useLeagueMembers.ts`: partecipanti e squadre dello spogliatoio;
- `src/hooks/useTeamRoster.ts`: rosa della squadra e dati demo;
- `src/hooks/useLineup.ts`: prossima partita e distinta;
- `src/hooks/useLeagueResults.ts`: giornate, risultati e chiusura ufficiale;
- `src/hooks/useLeagueStandings.ts`: classifica e aggiornamenti realtime;
- `src/hooks/useTransferMarket.ts`: mercato, svincoli e trattative;
- `src/hooks/useLeagueSettings.ts`: regole configurabili della lega;
- `src/hooks/useLeagueRulebook.ts`: regolamento condiviso e revisioni realtime;
- `src/hooks/useLiveMatchCenter.ts`: partita, voti e risultato realtime;
- `src/hooks/useNotifications.ts`: notifiche personali e contatore realtime;
- `src/hooks/usePushNotifications.ts`: permessi, dispositivo e apertura push;
- `src/hooks/usePlayerDirectory.ts`: archivio, filtri e dati demo dei calciatori;
- `src/hooks/useLeagueManagement.ts`: controlli e azioni della direzione;
- `src/hooks/useTeamDashboard.ts`: dati e aggiornamenti del cruscotto squadra;
- `src/hooks/useLeagueMatchup.ts`: prepartita, forma e precedenti diretti;
- `src/hooks/useSupportCenter.ts`: pratiche, conversazioni e aggiornamenti
  realtime dell’assistenza;
- `src/hooks/useLeagueHistory.ts`: stagioni collegate, albo e pluricampioni;
- `src/hooks/useLeagueRecords.ts`: record storici e carriere dei manager;
- `src/hooks/useLeagueTrophyCabinet.ts`: bacheca e ranking unificato dei trofei;
- `src/hooks/useLeaguePlayoffs.ts`: configurazione e tabellone Playoff;
- `src/hooks/useLeaguePlayoffHistory.ts`: albo, record e carriere dei Playoff;
- `src/hooks/useLeaguePostponements.ts`: rinvii e decisioni realtime della lega;
- `src/hooks/usePrivacyRights.ts`: richieste GDPR e aggiornamento del Centro
  Diritti Privacy;
- `src/lib/supabase.ts`: client Supabase per React Native;
- `src/services/auctionService.ts`: asta realtime;
- `src/services/rosterService.ts`: acquisti e ruoli della rosa;
- `src/services/lineupService.ts`: lettura e consegna formazione;
- `src/services/standingsService.ts`: risultati e classifica;
- `src/services/marketService.ts`: operazioni atomiche del mercato;
- `src/services/settingsService.ts`: lettura e salvataggio delle regole;
- `src/services/rulebookService.ts`: regolamento protetto e cronologia;
- `src/services/notificationService.ts`: inbox, letture e sottoscrizione realtime;
- `src/services/pushNotificationService.ts`: token Expo e preferenze push;
- `src/services/playerDirectoryService.ts`: statistiche e proprietà per lega;
- `src/services/accountService.ts`: profilo, password ed eliminazione account;
- `src/services/privacyService.ts`: consensi, versioni ed esportazione dati;
- `src/services/privacyRightsService.ts`: invio, lettura e annullamento delle
  richieste sui dati personali;
- `src/services/leagueManagementService.ts`: inviti, presidenza e avvio;
- `src/services/teamMembershipService.ts`: nome squadra e uscita autonoma;
- `src/services/teamDashboardService.ts`: rendimento, rosa e movimenti recenti;
- `src/services/matchupService.ts`: Centro Sfida e rivalità multi-stagione;
- `src/services/supportService.ts`: richieste e risposte protette del Centro
  Assistenza;
- `src/services/leagueHistoryService.ts`: archivio storico multi-stagione;
- `src/services/leagueRecordsService.ts`: record congelati e statistiche carriera;
- `src/services/leagueTrophyCabinetService.ts`: palmarès complessivo dei manager;
- `src/services/leaguePlayoffService.ts`: fase finale e risultati Playoff;
- `src/services/leaguePlayoffHistoryService.ts`: storico pluriennale dei Playoff;
- `src/services/postponementService.ts`: voto d’ufficio e Centro rinvii;
- `src/services/leagueService.ts`: creazione lega e accesso con codice;
- `src/services/calendarService.ts`: calendario e scontri diretti;
- `src/screens`: schermate principali;
- `src/legalDocuments.ts`: Informativa privacy e Termini pubblicati;
- `src/legalProfile.ts`: identità, contatti e fornitori dichiarati;
- `src/screens/AboutScreen.tsx`: pagina Informazioni su LEGHEVO;
- `database`: schema, sicurezza e integrazione dati;
- `supabase/functions`: codice server-side;
- `supabase/functions/send-push-notifications`: invio protetto tramite Expo;
- `docs/DATA_PROVIDER.md`: decisione e configurazione del provider.




## Aggiornamento database 0.61.6

Eseguire `database/100_notification_center_safety.sql` dopo la migrazione 099.
La lettura singola e la funzione “segna tutte lette” usano ora richieste
idempotenti, lock transazionali e un registro immutabile. Ogni notifica possiede
una revisione e un'impronta di stato; il client usa
`get_my_notification_center_v2`, `mark_notification_read_guarded_v1` e
`mark_all_notifications_read_guarded_v1`, mantenendo fallback compatibili.

La diagnostica finale `get_notification_center_safety_integrity_v1` deve
restituire esattamente 20 valori `true`.

## Aggiornamento database 0.59.8

Eseguire `database/082_season_completion_continuity_safety.sql` dopo la migrazione 081.
La chiusura della stagione richiede ora la progressione certificata di tutte le
giornate e l’ultima fotografia integra della classifica. Ogni chiusura è
idempotente, serializzata e registrata in `season_completion_runs`. Il client
usa `complete_league_season_guarded_v1`, `get_league_season_state_v4` e
`get_league_management_state_v11`, con fallback compatibili.

La diagnostica finale `get_league_season_completion_integrity_v1` deve
restituire uno stato sano. Lo script termina con 20 controlli booleani.

## Aggiornamento database 0.59.6

Eseguire `database/080_result_correction_continuity_safety.sql` dopo la migrazione
079. La riapertura di una partita o dell'intera giornata viene registrata con
richiesta idempotente, revisione e impronta. La successiva ufficializzazione
conserva i risultati non modificati, aggiorna soltanto quelli corretti e crea
una nuova fotografia completa e coerente della giornata.

La diagnostica finale
`get_league_result_correction_integrity_v1` deve restituire 20 valori `true`.

## Aggiornamento database 0.59.5

Eseguire `database/079_matchday_officialization_safety.sql` dopo la migrazione
078. La chiusura della giornata usa una richiesta idempotente, acquisisce tutte
le partite nella stessa transazione e collega ogni risultato alla proiezione
Live certificata che lo ha generato.

La diagnostica finale
`get_league_matchday_officialization_integrity_v1` deve restituire 20 valori
`true`.

## Aggiornamento database 0.59.4

Eseguire `database/078_live_matchday_projection_safety.sql` dopo la migrazione 077.
La versione introduce la proiezione Live protetta e revisionata per l'intera partita,
usa le risoluzioni certificate delle due formazioni e mantiene coerenti punti,
modificatore difesa, bonus casa, regola dello scarto, gol e sostituzioni.
Il client usa `get_my_live_match_v6` e ascolta in Realtime anche
`live_fixture_projection_runs`.

La diagnostica finale `get_league_live_projection_integrity_v1` deve restituire
20 valori `true`.

## Aggiornamento database 0.59.3

Eseguire `database/077_guarded_substitution_engine.sql` dopo la migrazione 076.
La versione certifica in modo deterministico e idempotente ordine della panchina,
limite dei cambi, assenti/senza voto, compatibilità di ruolo e modulo, registrando
ogni elaborazione e ogni sostituzione effettuata.

La diagnostica finale `get_league_substitution_integrity_v1` deve restituire
20 valori `true`.

## Aggiornamento database 0.59.2

Eseguire `database/076_lineup_deadline_and_continuity_safety.sql` dopo il file 075. La migrazione aggiunge il registro delle chiusure, rende immutabili le distinte dopo la scadenza e collega i vecchi percorsi interni alle funzioni protette.

> Revisione v0.59.7: la migrazione 081 include il ripristino idempotente della funzione di ufficializzazione v2 necessaria alla progressione v3.
