# In sviluppo — Fondazione Free/Premium

- contratto Free con una lega principale e massimo 6 partecipanti;
- contratto Premium da 2,99 EUR/mese o 9,99 EUR/anno con leghe senza limite commerciale,
  massimo 20 partecipanti per lega e nessuna pubblicità sul singolo account;
- entitlement autorevole Supabase, eventi store idempotenti e non modificabili
  dal client;
- limiti applicati atomicamente nella creazione lega con protezione dalla
  concorrenza;
- schermata Premium e selezione partecipanti coerente con il piano;
- acquisti e annunci mantenuti disattivati fino al completamento delle
  integrazioni RevenueCat, Apple, Google e AdMob.

# v0.62.43 — Sigillo finale di production readiness e go-live controllato

- certificazione conclusiva di dieci capacità terminali della produzione;
- run, controlli, certificati, teste ed eventi immutabili con fingerprint SHA-256;
- advisory lock, request ID idempotenti, RLS e trigger critici `ENABLE ALWAYS`;
- go-live fail-closed con riconciliazione automatica `affected`/`revalidated`;
- promozione rollout v9 e client eligibility v9 protette dal sigillo finale;
- provider health v42, season state v21 e management state v31;
- release v0.62.43 collegata a telemetria autorevole, consegna end-to-end, audit, checkpoint, backup fisico, restore rehearsal e ritorno in servizio;
- migrazione `147_final_production_readiness_and_go_live_seal.sql` e SQL standalone identico;
- diagnostica finale superata con 20/20 controlli in Supabase locale isolato;
- seconda applicazione della migrazione 147 superata, a conferma dell'idempotenza nel percorso verificato;
- typecheck, configurazione Expo, fingerprint release ed export Android/iOS superati;
- Sviluppo 10 concluso e avanzamento tecnico al 100%; il go-live di produzione resta subordinato alle verifiche operative reali documentate in `docs/VALIDAZIONE_V0.62.43.md`.

# v0.62.42 — Riapertura controllata post-restore e ritorno in servizio certificato
- Revisione v2 pre-validazione: corretto il guard della testa backup fisico, distinguendo la monotonicita globale della generazione dalla sequenza di custodia locale al nuovo artefatto.
- Revisione v3 pre-validazione: normalizzate le fingerprint dei controlli post-restore con fallback SHA-256 sul modello JSON, evitando parametri non validi quando un endpoint terminale non espone direttamente la fingerprint attesa.

- recovery mode esplicita con scritture, worker e traffico sospesi fino alla certificazione finale;
- run immutabili collegati a backup fisico, restore rehearsal, checkpoint, release e sequenze operative correnti;
- otto controlli obbligatori: integrità applicativa, compatibilità release, rollout, telemetria/fencing, outbox, consumer, audit e backup fisico;
- certificato immutabile di ritorno in servizio con fingerprint del run e della catena completa dei controlli;
- teste protette da trigger `ENABLE ALWAYS`, storico append-only e riconciliazione automatica `affected` sulle dipendenze;
- promozione rollout v8 e client eligibility v8 fail-closed finché la modalità non torna `active`;
- provider health v41, season state v20 e management state v30;
- release v0.62.42 certificata, nuovo backup/restore rehearsal e riapertura controllata con 8/8 controlli superati;
- migrazione `146_controlled_post_restore_service_return.sql` e SQL standalone identico;
- diagnostica finale a 20 controlli; avanzamento ufficiale invariato al 95% fino alla chiusura dello Sviluppo 10.

# v0.62.41 — Backup fisico certificato e restore rehearsal esterno

- artefatti di backup immutabili collegati al checkpoint disaster recovery corrente;
- checksum SHA-256, dimensione e cifratura a riposo verificati lato database;
- provider, storage locator, target esterno e riferimento KMS conservati soltanto come hash;
- catena di custodia append-only con sequenza monotona e fingerprint collegata all'evento precedente;
- restore rehearsal esterno isolato con controlli schema, dati, checksum, dimensione e assenza di scritture distruttive;
- teste protette da trigger `ENABLE ALWAYS` e stati `certified`, `affected`, `revalidated`;
- promozione rollout v7 e client eligibility v7 fail-closed;
- provider health v40, season state v19 e management state v29;
- release v0.62.41 certificata, attivata al 100% e collegata a un nuovo checkpoint/drill;
- migrazione `145_certified_physical_backup_and_external_restore_rehearsal.sql` e SQL standalone identico;
- diagnostica finale a 20 controlli; avanzamento ufficiale invariato al 95% fino alla chiusura dello Sviluppo 10.

# v0.62.40 — Checkpoint immutabile e prova di ripristino certificata

- avvio dello Sviluppo 10 verso il 100%, dopo la validazione dello Sviluppo 9 al 95%;
- checkpoint disaster recovery immutabili con generazione monotona e request ID idempotente;
- sette componenti certificati: sigillo applicativo, release, rollout, telemetria, outbox, consumer delivery e audit consegne;
- fingerprint SHA-256 della radice, dei componenti, dei drill e degli eventi;
- prove di ripristino con verifica anti-regressione di release, rollout, telemetria e sequenze operative;
- piano di recovery immutabile con punti di ripresa per telemetria, outbox, inbox e audit;
- teste protette da trigger `ENABLE ALWAYS` e storico append-only;
- promozione rollout v6 e client eligibility v6 fail-closed senza checkpoint e drill freschi;
- provider health v39, season state v18 e management state v28;
- release v0.62.40 certificata e portata 10 → 35 → 60 → 85 → 100 con cinque checkpoint e cinque drill;
- migrazione `144_certified_disaster_recovery_checkpoint_and_drill.sql` e SQL standalone identico;
- diagnostica finale a 20 controlli; avanzamento ufficiale invariato al 95% fino alla chiusura dello Sviluppo 10.

# v0.62.39 — Audit continuo end-to-end e chiusura certificata della catena operativa

Correzione pre-validazione v2: qualificato esplicitamente `destination_key` nel conteggio delle sequenze per eliminare l'ambiguità PostgreSQL `42702`; nessuna versione precedente o dato ufficializzato è stato modificato.

- run di audit immutabili con generazione monotona, request ID idempotente e fingerprint SHA-256;
- attestazioni separate per `operations_center` e `notification_dispatch` con hash della catena ricevute;
- verifica di messaggi, delivery head, ricevute, sequenze, fingerprint, consumer head e dead-letter;
- teste audit protette `ENABLE ALWAYS` con transizioni `certified`, `affected` e `revalidated`;
- remediation append-only controllata senza modifica dei dati operativi già ufficializzati;
- promozione rollout v5 bloccata quando l'audit è mancante, stale o affected;
- client eligibility v5 fail-closed e Centro Operativo aggiornato con generazione, sequenza e divergenze;
- provider health v38, season state v17 e management state v27;
- release v0.62.39 certificata, rollout 10 → 35 → 60 → 85 → 100 e audit finale di chiusura;
- migrazione `143_continuous_end_to_end_delivery_audit_and_closure.sql` e SQL standalone identico;
- diagnostica finale a 20 controlli; dopo la validazione lo Sviluppo 9 potrà raggiungere il 95%.

# v0.62.38 — Inbox autorevole e ack end-to-end

> Correzione pre-validazione v2: la diagnostica finale della v0.62.38 accetta soltanto i quattro falsi legacy attesi prodotti dalla revoca protetta di `claim_leghevo_operational_outbox_v1`, `complete_leghevo_operational_outbox_delivery_v1`, `promote_leghevo_application_rollout_v3` e dal passaggio della release attiva da v0.62.37 a v0.62.38. Tutti i controlli terminali correnti restano obbligatori.

- certificati immutabili per i consumatori `operations_center` e `notification_dispatch`, con generazione monotona e fencing token memorizzato soltanto come hash;
- nuove tabelle per certificati, teste, ricevute applicative ed eventi append-only;
- claim v2 consumer-aware limitato alla prossima sequenza esatta, con lease e fencing della consegna ancora obbligatori;
- applicazione atomica del messaggio, ricevuta firmata, avanzamento monotono dell'ack e completamento outbox nella stessa transazione;
- deduplicazione per messaggio/destinazione e request ID, senza possibilità di doppia applicazione;
- adozione esplicita `legacy_baseline` delle consegne storiche v0.62.37, senza riscriverne tentativi o teste;
- replay controllato soltanto da ricevute integre e già applicate, registrato nello storico senza generare un secondo ack;
- riconciliazione `affected`/`revalidated` per gap, fingerprint o mismatch tra outbox e inbox;
- promozione rollout v4 vincolata alla salute end-to-end e revoca dei bypass su claim v1, completion v1 e rollout v3;
- compatibilità client v4, provider health v37, season state v16 e management state v26;
- Centro Operativo aggiornato con ricevute, consumatori, gap e consistenza applicativa;
- release v0.62.38 certificata, rollout 10 → 35 → 60 → 85 → 100 e ack seed completo su entrambe le destinazioni;
- migrazione `142_authoritative_consumer_inbox_and_end_to_end_ack_safety.sql` e SQL standalone identico;
- diagnostica finale a 20 controlli; avanzamento ufficiale invariato al 90%.

# v0.62.37 — Outbox operativa transazionale e dead-letter queue

- cattura transazionale degli eventi critici di release, rollout e telemetria tramite trigger `ENABLE ALWAYS`;
- messaggi immutabili con fingerprint, payload versionato, sequenza monotona e deduplicazione per evento sorgente;
- due destinazioni certificate: Centro Operativo e dispatcher notifiche;
- claim concorrente con `FOR UPDATE SKIP LOCKED`, lease temporanea, generazione worker e fencing token hash;
- completamento idempotente con tentativi append-only, backoff esponenziale e massimo cinque tentativi;
- promozione rollout v3 vincolata all'integrità outbox, con revoca del bypass diretto sulla v2;
- dead-letter queue immutabile backend-only; la Direzione vede conteggi e stato sanificati senza accesso al payload operativo;
- compatibilità client v3 fail-closed quando cattura, fingerprint o sequenza non sono più protetti;
- provider health v36, season state v15 e management state v25;
- Centro Operativo aggiornato con stato outbox, backlog, retry, lease scadute e dead-letter;
- release v0.62.37 certificata, rollout al 100% e consegna seed completa su entrambe le destinazioni;
- migrazione `141_transactional_operational_outbox_and_dead_letter_safety.sql` e SQL standalone identico;
- diagnostica finale a 20 controlli; avanzamento ufficiale invariato al 90%.

# v0.62.36 — Telemetria operativa autorevole e rollback automatico

- sorgenti telemetriche certificate con generazione monotona e fencing token conservato soltanto come hash, non esposto ai client;
- osservazioni operative append-only collegate atomicamente a release, generazione release, piano rollout, generazione rollout e percentuale esposta;
- finestre temporali strettamente sequenziali, non sovrapponibili e protette da replay o dati futuri;
- classificazione `healthy`, `degraded` e `critical` basata sulle soglie certificate del piano rollout;
- nuova promozione `promote_leghevo_application_rollout_v2`, autorizzata esclusivamente da una finestra autorevole `healthy` della generazione corrente;
- revoca del bypass service-role sulle precedenti RPC di report salute e promozione v1;
- pausa automatica per telemetria degradata e kill switch con rollback automatico per telemetria critica;
- fingerprint immutabili di sorgente e osservazione, teste protette e storico eventi append-only;
- riconciliazione `affected`/`revalidated` senza cancellare o riscrivere il passato operativo;
- provider health v35, season state v14 e management state v24;
- Centro Operativo aggiornato con sorgente, sequenza, error rate, latenza p95 e rollback automatico;
- release v0.62.36 certificata, attivata e portata al 100% tramite cinque finestre autorevoli `healthy`;
- migrazione `140_authoritative_operational_telemetry_and_automatic_rollback_safety.sql` e SQL standalone identico;
- diagnostica finale a 20 controlli; avanzamento ufficiale invariato al 90%.

