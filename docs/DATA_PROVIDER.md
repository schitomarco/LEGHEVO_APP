# Provider dati di LEGHEVO

## Scelta iniziale

Per la beta utilizziamo **API-Football** tramite API-Sports.

Motivi principali:

- Serie A e principali competizioni incluse;
- rose, calendari, formazioni, eventi e statistiche nello stesso servizio;
- rating automatico 0–10 per ogni calciatore;
- aggiornamento delle statistiche dei giocatori durante le partite;
- piano gratuito utilizzabile per verificare la connessione e lavorare con i
  dati demo;
- piano Pro sufficiente per la prima beta;
- connettore isolato dal resto dell’app, quindi sostituibile in futuro.

## Sicurezza

La chiave `API_FOOTBALL_KEY` viene usata soltanto dalla Edge Function
`sync-football-data`. Non deve mai essere inserita nelle variabili
`EXPO_PUBLIC_*`, perché quelle vengono incorporate nell’app installata.

## Flussi automatici

| Flusso | Frequenza | Risultato |
|---|---:|---|
| Rose Serie A | ogni notte | anagrafica e ruoli aggiornati |
| Calendario odierno | ogni 5 minuti | orari, stati e risultati reali |
| Rating live | ogni minuto durante le gare | voto, bonus, malus e fantavoto |
| Chiusura gara | automatica dopo FT | voto marcato come definitivo |

Le partite sincronizzate aggiornano anche la giornata fantasy: il primo calcio
d'inizio diventa la scadenza delle formazioni, mentre l'ultima gara del turno
determina la fine della giornata. Finché il calendario reale non è disponibile,
LEGHEVO conserva date stimate e le sostituisce automaticamente appena arrivano
i dati del provider.

Alla scadenza LEGHEVO blocca le distinte consegnate e recupera, per chi non ha
consegnato, l'ultima formazione ancora compatibile con la rosa. Se non esiste
una distinta precedente, la squadra viene calcolata a zero al termine del
turno. La giornata può chiudersi anche con meno di undici voti: l'assenza del
voto diventa definitiva soltanto quando tutte le partite reali risultano
concluse.

I cron non vengono attivati nel piano gratuito. Il file
`database/004_automatic_provider_sync.sql` richiede infatti il segreto Vault
`leghevo_provider_plan=pro`.

## Limiti del piano gratuito

API-Football limita sia le stagioni sia l'intervallo di date interrogabile.
Questi limiti possono rendere impossibile ottenere partite reali di Serie A
durante lo sviluppo, anche restando entro le 100 richieste giornaliere.

Per questo LEGHEVO include `database/005_development_demo_data.sql`: lo script
carica undici calciatori fittizi, ruoli Classic e Mantra, una partita demo e i
relativi fantavoti. La schermata Live usa questi record quando sono presenti e
ripiega sui dati locali se il database non è raggiungibile.

## Rating e fantavoto standard

Il rating 0–10 del provider viene salvato senza modifiche. Il fantavoto
standard aggiunge o sottrae:

- gol: +3;
- assist: +1;
- rigore parato: +3;
- ammonizione: −0,5;
- espulsione: −1;
- rigore sbagliato: −3;
- gol subito dal portiere: −1.

Il dato grezzo del provider viene sempre conservato. Questo permette di
ricalcolare i risultati quando una lega usa regole diverse.

## Attivazione

1. Registrare un account API-Football e copiare la chiave.
2. Collegare il progetto Supabase.
3. Impostare i segreti della funzione:

   ```bash
   supabase secrets set --env-file supabase/.env
   ```

4. Distribuire la funzione:

   ```bash
   supabase functions deploy sync-football-data --no-verify-jwt
   ```

5. Creare una secret API key Supabase chiamata `automations`.
6. Salvare in Supabase Vault `leghevo_project_url` e
   `leghevo_automations_key`.
7. Durante lo sviluppo eseguire `database/005_development_demo_data.sql`.
8. Quando si passa al piano Pro, aggiungere nel Vault
   `leghevo_provider_plan=pro`.
9. Eseguire `database/004_automatic_provider_sync.sql`.

Il piano a pagamento non serve per sviluppare interfaccia, autenticazione,
leghe, asta e risultati demo.

## Protezione delle sincronizzazioni · v0.62.2

La migrazione `database/106_provider_sync_safety.sql` aggiunge un registro
revisionato e idempotente alle sincronizzazioni API-Football. Ogni richiesta
viene normalizzata e associata a una finestra temporale coerente con la sua
frequenza: un minuto per i rating live, cinque minuti per il calendario e un
giorno per le rose stagionali.

