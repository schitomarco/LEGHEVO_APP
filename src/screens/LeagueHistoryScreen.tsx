import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useLeagueCupHistory } from '../hooks/useLeagueCupHistory';
import { useLeagueHistory } from '../hooks/useLeagueHistory';
import { useLeaguePlayoffHistory } from '../hooks/useLeaguePlayoffHistory';
import { useLeagueRecords } from '../hooks/useLeagueRecords';
import { useLeagueSuperCupHistory } from '../hooks/useLeagueSuperCupHistory';
import { useLeagueTrophyCabinet } from '../hooks/useLeagueTrophyCabinet';
import { colors, radius } from '../theme';
import type {
  LeagueCupHistorySeason,
  LeagueCupHistoryTitleLeader,
  LeagueCupManagerCareer,
  LeagueCupMatchRecord,
  LeagueHistoryPodiumEntry,
  LeagueHistorySeason,
  LeagueHistoryTitleLeader,
  LeagueManagerCareer,
  LeagueMatchRecord,
  LeaguePlayoffHistorySeason,
  LeaguePlayoffHistoryTitleLeader,
  LeaguePlayoffManagerCareer,
  LeagueSeasonRecord,
  LeagueSuperCupHistorySeason,
  LeagueSuperCupTitleLeader,
  LeagueSummary,
  LeagueTrophyLeader,
  LeagueTrophyTimelineEntry,
} from '../types';

type Props = {
  league: LeagueSummary | null;
  onBack: () => void;
  onOpenSeason: (leagueId: string) => void;
};

