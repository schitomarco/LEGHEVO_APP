# Roadmap di sviluppo e collaudo LEGHEVO

Questa roadmap ordina il lavoro in base al rischio e alle dipendenze reali. Le versioni indicate sono obiettivi di lavoro e possono essere accorpate quando una fase non richiede modifiche al codice.

## Stato corrente · v0.62.45

- Sviluppo 8 concluso al 90%, Sviluppo 9 concluso al 95% e Sviluppo 10 concluso al 100% tecnico.
- La v0.62.45 applica override patch alle dipendenze transitive compatibili e riduce l'audit npm da 15 a 13 segnalazioni.
- La migrazione `153` ha superato simulazione con rollback, applicazione locale, verifica 10/10, riesecuzione idempotente e applicazione staging.
- La cronologia staging è allineata fino alla `153` e il lint SQL remoto non rileva errori; il test pubblico post-deploy resta da ripetere quando sarà nuovamente disponibile l'esecuzione approvata.
- La v0.62.43 chiude la catena di production readiness con dieci capacità terminali e diagnostica finale di 20 controlli.
- La sequenza di produzione `001`–`147`, esclusi i seed di sviluppo `005`, `057` e `058`, è stata applicata con successo a un database Supabase locale isolato.
- La migrazione 147 ha restituito 20/20 controlli `true` ed è stata riapplicata con lo stesso esito per verificare il percorso idempotente.
- Typecheck, configurazione Expo, fingerprint release ed export Android/iOS sono stati completati con successo.
- Il completamento tecnico non certifica infrastruttura, credenziali, backup fisico, restore esterno, telemetria o traffico reali di produzione.
- Le evidenze e i prerequisiti residui di go-live sono registrati in `docs/VALIDAZIONE_V0.62.43.md`.

## v0.62.45 — Hardening dipendenze transitive

- Override patch per `brace-expansion` e `js-yaml`, senza upgrade forzati.
- Nuovo lockfile, fingerprint applicativa e certificato release immutabile.
- Audit residuo documentato: una vulnerabilità alta e dodici moderate.
- Catena operativa riallineata localmente e su staging fino alla readiness 10/10.
- Upgrade Expo 57 rinviato a una release dedicata con regressione completa.

## v0.62.44 — Fingerprint dipendenze e ricertificazione

- Inclusione di `package-lock.json` nel digest riproducibile della release.
- Nuova release applicativa senza modifica retroattiva del certificato v0.62.43.
- Storico immutabile delle tre ricertificazioni di modello necessarie.
- Catena operativa riallineata fino alla production readiness 10/10.
- Collaudo locale e staging completati; la produzione reale resta esclusa e
  richiede comunque la checklist operativa dedicata.

## v0.62.43 — Chiusura tecnica dello Sviluppo 10

- Sigillo finale di production readiness e go-live controllato.
- Verifica congiunta di integrità applicativa, release, rollout, telemetria, outbox, consumer, audit, disaster recovery, backup fisico e ritorno in servizio.
- Run, controlli, certificati, teste ed eventi immutabili con fingerprint SHA-256.
- Advisory lock, request ID idempotenti, riconciliazione fail-closed e protezioni da esecuzioni concorrenti.
- Migrazione `database/147_final_production_readiness_and_go_live_seal.sql` e script standalone testualmente identici.
- Avanzamento tecnico: 100%. Go-live di produzione: ancora soggetto alla checklist operativa reale.

## v0.55.5 — Rifiniture Mercato e terminologia

- Uniformare `Svincolato` e `SVINCOLATO` in `LIBERO` nella scheda calciatore.
- Mostrare stati vuoti espliciti nel modulo Scambi.
- Disabilitare chiaramente l'invio quando la proposta non è compilabile.
- Nessuna migrazione Supabase prevista.

## v0.55.6 — Scambi end-to-end

Prerequisito: due squadre con almeno un calciatore ciascuna.

- Invio proposta.
- Visualizzazione proposta inviata.
- Ricezione sul secondo account.
- Rifiuto.
- Annullamento da parte del mittente.
- Accettazione.
- Trasferimento atomico di calciatori e crediti.
- Verifica Realtime su entrambi i dispositivi.

## v0.55.7 — Asta realtime

Prerequisito: Presidente e almeno un altro manager.

- Apertura sessione e nomina calciatore.
- Rilanci concorrenti.
- Timer, pausa e ripresa.
- Protezione crediti e quote ruolo.
- Assegnazione automatica.
- Annullamento lotto e chiusura asta.

## v0.55.8 — Ciclo amministrativo della lega

- Partecipanti e inviti.
- Nomina amministratori.
- Rimozione e uscita volontaria prima dell'avvio.
- Regolamento e impostazioni.
- Generazione e annullamento calendario.
- Avvio ufficiale della competizione.

## v0.55.9 — Giornata completa

Prerequisito: calendario generato e rose complete.

- Consegna formazione.
- Blocco alla scadenza.
- Live e sostituzioni.
- Calcolo risultati.
- Ufficializzazione.
- Classifica e criteri di spareggio.
- Correzione e riapertura risultato.

## v0.56.0 — Competizioni e storico

- Coppa di Lega.
- Playoff.
- Supercoppa.
- Chiusura stagione.
- Albo, record e rinnovo.

## v0.56.1 — Servizi account e rilascio

- Account e recupero password.
- Privacy ed esportazione dati.
- Centro Assistenza.
- Notifiche interne.
- Push su build configurata con EAS.
- Controlli di sicurezza, bundle iOS/Android e preparazione release.

## Regola operativa

Durante il collaudo con l'utente si esegue una sola azione alla volta. Ogni anomalia viene confrontata con il comportamento previsto nel codice prima di essere registrata come bug.


### v0.62.27 · chiusura stagione provider

La chiusura della stagione richiede ora una catena completa di progressioni
`clear`. Una stagione già conclusa resta invariata ma viene marcata `affected`
se una progressione causale precedente perde successivamente la certificazione.
