# Validazione tecnica LEGHEVO v0.62.43

Data della verifica: 6 agosto 2026.

## Esito

La v0.62.43 ha superato la validazione tecnica riproducibile nell'ambiente locale
isolato. Lo Sviluppo 10 è quindi concluso e l'avanzamento tecnico del progetto è
pari al 100%.

Questo esito non costituisce un deployment, una certificazione dell'infrastruttura
remota o un'autorizzazione automatica al go-live di produzione.

## Evidenze applicative

- `npm run typecheck`: superato.
- Risoluzione della configurazione Expo: superata.
- `expo export` per Android e iOS: superato, 891 moduli elaborati.
- Fingerprint calcolata dell'app:
  `9cd8380cc324b6292f0e74fd0b5a727171cacc137462942d6c69149304ca3e5e`.
- La fingerprint coincide tra `src/release.ts`, migrazione 147 e SQL standalone.

## Evidenze database locali

- Ambiente: stack Supabase locale isolato; nessun database remoto o di produzione coinvolto.
- Percorso applicato: migrazioni numerate `001`–`147`, escludendo i seed di sviluppo `005`, `057` e `058`.
- Migrazione 147: applicata con successo.
- Diagnostica finale: 20 controlli su 20 `true`.
- Riapplicazione della migrazione 147: superata con 20/20 controlli, verificando il percorso idempotente esercitato.
- Modello finale `production`: `protected=true`, `healthy=true`, `fresh=true`, `status=certified`, `checkCount=10`, `requiredCheckCount=10`, `goLiveAllowed=true`, `activeVersion=0.62.43`.
- Registri finali locali: un run, dieci controlli componente, un certificato, una testa e un evento.

La migrazione e lo script standalone sono testualmente identici. Il loro SHA-256
è `ee79d309f226ab66d1d5f39f0b0eeedac0a7830f10cf0bdb6de58fd3612f0c8c`.

## Nota sulla sequenza delle migrazioni

I file `005_development_demo_data.sql`, `057_development_player_pool.sql` e
`058_development_pippolandia_roster.sql` sono seed di sviluppo e non fanno parte
del percorso di produzione. In particolare, la migrazione 058 richiede dati demo
creati in precedenza e non è autonoma su un database pulito privo della lega
attesa. L'applicazione indiscriminata di tutti i file numerati non rappresenta
quindi la sequenza di produzione supportata.

## Controlli necessari prima del go-live reale

La procedura operativa è dettagliata in `docs/CHECKLIST_COLLAUDO_E2E.md`. Il
preflight locale completo si esegue dalla radice con:

```sh
node scripts/release-preflight.mjs
```

1. Applicare la sequenza approvata a un ambiente staging equivalente alla produzione.
2. Verificare configurazione e rotazione dei segreti senza registrarne i valori nel repository.
3. Eseguire un backup fisico reale, conservarlo esternamente e verificarne checksum e cifratura.
4. Eseguire un restore rehearsal su un target esterno isolato e conservarne le evidenze.
5. Esercitare worker, telemetria, outbox, consumer e audit con traffico realistico.
6. Eseguire collaudi end-to-end con account distinti per ruoli, mercato, asta, formazione, risultati e competizioni.
7. Preparare build firmate iOS/Android, testarle sui dispositivi target e approvare il piano di rollback.
8. Solo dopo queste verifiche, autorizzare esplicitamente il deployment e il rollout progressivo in produzione.