La Edge Function usa le RPC server-side
`start_provider_sync_run_guarded_v1` e
`finish_provider_sync_run_guarded_v1`. Una richiesta già completata nella
stessa finestra viene riutilizzata; una richiesta ancora in corso non viene
eseguita una seconda volta. Gli eventi Realtime non contengono payload,
chiavi, token o messaggi di errore del provider.

Il codice aggiornato della Edge Function è incluso nello ZIP. La distribuzione
della funzione e l'attivazione dei cron restano operazioni dell'ambiente di
rilascio e non sono richieste per eseguire la migrazione SQL.

## Freschezza e copertura dei dati · v0.62.3

La migrazione `database/107_provider_data_freshness_and_coverage_safety.sql`
registra una fotografia immutabile della qualità dopo ogni sincronizzazione
completata. Il controllo non conserva chiavi o payload aggiuntivi: usa soltanto
conteggi, timestamp e impronte tecniche.

Il Centro Operativo segnala:

- partite provider non collegate a una giornata;
- gare definitive prive del risultato o dei voti definitivi;
- rating e fantavoti fuori dagli intervalli ammessi;
- differenze tra i contatori della giornata e le partite realmente importate;
- calendario non aggiornato durante una giornata aperta;
- rating live fermi per più di tre minuti durante una gara.

Le RPC `get_league_provider_data_quality_v1` e
`get_league_provider_sync_health_v2` sono riservate alla Direzione della lega.
Il registro `provider_data_quality_snapshots` è leggibile dagli utenti
autenticati e pubblicato in Realtime, ma non può essere modificato dal client.

## Watchdog dei recuperi · v0.62.6

La migrazione `database/110_provider_recovery_watchdog_safety.sql` impedisce
che una richiesta di recupero rimanga indefinitamente nello stato `running`
quando il worker si interrompe prima di certificare l'esito.

Il watchdog usa finestre diverse in base al lavoro:

- 15 minuti per i voti di una singola partita;
- 20 minuti per il calendario;
- 60 minuti per le rose stagionali.

Quando il tempo massimo viene superato, il run viene chiuso attraverso la RPC
protetta del provider e l'incidente torna disponibile per una nuova richiesta.
L'intervento è registrato in `provider_recovery_watchdog_events`, senza payload,
chiavi o token. La Edge Function inclusa nello ZIP richiama le RPC v2 prima di
prendere in carico la coda; il deploy del worker resta un'operazione della fase
finale di configurazione dell'ambiente.

## Heartbeat del worker provider · v0.62.7

La migrazione `database/111_provider_worker_heartbeat_and_progress_safety.sql`
aggiunge un heartbeat revisionato ai run API-Football. Il worker aggiorna il
registro dopo ogni pagina delle rose stagionali, gruppo di calendario o squadra
della partita elaborata. Il watchdog può così distinguere un processo ancora
attivo da un'esecuzione realmente interrotta.

Ogni revisione conserva soltanto dati operativi: fase, avanzamento, totale
previsto, numero di record elaborati e timestamp. Non vengono registrati token,
chiavi API o payload del provider. Le RPC
`get_league_provider_recovery_center_v3` e
`get_league_provider_sync_health_v6` espongono alla Direzione il progresso
corrente. Il deploy della Edge Function aggiornata resta previsto nella fase
finale di configurazione dell'ambiente.



## Retry automatico e backoff · v0.62.8

La migrazione `database/112_provider_recovery_retry_backoff_safety.sql`
classifica i fallimenti dei recuperi provider e pianifica fino a tre nuovi
tentativi con attese crescenti. Errori di configurazione o richieste non valide
non vengono ripetuti automaticamente; rate limit, timeout, problemi di rete e
indisponibilità temporanee del provider seguono finestre dedicate.

Le decisioni sono salvate in `provider_recovery_retry_schedules` e nello
storico immutabile `provider_recovery_retry_events`. La Edge Function prova
prima i retry maturati tramite `claim_next_provider_recovery_request_v3` e poi
la coda manuale. Il Centro Operativo espone tentativi programmati, esauriti e
prossimo orario utile senza mostrare payload, chiavi o messaggi tecnici completi.
Il deploy del worker resta previsto nella fase finale di configurazione.


## Circuit breaker dei recuperi · v0.62.9

La migrazione `database/113_provider_recovery_circuit_breaker_safety.sql`
chiude il vuoto operativo successivo all’esaurimento dei retry automatici.
Quando una pianificazione termina come `exhausted`, viene aperto un circuit
breaker per la coppia lega/incidente. Da quel momento il database respinge
nuove richieste manuali, evitando catene potenzialmente illimitate di altri tre
tentativi.