# v0.62.35 — Rollout progressivo certificato e kill switch

- piano immutabile per release, ambiente, soglie di errore, crash e osservazioni minime;
- testa rollout protetta con stato sicuro, generazione monotona, percentuale esposta e kill switch;
- eventi e report salute append-only con request ID idempotenti;
- promozioni massime di 25 punti e report `healthy` obbligatorio prima di ogni scaglione;
- pausa automatica o kill switch quando error rate e crash superano le soglie;
- controllo manuale service-role per pausa, ripresa e arresto;
- riconciliazione `affected`/`revalidated` senza riscrivere piani o report;
- compatibilità client estesa alla coorte di installazione con fallback alla release precedente;
- v0.62.35 certificata e attivata, rollout seed 10 → 35 → 60 → 85 → 100;
- provider health v34, season state v13 e management state v23;
- Centro Operativo aggiornato con stato rollout e kill switch;
- migrazione `139_application_progressive_rollout_and_kill_switch_safety.sql` e SQL standalone identico;
- diagnostica finale a 20 controlli; avanzamento ufficiale invariato al 90%.

# v0.62.34 — Contratto di rilascio compatibile e rollback certificato

- certificazione immutabile della versione app, fingerprint bundle, sigillo schema e intervallo client supportato;
- registri `leghevo_application_release_certificates`, `leghevo_application_release_heads` e `leghevo_application_release_events`;
- advisory lock comune, request ID idempotenti e trigger critici `ENABLE ALWAYS`;
- attivazione atomica della release di produzione e rollback soltanto verso versioni precedenti già certificate;
- blocco anti-downgrade sull'RPC di attivazione e riconciliazione obbligatoria delle teste `affected`;
- riconciliazione append-only che preserva lo stato sicuro `active` o `rollback` senza riscrivere i certificati;
- v0.62.33 registrata come target di rollback e v0.62.34 attivata come testa corrente;
- RPC pubblica di compatibilità con verifica delle intestazioni `x-leghevo-version` e `x-leghevo-bundle-fingerprint`;
- barriera client all'avvio: fail-closed quando il contratto installato non è verificabile e fallback legacy soltanto prima dell'installazione della migrazione;
- fingerprint applicativo riproducibile tramite `npm run release:fingerprint`;
- provider health v33, season state v12 e management state v22;
- migrazione `138_application_release_compatibility_and_rollback_safety.sql` e SQL standalone identico;
- diagnostica finale a 20 controlli; avanzamento ufficiale invariato al 90%.

# v0.62.33 — Sigillo globale di integrità applicativa

> Correzione pre-validazione v2: cast espliciti `tgname::text` e `tgenabled::text` nella fingerprint dei trigger, necessari per evitare l’ambiguità PostgreSQL `text || "char"`. Nessuna versione precedente è stata modificata.

- avvio dello Sviluppo 9 verso il 95%, dopo la validazione dello Sviluppo 8 al 90%;
- certificazione immutabile `application_integrity_v1` dell’intero schema applicativo;
- aggregazione di ruoli, mercato, competizione, giornata, competizioni speciali, account e provider in 20 capacità;
- verifica dei contratti trasversali tra mercato, avvio, risultati, chiusura, rollover e bootstrap;
- fingerprint globale di certificazioni, funzioni terminali, trigger, policy RLS e ACL;
- nuove RPC application model v1, provider health v32, season state v11 e management state v21;
- Centro Operativo aggiornato con indicatore globale `MODELLO APP` 20/20;
- migrazione `137_application_integrity_global_seal.sql` e script standalone identico;
- avanzamento ufficiale invariato al 90% fino alla validazione dell’intero Sviluppo 9.

# v0.62.32 — Chiusura certificata del modello di affidabilità provider

- Correzione pre-validazione v2: la diagnostica globale riconosce in modo esplicito i soli falsi legacy attesi prodotti dai wrapper RPC superseded, senza attenuare nessun controllo corrente.

- chiusura strutturale dello Sviluppo 8 con sigillo globale `provider_reliability_v1`;
- aggregazione delle 30 diagnostiche provider precedenti in 20 capacità indipendenti;
- fingerprint stabile di tabelle, funzioni, trigger e policy critiche;
- certificazione immutabile in `leghevo_model_certifications`;
- distinzione tra integrità dello schema e salute operativa corrente della lega;
- nuove RPC provider health v31, season state v10 e management state v20;
- Centro Operativo aggiornato con stato e conteggio delle capacità certificate;
- migrazione `136_provider_reliability_model_closure.sql` e script standalone identico;
- validazione Supabase completata con 20/20 controlli `true`; Sviluppo 8 concluso e avanzamento ufficiale al 90%.

# v0.62.31 — Barriera causale certificata dell’avvio competizione provider

- avvio consentito soltanto con bootstrap provider certificato e calendario fantasy coerente;
- certificato immutabile di bootstrap, scope provider, fingerprint calendario e giornata inaugurale;
- testa di stato `waiting`, `ready`, `official` o `affected` e storico append-only;
- trigger di attivazione `ENABLE ALWAYS` su `leagues.competition_started_at`;
- RPC `start_league_competition_guarded_v4` e blocco delle RPC storiche per client e service role;
- riconciliazione automatica sulle variazioni del bootstrap provider senza riaprire o modificare la stagione;
- adozione non distruttiva delle competizioni già avviate e coerenti;
- stato stagione v9, management v19 e provider health v30;
- migrazione `135_provider_competition_start_causal_barrier_safety.sql`;
- script standalone `LEGHEVO_SUPABASE_PROVIDER_COMPETITION_START_CAUSAL_BARRIER_v1.sql`;
- diagnostica finale a 20 controlli; avanzamento invariato all’85%.

# v0.62.30 — Bootstrap provider certificato della nuova stagione

- catalogo calciatori della nuova stagione obbligatorio prima di mercato e asta;
- copertura provider completa di 20 squadre, 38 giornate e 380 partite prima del calendario;
- certificato immutabile legato al rollover anti-fork, alla generazione catalogo e allo scope fixture;
- teste di stato `waiting`, `catalog_ready`, `ready` e `affected`;
- storico append-only e trigger critici `ENABLE ALWAYS`;
- guard server-side su `roster_entries`, `auction_items` e `fantasy_fixtures`;
- RPC `renew_league_season_guarded_v3`, stato stagione v8, management v18 e provider health v29;
- backfill non distruttivo delle stagioni rinnovate esistenti;
- migrazione `134_provider_new_season_bootstrap_barrier_safety.sql`;
- script standalone `LEGHEVO_SUPABASE_PROVIDER_NEW_SEASON_BOOTSTRAP_BARRIER_v1.sql`;
- diagnostica finale a 20 controlli; avanzamento invariato all'85%.

# v0.62.29 — Rinnovo stagione certificato anti-fork

- barriera server-side sul rinnovo della stagione;
- snapshot ufficiale e integro obbligatorio;
- advisory lock comune e request ID idempotente;
- certificato immutabile della continuità tra stagioni;
- fingerprint atomici di partecipanti e identità delle squadre;
- protezione anti-fork di `previous_league_id`;
- RPC storica protetta e trigger critici `ENABLE ALWAYS`;
- adozione non distruttiva dei rinnovi esistenti;
- stato `affected` senza cancellare la nuova stagione;
- diagnostica finale a 20 controlli.

# v0.62.28

- snapshot ufficiale immutabile di campione, podio, classifica finale e criteri di spareggio;
- pubblicazione atomica nello stesso commit della chiusura stagione e sotto il lock causale comune;
- tabelle `league_season_official_snapshots`, `league_season_official_snapshot_heads` e `league_season_official_snapshot_events`;
- guard `ENABLE ALWAYS` su snapshot, testa, storico, riepilogo finale e identità della stagione;
- regressioni successive marcate `affected` senza riaprire o modificare campione e classifica;
- RPC `complete_league_season_guarded_v3`, `publish_league_season_official_snapshot_v1`, `reconcile_league_season_official_snapshot_v1` e `get_league_season_official_snapshot_v1`;
- stato stagione v6, management state v16 e provider health v27;
- avviso esplicito alla Direzione nell’app in caso di snapshot `affected`;
- migrazione `132_league_season_official_snapshot_safety.sql`;
- script standalone `LEGHEVO_SUPABASE_LEAGUE_SEASON_OFFICIAL_SNAPSHOT_v1.sql`, identico alla migrazione;
- diagnostica finale con esattamente 20 controlli booleani;
- avanzamento invariato all’85%; Sviluppo 8 ancora in corso.

# v0.62.27

- barriera causale server-side sulla chiusura stagione;
- lock comune tra progressioni e commit della stagione;
- certificato `clear`, `blocked` o `affected` dell’intera catena;
- RPC `complete_league_season_guarded_v2`;
- stato stagione v5 e management state v15;
- Centro Operativo provider health v26;
- migrazione `131_provider_season_completion_causal_barrier_safety.sql`;
- script standalone `LEGHEVO_SUPABASE_PROVIDER_SEASON_COMPLETION_CAUSAL_BARRIER_v1.sql`, identico alla migrazione;
- lock causale comune esteso a riconciliazione, INSERT e UPDATE delle progressioni;
- diagnostica finale con esattamente 20 controlli booleani.

# v0.62.26

- Aggiunta la barriera causale certificata della progressione giornata provider.
- Ogni giornata interamente ufficializzata viene valutata rispetto a impatto causale, lineage ufficiale e completamento certificato delle remediation.
- Gli stati `clear`, `blocked` e `affected` distinguono una progressione autorizzabile, non ancora autorizzabile o già registrata ma resa successivamente non affidabile.
- Un trigger `ENABLE ALWAYS` su `matchday_progression_runs` impedisce ai client legacy di avanzare una giornata sopra una officialization run cambiata o sopra una catena precedente non certificata.
- Le progressioni già registrate non vengono cancellate o arretrate automaticamente; restano disponibili per audit e vengono segnalate alla Direzione.
- Nuovi registri `provider_matchday_progression_gate_heads` e `provider_matchday_progression_gate_events`, con guard protetto, RLS ed eventi immutabili.
- Nuove RPC `compute_provider_matchday_progression_gate_v1`, `reconcile_provider_matchday_progression_gate_v1`, `get_league_provider_matchday_progression_gate_v1` e `get_league_provider_sync_health_v25`.
- Centro Operativo aggiornato con l’indicatore `PROGRESSIONE GIORNATA PROTETTA`.
- Migrazione `130_provider_matchday_progression_causal_barrier_safety.sql` con preflight e 20 controlli diagnostici.
- Avanzamento invariato all'85%; Sviluppo 8 ancora in corso.

# v0.62.25

