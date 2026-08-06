# Staging remoto LEGHEVO v0.62.43

Data della verifica: 7 agosto 2026.

## Esito

L'ambiente Supabase `LEGHEVO Staging`, ospitato nella regione europea
`eu-central-1`, è attivo e contiene la sequenza database approvata per la
v0.62.43. L'ambiente è separato dalla produzione; durante questa attività non
sono stati modificati altri progetti Supabase.

Questa verifica certifica la preparazione tecnica dello staging, non autorizza
il go-live di produzione e non sostituisce i collaudi funzionali end-to-end.

## Database

- Piano Supabase: Free, adeguato alla fase di sviluppo e collaudo iniziale.
- Migrazioni applicate: 145 file della sequenza `001`–`149`.
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

Il test controllato del 6 agosto 2026 ha consumato due richieste. Il provider ha
confermato la validità della connessione e del segreto, ma il piano Free accetta
soltanto le stagioni `2022`–`2024` e, contemporaneamente, date comprese tra il 5
e il 7 agosto 2026. Questi vincoli impediscono oggi di importare un calendario
Serie A coerente; non sono stati eseguiti ulteriori tentativi.

Il primo avvio iOS collegato allo staging aveva inoltre rilevato che la RPC
`get_leghevo_client_rollout_eligibility_v9` superava il timeout PostgREST con
codice PostgreSQL `57014`. Una misurazione diretta con limite esteso a 60 secondi
aveva confermato il timeout: la catena ricalcolava controlli di integrità dello
schema non adatti al percorso runtime. Il client era rimasto correttamente
fail-closed.

La migrazione 148 ha sostituito quel percorso con una proiezione certificata a
costo costante. Sullo staging ha superato 20/20 controlli; la chiamata con chiave
pubblicabile ha risposto HTTP 200 in 462 ms con contratto compatibile, protetto e
go-live consentito. Il successivo smoke test iOS ha superato la barriera e
visualizzato la schermata reale di registrazione/accesso.

Il collaudo visivo in modalità demo è invece riuscito su Simulator iPhone 17 Pro
con iOS 27.0 ed Expo Go: bundle caricato e schermata Notifiche renderizzata senza
errori bloccanti. Le notifiche push remote richiederanno una development build.

## Autenticazione staging

Il collaudo Auth del 7 agosto 2026 ha rilevato e corretto un'incompatibilità tra
le migrazioni 098 e 099: `profiles.profile_fingerprint` era ormai obbligatorio,
ma il trigger `handle_new_user()` non lo valorizzava. Ogni nuova registrazione
veniva quindi annullata dal database con errore HTTP 500.

La migrazione 149 calcola la fingerprint iniziale nello stesso inserimento
atomico del profilo, mantenendo invariata la certificazione delle accettazioni
legali. I test locali e staging hanno confermato quattro proprietà: creazione
del profilo, fingerprint di 32 caratteri, preferenze privacy e certificazione
dell'accettazione. I test sono stati eseguiti in transazioni con rollback.

È stato inoltre creato un account QA isolato e già confermato sul solo staging.
Con la stessa chiave pubblicabile usata dall'app hanno avuto esito positivo:
login email/password, verifica dell'utente, rinnovo della sessione, centro
account protetto e centro privacy con documenti correnti accettati. Le
credenziali non sono nei file: sono conservate nel Portachiavi macOS con servizio
`supabase-leghevo-staging-qa-auth`.

La registrazione pubblica richiede correttamente la conferma email. Il test di
consegna non usa indirizzi casuali: va completato con una casella reale
controllata dal team, insieme al recupero password.

## Lega e invito multi-account

Con l'account QA principale è stata creata sullo staging una lega classica in
stato `draft`, con limite di 8 squadre, 500 crediti iniziali e rosa da 25. Sono
risultati coerenti la membership amministratore, la squadra iniziale e la
persistenza dopo il reload del bundle. La Home iOS ha mostrato la lega con
conteggio `1/8`.

Un secondo account QA isolato ha poi verificato l'intero percorso invito:
anteprima del codice, disponibilità del posto, ingresso, ruolo `manager`,
creazione della seconda squadra con 500 crediti e lettura della lega tramite le
policy RLS. Dopo il reload, il primo dispositivo ha mostrato `2/8` partecipanti.
I riferimenti QA restano esclusivamente nel Portachiavi macOS; codici invito,
identificativi e credenziali non sono stati inseriti nei file versionati.

Metro non ha segnalato errori funzionali durante il test. Restano gli avvisi
attesi: notifiche push remote non pienamente supportate in Expo Go e
deprecazione non bloccante di `SafeAreaView`.

## Prossimi controlli

1. Collaudare su una casella reale la conferma registrazione e il recupero
   password; login, rinnovo sessione e centri account/privacy sono già validati.
2. Definire il piano API-Football necessario per stagioni e date reali, quindi
   ripetere una sincronizzazione minima verificando persistenza e telemetria.
3. Collaudare `send-push-notifications` con credenziali e dispositivo di test.
4. Proseguire la checklist `docs/CHECKLIST_COLLAUDO_E2E.md` con i due account QA
   già predisposti, partendo da gestione membri e configurazione della lega.
5. Completare build e test iOS/Android su simulatori e dispositivi target.
6. Mantenere la produzione separata finché backup, restore rehearsal, rollout e
   rollback non saranno stati verificati e approvati esplicitamente.