Presidente e Admin possono rilasciare il blocco dal Centro Operativo. Il
rilascio usa revisione ottimistica e chiave di idempotenza; non accoda da solo
un nuovo recupero, ma riabilita in modo esplicito la richiesta ordinaria. Se
l’incidente viene risolto dal provider mentre il blocco è aperto, il circuit
breaker viene chiuso automaticamente come risolto.

Lo stato è esposto tramite `get_league_provider_sync_health_v8`. Gli eventi di
apertura, rilascio e risoluzione sono immutabili e pubblicati in Realtime senza
motivazioni o payload del provider.


## Verifica dell'efficacia dei recuperi · v0.62.10

La migrazione `database/114_provider_recovery_outcome_verification_safety.sql`
chiude la differenza tra un run tecnicamente completato e un recupero realmente
efficace. Dopo ogni evento provider `completed`, LEGHEVO controlla l'incidente
collegato e l'eventuale fotografia qualità prodotta dallo stesso run.

Se l'incidente risulta risolto, viene creato un certificato `verified`. Se
l'incidente resta aperto, il tentativo non viene considerato sufficiente: il
sistema continua automaticamente la catena di retry e backoff dalla posizione
corretta. Al superamento del limite viene aperto il circuit breaker già
validato nella v0.62.9. Le richieste storiche già superate da una richiesta,
una pianificazione o un blocco successivo vengono marcate `superseded`, senza
creare una seconda catena. Finché un retry di verifica è attivo, il database
respinge nuove richieste manuali per lo stesso incidente.

I certificati sono conservati in
`provider_recovery_outcome_certificates`, sono immutabili e non contengono
payload `requested_for`, chiavi API o token. Il Centro Operativo legge lo stato
tramite `get_league_provider_sync_health_v9` e mostra recuperi verificati,
tentativi di efficacia ancora attivi ed eventuali esaurimenti.


## Lease e fencing del worker provider · v0.62.11

La migrazione `database/115_provider_worker_lease_fencing_safety.sql` impedisce
a un processo provider decaduto di continuare a modificare i dati dopo che il
watchdog ha già considerato fallito il relativo run. Ogni esecuzione acquisisce
una lease esclusiva, identificata da un token non riutilizzabile e da un'epoca
progressiva. Il token deve essere rinnovato durante gli heartbeat. La RPC
`apply_provider_sync_write_guarded_v1` mantiene il lock della lease e completa
la scrittura sportiva nella stessa transazione, eliminando la finestra tra
controllo e upsert. Anche la chiusura finale richiede il token corrente.

Se la lease scade, viene revocata o viene sostituita, il worker precedente non
può più aggiornare atleti, ruoli, calendario, risultati o voti, anche se il suo
processo è ancora materialmente in esecuzione. La scadenza chiude il run tramite
il percorso certificato già presente, lasciando proseguire watchdog, retry,
backoff, verifica di efficacia e circuit breaker senza creare flussi paralleli.

Lo storico `provider_sync_worker_lease_events` è immutabile e conserva soltanto
metadati operativi: non registra il token della lease, payload del provider,
chiavi API o credenziali. La Edge Function inclusa nello ZIP usa le nuove RPC
v2/v3/v4 per acquisizione, heartbeat, asserzione e conclusione; il deploy
definitivo rimane previsto nella fase finale di configurazione dell'ambiente.
Il Centro Operativo legge lo stato tramite
`get_league_provider_sync_health_v10` e mostra le lease attive, scadute o
revocate.

## Contratti runtime e quarantena dei payload provider · v0.62.12

La migrazione `database/116_provider_payload_contract_quarantine_safety.sql`
chiude il passaggio rimasto scoperto tra la risposta esterna di API-Football e
le scritture già protette dal fencing. I tipi TypeScript non sono più l'unica
garanzia: l'envelope e i campi realmente utilizzati da rose, calendario e voti
vengono verificati a runtime prima della trasformazione.

La stessa regola viene applicata una seconda volta nel database dalla RPC
`apply_provider_sync_write_guarded_v2`. Il controllo della lease, la validazione
del payload e l'upsert restano nella stessa transazione. Un worker alternativo o
non aggiornato non può quindi aggirare il contratto affidandosi direttamente
alla RPC di scrittura.