export function LeagueHistoryScreen({
  league,
  onBack,
  onOpenSeason,
}: Props) {
  const state = useLeagueHistory(
    league?.id ?? null,
    Boolean(league?.isDemo),
  );
  const recordsState = useLeagueRecords(
    league?.id ?? null,
    Boolean(league?.isDemo),
  );
  const cupHistoryState = useLeagueCupHistory(
    league?.id ?? null,
    Boolean(league?.isDemo),
  );
  const playoffHistoryState = useLeaguePlayoffHistory(
    league?.id ?? null,
    Boolean(league?.isDemo),
  );
  const superCupHistoryState = useLeagueSuperCupHistory(
    league?.id ?? null,
    Boolean(league?.isDemo),
  );
  const trophyCabinetState = useLeagueTrophyCabinet(
    league?.id ?? null,
    Boolean(league?.isDemo),
  );

  if (!league) {
    return (
      <View style={styles.centerRoot}>
        <Text style={styles.centerTitle}>Prima scegli una lega.</Text>
        <Pressable onPress={onBack} style={styles.retryButton}>
          <Text style={styles.retryButtonText}>TORNA ALLA LEGA</Text>
        </Pressable>
      </View>
    );
  }

  const history = state.history;
  const titleCount = history?.titleLeaders.reduce(
    (total, leader) => total + leader.titles,
    0,
  ) ?? 0;
  const isRefreshing =
    state.loading ||
    recordsState.loading ||
    cupHistoryState.loading ||
    playoffHistoryState.loading ||
    superCupHistoryState.loading ||
    trophyCabinetState.loading;

  return (
    <ScrollView
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
      style={styles.screen}
    >
      <View style={styles.header}>
        <Pressable onPress={onBack} style={styles.backButton}>
          <Text style={styles.backText}>‹</Text>
        </Pressable>
        <View style={styles.headerCopy}>
          <Text style={styles.eyebrow}>STORIA DELLA LEGA</Text>
          <Text numberOfLines={1} style={styles.title}>
            Albo, record e stagioni
          </Text>
        </View>
        <Pressable
          accessibilityLabel="Aggiorna la storia della lega"
          accessibilityState={{
            busy: isRefreshing,
            disabled: isRefreshing,
          }}
          disabled={isRefreshing}
          onPress={() => {
            void Promise.all([
              state.refresh(),
              recordsState.refresh(),
              cupHistoryState.refresh(),
              playoffHistoryState.refresh(),
              superCupHistoryState.refresh(),
              trophyCabinetState.refresh(),
            ]);
          }}
          style={[
            styles.reloadButton,
            isRefreshing && styles.reloadButtonDisabled,
          ]}
        >
          {isRefreshing ? (
            <ActivityIndicator color={colors.navy} size="small" />
          ) : (
            <Text style={styles.reloadText}>↻</Text>
          )}
        </Pressable>
      </View>

      {state.loading ? (
        <View style={styles.loadingCard}>
          <ActivityIndicator color={colors.lime} />
          <Text style={styles.loadingText}>Riapro tutti gli annali…</Text>
        </View>
      ) : state.error ? (
        <View style={styles.errorCard}>
          <Text style={styles.errorTitle}>Archivio indisponibile</Text>
          <Text style={styles.errorBody}>{state.error}</Text>
          <Pressable
            onPress={() => void state.refresh()}
            style={styles.retryButton}
          >
            <Text style={styles.retryButtonText}>RIPROVA</Text>
          </Pressable>
        </View>
      ) : history ? (
        <>
          <View style={styles.heroCard}>
            <Text style={styles.heroEyebrow}>ALBO STORICO</Text>
            <Text style={styles.heroTitle}>{history.leagueName}</Text>
            <Text style={styles.heroBody}>
              Ogni stagione resta consultabile. I verdetti, purtroppo, anche.
            </Text>
            <View style={styles.heroStats}>
              <HeroStat
                label="STAGIONI"
                value={String(history.totalSeasons)}
              />
              <HeroStat
                label="CONCLUSE"
                value={String(history.completedSeasons)}
              />
              <HeroStat label="TITOLI" value={String(titleCount)} />
            </View>
          </View>

          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Bacheca LEGHEVO</Text>
            <Text style={styles.sectionMeta}>TUTTI I TROFEI</Text>
          </View>

          {trophyCabinetState.loading ? (
            <View style={styles.recordsLoadingCard}>
              <ActivityIndicator color={colors.navy} />
              <Text style={styles.recordsLoadingText}>
                Lucido coppe e ricontrollo i nomi…
              </Text>
            </View>
          ) : trophyCabinetState.error ? (
            <View style={styles.emptyCard}>
              <Text style={styles.emptyTitle}>Bacheca non disponibile</Text>
              <Text style={styles.emptyBody}>
                {trophyCabinetState.error}
              </Text>
              <Pressable
                onPress={() => void trophyCabinetState.refresh()}
                style={styles.retryButton}
              >
                <Text style={styles.retryButtonText}>RIPROVA</Text>
              </Pressable>
            </View>
          ) : trophyCabinetState.cabinet ? (
            <>
              <View style={styles.trophyHeroCard}>
                <View style={styles.trophyHeroTop}>
                  <View style={styles.trophyMonogram}>
                    <Text style={styles.trophyMonogramText}>L</Text>
                  </View>
                  <View style={styles.trophyHeroCopy}>
                    <Text style={styles.heroEyebrow}>PALMARÈS ASSOLUTO</Text>
                    <Text style={styles.trophyHeroTitle}>
                      {trophyCabinetState.cabinet.totalTrophies}{' '}
                      {trophyCabinetState.cabinet.totalTrophies === 1
                        ? 'trofeo ufficiale'
                        : 'trofei ufficiali'}
                    </Text>
                    <Text style={styles.trophyHeroBody}>
                      {trophyCabinetState.cabinet.uniqueWinners}{' '}
                      {trophyCabinetState.cabinet.uniqueWinners === 1
                        ? 'manager vincitore'
                        : 'manager vincitori'}
                      {trophyCabinetState.cabinet.doubles > 0
                        ? ` · ${trophyCabinetState.cabinet.doubles} double`
                        : ''}
                    </Text>
                  </View>
                </View>
                <View style={styles.heroStats}>
                  <HeroStat
                    label="CAMPIONATI"
                    value={String(
                      trophyCabinetState.cabinet.leagueTitles,
                    )}
                  />
                  <HeroStat
                    label="COPPE"
                    value={String(trophyCabinetState.cabinet.cupTitles)}
                  />
                  <HeroStat
                    label="SUPERCOPPE"
                    value={String(
                      trophyCabinetState.cabinet.superCupTitles,
                    )}
                  />
                </View>
              </View>

              {trophyCabinetState.cabinet.leaders.length > 0 ? (
                <>
                  <View style={styles.subsectionHeader}>
                    <Text style={styles.subsectionTitle}>
                      Ranking dei trofei
                    </Text>
                    <Text style={styles.sectionMeta}>PALMARÈS MANAGER</Text>
                  </View>
                  <View style={styles.trophyLeaderList}>
                    {trophyCabinetState.cabinet.leaders.map(
                      (leader) => (
                        <TrophyLeaderCard
                          key={leader.managerId}
                          leader={leader}
                        />
                      ),
                    )}
                  </View>
                </>
              ) : (
                <View style={styles.emptyCard}>
                  <Text style={styles.emptyTitle}>
                    La bacheca aspetta il primo trofeo
                  </Text>
                  <Text style={styles.emptyBody}>
                    Entrano qui soltanto competizioni già concluse e
                    ufficializzate.
                  </Text>
                </View>
              )}

              {trophyCabinetState.cabinet.timeline.length > 0 ? (
                <>
                  <View style={styles.subsectionHeader}>
                    <Text style={styles.subsectionTitle}>
                      Cronologia dei titoli
                    </Text>
                    <Text style={styles.sectionMeta}>DAL PIÙ RECENTE</Text>
                  </View>
                  <View style={styles.trophyTimelineList}>
                    {trophyCabinetState.cabinet.timeline.map((entry) => (
                      <TrophyTimelineCard
                        entry={entry}
                        key={entry.id}
                        onOpen={() => onOpenSeason(entry.leagueId)}
                      />
                    ))}
                  </View>
                </>
              ) : null}
            </>
          ) : null}

          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Pluricampioni</Text>
            <Text style={styles.sectionMeta}>
              {history.titleLeaders.length > 0
                ? 'TITOLI PER MANAGER'
                : 'NESSUN VERDETTO'}
            </Text>
          </View>

          {history.titleLeaders.length > 0 ? (
            <View style={styles.leadersCard}>
              {history.titleLeaders.map((leader, index) => (
                <TitleLeaderRow
                  index={index}
                  key={leader.managerId || leader.managerName}
                  leader={leader}
                />
              ))}
            </View>
          ) : (
            <View style={styles.emptyCard}>
              <Text style={styles.emptyTitle}>
                Il primo campione deve ancora arrivare
              </Text>
              <Text style={styles.emptyBody}>
                La classifica finale entrerà qui dopo la chiusura ufficiale
                della stagione.
              </Text>
            </View>
          )}

          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Record della lega</Text>
            <Text style={styles.sectionMeta}>STAGIONI CONCLUSE</Text>
          </View>

          {recordsState.loading ? (
            <View style={styles.recordsLoadingCard}>
              <ActivityIndicator color={colors.navy} />
              <Text style={styles.recordsLoadingText}>
                Controllo chi può vantarsi davvero…
              </Text>
            </View>
          ) : recordsState.error ? (
            <View style={styles.emptyCard}>
              <Text style={styles.emptyTitle}>Record non disponibili</Text>
              <Text style={styles.emptyBody}>{recordsState.error}</Text>
              <Pressable
                onPress={() => void recordsState.refresh()}
                style={styles.retryButton}
              >
                <Text style={styles.retryButtonText}>RIPROVA</Text>
              </Pressable>
            </View>
          ) : recordsState.records &&
            recordsState.records.completedSeasons > 0 ? (
            <>
              <View style={styles.recordGrid}>
                {recordsState.records.seasonRecords.map((record) => (
                  <SeasonRecordCard key={record.key} record={record} />
                ))}
              </View>

              <View style={styles.matchRecordList}>
                {recordsState.records.matchRecords.map((record) => (
                  <MatchRecordCard key={record.key} record={record} />
                ))}
              </View>

              <View style={styles.sectionHeader}>
                <Text style={styles.sectionTitle}>Classifica carriera</Text>
                <Text style={styles.sectionMeta}>
                  {recordsState.records.completedSeasons}{' '}
                  {recordsState.records.completedSeasons === 1
                    ? 'STAGIONE'
                    : 'STAGIONI'}
                </Text>
              </View>

              <View style={styles.careerCard}>
                {recordsState.records.careerLeaders.map((career, index) => (
                  <CareerRow
                    career={career}
                    divider={index > 0}
                    key={career.managerId}
                  />
                ))}
              </View>
            </>
          ) : (
            <View style={styles.emptyCard}>
              <Text style={styles.emptyTitle}>
                I record aspettano la prima stagione
              </Text>
              <Text style={styles.emptyBody}>
                Entrano nell’archivio soltanto risultati e classifiche già
                congelati dalla chiusura ufficiale.
              </Text>
            </View>
          )}

          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Storia dei Playoff</Text>
            <Text style={styles.sectionMeta}>FASE FINALE SCUDETTO</Text>
          </View>

          {playoffHistoryState.loading ? (
            <View style={styles.recordsLoadingCard}>
              <ActivityIndicator color={colors.navy} />
              <Text style={styles.recordsLoadingText}>
                Ricostruisco tutte le fasi finali…
              </Text>
            </View>
          ) : playoffHistoryState.error ? (
            <View style={styles.emptyCard}>
              <Text style={styles.emptyTitle}>
                Storico Playoff non disponibile
              </Text>
              <Text style={styles.emptyBody}>
                {playoffHistoryState.error}
              </Text>
              <Pressable
                onPress={() => void playoffHistoryState.refresh()}
                style={styles.retryButton}
              >
                <Text style={styles.retryButtonText}>RIPROVA</Text>
              </Pressable>
            </View>
          ) : playoffHistoryState.history ? (
            <>
              <View style={styles.playoffHeroCard}>
                <Text style={styles.heroEyebrow}>ALBO PLAYOFF SCUDETTO</Text>
                <Text style={styles.heroTitle}>
                  La classifica apre la porta. Il tabellone decide.
                </Text>
                <Text style={styles.heroBody}>
                  Campioni, finalisti, teste di serie e record vengono
                  congelati soltanto dopo la finale ufficiale.
                </Text>
                <View style={styles.heroStats}>
                  <HeroStat
                    label="CONCLUSI"
                    value={String(
                      playoffHistoryState.history.completedPlayoffs,
                    )}
                  />
                  <HeroStat
                    label="IN CORSO"
                    value={String(
                      playoffHistoryState.history.activePlayoffs,
                    )}
                  />
                  <HeroStat
                    label="RIMONTE"
                    value={String(
                      playoffHistoryState.history.titleLeaders.reduce(
                        (total, leader) =>
                          total + leader.lowerSeedTitles,
                        0,
                      ),
                    )}
                  />
                </View>
              </View>

              {playoffHistoryState.history.titleLeaders.length > 0 ? (
                <>
                  <View style={styles.subsectionHeader}>
                    <Text style={styles.subsectionTitle}>
                      Campioni e finalisti
                    </Text>
                    <Text style={styles.sectionMeta}>PER MANAGER</Text>
                  </View>
                  <View style={styles.leadersCard}>
                    {playoffHistoryState.history.titleLeaders.map(
                      (leader, index) => (
                        <PlayoffTitleLeaderRow
                          index={index}
                          key={leader.managerId}
                          leader={leader}
                        />
                      ),
                    )}
                  </View>
                </>
              ) : (
                <View style={styles.cupEmptyCard}>
                  <Text style={styles.emptyTitle}>
                    I Playoff aspettano il primo verdetto
                  </Text>
                  <Text style={styles.emptyBody}>
                    Le fasi finali configurate o in corso restano visibili,
                    ma entrano nei record soltanto dopo la finale.
                  </Text>
                </View>
              )}

              {playoffHistoryState.history.seasons.some(
                (season) => season.playoffExists,
              ) ? (
                <>
                  <View style={styles.subsectionHeader}>
                    <Text style={styles.subsectionTitle}>
                      Fasi finali per stagione
                    </Text>
                    <Text style={styles.sectionMeta}>DALLA PIÙ RECENTE</Text>
                  </View>
                  <View style={styles.cupSeasonList}>
                    {playoffHistoryState.history.seasons
                      .filter((season) => season.playoffExists)
                      .map((season) => (
                        <PlayoffSeasonCard
                          key={season.leagueId}
                          onOpen={() => onOpenSeason(season.leagueId)}
                          season={season}
                        />
                      ))}
                  </View>
                </>
              ) : null}

              {playoffHistoryState.history.matchRecords.length > 0 ? (
                <>
                  <View style={styles.subsectionHeader}>
                    <Text style={styles.subsectionTitle}>
                      Record dei Playoff
                    </Text>
                    <Text style={styles.sectionMeta}>SOLE FASI CONCLUSE</Text>
                  </View>
                  <View style={styles.matchRecordList}>
                    {playoffHistoryState.history.matchRecords.map(
                      (record) => (
                        <PlayoffMatchRecordCard
                          key={record.key}
                          record={record}
                        />
                      ),
                    )}
                  </View>
                </>
              ) : null}

              {playoffHistoryState.history.careerLeaders.length > 0 ? (
                <>
                  <View style={styles.subsectionHeader}>
                    <Text style={styles.subsectionTitle}>
                      Carriera nei Playoff
                    </Text>
                    <Text style={styles.sectionMeta}>
                      RENDIMENTO NEL TABELLONE
                    </Text>
                  </View>
                  <View style={styles.careerCard}>
                    {playoffHistoryState.history.careerLeaders.map(
                      (career, index) => (
                        <PlayoffCareerRow
                          career={career}
                          divider={index > 0}
                          key={career.managerId}
                        />
                      ),
                    )}
                  </View>
                </>
              ) : null}
            </>
          ) : null}

          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Albo della Coppa</Text>
            <Text style={styles.sectionMeta}>ELIMINAZIONE DIRETTA</Text>
          </View>

          {cupHistoryState.loading ? (
            <View style={styles.recordsLoadingCard}>
              <ActivityIndicator color={colors.navy} />
              <Text style={styles.recordsLoadingText}>
                Riapro tutti i tabelloni…
              </Text>
            </View>
          ) : cupHistoryState.error ? (
            <View style={styles.emptyCard}>
              <Text style={styles.emptyTitle}>Albo Coppa non disponibile</Text>
              <Text style={styles.emptyBody}>{cupHistoryState.error}</Text>
              <Pressable
                onPress={() => void cupHistoryState.refresh()}
                style={styles.retryButton}
              >
                <Text style={styles.retryButtonText}>RIPROVA</Text>
              </Pressable>
            </View>
          ) : cupHistoryState.history ? (
            <>
              <View style={styles.cupHeroCard}>
                <Text style={styles.heroEyebrow}>STORIA DELLA COPPA</Text>
                <Text style={styles.heroTitle}>
                  Un trofeo, nessun appello.
                </Text>
                <Text style={styles.heroBody}>
                  Campioni, finalisti e record restano separati dal campionato
                  e vengono congelati soltanto a Coppa conclusa.
                </Text>
                <View style={styles.heroStats}>
                  <HeroStat
                    label="COPPE CONCLUSE"
                    value={String(cupHistoryState.history.completedCups)}
                  />
                  <HeroStat
                    label="IN CORSO"
                    value={String(cupHistoryState.history.activeCups)}
                  />
                  <HeroStat
                    label="VINCITORI"
                    value={String(
                      cupHistoryState.history.titleLeaders.filter(
                        (leader) => leader.titles > 0,
                      ).length,
                    )}
                  />
                </View>
              </View>

              {cupHistoryState.history.titleLeaders.length > 0 ? (
                <>
                  <View style={styles.subsectionHeader}>
                    <Text style={styles.subsectionTitle}>Titoli e finali</Text>
                    <Text style={styles.sectionMeta}>PER MANAGER</Text>
                  </View>
                  <View style={styles.leadersCard}>
                    {cupHistoryState.history.titleLeaders.map(
                      (leader, index) => (
                        <CupTitleLeaderRow
                          index={index}
                          key={leader.managerId}
                          leader={leader}
                        />
                      ),
                    )}
                  </View>
                </>
              ) : (
                <View style={styles.cupEmptyCard}>
                  <Text style={styles.emptyTitle}>
                    La Coppa aspetta il primo campione
                  </Text>
                  <Text style={styles.emptyBody}>
                    Una competizione in corso resta visibile, ma entra nei
                    record definitivi soltanto dopo la finale ufficiale.
                  </Text>
                </View>
              )}

              {cupHistoryState.history.seasons.some(
                (season) => season.cupExists,
              ) ? (
                <>
                  <View style={styles.subsectionHeader}>
                    <Text style={styles.subsectionTitle}>Coppe per stagione</Text>
                    <Text style={styles.sectionMeta}>DALLA PIÙ RECENTE</Text>
                  </View>
                  <View style={styles.cupSeasonList}>
                    {cupHistoryState.history.seasons
                      .filter((season) => season.cupExists)
                      .map((season) => (
                        <CupSeasonCard
                          key={season.leagueId}
                          onOpen={() => onOpenSeason(season.leagueId)}
                          season={season}
                        />
                      ))}
                  </View>
                </>
              ) : null}

              {cupHistoryState.history.matchRecords.length > 0 ? (
                <>
                  <View style={styles.subsectionHeader}>
                    <Text style={styles.subsectionTitle}>Record della Coppa</Text>
                    <Text style={styles.sectionMeta}>SOLE COPPE CONCLUSE</Text>
                  </View>
                  <View style={styles.matchRecordList}>
                    {cupHistoryState.history.matchRecords.map((record) => (
                      <CupMatchRecordCard key={record.key} record={record} />
                    ))}
                  </View>
                </>
              ) : null}

              {cupHistoryState.history.careerLeaders.length > 0 ? (
                <>
                  <View style={styles.subsectionHeader}>
                    <Text style={styles.subsectionTitle}>Carriera in Coppa</Text>
                    <Text style={styles.sectionMeta}>RENDIMENTO NEI TURNI</Text>
                  </View>
                  <View style={styles.careerCard}>
                    {cupHistoryState.history.careerLeaders.map(
                      (career, index) => (
                        <CupCareerRow
                          career={career}
                          divider={index > 0}
                          key={career.managerId}
                        />
                      ),
                    )}
                  </View>
                </>
              ) : null}
            </>
          ) : null}

          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Albo della Supercoppa</Text>
            <Text style={styles.sectionMeta}>TROFEO TRA STAGIONI</Text>
          </View>

          {superCupHistoryState.loading ? (
            <View style={styles.recordsLoadingCard}>
              <ActivityIndicator color={colors.navy} />
              <Text style={styles.recordsLoadingText}>
                Recupero tutte le finali…
              </Text>
            </View>
          ) : superCupHistoryState.error ? (
            <View style={styles.emptyCard}>
              <Text style={styles.emptyTitle}>
                Albo Supercoppa non disponibile
              </Text>
              <Text style={styles.emptyBody}>
                {superCupHistoryState.error}
              </Text>
              <Pressable
                onPress={() => void superCupHistoryState.refresh()}
                style={styles.retryButton}
              >
                <Text style={styles.retryButtonText}>RIPROVA</Text>
              </Pressable>
            </View>
          ) : superCupHistoryState.history ? (
            <>
              <View style={styles.superCupHeroCard}>
                <Text style={styles.heroEyebrow}>STORIA DELLA SUPERCOPPA</Text>
                <Text style={styles.heroTitle}>
                  I vincitori tornano in campo.
                </Text>
                <Text style={styles.heroBody}>
                  Ogni finale collega i titoli della stagione precedente alla
                  nuova annata e conserva un verdetto separato.
                </Text>
                <View style={styles.heroStats}>
                  <HeroStat
                    label="CONCLUSE"
                    value={String(
                      superCupHistoryState.history.completedSuperCups,
                    )}
                  />
                  <HeroStat
                    label="IN CORSO"
                    value={String(
                      superCupHistoryState.history.activeSuperCups,
                    )}
                  />
                  <HeroStat
                    label="VINCITORI"
                    value={String(
                      superCupHistoryState.history.titleLeaders.length,
                    )}
                  />
                </View>
              </View>

              {superCupHistoryState.history.titleLeaders.length > 0 ? (
                <>
                  <View style={styles.subsectionHeader}>
                    <Text style={styles.subsectionTitle}>
                      Re della Supercoppa
                    </Text>
                    <Text style={styles.sectionMeta}>TITOLI PER MANAGER</Text>
                  </View>
                  <View style={styles.leadersCard}>
                    {superCupHistoryState.history.titleLeaders.map(
                      (leader, index) => (
                        <SuperCupTitleLeaderRow
                          divider={index > 0}
                          key={leader.managerId}
                          leader={leader}
                        />
                      ),
                    )}
                  </View>
                </>
              ) : null}

              {superCupHistoryState.history.seasons.some(
                (season) => season.superCupExists,
              ) ? (
                <>
                  <View style={styles.subsectionHeader}>
                    <Text style={styles.subsectionTitle}>
                      Finali per stagione
                    </Text>
                    <Text style={styles.sectionMeta}>DALLA PIÙ RECENTE</Text>
                  </View>
                  <View style={styles.cupSeasonList}>
                    {superCupHistoryState.history.seasons
                      .filter((season) => season.superCupExists)
                      .map((season) => (
                        <SuperCupSeasonCard
                          key={season.leagueId}
                          onOpen={() => onOpenSeason(season.leagueId)}
                          season={season}
                        />
                      ))}
                  </View>
                </>
              ) : (
                <View style={styles.emptyCard}>
                  <Text style={styles.emptyTitle}>
                    La prima Supercoppa deve ancora arrivare
                  </Text>
                  <Text style={styles.emptyBody}>
                    Diventa disponibile dalla seconda stagione, dopo una
                    Coppa e un campionato conclusi.
                  </Text>
                </View>
              )}
            </>
          ) : null}

          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Tutte le stagioni</Text>
            <Text style={styles.sectionMeta}>DALLA PIÙ RECENTE</Text>
          </View>

          <View style={styles.seasonList}>
            {history.seasons.map((season) => (
              <SeasonCard
                championViaPlayoffs={Boolean(
                  playoffHistoryState.history?.seasons.some(
                    (playoffSeason) =>
                      playoffSeason.leagueId === season.leagueId &&
                      playoffSeason.playoffStatus === 'completed',
                  ),
                )}
                key={season.leagueId}
                onOpen={() => onOpenSeason(season.leagueId)}
                season={season}
              />
            ))}
          </View>
        </>
      ) : null}
    </ScrollView>
  );
}