- Aggiunta la chiusura causale certificata delle remediation provider sui risultati ufficiali.
- Una testa remediation non può passare a `resolved` senza impatto `clear`, lineage ufficiale certificata e collegamenti coerenti a proiezione e officialization run.
- Le correzioni manuali certificano lo stesso `result_correction_run` nella proprietà `source_correction_run_ids` della nuova ufficializzazione.
- I casi rientrati senza correzione vengono distinti come `auto_recovered`.
- Nuovi registri protetti e storico immutabile `provider_official_result_remediation_completion_heads/events`.
- Nuove RPC `compute_provider_official_result_remediation_completion_v1`, `reconcile_provider_official_result_remediation_completion_v1`, `get_league_provider_official_result_remediation_completion_v1` e `get_league_provider_sync_health_v24`.
- Centro Operativo aggiornato con l’indicatore `CHIUSURA REMEDIATION CERTIFICATA`.
- Migrazione `129_provider_official_result_remediation_completion_safety.sql` con preflight e 20 controlli diagnostici.
- Avanzamento invariato all'85%; Sviluppo 8 ancora in corso.

# v0.62.24

- Aggiunta la barriera di commit della lineage ufficiale dei risultati provider.
- L’ufficializzazione non viene più valutata durante la fase intermedia in cui proiezione e `finalized_at` sono già scritti ma `officialization_run_id` non è ancora collegato.
- Nuovi registri `provider_official_result_lineage_heads` e `provider_official_result_lineage_events`, con guard `ENABLE ALWAYS`, RLS e storico immutabile.
- La lineage certifica il collegamento tra partita fantasy, proiezione ufficiale, officialization run e, quando presente, correzione causale.
- Le lineage `assembling` sospendono temporaneamente il calcolo dell’impatto senza creare falsi `affected`; le lineage complete ma incoerenti diventano `invalid` e restano disponibili per la remediation.
- Il trigger sulla partita ascolta ora anche `officialization_run_id` e `correction_run_id`, così il secondo UPDATE dell’ufficializzazione chiude realmente il commit causale.
- Nuove RPC `compute_provider_official_result_lineage_v1`, `reconcile_provider_official_result_lineage_v1`, `get_league_provider_official_result_lineage_v1` e `get_league_provider_sync_health_v23`.
- Centro Operativo aggiornato con l’indicatore `LINEAGE UFFICIALE CERTIFICATA`.
- Migrazione `128_provider_official_result_lineage_commit_barrier_safety.sql` con preflight e 20 controlli diagnostici.
- Avanzamento invariato all'85%; Sviluppo 8 ancora in corso.

# v0.62.23

- Aggiunta la coda causale di remediation per i risultati ufficiali esposti a variazioni provider.
- Ogni presa in carico conserva la generazione d’impatto, l’impronta corrente e il collegamento al run di correzione realmente creato.
- La nuova RPC `start_provider_official_result_remediation_v1` usa lo stesso lock di giornata del motore risultati, un lock dedicato e rifiuta valutazioni d’impatto superate.
- Stati protetti `open`, `in_correction`, `resolved` e `superseded`, con testa monotona ed eventi immutabili.
- Un guard `ENABLE ALWAYS` impedisce ai client legacy di riaprire direttamente un risultato ancora `affected`; le correzioni già in corso al momento dell’installazione restano tracciate per audit.
- Centro Risultati aggiornato con badge e CTA `AVVIA CORREZIONE PROVIDER`.
- Nuove RPC `get_league_provider_official_result_remediation_v1` e `get_league_provider_sync_health_v22`.
- Centro Operativo aggiornato con indicatore `REMEDIATION RISULTATI PROTETTA`.
- Migrazione `127_provider_official_result_remediation_safety.sql` con preflight e 20 controlli diagnostici.
- Avanzamento invariato all'85%; Sviluppo 8 ancora in corso.

# v0.62.22

- Aggiunta la certificazione causale dell’impatto sui risultati fantasy già ufficiali.
- Ogni risultato ufficiale viene confrontato con gli input correnti delle risoluzioni home e away che avevano alimentato la proiezione ufficiale.
- Le divergenze vengono classificate per singola partita come `affected`, senza usare il precedente conteggio generico per giornata.
- Le riaperture protette passano a `in_correction`; la successiva ufficializzazione coerente torna `clear`.
- Nuovi registri `provider_official_result_impact_heads` e `provider_official_result_impact_events`, con guard `ENABLE ALWAYS` e storico immutabile.
- Nuove RPC `compute_provider_official_result_impact_v1`, `reconcile_provider_official_result_impact_v1`, `get_league_provider_official_result_impact_v1` e `get_league_provider_sync_health_v21`.
- Centro Operativo aggiornato con l’indicatore `IMPATTO RISULTATI CERTIFICATO`.
- Migrazione `126_provider_official_result_impact_safety.sql` con preflight e 20 controlli diagnostici.
- Avanzamento invariato all'85%; Sviluppo 8 ancora in corso.

# v0.62.21

- Aggiunto il gate certificato di consumo dei voti provider.
- I voti `stale`, `missing`, superati o privi del certificato corrente restano conservati ma non possono entrare in sostituzioni, proiezioni o nuovi risultati ufficiali.
- La vista server-side `provider_match_score_consumption_v1` distingue valori `trusted`, `legacy_trusted`, `retired`, `superseded`, `stale` e privi di certificato.
- `league_matchday_is_resolved` richiede ora una fotografia voti finale e causalmente allineata per ogni partita reale conclusa.
- `get_league_effective_player_score` restituisce un esito bloccato senza rating quando il voto non è consumabile dal motore sportivo.
- Ogni variazione della testa voti registra un evento immutabile e aggiorna automaticamente le proiezioni non ufficializzate della giornata.
- I risultati già ufficializzati non vengono riscritti automaticamente; il Centro Operativo segnala le eventuali partite ufficiali da verificare.
- Nuove RPC `get_provider_score_consumption_state_v1`, `get_league_provider_score_consumption_gate_v1` e `get_league_provider_sync_health_v20`.
- Centro Operativo aggiornato con l’indicatore `CONSUMO VOTI CERTIFICATO`.
- Migrazione `125_provider_score_consumption_gate_safety.sql` con preflight e 20 controlli diagnostici.
- Avanzamento invariato all'85%; Sviluppo 8 ancora in corso.

# v0.62.20

- Aggiunta la coerenza causale certificata tra generazione della partita e fotografia dei voti provider.
- Ogni riconciliazione `sync-fixture-players` cattura testa, riconciliazione, revisione tecnica e generazione causale del ciclo partita osservato.
- La generazione causale resta stabile sulle semplici riletture `refreshed` e avanza soltanto su creazione, avanzamento o correzione finale.
- Il guard della testa partita rifiuta revisioni tecniche iniziali o successive non monotone.
- Le fotografie voti vengono classificate `aligned`, `stale` o `missing` senza cancellare o alterare i valori già pubblicati.
- Un avanzamento o una correzione successiva della partita rende automaticamente superata la fotografia precedente.
- Le variazioni concorrenti durante il commit vengono rilevate tramite confronto delle generazioni.
- Nuovo registro immutabile `provider_fixture_score_coherence_events`, privo di payload, token e identificativi provider grezzi.
- Nuova RPC `finish_provider_sync_run_guarded_v10`; la v9 instrada le chiamate legacy nel nuovo completion gate.
- Nuove RPC `get_provider_fixture_score_coherence_result_v1`, `get_league_provider_fixture_score_coherence_center_v1` e `get_league_provider_sync_health_v19`.
- Edge Function e file standalone di deploy aggiornati con stato, generazioni e motivo della coerenza causale.
- Centro Operativo aggiornato con l’indicatore `COERENZA PARTITA/VOTI PROTETTA`.
- Migrazione `124_provider_fixture_score_causal_coherence_safety.sql` con preflight e 20 controlli diagnostici.
- Avanzamento invariato all'85%; Sviluppo 8 ancora in corso.

# v0.62.19

- Aggiunto il ciclo di vita monotono e certificato delle partite API-Football.
- Ogni run `sync-fixtures` crea una riconciliazione immutabile prima del commit atomico.
- Bloccate regressioni da `FT/AET/PEN` a stati provvisori, perdita dei gol finali e variazioni retroattive di squadre, giornata o data.
- Le correzioni finali legittime restano consentite e vengono tracciate come nuova generazione.
- Nuovi registri `provider_fixture_lifecycle_heads`, `provider_fixture_lifecycle_reconciliations`, `provider_fixture_lifecycle_members` e `provider_fixture_lifecycle_events`.
- Nuova RPC `finish_provider_sync_run_guarded_v9`; la v8 instrada le chiamate legacy nel nuovo completion gate.
- Gli errori `Partite provider non valide` sono deterministici e non generano retry identici inutili.
- Nuove RPC `get_league_provider_fixture_lifecycle_center_v1` e `get_league_provider_sync_health_v18`.
- Edge Function e file standalone di deploy aggiornati con esito e conteggi della riconciliazione.
- Centro Operativo aggiornato con l’indicatore `CICLO PARTITE PROTETTO`.
- Migrazione `123_provider_fixture_lifecycle_monotonic_safety.sql` con preflight e 20 controlli diagnostici.
- Avanzamento invariato all'85%; Sviluppo 8 ancora in corso.

# v0.62.18

- Aggiunta la fotografia autorevole e non distruttiva dei voti per singola partita provider.
- Ogni run `sync-fixture-players` certifica giocatori, squadra di appartenenza e stato finale prima del commit atomico.
- Una fotografia finale deve includere entrambe le squadre e non può regredire successivamente a provvisoria.
- I voti presenti in una precedente fotografia finale ma assenti dalla nuova vengono neutralizzati con ritiro logico, senza cancellare riga, payload o storico.
- I voti ritirati che ricompaiono vengono ripristinati nello stesso commit atomico.
- Nuovi registri `provider_fixture_score_heads`, `provider_fixture_score_reconciliations`, `provider_fixture_score_members` e `provider_fixture_score_events`.
- Nuova RPC `finish_provider_sync_run_guarded_v8`; la v7 instrada tutte le chiamate legacy nel nuovo completion gate.
- Gli errori di fotografia voti sono deterministici e non generano retry identici inutili.
- Nuove RPC `get_league_provider_fixture_score_center_v1` e `get_league_provider_sync_health_v17`.
- Centro Operativo aggiornato con l'indicatore `VOTI PARTITA RICONCILIATI`.
- Migrazione `122_provider_fixture_score_reconciliation_safety.sql` con preflight e 20 controlli diagnostici.
- Avanzamento invariato all'85%; Sviluppo 8 ancora in corso.

# v0.62.17

- Aggiunta la riconciliazione autorevole e non distruttiva del catalogo calciatori API-Football.
- Ogni run `sync-season-players` salva una fotografia immutabile di calciatori e ruoli prima del commit atomico.
- Le stagioni precedenti al catalogo corrente vengono scartate come `catalog.older_season` senza modificare i dati live.
- I calciatori mancanti dalla fotografia corrente vengono resi inattivi, ma anagrafiche, rose e storico non vengono cancellati.
- I ruoli classic/mantra superati vengono rimossi e sostituiti con il write-set certificato.
- Aggiunti guard `ENABLE ALWAYS` su `athletes` e `athlete_roles`: le sincronizzazioni successive non possono riattivare assenti o reintrodurre ruoli fuori catalogo.
- Nuovi registri `provider_player_catalog_heads`, `provider_player_catalog_reconciliations`, `provider_player_catalog_members` e `provider_player_catalog_events`.
- Nuova RPC `finish_provider_sync_run_guarded_v7`; la v6 instrada tutte le chiamate legacy nel nuovo completion gate.
- I recuperi su cataloghi storici vengono certificati `superseded` e non generano retry inutili.
- Nuove RPC `get_league_provider_player_catalog_center_v1` e `get_league_provider_sync_health_v16`.
- Edge Function e file standalone di deploy aggiornati con stato, stagione e conteggi della riconciliazione.
- Centro Operativo aggiornato con l'indicatore `CATALOGO CALCIATORI RICONCILIATO`.
- Migrazione `121_provider_player_catalog_reconciliation_safety.sql` con preflight e 20 controlli diagnostici.
- Avanzamento invariato all'85%; Sviluppo 8 ancora in corso.