Quando il provider cambia schema o restituisce dati strutturalmente incompleti,
il run viene fermato con un errore `Payload provider non valido`. Prima della
chiusura viene creato un record immutabile in
`provider_payload_contract_violations`. Il registro non conserva mai il payload
grezzo, chiavi, token o credenziali: contiene solo versione del contratto,
ambito, codice sintetico, eventuale indice, dimensione e impronta SHA-256. La
policy retry già presente classifica questo errore come richiesta non
recuperabile, evitando catene automatiche inutili.

Il Centro Operativo legge `get_league_provider_sync_health_v11` e mostra lo
stato delle validazioni runtime/database e le quarantene delle ultime 24 ore.
Il deploy definitivo della Edge Function rimane previsto nella fase finale di
configurazione dell'ambiente.

## Completezza e coerenza delle consegne provider · v0.62.13

La migrazione `database/117_provider_delivery_completeness_safety.sql` chiude il passaggio tra la validazione strutturale del payload e la chiusura positiva del run. Oltre alla forma dei dati, LEGHEVO verifica che il numero `results` coincida con gli elementi realmente ricevuti, che la pagina dichiarata sia quella richiesta, che il totale pagine resti stabile e che la stessa entità non venga consegnata due volte nello stesso run.

Ogni pagina o risposta viene registrata tramite `record_provider_sync_delivery_unit_v1` mentre la lease del worker è ancora attiva. Il database conserva conteggi, ordine delle unità e sole impronte SHA-256 delle identità tecniche; non salva identificativi grezzi, payload, token o chiavi. Le tabelle di dettaglio sono server-side e immutabili.

La RPC `finish_provider_sync_run_guarded_v3` costituisce il completion gate: prima di accettare `completed` controlla che tutte le unità attese siano presenti, consecutive e coerenti con `records_processed`. Una consegna incompleta viene respinta con un errore provider recuperabile, così retry, backoff, verifica di efficacia e circuit breaker continuano a operare senza percorsi paralleli.

Il Centro Operativo legge `get_league_provider_sync_health_v12` e mostra consegne certificate, respinte e ancora in acquisizione. Il deploy definitivo della Edge Function resta previsto nella fase finale di configurazione dell'ambiente.

## Staging isolato e pubblicazione atomica · v0.62.14

La migrazione `database/118_provider_atomic_publication_safety.sql` chiude il
vuoto rimasto dopo la certificazione della consegna. Nelle versioni precedenti
le pagine già elaborate potevano essere scritte nelle tabelle operative prima
di scoprire che una pagina successiva era mancante o incoerente. Il run veniva
respinto correttamente, ma le modifiche parziali potevano restare visibili.

Con la v0.62.14 la RPC `stage_provider_sync_write_guarded_v1` conserva le righe
normalizzate in cinque tabelle isolate per atleti, ruoli, giornate, partite e
voti. Queste tabelle hanno RLS attiva, non sono pubblicate in Realtime e non
sono leggibili dagli utenti autenticati. Lease, fencing e contratto runtime
continuano a essere verificati prima di ogni operazione.

La RPC `finish_provider_sync_run_guarded_v4` acquisisce un lock di pubblicazione,
certifica tutte le unità tramite il completion gate v0.62.13 e applica i dati
alle tabelle operative in una sola transazione. Se qualunque verifica o upsert
fallisce, PostgreSQL annulla l'intero commit. Quando il run termina come
`failed`, lo staging viene scartato senza modificare i dati live. Dopo un esito
finale, le righe temporanee vengono eliminate e rimane soltanto il manifest
sintetico `provider_sync_publications` con conteggi, stato e storico immutabile.

Il Centro Operativo legge `get_league_provider_sync_health_v13` e mostra
pubblicazioni completate, scartate e ancora in staging. Il deploy definitivo
della Edge Function resta previsto nella fase finale di configurazione
dell'ambiente.


## Scope semantico e write-set provider · v0.62.15

La migrazione `database/119_provider_semantic_scope_safety.sql` chiude il
vuoto rimasto tra lo staging atomico e il significato della richiesta. Prima
di questa versione il database validava forma, completezza e atomicità, ma non
impediva a un run di inserire nello staging una categoria di dati estranea al
proprio tipo oppure righe riferite a stagione, data o partita diverse da quelle
richieste.

I trigger di scope applicati alle cinque tabelle di staging legano ogni riga al
run e al manifest di pubblicazione. Le rose stagionali accettano solo atleti e
ruoli; il calendario accetta solo giornate e partite della stagione e della data
richieste; i voti accettano solo atleti, ruoli e punteggi della partita indicata,
con la stessa giornata già registrata nel calendario.

