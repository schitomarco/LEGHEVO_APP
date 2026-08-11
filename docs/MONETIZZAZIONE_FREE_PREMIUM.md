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

## Business Dashboard proprietario

La sezione `💰 Ricavi` è globale e non appartiene alla Direzione di una lega.
Essere Presidente o Admin non concede alcun accesso. Il database conserva un
solo proprietario in `platform_business_owners`; l'identità iniziale viene
riconosciuta tramite un'impronta SHA-256 e mai tramite un indirizzo e-mail
pubblicato nel codice.

`get_leghevo_business_dashboard_v1` aggrega esclusivamente dati server-side:

- utenti con accesso negli ultimi 30 giorni e Premium attivi;
- conversione, nuovi Premium, rinnovi, cancellazioni e ARPU;
- stima lorda Apple/Google dagli eventi RevenueCat di produzione;
- ricavi e leghe su serie giornaliera e mensile;
- costi manuali più commissione store gestionale stimata al 15%;
- margine operativo stimato.

Pubblicità, League Pro e costi esterni sono letti dal registro service-only
`business_financial_entries` e restano a zero finché una fonte attendibile non
li registra. La dashboard non crea numeri dimostrativi e mostra sempre
l'avvertenza che maturato, commissioni e liquidato ufficiali sono quelli di
Apple, Google e degli altri provider.

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

Le build TestFlight e Google Play testing usano invece la modalità `store` e
due chiavi SDK pubbliche distinte: `EXPO_PUBLIC_REVENUECAT_IOS_API_KEY` per iOS
e `EXPO_PUBLIC_REVENUECAT_ANDROID_API_KEY` per Android. Il selettore è
fail-closed: iOS accetta solo una chiave `appl_`, Android solo una chiave
`goog_`, mentre una chiave `test_` non può inizializzare una build release.
I profili EAS `testflight` e `play-testing` usano intenzionalmente l'ambiente
`preview`: chiavi store reali in sandbox e backend Supabase staging. Soltanto
il profilo store finale usa l'ambiente `production` e il backend di produzione.

Variabili richieste sia in EAS `preview` sia in EAS `production`, con URL e
chiavi Supabase appartenenti al rispettivo backend:

- `EXPO_PUBLIC_REVENUECAT_STORE_MODE=store`;
- `EXPO_PUBLIC_REVENUECAT_PURCHASES_ENABLED=true` soltanto durante il collaudo
  sandbox e dopo la configurazione completa dei prodotti;
- `EXPO_PUBLIC_REVENUECAT_IOS_API_KEY=appl_...`;
- `EXPO_PUBLIC_REVENUECAT_ANDROID_API_KEY=goog_...`.

In `preview` gli acquisti passano dagli ambienti sandbox/test di Apple e Google;
in `production` gli stessi prodotti vengono venduti realmente dopo
l'approvazione degli store. L'ambiente EAS `development` resta riservato al
Test Store RevenueCat.

Le chiavi SDK pubbliche non sostituiscono le credenziali private di App Store
Connect o Google Play, che devono restare nelle integrazioni server-side di
RevenueCat e non devono mai essere incluse nel bundle Expo.

Il webhook `revenuecat-webhook` verifica un header privato, accetta esclusivamente
eventi dell'entitlement `premium` e registra gli aggiornamenti usando il ruolo
server. Apple e Google restano disabilitati fino al collaudo completo e alla
preparazione della versione 1.0.0. Gli annunci reali restano assenti finché
AdMob, consenso e documenti legali aggiornati non sono pubblicati.

## Stato collaudo store · 11 agosto 2026

- App RevenueCat Apple e Google create per `com.leghevo.app`; chiavi SDK
  pubbliche configurate come variabili sensibili in EAS `preview` e
  `production`, senza valori conservati nel repository.
- Preflight fail-closed iOS e Android superato in entrambi gli ambienti EAS.
- App Store Connect: gruppo `LEGHEVO Premium`, prodotti mensile e annuale
  creati con gli identificatori previsti, prezzi Italia 2,99 EUR/mese e
  9,99 EUR/anno.
- RevenueCat: entrambi i prodotti Apple collegati all'entitlement `premium` e
  ai package Monthly/Annual dell'offerta predefinita `Premium`; i prodotti
  Test Store restano limitati allo sviluppo.
- Build iOS di collaudo `0.62.49 (4)` generata con ambiente `preview`, chiavi
  RevenueCat e backend Supabase staging completi, quindi inviata a TestFlight.
  `ascAppId` è dichiarato nel profilo submit per rendere ripetibili i
  caricamenti successivi.
- Google Play reale resta in attesa dell'attivazione dell'account sviluppatore;
  il prodotto `leghevo_premium` e i base plan `monthly`/`annual` non sono
  ancora stati creati.

## Collaudo minimo prima dell’attivazione

1. Acquisto sandbox Apple e Google.
2. Ripristino sullo stesso store e su un secondo dispositivo.
3. Rinnovo, disdetta, periodo di grazia, scadenza e rimborso.
4. Evento duplicato e fuori ordine senza regressione dell’entitlement.
5. Free: prima lega da 6 accettata, seconda e lega da 8 bloccate.
6. Premium: più leghe e lega da 20 accettate.
7. Pubblicità visibile solo al Free e mai prima della decisione UMP richiesta.
8. Eliminazione account con chiusura del collegamento commerciale interno.
9. Preflight release: modalità `store`, chiave `appl_` su iOS, chiave `goog_`
   su Android e assenza completa di `test_` nei bundle candidati.