# v0.62.16

- Aggiunto un watermark monotono per provider, tipo di sincronizzazione e scope certificato.
- Una pubblicazione iniziata prima non può più sovrascrivere dati già pubblicati da un run iniziato più recentemente sullo stesso scope.
- La decisione anti-regressione e la pubblicazione sono serializzate tramite advisory lock transazionale.
- I run superati conservano consegna e scope certificati, scartano lo staging e terminano senza aprire incidenti o retry inutili.
- Nuovi registri `provider_sync_scope_watermarks` e `provider_sync_scope_watermark_events`, con storico immutabile privo di payload e credenziali.
- Nuova RPC `finish_provider_sync_run_guarded_v6`; i worker v5 e v4 vengono instradati nel percorso monotono protetto.
- Il completion guard consente lo scarto benigno soltanto in presenza dell'evento immutabile `watermark.stale_run`.
- Nuove RPC `get_league_provider_scope_watermark_center_v1`, `get_league_provider_atomic_publication_center_v2` e `get_league_provider_sync_health_v15`.
- Edge Function e file standalone di deploy aggiornati con stato di pubblicazione superata e generazione del watermark.
- Centro Operativo aggiornato con l'indicatore `ORDINE TEMPORALE PROTETTO`.
- Migrazione `120_provider_monotonic_publication_watermark_safety.sql` con preflight e 20 controlli diagnostici.
- Avanzamento invariato all'85%; Sviluppo 8 ancora in corso.

# v0.62.15

- Aggiunto il vincolo semantico dello scope per ogni run provider.
- Il database lega il tipo di sincronizzazione alle sole operazioni consentite: rose, calendario o voti partita.
- Stagione, data e identificativo partita richiesti vengono ricontrollati sulle righe di staging prima della pubblicazione.
- Relazioni tra atleti, ruoli, giornate, partite e voti vengono certificate server-side prima del commit atomico.
- Nuovi registri `provider_sync_scope_certificates` e `provider_sync_scope_events`, con storico immutabile privo di payload e credenziali.
- La nuova RPC `finish_provider_sync_run_guarded_v5` certifica lo scope prima di richiamare la pubblicazione atomica v4.
- Il percorso legacy v4 non può pubblicare uno staging privo del certificato semantico.
- Gli errori `Ambito provider non valido` sono classificati come richieste non recuperabili, evitando retry identici inutili.
- Nuove RPC `get_league_provider_semantic_scope_center_v1` e `get_league_provider_sync_health_v14`.
- Edge Function e file standalone di deploy aggiornati per usare il finish v5.
- Centro Operativo aggiornato con l’indicatore `SCOPE PROVIDER VINCOLATO`.
- Migrazione `119_provider_semantic_scope_safety.sql` con preflight e 20 controlli diagnostici.
- Avanzamento invariato all'85%; Sviluppo 8 ancora in corso.

# v0.62.14

- Aggiunto staging isolato per atleti, ruoli, giornate, partite e voti provider.
- Le scritture del worker non modificano più immediatamente le tabelle operative.
- Nuova RPC `stage_provider_sync_write_guarded_v1` con lease, fencing e contratto runtime nella stessa transazione.
- Nuova RPC `finish_provider_sync_run_guarded_v4`: certificazione della consegna, pubblicazione dei dati e chiusura del run avvengono in un unico commit.
- Se il run fallisce, tutte le righe temporanee vengono scartate senza lasciare dati parziali visibili.
- Nuovi registri `provider_sync_publications` e `provider_sync_publication_events`; gli eventi sono immutabili e non contengono payload o credenziali.
- Le tabelle di staging sono accessibili esclusivamente al `service_role` e vengono svuotate dopo l'esito finale.
- Aggiunte le RPC `get_league_provider_atomic_publication_center_v1` e `get_league_provider_sync_health_v13`.
- Edge Function e file standalone di deploy aggiornati per staging e finish v4.
- Centro Operativo aggiornato con lo stato delle pubblicazioni atomiche.
- Migrazione `118_provider_atomic_publication_safety.sql` con preflight e 20 controlli diagnostici.
- Avanzamento invariato all'85%; Sviluppo 8 ancora in corso.

# v0.62.13

- Aggiunta la certificazione di completezza delle consegne API-Football prima della chiusura del run.
- Verificati conteggio `results`, pagina dichiarata, totale pagine stabile e assenza di entità duplicate.
- Nuove tabelle `provider_sync_delivery_certificates`, `provider_sync_delivery_units` e `provider_sync_delivery_entities`.
- Le entità sono registrate esclusivamente tramite impronte SHA-256; nessun identificativo grezzo o payload viene conservato.
- Nuova RPC `record_provider_sync_delivery_unit_v1` riservata al worker server.
- Nuova RPC `finish_provider_sync_run_guarded_v3` con completion gate atomico.
- Le consegne mancanti o incoerenti vengono respinte e classificate come errori provider recuperabili.
- Nuove RPC `get_league_provider_delivery_center_v1` e `get_league_provider_sync_health_v12`.
- Edge Function e file standalone di deploy aggiornati con i checkpoint di consegna.
- Centro Operativo aggiornato con stato delle consegne certificate, respinte e in corso.
- Migrazione `117_provider_delivery_completeness_safety.sql` con preflight e 20 controlli diagnostici.
- Avanzamento invariato all'85%; Sviluppo 8 ancora in corso.

# v0.62.12

- Aggiunta la validazione runtime dei payload API-Football prima della trasformazione e della scrittura.
- Aggiunto un secondo contratto database atomico con fencing tramite `apply_provider_sync_write_guarded_v2`.
- I payload fuori schema vengono respinti e certificati senza salvare il contenuto grezzo.
- Nuova tabella immutabile `provider_payload_contract_violations`, protetta da RLS e pubblicata in Realtime.
- La quarantena conserva soltanto ambito, codice, sintesi, indice, dimensione e impronta SHA-256.
- Gli errori `Payload provider non valido` sono compatibili con la policy retry esistente e non generano tentativi inutili.
- Nuove RPC `record_provider_payload_contract_violation_v1`, `get_league_provider_payload_contract_center_v1` e `get_league_provider_sync_health_v11`.
- Edge Function e file standalone di deploy aggiornati; il deploy definitivo resta nella fase finale di ambiente.
- Centro Operativo aggiornato con lo stato dei contratti payload.
- Migrazione `116_provider_payload_contract_quarantine_safety.sql` con preflight e 20 controlli diagnostici.
- Avanzamento invariato all'85%; Sviluppo 8 ancora in corso.

# v0.62.11

- Aggiunta una lease esclusiva con fencing token per ogni worker provider.
- Il token viene rinnovato durante gli heartbeat; verifica della lease e scrittura sportiva avvengono nella stessa transazione database.
- Un worker scaduto, revocato o sostituito viene respinto dal database anche se il processo precedente è ancora in esecuzione.
- Nuove tabelle `provider_sync_worker_leases` e `provider_sync_worker_lease_events`, con storico immutabile privo di token.
- Scadenza automatica delle lease inattive e chiusura del run tramite il percorso certificato esistente.
- Nuove RPC `start_provider_sync_run_guarded_v2`, `apply_provider_sync_write_guarded_v1`, `heartbeat_provider_sync_run_guarded_v2`, `finish_provider_sync_run_guarded_v2`, `claim_provider_recovery_request_v3`, `claim_next_provider_recovery_request_v4`, `get_league_provider_recovery_center_v7` e `get_league_provider_sync_health_v10`.
- Edge Function aggiornata per acquisizione, rinnovo e verifica della lease; il deploy resta nella fase finale di ambiente.
- Centro Operativo aggiornato con lo stato del fencing worker.
- Migrazione `115_provider_worker_lease_fencing_safety.sql` con preflight e 20 controlli diagnostici.
- Avanzamento invariato all'85%; Sviluppo 8 ancora in corso.

# v0.62.10

- Aggiunta la verifica protetta dell'efficacia dei recuperi provider completati.
- Certificazione storica `superseded` per evitare retry duplicati durante il backfill.
- Aggiunto un guard server-side contro nuove richieste manuali mentre la verifica ha un retry attivo.
- Nuovo registro immutabile `provider_recovery_outcome_certificates`, con RLS e pubblicazione Realtime.
- I recuperi tecnicamente completati ma con incidente ancora aperto proseguono automaticamente nella catena di retry e backoff.
- L'esaurimento della verifica riutilizza il circuit breaker esistente, evitando blocchi concorrenti o nuovi cicli manuali.
- Nuove RPC `get_league_provider_outcome_verification_center_v1`, `get_league_provider_retry_center_v3`, `get_league_provider_recovery_center_v6` e `get_league_provider_sync_health_v9`.
- Centro Operativo aggiornato con lo stato della verifica di efficacia.
- Migrazione `114_provider_recovery_outcome_verification_safety.sql` con preflight e 20 controlli diagnostici.
- Avanzamento invariato all'85%; Sviluppo 8 ancora in corso.

# v0.62.9

- Aggiunto il circuit breaker protetto per interrompere nuovi cicli manuali dopo l’esaurimento dei retry provider.
- Nuove tabelle `provider_recovery_circuit_breakers` e `provider_recovery_circuit_breaker_events`, con RLS, revisioni e storico immutabile.
- Nuova RPC Direzione `release_provider_recovery_circuit_breaker_guarded_v1` con controllo revisione e idempotenza.
- Nuove RPC `get_league_provider_circuit_breaker_center_v1`, `get_league_provider_retry_center_v2`, `get_league_provider_recovery_center_v5` e `get_league_provider_sync_health_v8`.
- Centro Operativo aggiornato per mostrare il blocco e autorizzare la riapertura.
- Migrazione `113_provider_recovery_circuit_breaker_safety.sql` con preflight e 20 controlli diagnostici.
- Avanzamento ufficiale confermato all’85%.

# v0.62.8

- Retry automatico dei recuperi provider con classificazione deterministica dei fallimenti.
- Backoff crescente e limite massimo di tre tentativi per ogni catena di recupero.
- Registri `provider_recovery_retry_schedules` e `provider_recovery_retry_events` con RLS e storico immutabile.
- Nuove RPC `dispatch_due_provider_recovery_retry_v1`, `claim_next_provider_recovery_request_v3`, `get_league_provider_recovery_center_v4` e `get_league_provider_sync_health_v7`.
- Edge Function aggiornata per elaborare prima i retry automatici maturati.
- Centro Operativo con indicatore `RETRY AUTOMATICO ATTIVO`.
- Migrazione `112_provider_recovery_retry_backoff_safety.sql` con preflight e 20 controlli diagnostici.

# v0.62.7

- Heartbeat protetto e revisionato per i worker API-Football ancora attivi.
- `provider_sync_runs` e `provider_sync_run_events` estesi con fase, avanzamento, totale e timestamp heartbeat.
- Nuova RPC `heartbeat_provider_sync_run_guarded_v1` riservata al worker server.
- Nuove RPC `get_league_provider_recovery_center_v3` e `get_league_provider_sync_health_v6`.
- Edge Function aggiornata con heartbeat dopo ogni unità di lavoro elaborata.
- Centro Operativo con indicatore `HEARTBEAT WORKER ATTIVO` e progresso certificato.
- Migrazione `111_provider_worker_heartbeat_and_progress_safety.sql` con preflight e 20 controlli diagnostici.