function SeasonRecordCard({ record }: { record: LeagueSeasonRecord }) {
  const presentation = seasonRecordPresentation(record);
  return (
    <View style={styles.recordCard}>
      <Text style={styles.recordLabel}>{presentation.label}</Text>
      <Text numberOfLines={1} style={styles.recordValue}>
        {presentation.value}
      </Text>
      <Text numberOfLines={1} style={styles.recordTeam}>
        {record.teamName}
      </Text>
      <Text numberOfLines={1} style={styles.recordMeta}>
        {record.managerName} · {record.season ?? '—'}
      </Text>
    </View>
  );
}

function MatchRecordCard({ record }: { record: LeagueMatchRecord }) {
  const presentation = matchRecordPresentation(record);
  return (
    <View style={styles.matchRecordCard}>
      <View style={styles.matchRecordTop}>
        <View style={styles.matchRecordCopy}>
          <Text style={styles.matchRecordLabel}>{presentation.label}</Text>
          <Text numberOfLines={1} style={styles.matchRecordTeam}>
            {record.teamName}
          </Text>
          <Text numberOfLines={1} style={styles.matchRecordManager}>
            {record.managerName} · {record.season ?? '—'} · GIORNATA{' '}
            {record.matchdayNumber}
          </Text>
        </View>
        <Text style={styles.matchRecordValue}>{presentation.value}</Text>
      </View>
      <View style={styles.matchScoreRow}>
        <Text numberOfLines={1} style={styles.matchScoreTeam}>
          {record.homeTeamName}
        </Text>
        <Text style={styles.matchScore}>
          {record.homeGoals}–{record.awayGoals}
        </Text>
        <Text
          numberOfLines={1}
          style={[styles.matchScoreTeam, styles.matchScoreTeamAway]}
        >
          {record.awayTeamName}
        </Text>
      </View>
    </View>
  );
}

function CareerRow({
  career,
  divider,
}: {
  career: LeagueManagerCareer;
  divider: boolean;
}) {
  return (
    <View style={[styles.careerRow, divider && styles.rowDivider]}>
      <View style={styles.careerRank}>
        <Text style={styles.careerRankText}>{career.rank}</Text>
      </View>
      <View style={styles.careerCopy}>
        <Text numberOfLines={1} style={styles.careerName}>
          {career.managerName}
        </Text>
        <Text numberOfLines={1} style={styles.careerTeams}>
          {career.teamNames.join(' · ')}
        </Text>
        <Text style={styles.careerMeta}>
          {career.seasons} ST · {career.won} V · {formatNumber(career.winRate)}%
        </Text>
      </View>
      <View style={styles.careerStats}>
        <Text style={styles.careerPoints}>{career.leaguePoints}</Text>
        <Text style={styles.careerPointsLabel}>PUNTI</Text>
        <Text style={styles.careerHonours}>
          {career.titles} T · {career.podiums} P
        </Text>
      </View>
    </View>
  );
}

