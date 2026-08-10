# LEGHEVO · contratto Free/Premium

## Offerta approvata

| Capacità | Free | Premium |
| --- | --- | --- |
| Prezzo | gratuito | 2,99 EUR/mese oppure 9,99 EUR/anno |
| Nuove leghe principali create | 1 | nessun limite commerciale |
| Partecipanti per lega | massimo 6 | massimo 20 |
| Partecipazione a leghe altrui | consentita | consentita |
| Pubblicità sul singolo account | attiva al lancio AdMob | assente |

Il limite delle leghe riguarda il Presidente che crea una nuova lega principale.
Le stagioni rinnovate della stessa lega appartengono alla medesima catena e non
consumano un nuovo posto Free. Un invitato non deve essere Premium per entrare
in una lega creata da un Presidente Premium.

## Comportamento alla scadenza

La scadenza non cancella leghe, squadre, rose, risultati o storico. L’account
torna Free, ricomincia a visualizzare pubblicità e non può creare una nuova lega
principale oltre il limite Free. Le leghe esistenti restano utilizzabili per non
danneggiare gli altri partecipanti.

## Autorità e sicurezza

Supabase è l’autorità dei limiti applicativi. Il client non può impostare il
proprio livello Premium. `commercial_entitlements` conserva la proiezione
corrente; `commercial_subscription_events` conserva gli eventi store idempotenti.
Soltanto `service_role` può registrare un evento commerciale.

`create_league_with_team` acquisisce un advisory lock per account e ricontrolla
nel database:

- entitlement Premium ancora temporalmente valido;
- numero di leghe principali già possedute;
- massimo partecipanti 6/20;
- limiti tecnici già esistenti del motore.

La funzione `get_my_commercial_entitlement_v1` espone al solo utente autenticato
la proiezione necessaria all’interfaccia, senza transazioni o payload privati.

## Integrazioni previste

- prodotti Apple: `leghevo_premium_monthly` e `leghevo_premium_annual`;
- prodotto Google: `leghevo_premium`, base plan `monthly` e `annual`;
- entitlement RevenueCat: `premium`;
- App User ID RevenueCat: UUID Supabase dell’utente;
- webhook RevenueCat: Edge Function Supabase autenticata;
- annunci: Google AdMob con UMP/CMP europeo e trattamento limitato per minori;
- acquisto e ripristino: SDK RevenueCat nelle development/store build native.

## Stato di attivazione

La fondazione applicativa e database è pronta. Il Test Store RevenueCat è
collegato soltanto alle build `development` con una chiave pubblica `test_` e non
può effettuare addebiti reali. Acquisto, ripristino e prezzi vengono letti
dall'offerta corrente `Premium`.

La configurazione Test Store richiede inoltre `__DEV__`: una build TestFlight o
release non inizializza mai la chiave `test_`, anche se l'ambiente EAS di staging
la contiene accidentalmente.

Il webhook `revenuecat-webhook` verifica un header privato, accetta esclusivamente
eventi dell'entitlement `premium` e registra gli aggiornamenti usando il ruolo
server. Apple e Google restano disabilitati fino al collaudo completo e alla
preparazione della versione 1.0.0. Gli annunci reali restano assenti finché
AdMob, consenso e documenti legali aggiornati non sono pubblicati.

## Collaudo minimo prima dell’attivazione

1. Acquisto sandbox Apple e Google.
2. Ripristino sullo stesso store e su un secondo dispositivo.
3. Rinnovo, disdetta, periodo di grazia, scadenza e rimborso.
4. Evento duplicato e fuori ordine senza regressione dell’entitlement.
5. Free: prima lega da 6 accettata, seconda e lega da 8 bloccate.
6. Premium: più leghe e lega da 20 accettate.
7. Pubblicità visibile solo al Free e mai prima della decisione UMP richiesta.
8. Eliminazione account con chiusura del collegamento commerciale interno.