# v0.62.6

- Watchdog protetto per le richieste di recupero provider rimaste bloccate nello stato `running`.
- Timeout differenziati per voti partita, calendario e rose stagionali.
- Chiusura atomica dei run scaduti tramite il percorso certificato del provider.
- Nuovo registro immutabile `provider_recovery_watchdog_events`, protetto da RLS e pubblicato in Realtime.
- Nuove RPC `expire_stale_provider_recovery_requests_v1`, `claim_provider_recovery_request_v2`, `claim_next_provider_recovery_request_v2`, `get_league_provider_recovery_center_v2` e `get_league_provider_sync_health_v5`.
- Edge Function aggiornata per eseguire il watchdog prima della presa in carico della coda.
- Centro Operativo con indicatore `WATCHDOG CODA ATTIVO` e conteggio dei timeout recenti.
- Migrazione `110_provider_recovery_watchdog_safety.sql` con preflight e 20 controlli diagnostici.

# v0.62.5

- Coda protetta e idempotente per il recupero degli incidenti API-Football.
- Tabelle `provider_recovery_requests` e `provider_recovery_request_events` con RLS, revisioni e storico immutabile.
- Un solo recupero attivo per incidente e collegamento certificato a un nuovo tentativo reale di `provider_sync_run`; vengono condivisi soltanto run ancora in corso.
- Nuove RPC per richiesta, presa in carico server e monitoraggio del Centro Recuperi.
- Edge Function `sync-football-data` aggiornata per elaborare un `recoveryRequestId` o il prossimo elemento della coda senza duplicare run già attivi; deploy e pianificazione del worker restano nella fase finale di ambiente.
- Centro Operativo con stato della coda e azione `ACCODA RECUPERO PROVIDER`.
- Migrazione `109_provider_recovery_queue_safety.sql` con preflight e 20 controlli diagnostici.

# v0.62.4

- Incidenti operativi API-Football aperti e aggiornati automaticamente dopo sync falliti o anomalie di qualità.
- Tabelle `provider_operational_incidents` e `provider_operational_incident_events` con revisioni, RLS e storico immutabile.
- Risoluzione automatica degli incidenti dopo il ripristino del flusso o della qualità dati.
- Nuove RPC `get_league_provider_incident_center_v1` e `get_league_provider_sync_health_v3`.
- Centro Operativo aggiornato con incidenti attivi, criticità e risoluzioni recenti.
- Migrazione `108_provider_operational_incident_safety.sql` con 20 controlli diagnostici.

# v0.62.3

- Certificazione della freschezza e della copertura dei dati API-Football.
- Nuovo registro immutabile `provider_data_quality_snapshots`, alimentato automaticamente dopo i run completati.
- Rilevamento di partite non collegate, risultati definitivi incompleti, voti fuori intervallo e flussi live non aggiornati.
- Nuove RPC `get_league_provider_data_quality_v1` e `get_league_provider_sync_health_v2`.
- Centro Operativo aggiornato con anomalie, copertura partite e copertura voti.
- Migrazione `107_provider_data_freshness_and_coverage_safety.sql` con diagnostica finale di 20 controlli.

# v0.62.2

- Sincronizzazioni API-Football protette da richiesta normalizzata, finestra idempotente e lock transazionale.
- `provider_sync_runs` ora conserva chiave, tentativo, revisione e impronte deterministiche senza alterare lo storico esistente.
- Nuovo registro immutabile `provider_sync_run_events` pubblicato in Realtime senza payload o messaggi di errore.
- Nuove RPC server-side `start_provider_sync_run_guarded_v1` e `finish_provider_sync_run_guarded_v1`.
- Edge Function `sync-football-data` aggiornata per riusare run già completati o in corso ed evitare elaborazioni duplicate.
- Nuova RPC `get_league_provider_sync_health_v1` e monitor del pipeline dati nel Centro Operativo.
- Migrazione `106_provider_sync_safety.sql` con preflight dettagliato, validazione transazionale e diagnostica finale di 20 controlli.

# v0.62.1

- Avviato lo Sviluppo 8 dedicato a dati ufficiali, rinvii e affidabilità operativa.
- Applicazione e revoca del voto d'ufficio rese atomiche, idempotenti e revisionate.
- Nuovo registro immutabile `fixture_resolution_action_runs` con impronta dello stato e sincronizzazione Realtime.
- Nuove RPC protette per applicazione, revoca e lettura del Centro Rinvii.
- Le vecchie RPC vengono instradate sul percorso protetto per compatibilità.
- Centro Rinvii aggiornato con indicatore di protezione e revisione certificata.
- Migrazione `105_postponed_fixture_resolution_safety.sql` con preflight dettagliato e diagnostica finale di 20 controlli.

# v0.62.0

- Corretto il riepilogo delle diagnostiche JSONB: il conteggio usa ora `jsonb_each`, compatibile con PostgreSQL/Supabase, senza richiamare l'inesistente `jsonb_object_length`.
- Chiusura certificata dello Sviluppo 7: account, privacy, assistenza, notifiche, push, credenziali ed esportazione dati.
- Certificazione globale `account_services_v1` nel registro immutabile `leghevo_model_certifications`.
- Nuove funzioni `get_account_services_schema_readiness_v1` e `compute_account_services_schema_fingerprint_v1`.
- Riuso delle nove diagnostiche precedentemente validate e controllo di esattamente 20 capacità strutturali.
- Nuove RPC `get_my_account_services_model_closure_integrity_v1` e `get_my_account_center_v5`.
- Centro Account aggiornato con indicatore `MODELLO CERTIFICATO`.
- Migrazione `104_account_services_model_closure.sql` idempotente, non distruttiva e con diagnostica finale di 20 controlli.

# v0.61.9

- Centro unificato degli otto servizi account con stato revisionato e registro immutabile.
- Nuove RPC `get_my_account_service_hub_v1` e `get_my_account_center_v4`.
- Migrazione `103_account_services_integrity_hub.sql` con 20 controlli diagnostici.

# v0.61.8

- Esportazione dei dati personali protetta da chiave idempotente e lock per account.
- Nuovo registro immutabile `personal_data_export_runs`, eliminato insieme all’account.
- Impronta SHA-256 del contenuto, revisione progressiva e certificato incluso nel JSON condiviso.
- Nuove RPC `export_my_personal_data_guarded_v1` e `get_my_privacy_center_v4`.
- Accesso diretto alle vecchie RPC di esportazione revocato agli utenti autenticati.
- Realtime esteso al registro esportazioni e indicatore `ESPORTAZIONE PROTETTA` nel Centro Privacy.
- Migrazione `102_personal_data_export_safety.sql` con preflight dettagliato, validazione transazionale e 20 controlli diagnostici.

# v0.61.7

- Cambio password certificato automaticamente tramite trigger su `auth.users`.
- Nuovo stato revisionato `account_security_states` e registro immutabile `account_security_events`.
- Tracciamento di cambio password, cambio email e conferma email senza salvare password, hash o token.
- Nuova RPC `get_my_account_center_v3` con stato della sicurezza credenziali.
- Realtime esteso allo stato e agli eventi di sicurezza dell'account.
- Schermata Profilo con indicatore `CREDENZIALI PROTETTE`, revisione e ultimo cambio certificato.
- Migrazione `101_account_credential_security_safety.sql` con preflight dettagliato e 20 controlli diagnostici.

# v0.61.6

- Centro Notifiche protetto con lettura singola e massiva atomiche e idempotenti.
- Stato revisionato e impronta SHA-256 per ogni notifica, mantenuti da trigger.
- Registro immutabile `notification_action_runs` per le azioni di lettura.
- Nuove RPC `mark_notification_read_guarded_v1`, `mark_all_notifications_read_guarded_v1` e `get_my_notification_center_v2`.
- RPC storiche instradate sul percorso protetto e scritture dirette residue bloccate.
- Realtime esteso al registro certificato e indicatore `INBOX PROTETTA` nell'app.
- Migrazione `100_notification_center_safety.sql` con preflight dettagliato, validazione transazionale e 20 controlli diagnostici.

# v0.61.5

- Accettazione dei documenti legali e dichiarazione sul requisito di età protette da chiave idempotente e revisione ottimistica.
- Registro immutabile `legal_acceptance_action_runs` per registrazione, aggiornamento e certificazione delle prese visione esistenti.
- Nuove RPC `save_my_privacy_preferences_guarded_v1` e `get_my_privacy_center_v3`.
- Collegamento esplicito alla release legale pubblicata e impronta SHA-256 dello stato accettato.
- Trigger di registrazione aggiornato, compatibilità della RPC storica e sincronizzazione Realtime multi-dispositivo.
- Centro Privacy e onboarding con indicatore `ACCETTAZIONE PROTETTA` e revisione certificata.
- Migrazione `099_legal_acceptance_and_age_gate_safety.sql` con preflight dettagliato, validazione transazionale e 20 controlli diagnostici.

# v0.61.4

- Profilo e cancellazione account protetti con chiavi idempotenti e revisione ottimistica.
- Registro immutabile `account_action_runs` per aggiornamento profilo ed eliminazione definitiva.
- Nuove RPC `update_my_profile_guarded_v1`, `delete_my_account_guarded_v1` e `get_my_account_center_v2`.
- Allineamento atomico del nome tra `public.profiles` e metadata di `auth.users`.
- Trasferimento protetto delle leghe, anonimizzazione storica e rimozione dei dispositivi push durante la cancellazione.
- RPC storiche instradate sul percorso protetto, Realtime e indicatore mobile `GESTIONE PROTETTA`.
- Migrazione `098_account_profile_and_deletion_safety.sql` con preflight esplicito e 20 controlli diagnostici.

# v0.61.3

- Preferenze push protette con chiavi idempotenti e revisione ottimistica.
- Registro immutabile `push_preference_action_runs` per salvataggi e gestione dispositivi.
- Nuove RPC `save_my_push_notification_preferences_guarded_v1`, `register_my_push_device_guarded_v1`, `disable_my_push_device_guarded_v1` e `release_stored_push_device_guarded_v1`.
- Blocco del trasferimento silenzioso di token attivi tra account diversi.
- Centro preferenze v2 con revisione certificata, Realtime e indicatore mobile `GESTIONE PROTETTA`.
- RPC storiche instradate sul percorso protetto e blocco delle scritture dirette residue.
- Migrazione `097_push_preferences_and_device_safety.sql` con preflight esplicito e 20 controlli diagnostici.

# v0.61.2

- Centro Assistenza protetto con chiavi idempotenti e revisione ottimistica.
- Registro immutabile `support_request_action_runs` per apertura, risposta, chiusura e lavorazione staff.
- Nuove RPC `create_my_support_request_guarded_v1`, `reply_to_my_support_request_guarded_v1`, `close_my_support_request_guarded_v1` e `process_support_request_guarded_v1`.
- Centro Assistenza v2 con stato di protezione e revisione certificata per ogni pratica.
- RPC storiche instradate sul percorso protetto e blocco delle scritture dirette residue.
- Pubblicazione Realtime idempotente di richieste, messaggi, eventi e registro azioni.
- Migrazione `096_support_request_safety.sql` con preflight esplicito e 20 controlli diagnostici.

# v0.61.1

