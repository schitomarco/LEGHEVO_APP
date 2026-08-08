# Checklist di collaudo end-to-end LEGHEVO v0.62.47

Questa checklist deve essere eseguita su staging con dati fittizi e almeno tre
account distinti. Non usare il database di produzione.

## Prerequisiti

- [x] Preflight superato con `node scripts/release-preflight.mjs`.
- [x] Supabase staging separato dalla produzione e migrazioni fino alla `155` applicate senza l'automazione provider `004` e i seed di sviluppo `005`, `057` e `058`.
- [ ] Provider configurato con credenziali di test o sorgente controllata.
- [ ] Account `Presidente`, `Admin` e `Mister` disponibili su dispositivi o sessioni separate.
- [ ] Orari dei dispositivi sincronizzati e notifiche abilitate dove richiesto.
- [ ] Nessuna credenziale, token o dato personale reale inserito nelle evidenze.

## Avvio locale sicuro

Per una prima sessione tecnica locale, senza creare file `.env` e senza copiare
chiavi nel repository:

```sh
npx --yes supabase@2.111.0 start
node scripts/local-e2e.mjs --check
node scripts/local-e2e.mjs --start
```

Il launcher accetta esclusivamente URL `localhost`/loopback. Le credenziali
effimere vengono passate direttamente al processo Expo e non vengono stampate o
salvate. La sessione locale serve a preparare le prove; il gate finale deve
comunque essere eseguito su uno staging remoto separato dalla produzione.

Per ogni prova conservare: data, ambiente, versione/fingerprint, account/ruolo,
passaggi, risultato atteso, risultato osservato e riferimento a screenshot o log
sanificato. Ogni esito diverso da quello atteso deve avere un ticket.

## Matrice delle prove

| ID | Area | Ruoli/sessioni | Prova | Risultato atteso | Esito |
|---|---|---|---|---|---|
| E2E-01 | Autenticazione | Tutti | Registrazione, accesso, uscita e recupero password | Sessioni isolate, errori chiari, nessun accesso incrociato | [ ] |
| E2E-02 | Lega | Presidente | Creazione lega con configurazione completa | Lega, stagione e squadra presidenziale create una sola volta | [ ] |
| E2E-03 | Inviti | Presidente + Mister | Anteprima e ingresso concorrente tramite codice | Posti e vincoli rispettati; nessuna iscrizione duplicata | [ ] |
| E2E-04 | Ruoli | Presidente + Admin + Mister | Nomina/revoca Admin e tentativi non autorizzati | Permessi aggiornati; Mister bloccato dalle azioni amministrative | [ ] |
| E2E-05 | Squadre e rose | Tutti | Consultazione rosa propria e avversaria | Visibilità solo nella lega; totali e quote coerenti | [ ] |
| E2E-06 | Mercato libero | Admin + Mister | Acquisti simultanei dello stesso calciatore | Un solo vincitore; crediti e rosa aggiornati atomicamente | [ ] |
| E2E-07 | Scambi | Due Mister | Invio, rifiuto, annullamento e accettazione | Stati monotoni; giocatori e crediti trasferiti atomicamente | [ ] |
| E2E-08 | Asta live | Presidente + due Mister | Apertura, rilanci concorrenti, pausa, ripresa e assegnazione | Timer e offerta autorevoli; quote e crediti protetti | [ ] |
| E2E-09 | Calendario | Presidente | Generazione e avvio competizione | Accoppiamenti validi, nessun duplicato, avvio protetto | [ ] |
| E2E-10 | Formazione | Mister | Titolari, panchina, ordine riserve e consegna | Modulo valido, quote rispettate e salvataggio idempotente | [ ] |
| E2E-11 | Scadenza | Due Mister | Consegna prima/dopo deadline e tentativo di modifica | Formazione congelata alla scadenza senza race condition | [ ] |
| E2E-12 | Sostituzioni | Admin + Mister | Automatiche, manuali autorizzate e limite sostituzioni | Ordine panchina e regole applicati deterministicamente | [ ] |
| E2E-13 | Giornata | Provider + Admin | Sync partite/voti, calcolo e ufficializzazione | Un solo risultato ufficiale; punteggi e bonus tracciabili | [ ] |
| E2E-14 | Classifica | Tutti | Aggiornamento dopo ufficializzazione e parità | Punti, differenza e criteri di spareggio coerenti | [ ] |
| E2E-15 | Correzioni | Presidente/Admin | Riapertura, correzione voto e nuova chiusura | Audit completo; risultati e classifica ricalcolati causalmente | [ ] |
| E2E-16 | Rinvii | Admin + Provider | Sospensione, recupero e pubblicazione tardiva | Nessun voto prematuro; recupero collegato alla giornata corretta | [ ] |
| E2E-17 | Coppe | Presidente + Mister | Sorteggio, turni, finale e certificazione | Avanzamento senza duplicati e albo aggiornato | [ ] |
| E2E-18 | Playoff/Supercoppa | Presidente + Mister | Configurazione, calendario e chiusura | Partecipanti eleggibili, esito immutabile e trofeo registrato | [ ] |
| E2E-19 | Notifiche | Tutti | Notifiche interne, preferenze e push | Deduplicazione, rispetto preferenze e deep link corretto | [ ] |
| E2E-20 | Account e privacy | Mister | Modifica profilo, export dati e richiesta cancellazione | Autorizzazione corretta, audit e dati esportati coerenti | [ ] |
| E2E-21 | Isolamento lega | Account in due leghe | Letture e RPC con identificativi dell'altra lega | RLS/RPC negano ogni accesso cross-league | [ ] |
| E2E-22 | Provider resiliente | Worker | Timeout, retry, backoff, lease scaduta e fencing | Nessun doppio worker; incidente, quarantena e recovery tracciati | [ ] |
| E2E-23 | Outbox/consumer | Due consumer | Claim concorrente, ack, retry e dead-letter | Sequenza esatta, una sola applicazione e ricevute immutabili | [ ] |
| E2E-24 | Rollout | Release operator | 10→35→60→85→100 e telemetria degradata | Promozioni protette; pausa/rollback automatico fail-closed | [ ] |
| E2E-25 | Disaster recovery | Release operator | Backup esterno, restore isolato e ritorno in servizio | Checksum valido, drill riuscito e riapertura solo dopo 10/10 | [ ] |

## Gate di uscita

Il collaudo è superato soltanto quando:

- [ ] Tutte le prove applicabili sono superate e corredate da evidenza.
- [ ] Non esistono problemi bloccanti o alti aperti.
- [ ] I problemi medi accettati hanno responsabile e scadenza.
- [x] La readiness v0.62.47 restituisce 10/10 nella validazione atomica dello staging.
- [x] Migrazione 155 applicata e controllata sullo staging finale.
- [x] Smoke test post-deploy con fingerprint valida e alterata superato.
- [ ] Backup e restore rehearsal reali sono verificati fuori dal database sorgente.
- [ ] Build firmate Android/iOS corrispondono alla fingerprint certificata.
- [ ] Piano di rollout, monitoraggio, rollback e responsabilità operative sono approvati.