La RPC `finish_provider_sync_run_guarded_v5` crea un certificato semantico,
ricontrolla l'intero write-set e soltanto dopo richiama il commit atomico v4. Il
trigger sulla pubblicazione impedisce anche a un worker legacy di pubblicare
senza certificato. I registri `provider_sync_scope_certificates` e
`provider_sync_scope_events` conservano soltanto conteggi, stato e impronte di
scope; non contengono payload, token o credenziali.

Il Centro Operativo legge `get_league_provider_sync_health_v14` e mostra scope
certificati, respinti e ancora in verifica. Il deploy definitivo della Edge
Function resta previsto nella fase finale di configurazione dell'ambiente.

## Watermark monotono e protezione anti-regressione · v0.62.16

La migrazione `database/120_provider_monotonic_publication_watermark_safety.sql`
chiude il rischio rimasto dopo staging, certificazione e scope semantico. Due run
validi sullo stesso ambito possono terminare in ordine diverso da quello in cui
sono iniziati: senza un vincolo temporale, il run più vecchio potrebbe applicare
per ultimo una fotografia ormai superata.

LEGHEVO mantiene ora un watermark per provider, tipo di sincronizzazione e
impronta dello scope. La decisione viene serializzata con un lock transazionale.
Se il run candidato è più recente, la pubblicazione atomica procede e il
watermark avanza. Se è stato iniziato prima del run già pubblicato, lo staging
viene eliminato senza toccare i dati live. La consegna e lo scope restano
certificati, mentre un evento immutabile `watermark.stale_run` documenta il
blocco della regressione.

La RPC `finish_provider_sync_run_guarded_v6` è il nuovo punto di chiusura. Le
versioni v5 e v4 vengono instradate server-side nella stessa protezione, così un
worker non aggiornato non può aggirare il watermark. Il Centro Operativo legge
`get_league_provider_sync_health_v15` e distingue gli scarti operativi dalle
pubblicazioni semplicemente superate. Registri ed eventi non contengono payload,
identificativi provider grezzi, token o chiavi.

## Riconciliazione autorevole del catalogo calciatori · v0.62.17

La migrazione `database/121_provider_player_catalog_reconciliation_safety.sql`
chiude il vuoto rimasto dopo il watermark per scope. Il catalogo `athletes` è
globale e non versionato per stagione: una sincronizzazione completa deve quindi
stabilire quale fotografia stagionale rappresenta il catalogo corrente, senza
permettere a una stagione storica di sostituirlo.

Per ogni run `sync-season-players`, LEGHEVO conserva prima del commit una
fotografia immutabile dei calciatori e dei ruoli classic/mantra. Se la stagione è
precedente al catalogo corrente, lo staging viene scartato e il run termina come
pubblicazione benignamente superata. Se la stagione è corrente o successiva, la
riconciliazione viene applicata nella stessa transazione della pubblicazione
atomica: i ruoli superati vengono sostituiti e i calciatori assenti vengono resi
inattivi.

La procedura non cancella fisicamente calciatori, rose o storico. Un calciatore
non più presente nel catalogo può quindi restare nella rosa che lo possiede,
mentre non compare più tra i disponibili per nuovi movimenti. Due guard
`ENABLE ALWAYS` mantengono questa decisione anche nei run successivi: un flusso
voti non può riattivare un assente né reinserire un ruolo diverso dalla
fotografia stagionale corrente. I registri
`provider_player_catalog_heads`, `provider_player_catalog_reconciliations`,
`provider_player_catalog_members` e `provider_player_catalog_events` non
contengono payload, token o chiavi.

La RPC `finish_provider_sync_run_guarded_v7` integra decisione stagionale,
certificazione dello scope, pubblicazione atomica e aggiornamento del watermark.
Il Centro Operativo legge `get_league_provider_sync_health_v16` e mostra
fotografia corrente, calciatori ritirati, ruoli corretti e stagioni storiche
bloccate. Il deploy definitivo della Edge Function resta previsto nella fase
finale di configurazione dell'ambiente.

## Fotografia autorevole dei voti partita · v0.62.18

La migrazione `database/122_provider_fixture_score_reconciliation_safety.sql`
lega ogni run `sync-fixture-players` a una fotografia immutabile dei voti
ricevuti per la partita richiesta. Il certificato conserva soltanto impronte
anonime dei calciatori e conteggi sintetici.

Per una partita conclusa la fotografia deve contenere almeno un calciatore per
entrambe le squadre. Dopo la prima fotografia finale, una consegna provvisoria
non può più sostituirla. I voti precedentemente presenti ma assenti dalla nuova
fotografia finale vengono ritirati logicamente: rating, fantavoto, bonus e
malus non incidono più sui risultati, mentre riga, statistiche grezze e payload
restano disponibili per audit. Nessun voto viene cancellato fisicamente.