function PlayoffTitleLeaderRow({
  index,
  leader,
}: {
  index: number;
  leader: LeaguePlayoffHistoryTitleLeader;
}) {
  return (
    <View style={[styles.leaderRow, index > 0 && styles.rowDivider]}>
      <View style={styles.playoffLeaderPosition}>
        <Text style={styles.playoffLeaderPositionText}>{index + 1}</Text>
      </View>
      <View style={styles.leaderCopy}>
        <Text numberOfLines={1} style={styles.leaderName}>
          {leader.managerName}
        </Text>
        <Text numberOfLines={1} style={styles.leaderTeams}>
          {leader.teamNames.join(' · ')}
        </Text>
        <Text style={styles.cupLeaderMeta}>
          {leader.finals} {leader.finals === 1 ? 'FINALE' : 'FINALI'}
          {leader.lowerSeedTitles > 0
            ? ` · ${leader.lowerSeedTitles} DA TESTA DI SERIE INFERIORE`
            : ''}
        </Text>
      </View>
      <View style={styles.cupTitleBadge}>
        <Text style={styles.cupTitleBadgeValue}>{leader.titles}</Text>
        <Text style={styles.cupTitleBadgeLabel}>
          {leader.titles === 1 ? 'TITOLO' : 'TITOLI'}
        </Text>
      </View>
    </View>
  );
}

function PlayoffSeasonCard({
  onOpen,
  season,
}: {
  onOpen: () => void;
  season: LeaguePlayoffHistorySeason;
}) {
  const inProgress =
    season.playoffStatus === 'active' ||
    season.playoffStatus === 'configured';
  const progress =
    season.totalTieCount > 0
      ? Math.min(
          100,
          Math.round(
            (season.officialTieCount / season.totalTieCount) * 100,
          ),
        )
      : 0;

  return (
    <View
      style={[
        styles.cupSeasonCard,
        inProgress && styles.cupSeasonCardActive,
      ]}
    >
      <View style={styles.cupSeasonTop}>
        <View>
          <Text
            style={[
              styles.cupSeasonEyebrow,
              inProgress && styles.latestSeasonMuted,
            ]}
          >
            {season.playoffStatus === 'completed'
              ? 'PLAYOFF CONCLUSI'
              : season.playoffStatus === 'active'
                ? 'PLAYOFF IN CORSO'
                : 'PLAYOFF CONFIGURATI'}
          </Text>
          <Text
            style={[
              styles.cupSeasonYear,
              inProgress && styles.latestSeasonText,
            ]}
          >
            {season.season ?? '—'}
          </Text>
        </View>
        <View
          style={[
            styles.cupRoundPill,
            inProgress && styles.latestStatusPill,
          ]}
        >
          <Text style={styles.statusPillText}>
            TOP {season.participantCount}
          </Text>
        </View>
      </View>

      {season.champion ? (
        <View style={styles.cupVerdict}>
          <View style={styles.playoffTrophyMark}>
            <Text style={styles.playoffTrophyMarkText}>P</Text>
          </View>
          <View style={styles.cupVerdictCopy}>
            <Text style={styles.cupVerdictLabel}>CAMPIONE LEGHEVO</Text>
            <Text numberOfLines={1} style={styles.cupVerdictTeam}>
              {season.champion.teamName}
            </Text>
            <Text numberOfLines={1} style={styles.cupVerdictManager}>
              {season.champion.managerName}
              {season.champion.seed
                ? ` · TESTA DI SERIE ${season.champion.seed}`
                : ''}
            </Text>
            {season.runnerUp ? (
              <Text numberOfLines={1} style={styles.cupRunnerUp}>
                FINALISTA · {season.runnerUp.teamName}
              </Text>
            ) : null}
            {season.regularSeasonLeader &&
            season.regularSeasonLeader.teamId !==
              season.champion.teamId ? (
              <Text numberOfLines={1} style={styles.playoffRegularLeader}>
                1ª REGULAR SEASON ·{' '}
                {season.regularSeasonLeader.teamName}
              </Text>
            ) : null}
          </View>
        </View>
      ) : season.playoffStatus === 'configured' ? (
        <View style={styles.cupProgressBlock}>
          <Text style={styles.latestSeasonText}>
            Il tabellone nascerà dopo l’ultimo risultato della regular
            season.
          </Text>
          <Text style={styles.cupProgressNote}>
            {season.roundCount} turni previsti · Top{' '}
            {season.participantCount}
          </Text>
        </View>
      ) : (
        <View style={styles.cupProgressBlock}>
          <View style={styles.progressHeading}>
            <Text style={styles.latestSeasonMuted}>SFIDE UFFICIALI</Text>
            <Text style={styles.latestSeasonText}>
              {season.officialTieCount}/{season.totalTieCount}
            </Text>
          </View>
          <View style={styles.cupProgressTrack}>
            <View
              style={[styles.cupProgressFill, { width: `${progress}%` }]}
            />
          </View>
          <Text style={styles.cupProgressNote}>
            {progress}% del tabellone ufficializzato
          </Text>
        </View>
      )}

      <View style={styles.cupSeasonFooter}>
        <Text
          style={[
            styles.cupSeasonDate,
            inProgress && styles.latestSeasonMuted,
          ]}
        >
          {season.completedAt
            ? `FINALE ${formatDate(season.completedAt)}`
            : `${season.currentRound}/${season.roundCount} TURNO`}
        </Text>
        <Pressable onPress={onOpen} style={styles.openButton}>
          <Text style={styles.openButtonText}>APRI STAGIONE →</Text>
        </Pressable>
      </View>
    </View>
  );
}

function PlayoffMatchRecordCard({
  record,
}: {
  record: LeagueCupMatchRecord;
}) {
  const presentation = playoffMatchRecordPresentation(record);
  return (
    <View style={styles.playoffRecordCard}>
      <View style={styles.matchRecordTop}>
        <View style={styles.matchRecordCopy}>
          <Text style={styles.cupRecordLabel}>{presentation.label}</Text>
          <Text numberOfLines={1} style={styles.cupRecordTeam}>
            {record.teamName}
          </Text>
          <Text numberOfLines={1} style={styles.cupRecordMeta}>
            {record.managerName} · {record.season ?? '—'} ·{' '}
            {record.roundName.toUpperCase()}
          </Text>
        </View>
        <Text style={styles.cupRecordValue}>{presentation.value}</Text>
      </View>
      <View style={styles.cupScoreRow}>
        <Text numberOfLines={1} style={styles.cupScoreTeam}>
          {record.homeTeamName}
        </Text>
        <Text style={styles.cupScore}>
          {record.homeGoals}–{record.awayGoals}
        </Text>
        <Text
          numberOfLines={1}
          style={[styles.cupScoreTeam, styles.matchScoreTeamAway]}
        >
          {record.awayTeamName}
        </Text>
      </View>
    </View>
  );
}

function PlayoffCareerRow({
  career,
  divider,
}: {
  career: LeaguePlayoffManagerCareer;
  divider: boolean;
}) {
  return (
    <View style={[styles.careerRow, divider && styles.rowDivider]}>
      <View style={styles.playoffCareerRank}>
        <Text style={styles.playoffCareerRankText}>{career.rank}</Text>
      </View>
      <View style={styles.careerCopy}>
        <Text numberOfLines={1} style={styles.careerName}>
          {career.managerName}
        </Text>
        <Text numberOfLines={1} style={styles.careerTeams}>
          {career.teamNames.join(' · ')}
        </Text>
        <Text style={styles.careerMeta}>
          {career.participations} PLAYOFF · {career.tiesWon}/
          {career.tiesPlayed} SFIDE · {formatNumber(career.winRate)}%
        </Text>
      </View>
      <View style={styles.careerStats}>
        <Text style={styles.playoffCareerValue}>{career.titles}</Text>
        <Text style={styles.careerPointsLabel}>TITOLI</Text>
        <Text style={styles.careerHonours}>{career.finals} FINALI</Text>
      </View>
    </View>
  );
}

function CupTitleLeaderRow({
  index,
  leader,
}: {
  index: number;
  leader: LeagueCupHistoryTitleLeader;
}) {
  return (
    <View style={[styles.leaderRow, index > 0 && styles.rowDivider]}>
      <View style={styles.cupLeaderPosition}>
        <Text style={styles.cupLeaderPositionText}>{index + 1}</Text>
      </View>
      <View style={styles.leaderCopy}>
        <Text numberOfLines={1} style={styles.leaderName}>
          {leader.managerName}
        </Text>
        <Text numberOfLines={1} style={styles.leaderTeams}>
          {leader.teamNames.join(' · ')}
        </Text>
        <Text style={styles.cupLeaderMeta}>
          {leader.finals} {leader.finals === 1 ? 'FINALE' : 'FINALI'} ·{' '}
          {leader.seasons.join(' · ')}
        </Text>
      </View>
      <View style={styles.cupTitleBadge}>
        <Text style={styles.cupTitleBadgeValue}>{leader.titles}</Text>
        <Text style={styles.cupTitleBadgeLabel}>
          {leader.titles === 1 ? 'COPPA' : 'COPPE'}
        </Text>
      </View>
    </View>
  );
}