- Avviato lo Sviluppo 7 dedicato ad account, privacy, notifiche, assistenza e preparazione al rilascio.
- Richieste privacy protette da chiavi idempotenti e revisione ottimistica.
- Registro immutabile `data_rights_request_action_runs` per invio, annullamento e lavorazione.
- Nuove RPC `submit_my_data_rights_request_guarded_v1`, `cancel_my_data_rights_request_guarded_v1` e `set_data_rights_request_status_guarded_v1`.
- Centro privacy v2 con revisione certificata e indicatore mobile della gestione protetta.
- RPC storiche instradate sul percorso protetto e sincronizzazione Realtime del registro.
- Migrazione `095_data_rights_request_safety.sql` con preflight esplicito e 20 controlli diagnostici.

# v0.61.0

- Chiusura certificata dello Sviluppo 6 dedicato alle competizioni speciali.
- Certificazione unificata di Coppa di Lega, Supercoppa e Playoff Scudetto tramite `leghevo_model_certifications`.
- Impronta strutturale di tabelle, funzioni, trigger, RLS, permessi e registri Realtime.
- Diagnostica globale `get_special_competitions_schema_readiness_v1` composta da 20 capacità.
- Stato operativo per lega `get_league_special_competitions_model_closure_integrity_v1`.
- Direzione Lega v14 e indicatore mobile `COMPETIZIONI SPECIALI · CERTIFICATE`.
- Migrazione `094_special_competitions_model_closure.sql` idempotente, non distruttiva e dotata di preflight esplicito.

# v0.60.9

- Certificazione immutabile della conclusione dei Playoff Scudetto.
- Registro `league_playoff_completion_certificates` collegato alla finale e alla relativa ufficializzazione protetta.
- Impronta SHA-256 di campione, finalista, tabellone, finale e qualificate.
- Certificazione automatica e backfill non distruttivo dei Playoff già conclusi.
- Stato Playoff v5, diagnostica dedicata, Realtime e indicatore mobile `ESITO FINALE CERTIFICATO`.

# v0.60.8

- Ufficializzazione atomica e idempotente dei turni Playoff con RPC `finalize_league_playoff_round_guarded_v1`.
- Registro immutabile `league_playoff_round_finalization_runs` collegato all’avvio certificato e all’ufficializzazione della giornata.
- Impronte SHA-256 di punteggi, vincitori, avanzamento del tabellone e podio finale.
- Endpoint storico instradato sul percorso protetto e backfill non distruttivo dei turni già ufficiali.
- Stato Playoff v4, diagnostica dedicata, Realtime e indicatore mobile dei turni certificati.

# v0.60.7

- Avvio atomico e idempotente dei Playoff Scudetto con RPC `start_league_playoffs_guarded_v1`.
- Registro immutabile `league_playoff_start_runs` collegato alla configurazione certificata v0.60.6.
- Congelamento delle qualificate, delle teste di serie, delle giornate e del tabellone iniziale tramite impronte SHA-256.
- Verifica della completa ufficializzazione e progressione certificata della stagione regolare.
- Endpoint storico instradato sul percorso protetto, backfill non distruttivo dei Playoff già avviati e stato `get_league_playoff_state_v3`.
- Diagnostica dedicata, Realtime e indicatore mobile `TABELLONE CERTIFICATO · AVVIO PROTETTO`.

# v0.60.6

- Configurazione atomica e idempotente dei Playoff Scudetto Top 4 o Top 8 con RPC `configure_league_playoffs_guarded_v1`.
- Registro immutabile `league_playoff_configuration_runs` con richiesta, formato e impronte SHA-256.
- Vecchio endpoint instradato sul percorso protetto e certificazione non distruttiva delle configurazioni esistenti.
- Stato Playoff v2, diagnostica dedicata, Realtime e indicatore mobile anti-doppio tocco.

# v0.60.5

- Ufficializzazione atomica e idempotente della Supercoppa con RPC `finalize_league_super_cup_guarded_v1`.
- Registro immutabile `league_super_cup_finalization_runs` collegato a programmazione, giornata ufficializzata e risoluzioni formazione.
- Impronte SHA-256 di fonti, punteggi, gol e verdetto finale.
- Vecchio endpoint instradato sul percorso protetto e backfill non distruttivo delle Supercoppe concluse.
- Stato Supercoppa v3, diagnostica dedicata, Realtime e indicatore mobile del verdetto certificato.

# v0.60.4

- Programmazione atomica e idempotente della Supercoppa con RPC `create_league_super_cup_guarded_v1`.
- Registro immutabile `league_super_cup_schedule_runs` con richiesta, qualificati, giornata e impronte SHA-256.
- Verifica della continuità dei manager tra stagione precedente e stagione corrente.
- Collegamento obbligatorio al certificato conclusivo della Coppa v0.60.3.
- Vecchio endpoint instradato sul percorso protetto e backfill non distruttivo delle Supercoppe esistenti.
- Stato Supercoppa v2, diagnostica dedicata, Realtime e indicatore mobile anti-doppio tocco.

# v0.60.3

- Certificazione immutabile della conclusione della Coppa di Lega.
- Impronta SHA-256 di finale, podio, tabellone e partecipanti.
- Certificazione automatica alla proclamazione del campione.
- Backfill non distruttivo delle Coppe già concluse.
- Stato Coppa v4, diagnostica dedicata e sincronizzazione Realtime.
- Indicatore mobile “ESITO FINALE CERTIFICATO”.

## [0.60.2] - 2026-07-31

### Revisione correttiva verificabile
- Aggiunto l'helper interno `leghevo_sha256_hex_v1`, indipendente dallo schema di installazione di `pgcrypto`.
- Uso esplicito della firma `digest(bytea, text)` per evitare l'errore `digest(text, unknown) does not exist`.
- Ripristinata anche la funzione di sorteggio v0.60.1, che conteneva lo stesso rischio latente con `search_path` vuoto.
- La diagnostica finale controlla ora l'intera pipeline hash della Coppa senza aumentare il numero dei 20 valori attesi.


### Coppa di Lega
- Ufficializzazione atomica e idempotente dei turni con RPC `finalize_league_cup_round_guarded_v1`.
- Registro immutabile `league_cup_round_finalization_runs` collegato all’ufficializzazione della giornata.
- Impronte di ingresso e risultato per punteggi, sostituzioni, vincitori e avanzamento del tabellone.
- Nuovo stato `get_league_cup_state_v3` e diagnostica `get_league_cup_round_integrity_v1`.

### Sicurezza
- Il client invia il turno atteso: due richieste concorrenti non possono ufficializzare accidentalmente il turno successivo.
- I risultati della Coppa derivano dal motore formazione e sostituzioni certificato.
- Il vecchio endpoint confluisce nel percorso protetto e le scritture dirette sul registro restano bloccate.

### Interfaccia
- La schermata Coppa mostra il numero di turni ufficiali certificati.
- Realtime esteso al registro delle ufficializzazioni della Coppa.

## [0.60.1] - 2026-07-31

### Avvio Sviluppo 6
- Primo blocco delle competizioni speciali: sorteggio protetto della Coppa di Lega.
- Registro immutabile `league_cup_draw_runs` con richiesta, partecipanti, calendario e impronta del tabellone.
- Nuova RPC idempotente `create_league_cup_guarded_v1` e stato Coppa `get_league_cup_state_v2`.
- Diagnostica `get_league_cup_draw_integrity_v1` e sincronizzazione Supabase Realtime.

### Sicurezza
- Una doppia pressione o un ritentativo di rete non può generare due Coppe o due tabelloni.
- Il sorteggio è deterministico rispetto alla richiesta ed è protetto da lock transazionale per lega.
- Partecipanti e giornate future consecutive vengono certificati prima della creazione.
- Le Coppe storiche già presenti vengono certificate senza alterare abbinamenti o risultati.

### Interfaccia
- La Coppa mostra lo stato `SORTEGGIO CERTIFICATO · ANTI-DOPPIO TOCCO`.
- Il client usa le RPC protette mantenendo un fallback compatibile con installazioni precedenti.

## [0.60.0] - 2026-07-31

### Chiusura Sviluppo 5
- Certificazione immutabile e verificabile dell’intero motore giornata.
- Impronta di schema per tabelle, funzioni, trigger e permessi critici.
- Direzione Lega v13 con stato del modello certificato.

### Revisione correttiva verificata
- Ripristino delle RPC `reopen_league_fixture_guarded_v1`,
  `reopen_league_matchday_guarded_v1` e della diagnostica correzioni v1.
- Ripristino delle relative ACL senza riaprire funzioni interne o accessi anonimi.
- Pubblicazione idempotente di tutti i registri dello Sviluppo 5 in Supabase Realtime.
- Errore preventivo reso diagnostico, mantenendo il rollback completo della transazione.

## [0.59.9] - 2026-07-31

### Aggiunto
- Coordinatore unico dello stato giornata e diagnostica end-to-end del ciclo sportivo.
- Direzione Lega v12 con indicatori distinti per formazione, Live e intero ciclo giornata.
- Blocco delle scritture dirette residue sulle tabelle operative e sui registri certificati.

### Revisione correttiva
- Ripristino idempotente della tabella `result_correction_runs` quando risulta assente.
- Ricostruzione sicura di indici, RLS, policy, trigger, collegamento alle partite e pubblicazione Realtime.
- Diagnostica finale resa esplicita anche sulla continuità del modulo correzioni v0.59.6.

## [0.59.8] - 2026-07-31

### Aggiunto
- Registro immutabile `season_completion_runs` collegato all’ultima progressione e ufficializzazione certificate.
- Chiusura idempotente `complete_league_season_guarded_v1` con blocco transazionale per lega.
- Stato stagione v4 e Direzione Lega v11 con requisito esplicito di progressione completa.
- Diagnostica `get_league_season_completion_integrity_v1` e sincronizzazione Realtime dedicata.

### Sicurezza
- Impossibile chiudere la stagione con giornate ufficiali prive della relativa fotografia di classifica.
- La classifica finale viene verificata tramite impronta prima di proclamare il campione.
- Doppie pressioni, ritentativi e richieste concorrenti restituiscono la stessa chiusura certificata.
- La vecchia RPC `complete_league_season` confluisce nel percorso protetto.

## 0.59.7 – revisione correttiva

- Correzione della migrazione 081: ripristino difensivo della RPC `finalize_league_matchday_guarded_v2(uuid, uuid, uuid)` prima della creazione della v3.

## [0.59.7] - 2026-07-31

### Aggiunto
- Fotografia certificata della classifica dopo ogni ufficializzazione della giornata.
- Registro protetto `matchday_progression_runs` con revisione, impronta e collegamento all'ufficializzazione sorgente.
- Avanzamento atomico del puntatore della competizione alla giornata successiva.
- Diagnostica `get_league_matchday_progression_integrity_v1` e sincronizzazione Realtime dedicata.

### Sicurezza
- Impossibile saltare giornate o avanzare con risultati parziali.
- Le riufficializzazioni aggiornano classifica e revisione senza far arretrare il calendario.
- Doppie pressioni e richieste concorrenti restituiscono la stessa progressione certificata.
- La giornata finale viene marcata come pronta alla chiusura della stagione senza chiuderla automaticamente.

## [0.59.6] - 2026-07-31

### Aggiunto
- Registro protetto `result_correction_runs` per riaperture di singole partite o dell'intera giornata.
- Chiave idempotente, revisione progressiva e impronta verificabile per ogni correzione.
- Ufficializzazione v2 capace di acquisire soltanto i risultati corretti e conservare quelli già ufficiali.
- Diagnostica `get_league_result_correction_integrity_v1` e aggiornamento Realtime dedicato.