La nuova RPC `finish_provider_sync_run_guarded_v8` prepara il certificato,
pubblica lo staging e riconcilia i voti nella stessa transazione già protetta
da lease, fencing, scope, completezza e watermark. Il Centro Operativo legge
`get_league_provider_sync_health_v17` e mostra lo stato `VOTI PARTITA
RICONCILIATI`.


## Ciclo di vita monotono delle partite provider · v0.62.19

La migrazione `database/123_provider_fixture_lifecycle_monotonic_safety.sql`
protegge la riga operativa della partita oltre alla fotografia dei voti. Prima
di questa versione una successiva sincronizzazione del calendario poteva
sovrascrivere una partita già conclusa con uno stato provvisorio, cancellare i
gol finali oppure cambiare squadre, giornata o data già consolidate.

Ogni run `sync-fixtures` crea ora una riconciliazione immutabile delle partite
ricevute. Gli stati grezzi API-Football vengono ricondotti a un ciclo semantico
`scheduled`, `live`, `interrupted`, `cancelled` o `final`. Il trigger
`provider_fixture_lifecycle_guard`, impostato `ENABLE ALWAYS`, richiede una
riconciliazione attiva per ogni scrittura e impedisce cancellazioni fisiche,
regressioni da finale a non finale, perdita dei gol finali e variazioni
retroattive delle squadre o della giornata.

Le correzioni finali legittime restano consentite e vengono tracciate con una
nuova generazione del relativo head. La RPC
`finish_provider_sync_run_guarded_v9` integra il certificato nel commit atomico
già protetto da lease, fencing, completezza, scope e watermark. Il Centro
Operativo legge `get_league_provider_sync_health_v18` e mostra lo stato
`CICLO PARTITE PROTETTO`. Registri ed eventi non espongono payload, token o
chiavi.

## Coerenza causale tra ciclo partita e fotografia voti · v0.62.20

La migrazione `database/124_provider_fixture_score_causal_coherence_safety.sql`
lega formalmente ogni fotografia dei voti alla generazione del ciclo partita
osservata quando il certificato viene creato. Prima di questa versione, la
partita e i voti disponevano di teste monotone indipendenti: una correzione del
calendario poteva quindi rendere obsoleta la fotografia voti senza che questa
perdesse lo stato di fotografia corrente.

Le riconciliazioni voti conservano ora la testa, la riconciliazione, la
revisione tecnica, la generazione causale e lo stato della partita osservati.
La revisione tecnica avanza a ogni fotografia calendario, mentre la generazione
causale resta stabile sulle semplici riletture `refreshed` e aumenta soltanto
per creazione, avanzamento o correzione finale. La testa dei voti viene
classificata `aligned`, `stale` o `missing`. Quando cambia la generazione
causale, un trigger `ENABLE ALWAYS` rivaluta automaticamente la coerenza e
registra un evento immutabile legato alla generazione causale corrente. Un guard
aggiuntivo rifiuta salti o regressioni della revisione tecnica. I voti, i bonus,
i malus e lo storico non vengono
cancellati o modificati: il Centro Operativo segnala che serve una nuova
fotografia coerente con la partita aggiornata.

La RPC `finish_provider_sync_run_guarded_v10` integra il certificato nel percorso
di chiusura già protetto da lease, fencing, completezza, scope, staging atomico,
watermark, riconciliazione catalogo, fotografia voti e ciclo partita. La v9
instrada server-side le chiamate legacy nella v10. Il Centro Operativo legge
`get_league_provider_sync_health_v19` e mostra conteggi allineati, superati e
partite finali prive di una fotografia coerente. Il registro
`provider_fixture_score_coherence_events` conserva soltanto impronte anonime,
generazioni e motivazioni sintetiche, senza payload, token o chiavi.



## Gate certificato di consumo dei voti provider · v0.62.21

La migrazione `database/125_provider_score_consumption_gate_safety.sql`
trasforma la coerenza causale certificata dalla v0.62.20 in una regola effettiva
di consumo per il motore sportivo. I record di `player_match_scores` non vengono
cancellati né modificati: la vista server-side
`provider_match_score_consumption_v1` verifica invece che la riga sia corrente,
che appartenga all’ultima riconciliazione della partita e che la relativa testa
voti risulti `aligned` con la generazione causale corrente.