function CupSeasonCard({
  onOpen,
  season,
}: {
  onOpen: () => void;
  season: LeagueCupHistorySeason;
}) {
  const progress =
    season.totalTieCount > 0
      ? Math.min(
          100,
          Math.round(
            (season.officialTieCount / season.totalTieCount) * 100,
          ),
        )
      : 0;

  return (
    <View
      style={[
        styles.cupSeasonCard,
        season.cupStatus === 'active' && styles.cupSeasonCardActive,
      ]}
    >
      <View style={styles.cupSeasonTop}>
        <View>
          <Text
            style={[
              styles.cupSeasonEyebrow,
              season.cupStatus === 'active' && styles.latestSeasonMuted,
            ]}
          >
            {season.cupStatus === 'completed'
              ? 'COPPA CONCLUSA'
              : 'COPPA IN CORSO'}
          </Text>
          <Text
            style={[
              styles.cupSeasonYear,
              season.cupStatus === 'active' && styles.latestSeasonText,
            ]}
          >
            {season.season ?? '—'}
          </Text>
        </View>
        <View
          style={[
            styles.cupRoundPill,
            season.cupStatus === 'active' && styles.latestStatusPill,
          ]}
        >
          <Text style={styles.statusPillText}>
            {season.cupStatus === 'completed'
              ? `${season.roundCount}/${season.roundCount} TURNI`
              : `${season.currentRound}/${season.roundCount} TURNO`}
          </Text>
        </View>
      </View>

      {season.champion ? (
        <View style={styles.cupVerdict}>
          <View style={styles.cupTrophyMark}>
            <Text style={styles.cupTrophyMarkText}>C</Text>
          </View>
          <View style={styles.cupVerdictCopy}>
            <Text style={styles.cupVerdictLabel}>CAMPIONE DELLA COPPA</Text>
            <Text numberOfLines={1} style={styles.cupVerdictTeam}>
              {season.champion.teamName}
            </Text>
            <Text numberOfLines={1} style={styles.cupVerdictManager}>
              {season.champion.managerName}
            </Text>
            {season.runnerUp ? (
              <Text numberOfLines={1} style={styles.cupRunnerUp}>
                FINALISTA · {season.runnerUp.teamName}
              </Text>
            ) : null}
          </View>
        </View>
      ) : (
        <View style={styles.cupProgressBlock}>
          <View style={styles.progressHeading}>
            <Text style={styles.latestSeasonMuted}>SFIDE UFFICIALI</Text>
            <Text style={styles.latestSeasonText}>
              {season.officialTieCount}/{season.totalTieCount}
            </Text>
          </View>
          <View style={styles.cupProgressTrack}>
            <View
              style={[styles.cupProgressFill, { width: `${progress}%` }]}
            />
          </View>
          <Text style={styles.cupProgressNote}>
            {progress}% del tabellone ufficializzato
          </Text>
        </View>
      )}

      <View style={styles.cupSeasonFooter}>
        <Text
          style={[
            styles.cupSeasonDate,
            season.cupStatus === 'active' && styles.latestSeasonMuted,
          ]}
        >
          {season.completedAt
            ? `FINALE ${formatDate(season.completedAt)}`
            : `${season.teamCount} SQUADRE`}
        </Text>
        <Pressable onPress={onOpen} style={styles.openButton}>
          <Text style={styles.openButtonText}>APRI STAGIONE →</Text>
        </Pressable>
      </View>
    </View>
  );
}

function CupMatchRecordCard({
  record,
}: {
  record: LeagueCupMatchRecord;
}) {
  const presentation = cupMatchRecordPresentation(record);
  return (
    <View style={styles.cupRecordCard}>
      <View style={styles.matchRecordTop}>
        <View style={styles.matchRecordCopy}>
          <Text style={styles.cupRecordLabel}>{presentation.label}</Text>
          <Text numberOfLines={1} style={styles.cupRecordTeam}>
            {record.teamName}
          </Text>
          <Text numberOfLines={1} style={styles.cupRecordMeta}>
            {record.managerName} · {record.season ?? '—'} ·{' '}
            {record.roundName.toUpperCase()}
          </Text>
        </View>
        <Text style={styles.cupRecordValue}>{presentation.value}</Text>
      </View>
      <View style={styles.cupScoreRow}>
        <Text numberOfLines={1} style={styles.cupScoreTeam}>
          {record.homeTeamName}
        </Text>
        <Text style={styles.cupScore}>
          {record.homeGoals}–{record.awayGoals}
        </Text>
        <Text
          numberOfLines={1}
          style={[styles.cupScoreTeam, styles.matchScoreTeamAway]}
        >
          {record.awayTeamName}
        </Text>
      </View>
    </View>
  );
}

function CupCareerRow({
  career,
  divider,
}: {
  career: LeagueCupManagerCareer;
  divider: boolean;
}) {
  return (
    <View style={[styles.careerRow, divider && styles.rowDivider]}>
      <View style={styles.cupCareerRank}>
        <Text style={styles.cupCareerRankText}>{career.rank}</Text>
      </View>
      <View style={styles.careerCopy}>
        <Text numberOfLines={1} style={styles.careerName}>
          {career.managerName}
        </Text>
        <Text numberOfLines={1} style={styles.careerTeams}>
          {career.teamNames.join(' · ')}
        </Text>
        <Text style={styles.careerMeta}>
          {career.participations} COPPE · {career.tiesWon}/
          {career.tiesPlayed} SFIDE · {formatNumber(career.winRate)}%
        </Text>
      </View>
      <View style={styles.careerStats}>
        <Text style={styles.cupCareerValue}>{career.titles}</Text>
        <Text style={styles.careerPointsLabel}>TITOLI</Text>
        <Text style={styles.careerHonours}>{career.finals} FINALI</Text>
      </View>
    </View>
  );
}

function SuperCupTitleLeaderRow({
  divider,
  leader,
}: {
  divider: boolean;
  leader: LeagueSuperCupTitleLeader;
}) {
  return (
    <View style={[styles.leaderRow, divider && styles.rowDivider]}>
      <View style={styles.superCupLeaderPosition}>
        <Text style={styles.superCupLeaderPositionText}>{leader.rank}</Text>
      </View>
      <View style={styles.leaderCopy}>
        <Text numberOfLines={1} style={styles.leaderName}>
          {leader.managerName}
        </Text>
        <Text numberOfLines={1} style={styles.leaderTeams}>
          {leader.teamNames.join(' · ')}
        </Text>
      </View>
      <View style={styles.titleBadge}>
        <Text style={styles.superCupTitleValue}>{leader.titles}</Text>
        <Text style={styles.titleBadgeLabel}>
          {leader.titles === 1 ? 'TITOLO' : 'TITOLI'}
        </Text>
      </View>
    </View>
  );
}

function SuperCupSeasonCard({
  onOpen,
  season,
}: {
  onOpen: () => void;
  season: LeagueSuperCupHistorySeason;
}) {
  const active = season.superCupStatus === 'active';
  return (
    <View
      style={[
        styles.cupSeasonCard,
        active && styles.superCupSeasonCardActive,
      ]}
    >
      <View style={styles.cupSeasonTop}>
        <View>
          <Text
            style={[
              styles.cupSeasonEyebrow,
              active && styles.latestSeasonMuted,
            ]}
          >
            {active ? 'FINALE PROGRAMMATA' : 'SUPERCOPPA CONCLUSA'}
          </Text>
          <Text
            style={[
              styles.cupSeasonYear,
              active && styles.latestSeasonText,
            ]}
          >
            {season.season ?? '—'}
          </Text>
        </View>
        <View
          style={[
            styles.cupRoundPill,
            active && styles.superCupStatusPill,
          ]}
        >
          <Text style={styles.statusPillText}>
            GIORNATA {season.matchdayNumber || '—'}
          </Text>
        </View>
      </View>

      {season.winner ? (
        <View style={styles.cupVerdict}>
          <View style={styles.superCupTrophyMark}>
            <Text style={styles.superCupTrophyMarkText}>S</Text>
          </View>
          <View style={styles.cupVerdictCopy}>
            <Text style={styles.cupVerdictLabel}>
              VINCITORE DELLA SUPERCOPPA
            </Text>
            <Text numberOfLines={1} style={styles.cupVerdictTeam}>
              {season.winner.teamName}
            </Text>
            <Text numberOfLines={1} style={styles.cupVerdictManager}>
              {season.winner.managerName}
            </Text>
            {season.runnerUp ? (
              <Text numberOfLines={1} style={styles.cupRunnerUp}>
                FINALISTA · {season.runnerUp.teamName}
              </Text>
            ) : null}
          </View>
        </View>
      ) : (
        <View style={styles.superCupPairing}>
          <View style={styles.superCupPairingTeam}>
            <Text style={styles.superCupPairingLabel}>CAMPIONE</Text>
            <Text numberOfLines={1} style={styles.superCupPairingName}>
              {season.leagueChampion?.teamName ?? '—'}
            </Text>
          </View>
          <Text style={styles.superCupPairingVs}>VS</Text>
          <View style={styles.superCupPairingTeamAway}>
            <Text style={styles.superCupPairingLabel}>
              {season.challengerQualification === 'cup_runner_up'
                ? 'FINALISTA COPPA'
                : 'VINCITORE COPPA'}
            </Text>
            <Text
              numberOfLines={1}
              style={styles.superCupPairingNameAway}
            >
              {season.challenger?.teamName ?? '—'}
            </Text>
          </View>
        </View>
      )}

      <View style={styles.cupSeasonFooter}>
        <Text
          style={[
            styles.cupSeasonDate,
            active && styles.latestSeasonMuted,
          ]}
        >
          {season.completedAt
            ? `FINALE ${formatDate(season.completedAt)}`
            : `TITOLI ${season.sourceSeason ?? 'PRECEDENTI'}`}
        </Text>
        <Pressable onPress={onOpen} style={styles.openButton}>
          <Text style={styles.openButtonText}>APRI STAGIONE →</Text>
        </Pressable>
      </View>
    </View>
  );
}

function TrophyLeaderCard({ leader }: { leader: LeagueTrophyLeader }) {
  return (
    <View style={styles.trophyLeaderCard}>
      <View style={styles.trophyLeaderTop}>
        <View style={styles.trophyLeaderRank}>
          <Text style={styles.trophyLeaderRankText}>{leader.rank}</Text>
        </View>
        <View style={styles.trophyLeaderCopy}>
          <Text numberOfLines={1} style={styles.trophyLeaderName}>
            {leader.managerName}
          </Text>
          <Text numberOfLines={1} style={styles.trophyLeaderTeams}>
            {leader.teamNames.join(' · ')}
          </Text>
        </View>
        <View style={styles.trophyLeaderTotal}>
          <Text style={styles.trophyLeaderTotalValue}>
            {leader.totalTrophies}
          </Text>
          <Text style={styles.trophyLeaderTotalLabel}>TROFEI</Text>
        </View>
      </View>
      <View style={styles.trophyBreakdown}>
        <TrophyBreakdownStat
          label="CAMP."
          value={leader.leagueTitles}
        />
        <TrophyBreakdownStat label="COPPE" value={leader.cupTitles} />
        <TrophyBreakdownStat
          label="SUPER"
          value={leader.superCupTitles}
        />
        <TrophyBreakdownStat label="DOUBLE" value={leader.doubles} />
      </View>
      <Text style={styles.trophyLeaderMeta}>
        {leader.leaguePodiums} PODI · {leader.cupFinals} FINALI COPPA ·{' '}
        {leader.superCupFinals} FINALI SUPERCOPPA
      </Text>
    </View>
  );
}

