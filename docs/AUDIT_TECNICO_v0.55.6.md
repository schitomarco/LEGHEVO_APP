# Audit tecnico LEGHEVO Mobile v0.55.6

Data audit: 29 luglio 2026

## 1. Baseline verificata

Il progetto analizzato è `LEGHEVO_mobile_prototype_v0.55.6`.

Controlli tecnici eseguiti sulla baseline:

- TypeScript con `tsc --noEmit`: superato.
- Configurazione Expo pubblica: valida.
- Bundle iOS Expo/Hermes: generato correttamente, 885 moduli.
- Versione coerente tra `package.json` e `app.json`: `0.55.4`.
- Nessuna chiave o file `.env` presente nello ZIP di rilascio.

Struttura rilevata:

- 32 schermate React Native.
- 32 hook applicativi.
- 33 servizi dati.
- 56 migrazioni SQL numerate.
- 2 Edge Functions Supabase.

## 2. Correzione sull'ultimo test Scambi

Il pulsante `Pippolandia` non è progettato per aprire un popup o una nuova schermata. È un selettore orizzontale di squadra.

Il secondo screenshot del test mostra che il tap ha funzionato:

- prima del tap il chip era chiaro e compariva `Scegli prima la squadra destinataria`;
- dopo il tap il chip è diventato scuro con testo verde e il messaggio è scomparso.

Le sezioni `TU OFFRI` e `TU CHIEDI` sono rimaste vuote perché:

- `Diavoli del Sud` aveva una rosa di 0/25;
- la rosa di `Pippolandia` non contiene calciatori selezionabili nel dataset corrente.

Quindi il selettore squadra è funzionante. Il problema residuo è di chiarezza dell'interfaccia quando una rosa è vuota, non di navigazione.

## 3. Funzioni già collaudate su iPhone

### Autenticazione e dati

- Avvio con Expo Go.
- Login con account reale.
- Collegamento al progetto Supabase.
- Lettura della lega `Serie A da Divano`.
- Lettura della squadra `Diavoli del Sud`.

### Rosa e calciatori

- Caricamento della rosa.
- Apertura scheda calciatore dalla Rosa.
- Ritorno corretto alla Rosa.
- Archivio calciatori.
- Ricerca per nome.
- Filtri squadra, liberi e ruolo.
- Apertura scheda calciatore libero.
- Ritorno all'Archivio conservando il filtro.

### Formazione

- Inserimento e rimozione del calciatore dal campo.
- Cambio modulo, incluso 3-5-2.
- Formazione automatica con avviso su rosa incompleta.

### Live, calendario e classifica

- Live stabile senza crash.
- Stato vuoto `Nessuna partita convocata`.
- Blocco calendario con lega incompleta.
- Solo andata e andata/ritorno.
- Calcolo di giornate, partite e giornata finale.
- Cambio giornata iniziale e ricalcolo dell'ultima.
- Apertura Risultati e classifica.
- Classifica e criteri di ordinamento.

### Mercato

- Apertura Mercato.
- Caricamento dei liberi.
- Acquisto diretto tramite pulsante crediti.
- Aggiornamento rosa e crediti.
- Apertura scheda calciatore dal Mercato, corretta nella v0.55.6.
- Svincolo con rimborso percentuale arrotondato per difetto.
- Ritorno del calciatore tra i liberi.
- Apertura tab Scambi.
- Apertura modulo nuova proposta.
- Selezione della squadra destinataria tramite chip.

## 4. Implementato nel codice ma non ancora collaudato end-to-end

L'audit statico rileva interfaccia, hook, servizio Supabase e migrazioni dedicate per le seguenti aree. La loro presenza nel codice non equivale ancora a un test completo su due o più account reali.

### Gestione della lega

- Creazione e ingresso tramite codice.
- Partecipanti e squadra personale.
- Direzione lega e ruoli amministrativi.
- Impostazioni e regolamento condiviso.
- Avvio, chiusura e rinnovo stagione.
- Centro operativo della giornata.
- Storico, albo, record e carriere manager.

### Competizioni

- Asta realtime.
- Calendario round-robin.
- Campionato e risultati.
- Coppa di Lega.
- Playoff.
- Supercoppa.
- Centro Sfida.
- Gestione rinvii e voto d'ufficio.

### Account e servizi

- Profilo e sicurezza account.
- Recupero password.
- Centro notifiche.
- Preferenze notifiche e registrazione push.
- Privacy, esportazione dati e richieste diritti.
- Centro Assistenza.

## 5. Dipendenze esterne da distinguere dai bug dell'app

### Push native

Il codice è presente, ma la registrazione completa richiede un `EXPO_PUBLIC_EAS_PROJECT_ID` valido e la configurazione del progetto di distribuzione. L'assenza di questo valore non deve essere classificata come bug della schermata.

### Dati calcistici reali

Le Edge Functions per la sincronizzazione sono presenti. Il funzionamento reale dipende dai segreti server-side di API-Football e dal piano provider configurato. Il progetto contiene anche protezioni per non avviare automaticamente i cron quando il provider non è abilitato.

### Funzioni multiutente

Asta realtime, scambi, notifiche tra manager e varie azioni di Direzione richiedono almeno due account reali e dati coerenti su entrambe le squadre. Un dataset con una sola rosa popolata non permette un collaudo completo.

## 6. Rifiniture certe individuate

### Terminologia calciatore libero

Nella scheda calciatore compaiono ancora:

- `SVINCOLATO` nella riga club/squadra;
- `Svincolato` nel riepilogo proprietà;
- `LIBERO` nel badge.

La correzione prevista è uniformare la scheda su `LIBERO`.

### Scambi con rose vuote

Il componente che elenca i calciatori non mostra alcun testo quando riceve una lista vuota. Questo produce due spazi bianchi sotto `TU OFFRI` e `TU CHIEDI`.

Rifinitura consigliata:

- `La tua rosa è vuota. Acquista almeno un calciatore.`
- `Questa squadra non ha calciatori disponibili per lo scambio.`
- pulsante `INVIA PROPOSTA` disabilitato finché mancano le selezioni obbligatorie.

### Nome della lega

Il testo errato `Seria A da Divano` non è stato trovato nel codice. Il codice demo e gli screenshot correnti usano `Serie A da Divano`. Un eventuale refuso futuro andrà quindi cercato direttamente nei dati Supabase, non corretto alla cieca nell'app.

## 7. Valutazione sintetica

La v0.55.6 non è una semplice demo grafica: dispone già di una struttura applicativa e database molto ampia. Il rischio principale non è l'assenza generalizzata di funzioni, ma la quantità di flussi avanzati ancora da verificare con dati reali, stati limite e più account.

La strategia corretta è quindi:

1. correggere soltanto le rifiniture certe;
2. collaudare ogni area end-to-end;
3. non dichiarare completa una funzione solo perché la schermata si apre;
4. evitare nuove migrazioni finché quelle esistenti coprono il caso;
5. mantenere una matrice dei test superati per ogni versione.


## Aggiornamento v0.55.6
- Corretta la validazione del modulo Scambi: è consentita una proposta con un calciatore offerto e crediti richiesti, oppure viceversa, purché sia presente almeno un calciatore complessivo.