### Sicurezza
- La riapertura rende obsoleta la precedente fotografia ufficiale della giornata senza cancellarne lo storico.
- Una nuova ufficializzazione ricostruisce una fotografia completa collegando proiezioni precedenti e corrette.
- Bloccate doppie riaperture, richieste concorrenti, collegamenti incoerenti e scritture dirette sul registro.
- Le vecchie RPC di correzione e ufficializzazione confluiscono nei percorsi protetti.

## [0.59.5] - 2026-07-31

### Aggiunto
- Ufficializzazione atomica e idempotente dell'intera giornata.
- Registro `matchday_officialization_runs` con revisione, impronta e snapshot.
- Collegamento di ogni risultato ufficiale alla proiezione Live sorgente.
- Diagnostica `get_league_matchday_officialization_integrity_v1`.

### Sicurezza
- Tutti i risultati della giornata vengono acquisiti nella stessa transazione.
- Punti, gol, modificatori e sostituzioni derivano dalla proiezione certificata.
- Bloccate ufficializzazioni parziali, concorrenti o duplicate.
- La vecchia RPC di chiusura viene instradata sul nuovo percorso protetto.

### Tooling
- Aggiunta configurazione npm locale contro registry proxy incompleti.
- Aggiunti i comandi `doctor`, `install:clean` e `verify`.

## [0.59.4] - 2026-07-31

### Aggiunto
- Proiezione Live protetta e revisionata per ogni partita della giornata.
- Registro `live_fixture_projection_runs` con impronta di input e risultato.
- API `get_my_live_match_v6` coerente con le sostituzioni certificate.
- Aggiornamento Realtime del client anche sulle revisioni Live.

### Sicurezza
- Elaborazioni concorrenti e duplicate ricondotte alla stessa revisione idempotente.
- Punti, modificatore difesa, bonus casa, gol e regola dello scarto derivano dalla stessa proiezione certificata.
- Scritture dirette sulle revisioni Live bloccate.

## [0.59.3] - 2026-07-31

### Aggiunto
- Motore protetto delle sostituzioni con ordine panchina e limite regolamentare.
- Registri `lineup_resolution_runs` e `lineup_substitution_events`.
- Gestione deterministica di assenti, senza voto, ruoli e modulo.

### Sicurezza
- Certificazione idempotente della risoluzione della formazione.
- Blocco delle doppie elaborazioni e storico delle revisioni.
- Risultati e Live instradati sul motore protetto.

## [0.59.2] - 2026-07-30

### Aggiunto
- Certificazione atomica della scadenza per ogni squadra e giornata.
- Registro `lineup_deadline_events` con esito consegnata, recuperata o mancante.
- Chiusura idempotente dell’intera giornata con revisione, riepilogo e impronta verificabile.
- Workspace formazione v3 e diagnostica `get_league_lineup_integrity_v2`.

### Sicurezza
- Titolari, panchina e ordine delle riserve diventano immutabili dopo il primo calcio d’inizio.
- Le vecchie funzioni interne di blocco e continuità passano ora dal percorso protetto.
- Un dispositivo o processo ripetuto non può congelare due volte la stessa distinta.

### Interfaccia
- La schermata Formazione mostra lo stato “Scadenza protetta” e la certificazione del blocco.
- Realtime esteso agli eventi di chiusura delle distinte.

## [0.59.1] - 2026-07-30

### Aggiunto
- Consegna formazione atomica con revisione progressiva per evitare sovrascritture tra dispositivi.
- Chiave idempotente per impedire doppie consegne causate da tap ripetuti o ritentativi di rete.
- Impronta della distinta su modulo, titolari e ordine della panchina.
- Registro di audit delle consegne e diagnostica dell'integrità delle formazioni.
- Nuovo workspace formazione v2 con stato del lock, revisione e protezione delle scritture.

### Sicurezza
- Bloccate le scritture dirette del client su `lineups` e `lineup_entries`.
- La consegna passa esclusivamente dalla RPC protetta `save_team_lineup_guarded_v1`.

### Interfaccia
- La schermata Formazione mostra lo stato “Consegna protetta” e la revisione corrente.
- Il pulsante di consegna viene bloccato quando la scadenza è già trascorsa.

## v0.59.0

- Chiuso lo Sviluppo 4 dedicato a completamento rose, calendario e avvio competizione.
- Il calendario ufficiale riceve un’impronta strutturale certificata al fischio d’inizio.
- Dopo l’avvio non è più possibile aggiungere, rimuovere o spostare partite e avversari; i risultati restano aggiornabili.
- Protetti anche formato, numero squadre, dimensione rose e metadati del sorteggio.
- Introdotte diagnostica unificata del ciclo competizione e gestione stato `get_league_management_state_v10`.
- L’avvio passa dalla nuova RPC idempotente `start_league_competition_guarded_v3`.
- Aggiunto `database/074_competition_model_closure.sql`.

## v0.58.3
- Attivazione della competizione certificata e idempotente.
- Inizializzazione atomica della prima giornata e revisione di avvio.
- Registro eventi di competizione consultabile dai partecipanti.
- Protezione delle colonne di avvio da modifiche dirette.
- Diagnostica dell'apertura nella Direzione Lega.

# Changelog

## 0.58.2

- Congelato l’assetto pre-campionato dopo il sorteggio: rose, crediti, partecipanti, scambi e Asta Live non possono più cambiare fino all’annullamento del calendario o all’avvio.
- Le modifiche di ruolo Presidente/Admin/Mister non invalidano più l’impronta sportiva del calendario.
- Aggiunti nove guard database sulle tabelle strutturali e di mercato.
- Introdotti `get_league_competition_readiness_v2`, `get_league_calendar_state_v3` e `get_league_management_state_v8`.
- Il calendario viene ora generato tramite `generate_head_to_head_calendar_guarded_v2`, che registra il congelamento della fotografia iniziale.
- L’avvio passa da `start_league_competition_guarded`: ricontrolla calendario, rose, crediti, trattative, Asta e impronta prima del fischio d’inizio.
- Bloccate le vecchie RPC di sorteggio e avvio non protette.
- Calendario e Direzione Lega mostrano lo stato dell’assetto iniziale congelato.
- Aggiunto `database/072_precompetition_snapshot_and_guarded_start.sql`.

## 0.58.1

- Avviato lo Sviluppo 4 con un preflight unico per il sorteggio del calendario.
- Il calendario richiede ora partecipanti, squadre e rose complete, Mercato integro, trattative chiuse e Asta Live conclusa.
- Aggiunta un’impronta deterministica di partecipanti, crediti e rose, salvata al momento del sorteggio.
- Il nuovo generatore protetto verifica numero di giornate, numero di partite, unicità degli accoppiamenti e una sola partita per squadra in ogni giornata.
- In caso di verifica fallita l’intero sorteggio viene annullato automaticamente dalla transazione.
- Aggiunti `get_league_competition_readiness_v1`, `get_league_calendar_state_v2` e `generate_head_to_head_calendar_guarded`.
- La schermata Calendario mostra anche lo stato di Mercato, trattative e Asta pre-campionato.
- Aggiunto `database/071_competition_readiness_and_guarded_calendar.sql`.

## 0.58.0

- Chiusura dello Sviluppo 3: modello Mercato, Scambi e Asta Live consolidato.
- Rimosse le scritture dirette del client sulle tabelle operative sensibili.
- Acquisti, svincoli, scambi, rilanci e assegnazioni passano esclusivamente da RPC protette.
- Aggiunta diagnostica unificata `get_league_market_integrity_v4`.
- Aggiunto indicatore “Operazioni protette” nella schermata Mercato.

## v0.57.4

- Coordinati Mercato libero e Asta Live sullo stesso calciatore.
- Un calciatore sul banco d’asta non può più essere acquistato contemporaneamente dal Mercato.
- Il Mercato esclude in tempo reale i calciatori con lotto attivo e mantiene un controllo server-side anche in caso di schermate non aggiornate.
- Aggiunta la diagnostica `get_league_market_integrity_v3`, che verifica conflitti tra rosa e asta e la corrispondenza tra lotti venduti e movimenti crediti.
- Aggiunto `database/069_market_auction_coordination.sql`.

## v0.57.3

- Rafforzata l’Asta Live con una sola stanza aperta per lega e un solo lotto attivo per stanza.
- Nomina, configurazione, pausa, ripresa, annullamento, rilanci e assegnazione ora condividono blocchi transazionali coerenti per evitare conflitti tra dispositivi.
- I rilanci vengono serializzati lato Supabase, registrano una revisione progressiva e rispettano i crediti già promessi negli scambi pendenti.
- L’assegnazione del lotto è idempotente e ricontrolla disponibilità del calciatore, quote di reparto, capienza rosa, crediti residui e riserva necessaria per completare la squadra.
- Aggiunta la diagnostica `get_league_auction_integrity_v1` con indicatore “Asta protetta” nell’app.
- Aggiunto `database/068_live_auction_safety.sql`.

## v0.57.2

- Aggiunte prenotazioni database per i calciatori offerti e i crediti promessi nelle trattative pendenti.
- Lo stesso calciatore non può più essere impegnato in più proposte in uscita contemporaneamente.
- Le offerte non possono superare i crediti realmente disponibili o rendere impossibile il completamento della rosa.
- Il risultato dello scambio viene validato in anticipo anche per dimensione rosa e quote di reparto.
- Creazione, risposta, annullamento e svincolo sono serializzati per lega per evitare conflitti e deadlock tra dispositivi.
- Corretto il trigger degli svincoli, che ora non annulla la trattativa mentre la stessa viene accettata.
- Aggiunta diagnostica `get_league_market_integrity_v2` e indicatore “Scambi protetti” nel Mercato.

## v0.57.1

- Avviato lo Sviluppo 3 dedicato a integrità di rose, crediti, mercato, scambi e asta live.
- Aggiunto `database/066_market_roster_integrity.sql` con protezioni su crediti non negativi, coerenza lega/squadra e limite generale della rosa.
- Gli acquisti dal mercato libero conservano ora i crediti minimi necessari per completare tutti i posti ancora vuoti.
- Le proposte di scambio pendenti vengono annullate automaticamente quando uno dei calciatori coinvolti lascia la rosa.
- Aggiunta diagnostica `get_league_market_integrity_v1` per confrontare crediti reali e registro movimenti, rose, riserve minime e trattative pendenti.
- Il Mercato mostra un avviso soltanto quando Supabase rileva una reale anomalia; la diagnostica non blocca il caricamento se non è disponibile.

## v0.57.0

- Chiuso lo Sviluppo 2 dedicato a ruoli e permessi multi-account.
- Bloccate le RPC interne non protette per nomina Admin, trasferimento presidenza e rimozione partecipanti.
- Tutte le azioni sensibili passano ora dalle funzioni con revisione e protezione multi-dispositivo.
- Aggiunta la matrice accessi Presidente/Admin/Mister nella Direzione Lega.
- Aggiunta diagnostica database su gerarchia, permessi e azioni protette.
- La Direzione Lega usa il nuovo stato `get_league_management_state_v7`, con fallback compatibile alla v6.

## v0.56.4

- Aggiunta protezione di concorrenza alle azioni su ruoli, presidenza e rimozione partecipanti.
- Ogni comando sensibile verifica la revisione permessi visualizzata dal dispositivo.
- Le decisioni obsolete vengono bloccate quando un altro dispositivo ha già modificato la direzione della lega.
- Migliorati i messaggi di aggiornamento richiesto e la diagnostica multi-account.

## v0.56.3