function TrophyBreakdownStat({
  label,
  value,
}: {
  label: string;
  value: number;
}) {
  return (
    <View style={styles.trophyBreakdownStat}>
      <Text style={styles.trophyBreakdownValue}>{value}</Text>
      <Text style={styles.trophyBreakdownLabel}>{label}</Text>
    </View>
  );
}

function TrophyTimelineCard({
  entry,
  onOpen,
}: {
  entry: LeagueTrophyTimelineEntry;
  onOpen: () => void;
}) {
  const presentation = trophyCompetitionPresentation(entry);
  return (
    <Pressable onPress={onOpen} style={styles.trophyTimelineCard}>
      <View
        style={[
          styles.trophyTimelineMark,
          entry.competition === 'cup' && styles.trophyTimelineMarkCup,
          entry.competition === 'super_cup' &&
            styles.trophyTimelineMarkSuperCup,
        ]}
      >
        <Text style={styles.trophyTimelineMarkText}>
          {presentation.mark}
        </Text>
      </View>
      <View style={styles.trophyTimelineCopy}>
        <Text style={styles.trophyTimelineCompetition}>
          {presentation.label} · {entry.season ?? '—'}
        </Text>
        <Text numberOfLines={1} style={styles.trophyTimelineWinner}>
          {entry.winner.teamName}
        </Text>
        <Text numberOfLines={1} style={styles.trophyTimelineManager}>
          {entry.winner.managerName}
          {entry.runnerUp
            ? ` · finale contro ${entry.runnerUp.teamName}`
            : ''}
        </Text>
      </View>
      <Text style={styles.trophyTimelineArrow}>›</Text>
    </Pressable>
  );
}

function trophyCompetitionPresentation(
  entry: LeagueTrophyTimelineEntry,
) {
  if (entry.competition === 'cup') {
    return { label: 'COPPA DI LEGA', mark: 'C' };
  }
  if (entry.competition === 'super_cup') {
    return {
      label: entry.sourceSeason
        ? `SUPERCOPPA ${entry.sourceSeason}`
        : 'SUPERCOPPA',
      mark: 'S',
    };
  }
  return { label: 'CAMPIONATO', mark: '1' };
}

function HeroStat({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.heroStat}>
      <Text style={styles.heroStatValue}>{value}</Text>
      <Text style={styles.heroStatLabel}>{label}</Text>
    </View>
  );
}

function TitleLeaderRow({
  index,
  leader,
}: {
  index: number;
  leader: LeagueHistoryTitleLeader;
}) {
  return (
    <View style={[styles.leaderRow, index > 0 && styles.rowDivider]}>
      <View style={styles.leaderPosition}>
        <Text style={styles.leaderPositionText}>{index + 1}</Text>
      </View>
      <View style={styles.leaderCopy}>
        <Text numberOfLines={1} style={styles.leaderName}>
          {leader.managerName}
        </Text>
        <Text numberOfLines={1} style={styles.leaderTeams}>
          {leader.teamNames.join(' · ')}
        </Text>
      </View>
      <View style={styles.titleBadge}>
        <Text style={styles.titleBadgeValue}>{leader.titles}</Text>
        <Text style={styles.titleBadgeLabel}>
          {leader.titles === 1 ? 'TITOLO' : 'TITOLI'}
        </Text>
      </View>
    </View>
  );
}

function SeasonCard({
  championViaPlayoffs,
  onOpen,
  season,
}: {
  championViaPlayoffs: boolean;
  onOpen: () => void;
  season: LeagueHistorySeason;
}) {
  const progress =
    season.fixtureCount > 0
      ? Math.min(
          100,
          Math.round(
            (season.officialFixtureCount / season.fixtureCount) * 100,
          ),
        )
      : 0;

  return (
    <View
      style={[
        styles.seasonCard,
        season.isLatest && styles.latestSeasonCard,
      ]}
    >
      <View style={styles.seasonTopRow}>
        <View>
          <Text
            style={[
              styles.seasonEyebrow,
              season.isLatest && styles.latestSeasonMuted,
            ]}
          >
            {season.isLatest ? 'STAGIONE PIÙ RECENTE' : 'STAGIONE ARCHIVIATA'}
          </Text>
          <Text
            style={[
              styles.seasonYear,
              season.isLatest && styles.latestSeasonText,
            ]}
          >
            {season.season ?? '—'}
          </Text>
        </View>
        <View
          style={[
            styles.statusPill,
            season.isLatest && styles.latestStatusPill,
          ]}
        >
          <Text
            style={[
              styles.statusPillText,
              season.isLatest && styles.latestStatusPillText,
            ]}
          >
            {statusLabel(season.status)}
          </Text>
        </View>
      </View>

      {season.champion ? (
        <>
          <View style={styles.championRow}>
            <View style={styles.championMark}>
              <Text style={styles.championMarkText}>1</Text>
            </View>
            <View style={styles.championCopy}>
              <Text
                style={[
                  styles.championLabel,
                  season.isLatest && styles.latestSeasonMuted,
                ]}
              >
                {championViaPlayoffs
                  ? 'CAMPIONE · VERDETTO PLAYOFF'
                  : 'CAMPIONE · REGULAR SEASON'}
              </Text>
              <Text
                numberOfLines={1}
                style={[
                  styles.championTeam,
                  season.isLatest && styles.latestSeasonText,
                ]}
              >
                {season.champion.teamName}
              </Text>
              <Text
                style={[
                  styles.championManager,
                  season.isLatest && styles.latestSeasonMuted,
                ]}
              >
                {season.champion.managerName} ·{' '}
                {season.champion.leaguePoints} punti
              </Text>
            </View>
          </View>
          <View style={styles.podiumList}>
            {season.podium.map((entry) => (
              <PodiumRow
                entry={entry}
                key={`${season.leagueId}-${entry.position}`}
                latest={season.isLatest}
              />
            ))}
          </View>
        </>
      ) : (
        <View style={styles.progressBlock}>
          <View style={styles.progressHeading}>
            <Text
              style={[
                styles.progressLabel,
                season.isLatest && styles.latestSeasonMuted,
              ]}
            >
              RISULTATI UFFICIALI
            </Text>
            <Text
              style={[
                styles.progressValue,
                season.isLatest && styles.latestSeasonText,
              ]}
            >
              {season.officialFixtureCount}/{season.fixtureCount}
            </Text>
          </View>
          <View style={styles.progressTrack}>
            <View style={[styles.progressFill, { width: `${progress}%` }]} />
          </View>
          <Text
            style={[
              styles.progressNote,
              season.isLatest && styles.latestSeasonMuted,
            ]}
          >
            {season.status === 'draft'
              ? 'Stagione in preparazione'
              : `${progress}% del campionato ufficializzato`}
          </Text>
        </View>
      )}

      <View style={styles.seasonFooter}>
        <Text
          style={[
            styles.seasonDate,
            season.isLatest && styles.latestSeasonMuted,
          ]}
        >
          {season.completedAt
            ? `CHIUSA ${formatDate(season.completedAt)}`
            : season.startedAt
              ? `INIZIATA ${formatDate(season.startedAt)}`
              : `${season.memberCount} PARTECIPANTI`}
        </Text>
        <Pressable onPress={onOpen} style={styles.openButton}>
          <Text style={styles.openButtonText}>
            {season.isSelected ? 'APRI DI NUOVO →' : 'APRI STAGIONE →'}
          </Text>
        </Pressable>
      </View>
    </View>
  );
}

function PodiumRow({
  entry,
  latest,
}: {
  entry: LeagueHistoryPodiumEntry;
  latest: boolean;
}) {
  return (
    <View style={styles.podiumRow}>
      <Text
        style={[styles.podiumPosition, latest && styles.latestSeasonText]}
      >
        {entry.position}°
      </Text>
      <View style={styles.podiumCopy}>
        <Text
          numberOfLines={1}
          style={[styles.podiumTeam, latest && styles.latestSeasonText]}
        >
          {entry.teamName}
        </Text>
        <Text
          numberOfLines={1}
          style={[styles.podiumManager, latest && styles.latestSeasonMuted]}
        >
          {entry.managerName}
        </Text>
      </View>
      <Text
        style={[styles.podiumPoints, latest && styles.latestSeasonText]}
      >
        {entry.leaguePoints} PT
      </Text>
    </View>
  );
}

function statusLabel(status: LeagueSummary['status']) {
  if (status === 'active') {
    return 'IN CORSO';
  }
  if (status === 'completed') {
    return 'CONCLUSA';
  }
  if (status === 'archived') {
    return 'ARCHIVIATA';
  }
  return 'IN PREPARAZIONE';
}

function seasonRecordPresentation(record: LeagueSeasonRecord) {
  if (record.key === 'league_points') {
    return { label: 'PIÙ PUNTI', value: formatNumber(record.value) };
  }
  if (record.key === 'fantasy_points') {
    return { label: 'PIÙ FANTAPUNTI', value: formatNumber(record.value) };
  }
  if (record.key === 'wins') {
    return { label: 'PIÙ VITTORIE', value: formatNumber(record.value) };
  }
  if (record.key === 'goals_for') {
    return { label: 'PIÙ GOL', value: formatNumber(record.value) };
  }
  return {
    label: 'MIGLIOR DIFFERENZA',
    value: record.value > 0
      ? `+${formatNumber(record.value)}`
      : formatNumber(record.value),
  };
}

function matchRecordPresentation(record: LeagueMatchRecord) {
  if (record.key === 'highest_score') {
    return {
      label: 'PUNTEGGIO PIÙ ALTO',
      value: formatNumber(record.value),
    };
  }
  if (record.key === 'biggest_win') {
    return {
      label: 'VITTORIA PIÙ LARGA',
      value: `+${formatNumber(record.value)}`,
    };
  }
  return {
    label: 'PARTITA CON PIÙ GOL',
    value: formatNumber(record.value),
  };
}