Un voto `stale`, privo di testa, privo di riconciliazione o superato resta
consultabile per audit, ma `get_league_effective_player_score` lo restituisce
come bloccato senza rating. Di conseguenza non può essere conteggiato, non può
far scattare una sostituzione e non può contribuire a una nuova proiezione o
ufficializzazione. Anche `league_matchday_is_resolved` richiede ora una
fotografia finale e allineata per ogni partita reale conclusa.

Il trigger `provider_score_consumption_gate_event_writer`, impostato
`ENABLE ALWAYS`, registra ogni apertura o chiusura del gate in
`provider_score_consumption_gate_events` e aggiorna le proiezioni non ancora
ufficializzate. I risultati già ufficiali non vengono riscritti automaticamente:
il Centro Operativo li segnala nel conteggio `officialFixtureRiskCount` affinché
la Direzione possa usare il percorso di correzione protetto già esistente.
Il Centro Operativo legge `get_league_provider_sync_health_v20` e mostra lo
stato `CONSUMO VOTI CERTIFICATO`.


## Impatto causale sui risultati ufficiali · v0.62.22

La migrazione `database/126_provider_official_result_impact_safety.sql`
trasforma il semplice conteggio dei risultati ufficiali potenzialmente esposti
in una certificazione puntuale. Per ogni `fantasy_fixture` ufficializzato legge
la proiezione realmente collegata, recupera gli `input_hash` delle risoluzioni
home e away utilizzate e li confronta con gli hash correnti generati dal motore
protetto.

Se gli input coincidono, il risultato è `clear`. Se uno o entrambi differiscono,
il risultato è `affected`; la classifica non viene riscritta automaticamente.
Quando il Presidente riapre il risultato attraverso il percorso di correzione
già certificato, lo stato diventa `in_correction`. Una nuova ufficializzazione
coerente genera una nuova valutazione `clear`. Le teste sono scrivibili soltanto
nel contesto server-side dedicato e gli eventi sono immutabili.

Il Centro Operativo legge `get_league_provider_sync_health_v21` e mostra
`IMPATTO RISULTATI CERTIFICATO`, con conteggi precisi di risultati coerenti, da
rivedere e già in correzione.


## Remediation causale dei risultati ufficiali · v0.62.23

La migrazione `database/127_provider_official_result_remediation_safety.sql`
trasforma le valutazioni `affected` della v0.62.22 in una coda operativa
causale. Ogni testa conserva la generazione dell’impatto ancora corrente,
l’impronta del rischio, lo stato della presa in carico e l’eventuale run di
correzione creato dal motore risultati.

La RPC `start_provider_official_result_remediation_v1` acquisisce prima lo stesso lock di giornata del motore risultati e poi il lock dedicato alla remediation, verifica che la generazione mostrata al Presidente sia ancora quella corrente e solo allora richiama la riapertura protetta già esistente. Se una
nuova sincronizzazione ha cambiato o risolto l’impatto, la richiesta viene
respinta prima di modificare il risultato ufficiale. La stessa transazione
collega la presa in carico al `result_correction_run` e registra un evento
immutabile. Un guard `ENABLE ALWAYS` impedisce ai percorsi legacy di riaprire direttamente un risultato ancora `affected`; soltanto eventuali correzioni già in corso al momento dell’installazione restano marcate come non certificate causalmente per l’audit.

Il Centro Risultati riceve la coda tramite
`get_league_provider_official_result_remediation_v1` e usa automaticamente la
RPC race-safe per le partite interessate. Il Centro Operativo legge
`get_league_provider_sync_health_v22` e mostra `REMEDIATION RISULTATI PROTETTA`
con conteggi aperti, in correzione, risolti e non certificati. Nessun risultato
o valore di classifica viene modificato automaticamente.

## Barriera di commit della lineage ufficiale · v0.62.24

La migrazione `database/128_provider_official_result_lineage_commit_barrier_safety.sql`
chiude una finestra transitoria del flusso risultati. L’ufficializzazione della
giornata aggiorna prima proiezione e `finalized_at`, poi collega tutte le
partite alla `matchday_officialization_run` appena creata. Prima di questa
versione il trigger d’impatto osservava il primo UPDATE ma non il secondo:
poteva quindi certificare una lineage mancante mentre la stessa transazione era
ancora in fase di completamento.

La nuova testa `provider_official_result_lineage_heads` classifica ogni partita
come `reopened`, `assembling`, `certified` o `invalid`. Lo stato `assembling`
non genera un impatto `affected`; il calcolo viene ripreso automaticamente
quando il secondo UPDATE collega `officialization_run_id`. La certificazione
verifica inoltre che la proiezione appartenga alla partita, che l’officialization
run appartenga alla stessa lega e giornata, che non sia superata e che
l’eventuale `correction_run_id` sia presente tra le sorgenti della revisione
ufficiale.