- Aggiunto `database/063_role_session_sync.sql` per sincronizzare revoche, nomine Admin e trasferimenti di presidenza tra dispositivi già aperti.
- Introdotta una revisione incrementale dei ruoli della lega e il timestamp dell’ultima variazione del singolo partecipante.
- La Direzione Lega verifica prima lo stato di accesso corrente: un Admin revocato perde immediatamente l’area riservata, mentre un partecipante rimosso viene riportato alle leghe.
- Aggiunti listener Realtime dedicati a partecipanti e audit dei ruoli, con protezione degli eventi DELETE tramite replica identity completa.
- La scheda permessi mostra la revisione sincronizzata, utile nei test multi-account.
- Nessuna modifica a rose, crediti, calendario o risultati.

## [0.56.2] - 2026-07-30

### Aggiunto
- Diagnostica server-side dell’integrità dei ruoli: Presidente attivo, manager iscritti e una sola squadra per Mister.
- Registro leggibile delle ultime nomine Admin, revoche e trasferimenti di presidenza.
- Protezioni database contro la cancellazione accidentale del Presidente e l’assegnazione della presidenza a utenti esterni alla lega.
- Nuova scheda “Integrità ruoli” nella Direzione Lega.

## v0.56.1

- Aggiunta matrice esplicita dei permessi Presidente, Admin e Mister.
- Aggiunto riepilogo ruolo nella Direzione lega.
- Bloccate le modifiche dirette a leghe, partecipanti e squadre: le azioni sensibili passano ora da RPC atomiche.
- Solo il Presidente può nominare/revocare Admin e trasferire la presidenza.
- Aggiunto audit delle modifiche di ruolo e notifiche dedicate.

## v0.56.0

- Completato lo Sviluppo 1 dell’onboarding leghe.
- Aggiunta l’anteprima sicura della lega prima dell’ingresso tramite codice invito.
- L’anteprima mostra nome lega, sistema ruoli, squadre presenti, posti disponibili, crediti iniziali e dimensione rosa.
- Gli inviti chiusi, le leghe complete, le competizioni già avviate e le iscrizioni duplicate vengono bloccati prima della creazione della squadra.
- Aggiunto `database/060_invite_preview.sql` con RPC autenticata `preview_league_invite`.
- L’ingresso in lega ora conta le squadre reali, gestisce in sicurezza eventuali iscrizioni incomplete e mantiene la protezione contro accessi simultanei.
- Confermate le aperture delle rose pubbliche da Partecipanti e Classifica introdotte nella fase precedente.
- Versione di avanzamento: 55% del percorso verso la pubblicazione.

## v0.55.18

- Aggiunto `database/059_onboarding_hardening.sql` per irrobustire creazione e ingresso nelle leghe.
- Nomi lega e squadra normalizzati e validati anche lato Supabase.
- I nomi squadra sono ora univoci nella stessa lega ignorando maiuscole, minuscole e spazi esterni.
- Bloccate iscrizioni duplicate dello stesso utente e gestiti gli accessi simultanei senza creare doppie squadre.
- Il codice invito viene normalizzato e validato a 10 caratteri alfanumerici.
- Il modulo Nuova lega elimina automaticamente caratteri non validi dal codice, limita le lunghezze e cancella il messaggio di errore appena l’utente corregge un campo.

## v0.55.17

- Aggiunta la schermata pubblica della rosa per consultare le squadre avversarie all’interno della stessa lega.
- Le righe nella sezione `Partecipanti` ora aprono la rosa della squadra; la propria squadra continua ad aprire la rosa personale.
- Anche le righe della classifica, sia nell’anteprima della lega sia nella classifica completa, sono ora selezionabili.
- La rosa pubblica mostra composizione per reparto, spesa totale, media acquisti e percentuale di completamento.
- Gestito esplicitamente lo stato di rosa avversaria vuota, senza pulsanti fuorvianti.
- Dalla rosa pubblica è possibile aprire la scheda del singolo calciatore e tornare alla schermata corretta.
- Nessuna migrazione Supabase: vengono usate le policy esistenti che consentono ai membri della lega di leggere le rose.
- Aggiunto `database/058_development_pippolandia_roster.sql`, seed opzionale e protetto che completa soltanto la rosa vuota di Pippolandia con 3 P, 8 D, 8 C e 6 A.

## v0.55.16

- Aggiunto `database/057_development_player_pool.sql`.
- Creato un parco dati idempotente di 150 calciatori fittizi: 18 portieri, 48 difensori, 48 centrocampisti e 36 attaccanti.
- Aggiunti ruoli Classico e Mantra per tutti i calciatori del nuovo dataset.
- Inserita la correzione mirata del nome lega `Seria A da Divano` in `Serie A da Divano`.
- Nessuna modifica alle rose, agli utenti, alle squadre o agli acquisti esistenti.

# Changelog LEGHEVO Mobile

Tutte le modifiche rilevanti dell'app mobile vengono registrate in questo file.

## [Non rilasciato]


## [0.62.4] - 2026-08-01

### Aggiunto
- Ciclo protetto degli incidenti operativi del provider dati.
- Apertura automatica dopo sync falliti o anomalie di qualità e chiusura automatica dopo il ripristino.
- Registri revisionati `provider_operational_incidents` e `provider_operational_incident_events`.
- Nuove RPC `get_league_provider_incident_center_v1` e `get_league_provider_sync_health_v3`.
- Centro Operativo aggiornato con incidenti attivi, critici e risolti nelle ultime 24 ore.
- Migrazione `108_provider_operational_incident_safety.sql` con diagnostica finale di 20 controlli.


## [0.62.3] - 2026-08-01

### Aggiunto
- Certificazione della freschezza e della copertura dei dati API-Football.
- Registro immutabile `provider_data_quality_snapshots`, alimentato dopo ogni sincronizzazione completata.
- Controlli su partite non collegate, risultati incompleti, voti fuori intervallo e dati live non aggiornati.
- Nuove RPC `get_league_provider_data_quality_v1` e `get_league_provider_sync_health_v2`.
- Centro Operativo aggiornato con anomalie e copertura dei dati ufficiali.
- Migrazione `107_provider_data_freshness_and_coverage_safety.sql` con diagnostica finale di 20 controlli.


## [0.61.9] - 2026-07-31

### Aggiunto
- Centro unificato dei servizi account con stato revisionato e registro eventi immutabile.
- Collegamento automatico di privacy, assistenza, push, notifiche, profilo, credenziali, documenti legali ed esportazioni.
- Nuova RPC `get_my_account_center_v4` e indicatore mobile dei servizi protetti.
- Migrazione `103_account_services_integrity_hub.sql` con diagnostica finale di 20 controlli.



### Da rifinire
- Uniformare nella scheda calciatore libero le diciture `Svincolato` e `SVINCOLATO` in `LIBERO`.
- Aggiungere messaggi espliciti nel modulo Scambi quando la propria rosa o quella della squadra destinataria è vuota.

### Da collaudare
- Ciclo completo degli scambi con due squadre dotate di almeno un calciatore: invio, ricezione, accettazione, rifiuto e annullamento.
- Funzioni avanzate di Asta, Direzione lega, Coppa, Playoff, Supercoppa, rinvii, notifiche push e assistenza.

## [0.55.15] - 2026-07-30

### Corretto
- Risultati e classifica: il pulsante di aggiornamento ora mostra un indicatore di caricamento mentre rilegge risultati, giornate e classifica.
- Il comando viene temporaneamente disabilitato durante l’aggiornamento, evitando pressioni ripetute senza feedback.
- Nessuna modifica a Supabase o ai dati della lega.

## [0.55.14] - 2026-07-30

### Corretto
- Asta Live: il primo rilancio ora aumenta davvero l’offerta corrente dell’importo indicato sul pulsante.
- Con rilancio minimo impostato a 2 crediti, il pulsante `+2` porta correttamente la base d’asta da 1 a 3 crediti; i rilanci successivi continuano ad aumentare di 2.
- Nessuna modifica a Supabase o ai dati della lega.

## [0.55.13] - 2026-07-30

### Corretto
- Centro Operativo: il pulsante di aggiornamento ora mostra un indicatore di caricamento mentre rilegge consegne, voti e priorità.
- Il comando viene temporaneamente disabilitato durante l’aggiornamento, evitando pressioni ripetute senza feedback.

## [0.55.12] - 2026-07-30

### Corretto
- Storia e albo della Lega: il pulsante di aggiornamento ora mostra un indicatore di caricamento mentre rilegge stagioni, record e trofei.
- Il comando viene temporaneamente disabilitato durante l’aggiornamento, evitando pressioni ripetute senza feedback.

## [0.55.11] - 2026-07-30

### Corretto
- Regolamento: risolto l’errore `record "v_league" has no field "season"` causato dalla diversa denominazione del campo stagione nel database reale.
- L’app usa un caricamento compatibile diretto quando incontra la vecchia funzione Supabase difettosa, senza richiedere migrazioni e mantenendo impostazioni, revisioni e permessi del Presidente.
- Corretto anche lo script 056 per le future installazioni pulite, usando `calendar_season`.

## [0.55.10] - 2026-07-30

### Corretto
- Rinvii e sospensioni: il pulsante di aggiornamento ora mostra un indicatore di caricamento mentre rilegge le segnalazioni.
- Il comando viene temporaneamente disabilitato durante l’aggiornamento, evitando pressioni ripetute senza feedback.

## [0.55.9] - 2026-07-30

### Corretto
- Supercoppa: il pulsante di aggiornamento ora mostra un indicatore di caricamento mentre rilegge la competizione.
- Il comando viene temporaneamente disabilitato durante l’aggiornamento, evitando pressioni ripetute senza feedback.

## [0.55.8] - 2026-07-30

### Corretto
- Playoff Scudetto: il pulsante di aggiornamento ora mostra un indicatore di caricamento mentre rilegge la fase finale.
- Il comando viene temporaneamente disabilitato durante l’aggiornamento, evitando pressioni ripetute senza feedback.

## [0.55.7] - 2026-07-30

### Corretto
- Coppa di Lega: il pulsante di aggiornamento ora mostra un indicatore di caricamento mentre rilegge il tabellone.
- Il comando viene temporaneamente disabilitato durante l’aggiornamento, evitando pressioni ripetute senza feedback.

## [0.55.6] - 2026-07-29

### Corretto
- Centro Sfida: il pulsante di aggiornamento ora mostra un indicatore di caricamento mentre rilegge i dati.
- Il comando viene temporaneamente disabilitato durante l’aggiornamento, evitando pressioni ripetute senza feedback.

## [0.55.5] - 2026-07-29

### Corretto
- Scambi: ora è possibile inviare una proposta con un calciatore su un solo lato e una contropartita in crediti, come già previsto dal database.
- La validazione richiede la squadra destinataria e almeno un calciatore complessivo, senza obbligare entrambe le squadre ad avere una rosa.

## [0.55.4] - 2026-07-29

### Corretto
- Mercato: il tap su avatar, nome o informazioni apre la scheda completa del calciatore.
- Il pulsante crediti resta separato e continua ad acquistare direttamente il calciatore.
- Il ritorno dalla scheda calciatore riporta correttamente al Mercato.

## [0.55.3] - 2026-07-29

### Corretto
- Live: eliminato il crash causato dal conflitto tra i listener Supabase Realtime della Home e della schermata Live.
- Ogni istanza Realtime utilizza ora un canale indipendente.

## [0.55.2] - 2026-07-29

### Corretto
- Formazione automatica: l'avviso compare immediatamente quando la rosa contiene meno di 11 calciatori.

## [0.55.1] - 2026-07-29

### Corretto
- Rosa: il tap su Luca Conti apre correttamente la scheda del calciatore.
- La freccia indietro dalla scheda riporta alla Rosa.