function cupMatchRecordPresentation(record: LeagueCupMatchRecord) {
  if (record.key === 'highest_score') {
    return {
      label: 'PUNTEGGIO PIÙ ALTO IN COPPA',
      value: formatNumber(record.value),
    };
  }
  if (record.key === 'biggest_win') {
    return {
      label: 'VITTORIA PIÙ LARGA IN COPPA',
      value: `+${formatNumber(record.value)}`,
    };
  }
  return {
    label: 'SFIDA DI COPPA CON PIÙ GOL',
    value: formatNumber(record.value),
  };
}

function playoffMatchRecordPresentation(record: LeagueCupMatchRecord) {
  if (record.key === 'highest_score') {
    return {
      label: 'PUNTEGGIO PIÙ ALTO NEI PLAYOFF',
      value: formatNumber(record.value),
    };
  }
  if (record.key === 'biggest_win') {
    return {
      label: 'VITTORIA PIÙ LARGA NEI PLAYOFF',
      value: `+${formatNumber(record.value)}`,
    };
  }
  return {
    label: 'SFIDA PLAYOFF CON PIÙ GOL',
    value: formatNumber(record.value),
  };
}

function formatNumber(value: number) {
  return new Intl.NumberFormat('it-IT', {
    maximumFractionDigits: 2,
  }).format(value);
}

function formatDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return '—';
  }
  return new Intl.DateTimeFormat('it-IT', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  })
    .format(date)
    .toUpperCase();
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
  content: {
    paddingHorizontal: 20,
    paddingTop: 22,
    paddingBottom: 34,
  },
  centerRoot: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 28,
    backgroundColor: colors.canvas,
  },
  centerTitle: {
    color: colors.navy,
    fontSize: 22,
    fontWeight: '900',
    textAlign: 'center',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 22,
  },
  backButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  backText: {
    color: colors.navy,
    fontSize: 32,
    lineHeight: 34,
  },
  headerCopy: {
    flex: 1,
    marginLeft: 14,
  },
  eyebrow: {
    color: colors.muted,
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 0.5,
  },
  title: {
    color: colors.navy,
    fontSize: 27,
    fontWeight: '900',
    marginTop: 4,
  },
  reloadButton: {
    width: 40,
    height: 40,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  reloadButtonDisabled: {
    opacity: 0.72,
  },
  reloadText: {
    color: colors.navy,
    fontSize: 21,
    fontWeight: '900',
  },
  loadingCard: {
    minHeight: 180,
    borderRadius: radius.xl,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
    backgroundColor: colors.navy,
  },
  loadingText: {
    color: colors.warmWhite,
    fontSize: 13,
  },
  errorCard: {
    borderRadius: radius.xl,
    padding: 24,
    backgroundColor: colors.white,
  },
  errorTitle: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
  },
  errorBody: {
    color: colors.muted,
    fontSize: 13,
    lineHeight: 20,
    marginTop: 8,
  },
  retryButton: {
    minHeight: 44,
    borderRadius: 22,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 20,
    marginTop: 18,
    backgroundColor: colors.lime,
  },
  retryButtonText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  heroCard: {
    borderRadius: radius.xl,
    padding: 24,
    backgroundColor: colors.navy,
  },
  heroEyebrow: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.7,
  },
  heroTitle: {
    color: colors.warmWhite,
    fontSize: 26,
    fontWeight: '900',
    marginTop: 7,
  },
  heroBody: {
    color: colors.mutedLight,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 8,
  },
  heroStats: {
    flexDirection: 'row',
    marginTop: 22,
    paddingTop: 19,
    borderTopWidth: 1,
    borderTopColor: colors.navyLine,
  },
  heroStat: {
    flex: 1,
  },
  heroStatValue: {
    color: colors.lime,
    fontSize: 24,
    fontWeight: '900',
  },
  heroStatLabel: {
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.4,
    marginTop: 4,
  },
  trophyHeroCard: {
    borderRadius: radius.xl,
    padding: 22,
    backgroundColor: colors.navySoft,
  },
  trophyHeroTop: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  trophyMonogram: {
    width: 58,
    height: 58,
    borderRadius: 21,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  trophyMonogramText: {
    color: colors.navy,
    fontSize: 27,
    fontWeight: '900',
  },
  trophyHeroCopy: {
    flex: 1,
    marginLeft: 16,
  },
  trophyHeroTitle: {
    color: colors.warmWhite,
    fontSize: 21,
    fontWeight: '900',
    marginTop: 5,
  },
  trophyHeroBody: {
    color: colors.mutedLight,
    fontSize: 10,
    marginTop: 5,
  },
  trophyLeaderList: {
    gap: 10,
  },
  trophyLeaderCard: {
    borderRadius: radius.lg,
    padding: 18,
    backgroundColor: colors.white,
  },
  trophyLeaderTop: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  trophyLeaderRank: {
    width: 38,
    height: 38,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  trophyLeaderRankText: {
    color: colors.lime,
    fontSize: 14,
    fontWeight: '900',
  },
  trophyLeaderCopy: {
    flex: 1,
    marginLeft: 12,
  },
  trophyLeaderName: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
  },
  trophyLeaderTeams: {
    color: colors.muted,
    fontSize: 9,
    marginTop: 4,
  },
  trophyLeaderTotal: {
    alignItems: 'center',
    marginLeft: 12,
  },
  trophyLeaderTotalValue: {
    color: colors.navy,
    fontSize: 24,
    fontWeight: '900',
  },
  trophyLeaderTotalLabel: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
  },
  trophyBreakdown: {
    flexDirection: 'row',
    marginTop: 16,
    paddingTop: 14,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.canvasMuted,
  },
  trophyBreakdownStat: {
    flex: 1,
    alignItems: 'center',
  },
  trophyBreakdownValue: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
  },
  trophyBreakdownLabel: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
    marginTop: 3,
  },
  trophyLeaderMeta: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '800',
    textAlign: 'center',
    marginTop: 12,
  },
  trophyTimelineList: {
    gap: 9,
  },
  trophyTimelineCard: {
    minHeight: 82,
    borderRadius: radius.lg,
    flexDirection: 'row',
    alignItems: 'center',
    padding: 15,
    backgroundColor: colors.white,
  },
  trophyTimelineMark: {
    width: 42,
    height: 42,
    borderRadius: 15,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  trophyTimelineMarkCup: {
    backgroundColor: colors.limeSoft,
  },
  trophyTimelineMarkSuperCup: {
    backgroundColor: colors.success,
  },
  trophyTimelineMarkText: {
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
  },
  trophyTimelineCopy: {
    flex: 1,
    marginLeft: 13,
  },
  trophyTimelineCompetition: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.35,
  },
  trophyTimelineWinner: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
    marginTop: 4,
  },
  trophyTimelineManager: {
    color: colors.muted,
    fontSize: 9,
    marginTop: 3,
  },
  trophyTimelineArrow: {
    color: colors.navy,
    fontSize: 26,
    marginLeft: 8,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    marginTop: 26,
    marginBottom: 11,
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 19,
    fontWeight: '900',
  },
  sectionMeta: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  leadersCard: {
    borderRadius: radius.lg,
    paddingHorizontal: 18,
    backgroundColor: colors.white,
  },
  leaderRow: {
    minHeight: 76,
    flexDirection: 'row',
    alignItems: 'center',
  },
  rowDivider: {
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.canvasMuted,
  },
  leaderPosition: {
    width: 34,
    height: 34,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  leaderPositionText: {
    color: colors.lime,
    fontSize: 13,
    fontWeight: '900',
  },
  leaderCopy: {
    flex: 1,
    marginLeft: 12,
  },
  leaderName: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
  },
  leaderTeams: {
    color: colors.muted,
    fontSize: 10,
    marginTop: 4,
  },
  titleBadge: {
    alignItems: 'center',
    marginLeft: 10,
  },
  titleBadgeValue: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
  },
  titleBadgeLabel: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
  },
  emptyCard: {
    borderRadius: radius.lg,
    padding: 22,
    backgroundColor: colors.white,
  },
  emptyTitle: {
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
  },
  emptyBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 7,
  },
  recordsLoadingCard: {
    minHeight: 106,
    borderRadius: radius.lg,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 9,
    backgroundColor: colors.white,
  },
  recordsLoadingText: {
    color: colors.muted,
    fontSize: 11,
  },
  recordGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
  },
  recordCard: {
    width: '48.4%',
    minHeight: 142,
    borderRadius: radius.lg,
    padding: 16,
    backgroundColor: colors.navy,
  },
  recordLabel: {
    color: colors.lime,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.45,
  },
  recordValue: {
    color: colors.warmWhite,
    fontSize: 25,
    fontWeight: '900',
    marginTop: 10,
  },
  recordTeam: {
    color: colors.warmWhite,
    fontSize: 12,
    fontWeight: '800',
    marginTop: 11,
  },
  recordMeta: {
    color: colors.mutedLight,
    fontSize: 9,
    marginTop: 4,
  },
  matchRecordList: {
    gap: 10,
    marginTop: 12,
  },
  matchRecordCard: {
    borderRadius: radius.lg,
    padding: 18,
    backgroundColor: colors.white,
  },
  matchRecordTop: {
    flexDirection: 'row',
    alignItems: 'flex-start',
  },
  matchRecordCopy: {
    flex: 1,
    paddingRight: 12,
  },
  matchRecordLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  matchRecordTeam: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
    marginTop: 5,
  },
  matchRecordManager: {
    color: colors.muted,
    fontSize: 9,
    marginTop: 4,
  },
  matchRecordValue: {
    color: colors.navy,
    fontSize: 25,
    fontWeight: '900',
  },
  matchScoreRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 15,
    paddingTop: 13,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.canvasMuted,
  },
  matchScoreTeam: {
    flex: 1,
    color: colors.navy,
    fontSize: 10,
    fontWeight: '800',
  },
  matchScoreTeamAway: {
    textAlign: 'right',
  },
  matchScore: {
    minWidth: 52,
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
    textAlign: 'center',
  },
  careerCard: {
    borderRadius: radius.lg,
    paddingHorizontal: 17,
    backgroundColor: colors.white,
  },
  careerRow: {
    minHeight: 91,
    flexDirection: 'row',
    alignItems: 'center',
  },
  careerRank: {
    width: 34,
    height: 34,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  careerRankText: {
    color: colors.lime,
    fontSize: 13,
    fontWeight: '900',
  },
  careerCopy: {
    flex: 1,
    marginLeft: 12,
  },
  careerName: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
  },
  careerTeams: {
    color: colors.muted,
    fontSize: 9,
    marginTop: 3,
  },
  careerMeta: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '800',
    marginTop: 6,
  },
  careerStats: {
    alignItems: 'flex-end',
    marginLeft: 9,
  },
  careerPoints: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
  },
  careerPointsLabel: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
  },
  careerHonours: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
    marginTop: 6,
  },
  subsectionHeader: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    marginTop: 18,
    marginBottom: 10,
  },
  subsectionTitle: {
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
  },
  cupHeroCard: {
    borderRadius: radius.xl,
    padding: 24,
    backgroundColor: colors.navy,
  },
  playoffHeroCard: {
    borderRadius: radius.xl,
    padding: 24,
    backgroundColor: colors.navy,
    borderWidth: 1,
    borderColor: colors.success,
  },
  superCupHeroCard: {
    borderRadius: radius.xl,
    padding: 24,
    backgroundColor: colors.navy,
    borderWidth: 1,
    borderColor: colors.lime,
  },
  cupEmptyCard: {
    borderRadius: radius.lg,
    padding: 22,
    marginTop: 12,
    backgroundColor: colors.white,
  },
  cupLeaderPosition: {
    width: 34,
    height: 34,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  cupLeaderPositionText: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
  },
  playoffLeaderPosition: {
    width: 34,
    height: 34,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.success,
  },
  playoffLeaderPositionText: {
    color: colors.white,
    fontSize: 13,
    fontWeight: '900',
  },
  cupLeaderMeta: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '800',
    marginTop: 5,
  },
  cupTitleBadge: {
    minWidth: 46,
    alignItems: 'center',
    marginLeft: 10,
  },
  cupTitleBadgeValue: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
  },
  cupTitleBadgeLabel: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
  },
  cupSeasonList: {
    gap: 11,
  },
  cupSeasonCard: {
    borderRadius: radius.xl,
    padding: 20,
    backgroundColor: colors.white,
  },
  cupSeasonCardActive: {
    backgroundColor: colors.navy,
  },
  superCupSeasonCardActive: {
    backgroundColor: colors.navy,
  },
  cupSeasonTop: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
  },
  cupSeasonEyebrow: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.45,
  },
  cupSeasonYear: {
    color: colors.navy,
    fontSize: 27,
    fontWeight: '900',
    marginTop: 4,
  },
  cupRoundPill: {
    minHeight: 27,
    borderRadius: 14,
    paddingHorizontal: 11,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  superCupStatusPill: {
    backgroundColor: colors.lime,
  },
  cupVerdict: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 18,
  },
  cupTrophyMark: {
    width: 46,
    height: 46,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  cupTrophyMarkText: {
    color: colors.navy,
    fontSize: 19,
    fontWeight: '900',
  },
  playoffTrophyMark: {
    width: 46,
    height: 46,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.success,
  },
  playoffTrophyMarkText: {
    color: colors.white,
    fontSize: 19,
    fontWeight: '900',
  },
  superCupTrophyMark: {
    width: 46,
    height: 46,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  superCupTrophyMarkText: {
    color: colors.lime,
    fontSize: 19,
    fontWeight: '900',
  },
  cupVerdictCopy: {
    flex: 1,
    marginLeft: 13,
  },
  cupVerdictLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  cupVerdictTeam: {
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
    marginTop: 3,
  },
  cupVerdictManager: {
    color: colors.muted,
    fontSize: 10,
    marginTop: 3,
  },
  cupRunnerUp: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
    marginTop: 7,
  },
  playoffRegularLeader: {
    color: colors.success,
    fontSize: 8,
    fontWeight: '900',
    marginTop: 7,
  },
  cupProgressBlock: {
    marginTop: 20,
  },
  cupProgressTrack: {
    height: 7,
    borderRadius: 4,
    overflow: 'hidden',
    marginTop: 9,
    backgroundColor: colors.navyLine,
  },
  cupProgressFill: {
    height: 7,
    borderRadius: 4,
    backgroundColor: colors.lime,
  },
  cupProgressNote: {
    color: colors.mutedLight,
    fontSize: 10,
    marginTop: 8,
  },
  cupSeasonFooter: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: 18,
    paddingTop: 15,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.navyLine,
  },
  cupSeasonDate: {
    flex: 1,
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  superCupPairing: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 21,
  },
  superCupPairingTeam: {
    flex: 1,
  },
  superCupPairingTeamAway: {
    flex: 1,
    alignItems: 'flex-end',
  },
  superCupPairingLabel: {
    color: colors.mutedLight,
    fontSize: 7,
    fontWeight: '900',
  },
  superCupPairingName: {
    color: colors.warmWhite,
    fontSize: 13,
    fontWeight: '900',
    marginTop: 5,
  },
  superCupPairingNameAway: {
    color: colors.warmWhite,
    fontSize: 13,
    fontWeight: '900',
    textAlign: 'right',
    marginTop: 5,
  },
  superCupPairingVs: {
    width: 42,
    color: colors.lime,
    fontSize: 12,
    fontWeight: '900',
    textAlign: 'center',
  },
  superCupLeaderPosition: {
    width: 34,
    height: 34,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
    borderWidth: 1,
    borderColor: colors.lime,
  },
  superCupLeaderPositionText: {
    color: colors.lime,
    fontSize: 13,
    fontWeight: '900',
  },
  superCupTitleValue: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
  },
  cupRecordCard: {
    borderRadius: radius.lg,
    padding: 18,
    backgroundColor: colors.navy,
  },
  playoffRecordCard: {
    borderRadius: radius.lg,
    padding: 18,
    backgroundColor: colors.navy,
    borderWidth: 1,
    borderColor: colors.success,
  },
  cupRecordLabel: {
    color: colors.lime,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  cupRecordTeam: {
    color: colors.warmWhite,
    fontSize: 15,
    fontWeight: '900',
    marginTop: 5,
  },
  cupRecordMeta: {
    color: colors.mutedLight,
    fontSize: 9,
    marginTop: 4,
  },
  cupRecordValue: {
    color: colors.lime,
    fontSize: 25,
    fontWeight: '900',
  },
  cupScoreRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 15,
    paddingTop: 13,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.navyLine,
  },
  cupScoreTeam: {
    flex: 1,
    color: colors.warmWhite,
    fontSize: 10,
    fontWeight: '800',
  },
  cupScore: {
    minWidth: 52,
    color: colors.lime,
    fontSize: 17,
    fontWeight: '900',
    textAlign: 'center',
  },
  cupCareerRank: {
    width: 34,
    height: 34,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  cupCareerRankText: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
  },
  cupCareerValue: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
  },
  playoffCareerRank: {
    width: 34,
    height: 34,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.success,
  },
  playoffCareerRankText: {
    color: colors.white,
    fontSize: 13,
    fontWeight: '900',
  },
  playoffCareerValue: {
    color: colors.success,
    fontSize: 20,
    fontWeight: '900',
  },
  seasonList: {
    gap: 13,
  },
  seasonCard: {
    borderRadius: radius.xl,
    padding: 21,
    backgroundColor: colors.white,
  },
  latestSeasonCard: {
    backgroundColor: colors.navy,
  },
  seasonTopRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
  },
  seasonEyebrow: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.45,
  },
  seasonYear: {
    color: colors.navy,
    fontSize: 30,
    fontWeight: '900',
    marginTop: 4,
  },
  latestSeasonText: {
    color: colors.warmWhite,
  },
  latestSeasonMuted: {
    color: colors.mutedLight,
  },
  statusPill: {
    minHeight: 27,
    borderRadius: 14,
    paddingHorizontal: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  latestStatusPill: {
    backgroundColor: colors.lime,
  },
  statusPillText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  latestStatusPillText: {
    color: colors.navy,
  },
  championRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 20,
  },
  championMark: {
    width: 46,
    height: 46,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  championMarkText: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
  },
  championCopy: {
    flex: 1,
    marginLeft: 13,
  },
  championLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  championTeam: {
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
    marginTop: 3,
  },
  championManager: {
    color: colors.muted,
    fontSize: 10,
    marginTop: 3,
  },
  podiumList: {
    marginTop: 17,
    paddingTop: 10,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.navyLine,
  },
  podiumRow: {
    minHeight: 42,
    flexDirection: 'row',
    alignItems: 'center',
  },
  podiumPosition: {
    width: 30,
    color: colors.navy,
    fontSize: 12,
    fontWeight: '900',
  },
  podiumCopy: {
    flex: 1,
  },
  podiumTeam: {
    color: colors.navy,
    fontSize: 12,
    fontWeight: '800',
  },
  podiumManager: {
    color: colors.muted,
    fontSize: 9,
    marginTop: 2,
  },
  podiumPoints: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  progressBlock: {
    marginTop: 22,
  },
  progressHeading: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  progressLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  progressValue: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  progressTrack: {
    height: 7,
    borderRadius: 4,
    overflow: 'hidden',
    marginTop: 9,
    backgroundColor: colors.navyLine,
  },
  progressFill: {
    height: 7,
    borderRadius: 4,
    backgroundColor: colors.lime,
  },
  progressNote: {
    color: colors.muted,
    fontSize: 10,
    marginTop: 8,
  },
  seasonFooter: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: 19,
    paddingTop: 16,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.navyLine,
  },
  seasonDate: {
    flex: 1,
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  openButton: {
    minHeight: 32,
    borderRadius: 16,
    paddingHorizontal: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  openButtonText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
});