Gli stati e le transizioni sono conservati in eventi immutabili senza payload o
credenziali. Una lineage completa ma incoerente viene classificata `invalid` e
trasformata in un impatto reale disponibile per il percorso di remediation,
senza modificare automaticamente risultati o classifica. Il Centro Operativo
legge `get_league_provider_sync_health_v23` e mostra
`LINEAGE UFFICIALE CERTIFICATA`.

## Chiusura causale certificata della remediation · v0.62.25

La migrazione `database/129_provider_official_result_remediation_completion_safety.sql`
chiude il vuoto tra l’avvio causale della correzione e la sua conclusione. Una
remediation non può più passare a `resolved` senza una prova server-side che
l’impatto sia tornato `clear` e che la lineage ufficiale sia completa. Quando è
stata avviata una correzione, il certificato verifica che lo stesso
`result_correction_run` compaia tra le sorgenti della nuova officialization run,
che la proiezione ufficiale sia collegata alla partita e che la finalizzazione
sia successiva alla riapertura. Il recupero spontaneo del provider viene invece
certificato separatamente come `auto_recovered`.

Le tabelle `provider_official_result_remediation_completion_heads` e
`provider_official_result_remediation_completion_events` conservano stato,
generazione e impronta della prova senza modificare risultati, classifiche, voti
o storico sportivo. Il Centro Operativo legge
`get_league_provider_sync_health_v24` e mostra `CHIUSURA REMEDIATION CERTIFICATA`.



## Barriera causale della progressione giornata · v0.62.26

La migrazione `database/130_provider_matchday_progression_causal_barrier_safety.sql`
impedisce che una giornata venga avanzata sopra risultati ufficiali provider non
più causalmente affidabili. Ogni giornata interamente ufficializzata riceve una
testa protetta con gli stati `clear`, `blocked` o `affected`. Il certificato
verifica impatto puntuale, lineage ufficiale e chiusura certificata di eventuali
remediation per tutte le partite fantasy della giornata.

Un trigger `ENABLE ALWAYS` protegge anche i client precedenti: l'inserimento di
una nuova `matchday_progression_run` viene rifiutato se l'officialization run è
cambiata, se una partita è `affected` o se una progressione precedente della
stessa lega è diventata non affidabile. Le progressioni già esistenti non vengono
annullate automaticamente; vengono marcate `affected` e segnalate alla Direzione,
senza arretrare calendario, classifica o risultati. Il Centro Operativo legge
`get_league_provider_sync_health_v25` e mostra `PROGRESSIONE GIORNATA PROTETTA`.


## Barriera causale della chiusura stagione · v0.62.27

La migrazione `database/131_provider_season_completion_causal_barrier_safety.sql`
impedisce di proclamare il campione se una qualsiasi giornata non possiede la
progressione corrente certificata dal gate provider. Il commit usa un lock
comune con le nuove progressioni e ricontrolla la generazione finale nello
stesso inserimento protetto. Le chiusure già registrate non vengono annullate:
se la catena regredisce, la testa diventa `affected` e viene mostrata alla
Direzione. Il Centro Operativo usa `get_league_provider_sync_health_v26`.

## Snapshot ufficiale immutabile della stagione · v0.62.28

La migrazione `database/132_league_season_official_snapshot_safety.sql`
materializza la fotografia definitiva della stagione nello stesso commit che
certifica la chiusura. Campione, podio, classifica finale, criteri di spareggio,
hash e riferimenti alla generazione provider vengono conservati in
`league_season_official_snapshots`, protetta da un guard `ENABLE ALWAYS` che
ammette soltanto l’inserimento interno e rifiuta aggiornamenti o cancellazioni.

La testa `league_season_official_snapshot_heads` separa lo stato corrente
dall’artefatto storico. Se il gate provider cambia generazione, fingerprint,
progressione finale o stato, lo snapshot non viene riscritto: la testa diventa
`affected` e `league_season_official_snapshot_events` registra l’evento in modo
append-only. Un ritorno successivo alla coerenza viene tracciato come
`revalidated`, ma non riabilita automaticamente lo snapshot e richiede una
verifica della Direzione.

La RPC `complete_league_season_guarded_v3` richiama la barriera v2 e pubblica lo
snapshot nella stessa transazione. `get_league_season_state_v6`,
`get_league_management_state_v16` e `get_league_provider_sync_health_v27`
espongono la fotografia ufficiale e l’eventuale stato `affected` all’app.
