# Architettura multi-provider LEGHEVO

## Stato

Fondazione locale successiva alla release validata `0.62.49`. Le migrazioni
`159` e `160` non costituiscono un'autorizzazione al go-live di produzione.

## Flusso obbligatorio

```text
football-data.org + API-Football
              ↓
      provider layer server-side
              ↓
 quota → cache → contratto → staging → certificazione → pubblicazione
              ↓
            Supabase
              ↓
        client iOS e Android
```

Le chiavi non fanno parte del bundle mobile. I client leggono esclusivamente
Supabase e non contattano mai i provider.

## Responsabilità

- `football-data`: competizioni, club, calendario, orari, risultati e
  classifiche non live. È predisposto l'adapter, ma resta disattivato finché il
  relativo secret server-side non viene configurato e collaudato su staging.
- `api-football`: catalogo giocatori, rose, formazioni, eventi e statistiche
  individuali. Il worker esistente usa attualmente `/players`, `/fixtures` e
  `/fixtures/players`.
- `Supabase`: identità canoniche, mapping, cache, budget, audit, conflitti,
  staging, validazione e pubblicazione autorevole.

## Budget

La policy è contenuta in `provider_quota_policies`, non nel client:

- API-Football: 100 unità/giorno;
- 20 unità riservate a P0/P1;
- P2/P3 vengono bloccate al raggiungimento del budget ordinario;
- la cache viene consultata prima di acquisire una quota;
- ogni tentativo esterno e ogni cache hit vengono registrati.

Il quota manager è fail-closed: policy assente, RPC assente o budget esaurito
impediscono la chiamata esterna.

## TTL iniziali

| Risorsa | Priorità | TTL |
|---|---:|---:|
| Catalogo giocatori | P2 | 24 ore |
| Calendario/lifecycle | P1 | 1 ora |
| Statistiche finali partita | P0 | 5 minuti |

Lo scheduler ridotto interroga il calendario una volta l'ora, il catalogo una
volta a settimana e le statistiche soltanto per partite finali senza fotografia
voti certificata. La migrazione 160 modifica esclusivamente cron già esistenti.

## Identità

`canonical_football_entities` assegna UUID LEGHEVO indipendenti dal provider.
`provider_entity_mappings` collega gli ID esterni. Trigger server-side creano
automaticamente mapping per nuovi giocatori, club, competizioni e partite.

Fusioni fra due provider non vengono mai eseguite usando soltanto il nome. I
casi ambigui devono entrare in `provider_identity_conflicts` e restare in
quarantena fino a verifica.

## Osservabilità

Il Centro Operativo legge `get_league_provider_budget_center_v1` e mostra:

- consumo e residuo giornaliero;
- riserva P0/P1;
- cache hit rate e chiamate evitate;
- retry, fallback, conflitti e worker attivi;
- picco giornaliero e previsione a 30 giorni.

Le funzioni tecniche `get_multi_provider_diagnostics_v1` e
`get_provider_cost_metrics_v1` sono riservate al service role.

## Attivazione football-data.org

Prima dell'attivazione servono:

1. secret server-side `FOOTBALL_DATA_API_KEY` su staging;
2. collaudo dei payload Serie A reali contro l'adapter;
3. mapping verificato dei club fra i due provider;
4. ingestion tramite lo staging atomico già esistente;
5. test di conflitto, fallback, quota esaurita e snapshot certificato;
6. solo dopo, promozione del calendario a provider primario.

La produzione resta esclusa fino a un'autorizzazione esplicita e a una nuova
release candidate validata.
