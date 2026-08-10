# Piano di rilascio LEGHEVO 1.0.0

## Stato di partenza

La candidata `0.62.49` e' verificata su staging, TestFlight e Android. Il numero
`1.0.0` resta riservato alla release finale: non viene assegnato finche' tutti
i gate qui sotto non sono chiusi.

## Configurazione pronta

- Identificativo iOS: `com.leghevo.app`.
- Identificativo Android: `com.leghevo.app`.
- Profili EAS presenti in `eas.json`:
  - `development` per notifiche e debug su dispositivi QA;
  - `preview` per distribuzione interna;
  - `testflight` e `play-testing` per store sandbox collegati allo staging;
  - `production` per la build candidata alla pubblicazione.
- La versione applicativa e' letta dal repository; EAS incrementera' soltanto
  il numero interno di build per il profilo di produzione.

## Gate obbligatori

1. Completare la checklist multi-account su staging con i tre ruoli fittizi.
2. Creare una development build e verificare le notifiche push reali su almeno
   un dispositivo iOS e uno Android, inclusi consenso e deep link.
3. Creare una preview firmata per iOS e Android, installarla su dispositivi
   fisici e ripetere gli smoke test principali.
4. Eseguire un backup reale dello staging, conservarlo fuori dal database
   sorgente e completare un restore rehearsal su un target isolato.
5. Registrare e accettare esplicitamente il rischio delle vulnerabilita'
   transitive Expo/Metro rimaste dopo l'upgrade, oppure aggiornare quando sara'
   disponibile una correzione compatibile.
6. Rieseguire preflight, test compatibilita' staging con fingerprint valida e
   alterata, e validare il piano di rollback.
7. Creare e configurare gli abbonamenti reali su App Store Connect e Google
   Play, collegarli all'entitlement RevenueCat `premium` e sostituire il Test
   Store con le chiavi SDK pubbliche specifiche iOS/Android.
8. Superare su entrambi gli store i test sandbox di acquisto, ripristino,
   rinnovo, disdetta, grazia, scadenza e rimborso, verificando il webhook su
   Supabase staging.
9. Verificare che i bundle candidati non contengano una chiave `test_` e che
   usino l'ambiente EAS/backend corretto per piattaforma.
10. Solo allora: impostare `1.0.0`, calcolare una nuova fingerprint, creare una
   nuova migrazione additiva e certificare una nuova release candidata.

## Azioni che richiedono il proprietario

- Accesso al progetto Expo/EAS per creare o collegare il progetto cloud.
- Creazione o conferma delle credenziali Apple Developer e Google Play.
- Autorizzazione esplicita prima di creare build cloud, distribuire artefatti,
  accedere a servizi store o avvicinarsi alla produzione.

Nessun passaggio di questo piano autorizza modifiche al database di produzione.
