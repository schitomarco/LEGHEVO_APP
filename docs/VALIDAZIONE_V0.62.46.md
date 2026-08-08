# Validazione tecnica LEGHEVO v0.62.46

## Obiettivo

Rendere affidabile il collaudo locale della release e coerenti i dati demo
della lega, senza modificare la produzione.

## Modifiche validate

- Il launcher `node scripts/local-e2e.mjs --start` isola temporaneamente
  `.env.local`, passa a Expo solo le credenziali loopback e lo ripristina alla
  chiusura. Questo evita di usare accidentalmente lo staging nei test locali.
- La lega demo ora espone otto partecipanti, coerenti con il contatore `8/8`.
- Le card operative della lega espongono nome e ruolo accessibili; Calendario
  può essere individuato dai test senza coordinate.
- Versione aggiornata a `0.62.46` e fingerprint SHA-256 certificata:
  `61b3336cc006d8b2739696dd9d6c0f9432585bd6f3ca70eb56656a7b9196d9e6`.
- Migrazione additiva `154`; nessun certificato delle release precedenti viene
  riscritto.

## Evidenze locali

- Simulazione completa con `ROLLBACK`, applicazione persistente e riesecuzione
  idempotente della migrazione 154: superate sul solo Supabase locale.
- Readiness locale: `certified`, 10/10 controlli, release attiva `0.62.46`.
- Preflight: contratto SQL `001`–`154`, TypeScript, configurazione Expo ed
  export Android/iOS: superati.
- Simulator iOS: barriera release superata dopo il controllo; accesso ospite,
  home e apertura della lega demo verificati, inclusa intestazione `8/8`.
- Il file `.env.local` è stato ripristinato dopo il test locale.

## Staging e limiti

La migrazione 154 è stata proposta dal dry-run come unica variazione. Il
deploy remoto non è certificato: i processi Supabase sono rimasti bloccati
sulla connessione IPv6 e sono stati interrotti in modo controllato. Prima del
collaudo staging occorre ristabilire il link IPv4 con la password del database
di staging, applicare la sola migrazione 154 e ripetere gli smoke test della
RPC di compatibilità con fingerprint valida e alterata.

La produzione reale non è stata interrogata, modificata o distribuita.
