import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  Share,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useLeagueMembers } from '../hooks/useLeagueMembers';
import { useLeagueStandings } from '../hooks/useLeagueStandings';
import { useTeamDashboard } from '../hooks/useTeamDashboard';
import { colors, radius } from '../theme';
import type {
  AppScreen,
  LeagueMemberSummary,
  LeagueSummary,
  PublicTeamSelection,
  TeamDashboard,
  TeamDashboardTransaction,
} from '../types';

type Props = {
  currentUserId: string | null;
  league: LeagueSummary | null;
  onNavigate: (screen: AppScreen) => void;
  onOpenTeam: (team: PublicTeamSelection, isCurrent: boolean) => void;
};

export function LeagueScreen({
  currentUserId,
  league,
  onNavigate,
  onOpenTeam,
}: Props) {
  const memberState = useLeagueMembers(
    league?.id ?? null,
    Boolean(league?.isDemo),
  );
  const standingsState = useLeagueStandings(
    league?.id ?? null,
    Boolean(league?.isDemo),
  );
  const teamDashboardState = useTeamDashboard(league);

  if (!league) {
    return (
      <View style={styles.emptyRoot}>
        <View style={styles.emptyBadge}>
          <Text style={styles.emptyBadgeText}>L</Text>
        </View>
        <Text style={styles.emptyTitle}>Nessuna lega convocata</Text>
        <Text style={styles.emptyBody}>
          Creane una o fatti passare il codice invito. Senza imbucati.
        </Text>
        <Pressable
          onPress={() => onNavigate('leagueSetup')}
          style={styles.emptyButton}
        >
          <Text style={styles.emptyButtonText}>CREA O ENTRA</Text>
        </Pressable>
      </View>
    );
  }

  const teamName = league.team?.name ?? 'Squadra da completare';
  const modeName = league.mode === 'classic' ? 'CLASSICA' : 'MANTRA';
  const memberCount =
    !memberState.loading && !memberState.error
      ? memberState.members.length
      : league.memberCount;
  const canManageLeague =
    Boolean(league.isDemo) || league.currentRole === 'admin';
  const dashboard = teamDashboardState.dashboard;
  const shareInvite = async () => {
    await Share.share({
      title: `Invito a ${league.name}`,
      message:
        `Ti aspetto nella lega “${league.name}” su LEGHEVO.\n` +
        `Codice invito: ${league.inviteCode}\n` +
        'Porta una squadra. Le scuse sono già comprese.',
    });
  };

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
    >
      <View style={styles.header}>
        <Pressable onPress={() => onNavigate('home')} style={styles.backButton}>
          <Text style={styles.backText}>‹</Text>
        </Pressable>
        <View style={styles.headerCopy}>
          <Text style={styles.eyebrow}>
            LEGA {modeName} · {memberCount}/{league.teamLimit} SQUADRE
          </Text>
          <Text style={styles.title}>{league.name}</Text>
        </View>
      </View>

      {(standingsState.season?.status === 'completed' ||
        standingsState.season?.status === 'archived') &&
      standingsState.season.champion ? (
        <Pressable
          onPress={() => onNavigate('standings')}
          style={styles.championBanner}
        >
          <View style={styles.championBannerCopy}>
            <Text style={styles.championBannerEyebrow}>
              ALBO D’ORO · {standingsState.season.season ?? 'STAGIONE'}
            </Text>
            <Text style={styles.championBannerTitle}>
              {standingsState.season.champion.teamName}
            </Text>
            <Text style={styles.championBannerSubtitle}>
              CAMPIONE · {standingsState.season.champion.leaguePoints} PUNTI
            </Text>
          </View>
          <Text style={styles.championBannerArrow}>→</Text>
        </Pressable>
      ) : null}

      <View style={styles.teamCard}>
        <View>
          <Text style={styles.cardLabel}>LA TUA SQUADRA</Text>
          <Text style={styles.teamName}>{teamName}</Text>
        </View>
        <View style={styles.rankBadge}>
          <Text style={styles.rank}>
            {dashboard?.position ? `${dashboard.position}°` : '—'}
          </Text>
          <Text style={styles.rankLabel}>
            {dashboard?.played ? 'POSTO' : 'PROVVISORIA'}
          </Text>
        </View>
        <View style={styles.statsRow}>
          <LeagueStat
            label="PUNTI"
            value={String(dashboard?.leaguePoints ?? 0)}
          />
          <LeagueStat
            label="CALCIATORI"
            value={`${dashboard?.rosterCount ?? 0}/${
              dashboard?.rosterSize ?? league.rosterSize
            }`}
          />
          <LeagueStat
            label="CREDITI"
            value={String(
              dashboard?.creditsRemaining ??
                league.team?.creditsRemaining ??
                league.startingCredits,
            )}
          />
        </View>
      </View>

      <TeamSnapshot
        dashboard={dashboard}
        error={teamDashboardState.error}
        loading={teamDashboardState.loading}
        onOpenCalendar={() => onNavigate('calendar')}
        onOpenRoster={() => onNavigate('roster')}
        onRetry={() => void teamDashboardState.refresh()}
      />

      <Pressable
        accessibilityLabel="Condividi codice invito"
        accessibilityRole="button"
        onPress={() => void shareInvite()}
        style={styles.inviteCard}
      >
        <View>
          <Text style={styles.inviteLabel}>CODICE INVITO</Text>
          <Text style={styles.inviteCode}>{league.inviteCode}</Text>
        </View>
        <View style={styles.shareButton}>
          <Text style={styles.shareButtonText}>CONDIVIDI ↗</Text>
        </View>
      </Pressable>

      <Pressable
        accessibilityLabel="Gestisci squadra e partecipazione"
        accessibilityRole="button"
        onPress={() => onNavigate('teamMembership')}
        style={styles.teamManageButton}
      >
        <View style={styles.teamManageIcon}>
          <Text style={styles.teamManageIconText}>TU</Text>
        </View>
        <View style={styles.teamManageCopy}>
          <Text style={styles.teamManageEyebrow}>IDENTITÀ SQUADRA</Text>
          <Text style={styles.teamManageTitle}>Squadra e partecipazione</Text>
          <Text style={styles.teamManageSubtitle}>
            Nome, ruolo e permanenza nella lega
          </Text>
        </View>
        <Text style={styles.teamManageArrow}>→</Text>
      </Pressable>

      <Text style={styles.sectionTitle}>Centro squadra</Text>
      <View style={styles.actionsGrid}>
        <ActionCard
          onPress={() => onNavigate('matchup')}
          symbol="VS"
          title="Centro Sfida"
          subtitle="Forma e precedenti"
        />
        <ActionCard
          onPress={() => onNavigate('lineup')}
          symbol="11"
          title="Formazione"
          subtitle="Consegna gli undici"
        />
        <ActionCard
          onPress={() => onNavigate('roster')}
          symbol="≡"
          title="Rosa"
          subtitle="I tuoi acquisti"
        />
        <ActionCard
          onPress={() => onNavigate('market')}
          symbol="↔"
          title="Mercato"
          subtitle="Acquisti e scambi"
        />
        <ActionCard
          onPress={() => onNavigate('calendar')}
          symbol="↻"
          title="Calendario"
          subtitle="Scontri diretti"
        />
        <ActionCard
          onPress={() => onNavigate('leagueCup')}
          symbol="C"
          title="Coppa"
          subtitle="Eliminazione diretta"
        />
        <ActionCard
          onPress={() => onNavigate('leaguePlayoffs')}
          symbol="P"
          title="Playoff"
          subtitle="Finali Scudetto"
        />
        <ActionCard
          onPress={() => onNavigate('leagueSuperCup')}
          symbol="S"
          title="Supercoppa"
          subtitle="Campione contro Coppa"
        />
        <ActionCard
          onPress={() => onNavigate('postponements')}
          symbol="6"
          title="Rinvii"
          subtitle="Voti d’ufficio"
        />
        <ActionCard
          onPress={() => onNavigate('leagueRulebook')}
          symbol="R"
          title="Regolamento"
          subtitle="Regole e revisioni"
        />
      </View>

      <Pressable
        accessibilityLabel="Apri storia e albo della lega"
        accessibilityRole="button"
        onPress={() => onNavigate('leagueHistory')}
        style={styles.playersButton}
      >
        <View style={styles.playersIcon}>
          <Text style={styles.playersIconText}>∞</Text>
        </View>
        <View style={styles.playersCopy}>
          <Text style={styles.playersEyebrow}>ARCHIVIO STORICO</Text>
          <Text style={styles.playersTitle}>Storia e albo della lega</Text>
          <Text style={styles.playersSubtitle}>
            Stagioni, campioni, podi e titoli
          </Text>
        </View>
        <Text style={styles.playersArrow}>→</Text>
      </Pressable>

      <Pressable
        accessibilityLabel="Apri archivio calciatori"
        accessibilityRole="button"
        onPress={() => onNavigate('players')}
        style={styles.playersButton}
      >
        <View style={styles.playersIcon}>
          <Text style={styles.playersIconText}>⌕</Text>
        </View>
        <View style={styles.playersCopy}>
          <Text style={styles.playersEyebrow}>SCOUTING CENTER</Text>
          <Text style={styles.playersTitle}>Archivio calciatori</Text>
          <Text style={styles.playersSubtitle}>
            Cerca, filtra e studia i numeri
          </Text>
        </View>
        <Text style={styles.playersArrow}>→</Text>
      </Pressable>

      {canManageLeague ? (
        <>
          <Pressable
            onPress={() => onNavigate('leagueOperations')}
            style={styles.presidentButton}
          >
            <View style={styles.presidentIcon}>
              <Text style={styles.presidentIconText}>O</Text>
            </View>
            <View style={styles.presidentCopy}>
              <Text style={styles.presidentEyebrow}>CONTROLLO GIORNATA</Text>
              <Text style={styles.presidentTitle}>Centro Operativo</Text>
              <Text style={styles.presidentSubtitle}>
                Consegne, voti e priorità
              </Text>
            </View>
            <Text style={styles.presidentArrow}>→</Text>
          </Pressable>

          <Pressable
            onPress={() => onNavigate('leagueManagement')}
            style={styles.presidentButton}
          >
            <View style={styles.presidentIcon}>
              <Text style={styles.presidentIconText}>P</Text>
            </View>
            <View style={styles.presidentCopy}>
              <Text style={styles.presidentEyebrow}>AREA PRESIDENTE</Text>
              <Text style={styles.presidentTitle}>Direzione lega</Text>
              <Text style={styles.presidentSubtitle}>
                Inviti, partecipanti e avvio
              </Text>
            </View>
            <Text style={styles.presidentArrow}>→</Text>
          </Pressable>

          <Pressable
            onPress={() => onNavigate('leagueSettings')}
            style={styles.presidentButton}
          >
            <View style={styles.presidentIcon}>
              <Text style={styles.presidentIconText}>R</Text>
            </View>
            <View style={styles.presidentCopy}>
              <Text style={styles.presidentEyebrow}>REGOLAMENTO</Text>
              <Text style={styles.presidentTitle}>Regole e calcoli</Text>
              <Text style={styles.presidentSubtitle}>
                Mercato, rimborsi e fasce gol
              </Text>
            </View>
            <Text style={styles.presidentArrow}>→</Text>
          </Pressable>
        </>
      ) : null}

      <Pressable
        onPress={() => onNavigate('auction')}
        style={styles.auctionButton}
      >
        <View>
          <Text style={styles.auctionEyebrow}>
            {league.isDemo ? 'STANZA DEMO ATTIVA' : 'ASTA LIVE'}
          </Text>
          <Text style={styles.auctionTitle}>
            {memberCount > 1 || league.isDemo
              ? 'Entra nella stanza'
              : 'In attesa degli avversari'}
          </Text>
        </View>
        <Text style={styles.auctionArrow}>→</Text>
      </Pressable>

      <View style={styles.standingsHeader}>
        <Text style={styles.sectionTitle}>Partecipanti</Text>
        <Text style={styles.allLink}>
          {memberCount}/{league.teamLimit}
        </Text>
      </View>
      <View style={styles.membersCard}>
        {memberState.loading ? (
          <View style={styles.membersLoading}>
            <ActivityIndicator color={colors.navy} size="small" />
            <Text style={styles.membersLoadingText}>Faccio l’appello…</Text>
          </View>
        ) : memberState.error ? (
          <Text style={styles.membersError}>{memberState.error}</Text>
        ) : (
          <>
            {memberState.members.map((member) => (
              <MemberRow
                current={
                  league.isDemo
                    ? member.userId === 'demo-user'
                    : member.userId === currentUserId
                }
                key={member.userId}
                member={member}
                onPress={(isCurrent) => {
                  if (!member.team) {
                    return;
                  }
                  onOpenTeam(
                    {
                      id: member.team.id,
                      name: member.team.name,
                      managerName: member.displayName,
                    },
                    isCurrent,
                  );
                }}
              />
            ))}
            {league.teamLimit > memberCount ? (
              <Pressable
                onPress={() => void shareInvite()}
                style={styles.openSlotsRow}
              >
                <View style={styles.openSlotsIcon}>
                  <Text style={styles.openSlotsIconText}>+</Text>
                </View>
                <View style={styles.memberCopy}>
                  <Text style={styles.openSlotsTitle}>
                    {league.teamLimit - memberCount}{' '}
                    {league.teamLimit - memberCount === 1
                      ? 'posto libero'
                      : 'posti liberi'}
                  </Text>
                  <Text style={styles.memberManager}>CONDIVIDI L’INVITO</Text>
                </View>
                <Text style={styles.memberArrow}>→</Text>
              </Pressable>
            ) : null}
          </>
        )}
      </View>

      <View style={styles.standingsHeader}>
        <Text style={styles.sectionTitle}>Classifica</Text>
        <Pressable onPress={() => onNavigate('standings')}>
          <Text style={styles.allLink}>VEDI TUTTA</Text>
        </Pressable>
      </View>
      {standingsState.loading ? (
        <View style={styles.waitingCard}>
          <ActivityIndicator color={colors.navy} size="small" />
          <Text style={styles.waitingBody}>Rifaccio i conti del lunedì…</Text>
        </View>
      ) : standingsState.error ? (
        <View style={styles.waitingCard}>
          <Text style={styles.waitingTitle}>Classifica indisponibile</Text>
          <Text style={styles.waitingBody}>{standingsState.error}</Text>
        </View>
      ) : standingsState.standings.length > 0 ? (
        <View style={styles.table}>
          {standingsState.standings.slice(0, 4).map((team) => {
            const current = team.teamId === league.team?.id;
            return (
              <Pressable
                accessibilityLabel={`Apri la rosa di ${team.teamName}`}
                accessibilityRole="button"
                key={team.teamId}
                onPress={() =>
                  onOpenTeam(
                    { id: team.teamId, name: team.teamName },
                    current,
                  )
                }
                style={({ pressed }) => [
                  styles.tableRow,
                  current && styles.currentRow,
                  pressed && styles.tableRowPressed,
                ]}
              >
                <Text style={styles.tablePosition}>{team.position}</Text>
                <Text numberOfLines={1} style={styles.tableName}>
                  {team.teamName}
                </Text>
                <Text style={styles.tablePoints}>{team.leaguePoints}</Text>
              </Pressable>
            );
          })}
        </View>
      ) : (
        <View style={styles.waitingCard}>
          <Text style={styles.waitingTitle}>Il campionato deve ancora parlare</Text>
          <Text style={styles.waitingBody}>
            La classifica apparirà dopo la prima giornata. Per ora siete tutti
            primi: godetevela.
          </Text>
        </View>
      )}
    </ScrollView>
  );
}

function MemberRow({
  current,
  member,
  onPress,
}: {
  current: boolean;
  member: LeagueMemberSummary;
  onPress: (isCurrent: boolean) => void;
}) {
  const initials = member.displayName
    .trim()
    .split(/\s+/)
    .map((part) => part[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();

  const canOpen = Boolean(member.team);

  return (
    <Pressable
      accessibilityHint={
        canOpen ? 'Apre la rosa della squadra' : 'Squadra non ancora creata'
      }
      accessibilityLabel={
        canOpen
          ? `Apri la rosa di ${member.team?.name}`
          : `${member.displayName} non ha ancora una squadra`
      }
      accessibilityRole={canOpen ? 'button' : undefined}
      disabled={!canOpen}
      onPress={() => onPress(current)}
      style={({ pressed }) => [
        styles.memberRow,
        current && styles.memberRowCurrent,
        pressed && styles.memberRowPressed,
      ]}
    >
      <View style={[styles.memberAvatar, current && styles.memberAvatarCurrent]}>
        <Text
          style={[
            styles.memberAvatarText,
            current && styles.memberAvatarTextCurrent,
          ]}
        >
          {initials || 'LV'}
        </Text>
      </View>
      <View style={styles.memberCopy}>
        <Text style={styles.memberTeam}>
          {member.team?.name ?? 'Squadra da completare'}
          {current ? ' · TU' : ''}
        </Text>
        <Text style={styles.memberManager}>
          {member.displayName}
          {member.role === 'admin' ? ' · PRESIDENTE' : ''}
        </Text>
      </View>
      <Text style={styles.memberArrow}>{canOpen ? '›' : '—'}</Text>
    </Pressable>
  );
}

function LeagueStat({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.stat}>
      <Text style={styles.statLabel}>{label}</Text>
      <Text style={styles.statValue}>{value}</Text>
    </View>
  );
}

function TeamSnapshot({
  dashboard,
  loading,
  error,
  onRetry,
  onOpenRoster,
  onOpenCalendar,
}: {
  dashboard: TeamDashboard | null;
  loading: boolean;
  error: string;
  onRetry: () => void;
  onOpenRoster: () => void;
  onOpenCalendar: () => void;
}) {
  if (loading && !dashboard) {
    return (
      <View style={styles.snapshotLoading}>
        <ActivityIndicator color={colors.navy} size="small" />
        <Text style={styles.snapshotLoadingText}>
          Aggiorno i numeri della squadra…
        </Text>
      </View>
    );
  }

  if (error && !dashboard) {
    return (
      <View style={styles.snapshotError}>
        <Text style={styles.snapshotErrorTitle}>Cruscotto non disponibile</Text>
        <Text style={styles.snapshotErrorBody}>{error}</Text>
        <Pressable onPress={onRetry} style={styles.snapshotRetry}>
          <Text style={styles.snapshotRetryText}>RIPROVA</Text>
        </Pressable>
      </View>
    );
  }

  if (!dashboard) {
    return null;
  }

  const rosterProgress = Math.min(
    (dashboard.rosterCount / Math.max(dashboard.rosterSize, 1)) * 100,
    100,
  );

  return (
    <View style={styles.snapshotCard}>
      <View style={styles.snapshotHeader}>
        <View>
          <Text style={styles.snapshotEyebrow}>CRUSCOTTO SQUADRA</Text>
          <Text style={styles.snapshotTitle}>
            {dashboard.competitionStartedAt
              ? 'Campionato in corso'
              : 'Preparazione al via'}
          </Text>
        </View>
        <View
          style={[
            styles.snapshotStatus,
            dashboard.competitionStartedAt && styles.snapshotStatusActive,
          ]}
        >
          <Text style={styles.snapshotStatusText}>
            {dashboard.competitionStartedAt ? 'ATTIVA' : 'PRE-CAMPIONATO'}
          </Text>
        </View>
      </View>

      <View style={styles.snapshotReadiness}>
        <ReadinessItem
          label="SPOGLIATOIO"
          ready={dashboard.memberCount === dashboard.teamLimit}
          value={`${dashboard.memberCount}/${dashboard.teamLimit}`}
        />
        <ReadinessItem
          label="ROSA"
          ready={dashboard.rosterCount === dashboard.rosterSize}
          value={`${dashboard.rosterCount}/${dashboard.rosterSize}`}
        />
        <ReadinessItem
          label="CALENDARIO"
          ready={dashboard.fixtureCount > 0}
          value={dashboard.fixtureCount > 0 ? 'PRONTO' : 'DA CREARE'}
        />
      </View>

      <View style={styles.snapshotProgressTrack}>
        <View
          style={[styles.snapshotProgressValue, { width: `${rosterProgress}%` }]}
        />
      </View>
      <View style={styles.snapshotProgressCopy}>
        <Text style={styles.snapshotProgressLabel}>COMPLETAMENTO ROSA</Text>
        <Text style={styles.snapshotProgressNumber}>
          {Math.round(rosterProgress)}%
        </Text>
      </View>

      <View style={styles.snapshotPerformance}>
        <PerformanceItem label="V" value={dashboard.won} />
        <PerformanceItem label="N" value={dashboard.drawn} />
        <PerformanceItem label="P" value={dashboard.lost} />
        <PerformanceItem
          label="FANTAPUNTI"
          value={formatNumber(dashboard.pointsFor)}
          wide
        />
      </View>

      {dashboard.nextMatch ? (
        <Pressable onPress={onOpenCalendar} style={styles.nextMatchCard}>
          <View>
            <Text style={styles.nextMatchEyebrow}>
              PROSSIMA · GIORNATA {dashboard.nextMatch.matchdayNumber}
            </Text>
            <Text style={styles.nextMatchTitle}>
              {dashboard.nextMatch.home ? 'VS ' : '@ '}
              {dashboard.nextMatch.opponentName}
            </Text>
            <Text style={styles.nextMatchDate}>
              {formatDashboardDate(dashboard.nextMatch.startsAt)}
            </Text>
          </View>
          <Text style={styles.nextMatchArrow}>→</Text>
        </Pressable>
      ) : (
        <Pressable onPress={onOpenCalendar} style={styles.nextMatchEmpty}>
          <View>
            <Text style={styles.nextMatchEyebrow}>PROSSIMA PARTITA</Text>
            <Text style={styles.nextMatchEmptyTitle}>
              Calendario non ancora generato
            </Text>
          </View>
          <Text style={styles.nextMatchArrow}>→</Text>
        </Pressable>
      )}

      <View style={styles.movementsHeader}>
        <Text style={styles.movementsTitle}>Ultimi movimenti</Text>
        <Pressable onPress={onOpenRoster}>
          <Text style={styles.movementsLink}>APRI ROSA</Text>
        </Pressable>
      </View>
      {dashboard.recentTransactions.length > 0 ? (
        dashboard.recentTransactions.slice(0, 3).map((transaction) => (
          <MovementRow key={transaction.id} transaction={transaction} />
        ))
      ) : (
        <Text style={styles.movementsEmpty}>
          Nessun movimento registrato. L’asta deve ancora battere il primo
          colpo.
        </Text>
      )}
    </View>
  );
}

function ReadinessItem({
  label,
  value,
  ready,
}: {
  label: string;
  value: string;
  ready: boolean;
}) {
  return (
    <View style={styles.readinessItem}>
      <Text style={styles.readinessLabel}>{label}</Text>
      <Text
        style={[styles.readinessValue, ready && styles.readinessValueReady]}
      >
        {value}
      </Text>
    </View>
  );
}

function PerformanceItem({
  label,
  value,
  wide = false,
}: {
  label: string;
  value: string | number;
  wide?: boolean;
}) {
  return (
    <View style={[styles.performanceItem, wide && styles.performanceItemWide]}>
      <Text style={styles.performanceValue}>{value}</Text>
      <Text style={styles.performanceLabel}>{label}</Text>
    </View>
  );
}

function MovementRow({
  transaction,
}: {
  transaction: TeamDashboardTransaction;
}) {
  const positive = transaction.creditDelta > 0;
  return (
    <View style={styles.movementRow}>
      <View style={styles.movementIcon}>
        <Text style={styles.movementIconText}>
          {transaction.type === 'release'
            ? 'S'
            : transaction.type === 'trade'
              ? '↔'
              : 'A'}
        </Text>
      </View>
      <View style={styles.movementCopy}>
        <Text numberOfLines={1} style={styles.movementName}>
          {transaction.athleteName}
        </Text>
        <Text style={styles.movementType}>
          {transactionLabel(transaction.type)} ·{' '}
          {formatShortDate(transaction.createdAt)}
        </Text>
      </View>
      <Text
        style={[
          styles.movementCredits,
          positive && styles.movementCreditsPositive,
        ]}
      >
        {positive ? '+' : ''}
        {transaction.creditDelta} CR
      </Text>
    </View>
  );
}

function transactionLabel(type: TeamDashboardTransaction['type']) {
  if (type === 'auction_purchase') return 'ACQUISTO ASTA';
  if (type === 'market_purchase') return 'ACQUISTO MERCATO';
  if (type === 'release') return 'SVINCOLO';
  return 'SCAMBIO';
}

function formatNumber(value: number) {
  return new Intl.NumberFormat('it-IT', {
    maximumFractionDigits: 2,
  }).format(value);
}

function formatDashboardDate(value: string) {
  return new Intl.DateTimeFormat('it-IT', {
    weekday: 'short',
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  })
    .format(new Date(value))
    .toUpperCase();
}

function formatShortDate(value: string) {
  return new Intl.DateTimeFormat('it-IT', {
    day: '2-digit',
    month: 'short',
  })
    .format(new Date(value))
    .toUpperCase();
}

function ActionCard({
  symbol,
  title,
  subtitle,
  onPress,
}: {
  symbol: string;
  title: string;
  subtitle: string;
  onPress?: () => void;
}) {
  return (
    <Pressable onPress={onPress} style={styles.actionCard}>
      <View style={styles.actionIcon}>
        <Text style={styles.actionSymbol}>{symbol}</Text>
      </View>
      <Text style={styles.actionTitle}>{title}</Text>
      <Text style={styles.actionSubtitle}>{subtitle}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
  content: {
    padding: 20,
    paddingBottom: 36,
  },
  emptyRoot: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 28,
    backgroundColor: colors.canvas,
  },
  emptyBadge: {
    width: 62,
    height: 62,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  emptyBadgeText: {
    color: colors.lime,
    fontSize: 27,
    fontWeight: '900',
  },
  emptyTitle: {
    color: colors.navy,
    fontSize: 22,
    fontWeight: '900',
    textAlign: 'center',
    marginTop: 20,
  },
  emptyBody: {
    color: colors.muted,
    fontSize: 13,
    lineHeight: 19,
    textAlign: 'center',
    marginTop: 8,
  },
  emptyButton: {
    height: 50,
    paddingHorizontal: 24,
    borderRadius: 25,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginTop: 22,
  },
  emptyButtonText: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
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
    backgroundColor: colors.white,
    alignItems: 'center',
    justifyContent: 'center',
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
  championBanner: {
    minHeight: 118,
    borderRadius: radius.xl,
    flexDirection: 'row',
    alignItems: 'center',
    padding: 20,
    marginBottom: 14,
    backgroundColor: colors.lime,
  },
  championBannerCopy: {
    flex: 1,
    paddingRight: 14,
  },
  championBannerEyebrow: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.6,
  },
  championBannerTitle: {
    color: colors.navy,
    fontSize: 21,
    fontWeight: '900',
    marginTop: 6,
  },
  championBannerSubtitle: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '800',
    marginTop: 5,
  },
  championBannerArrow: {
    color: colors.navy,
    fontSize: 25,
    fontWeight: '900',
  },
  teamCard: {
    borderRadius: radius.xl,
    backgroundColor: colors.navy,
    padding: 22,
  },
  cardLabel: {
    color: colors.mutedLight,
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 0.5,
  },
  teamName: {
    color: colors.warmWhite,
    fontSize: 23,
    fontWeight: '900',
    marginTop: 6,
  },
  rankBadge: {
    position: 'absolute',
    right: 22,
    top: 22,
    alignItems: 'center',
  },
  rank: {
    color: colors.lime,
    fontSize: 30,
    fontWeight: '900',
  },
  rankLabel: {
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '800',
  },
  statsRow: {
    flexDirection: 'row',
    marginTop: 24,
    paddingTop: 20,
    borderTopWidth: 1,
    borderTopColor: colors.navyLine,
  },
  snapshotLoading: {
    minHeight: 82,
    borderRadius: radius.lg,
    paddingHorizontal: 20,
    marginTop: 14,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.white,
  },
  snapshotLoadingText: {
    color: colors.muted,
    fontSize: 12,
    marginLeft: 11,
  },
  snapshotError: {
    borderRadius: radius.lg,
    padding: 20,
    marginTop: 14,
    backgroundColor: colors.white,
  },
  snapshotErrorTitle: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
  },
  snapshotErrorBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 6,
  },
  snapshotRetry: {
    alignSelf: 'flex-start',
    height: 34,
    borderRadius: 17,
    paddingHorizontal: 14,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginTop: 14,
  },
  snapshotRetryText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
  },
  snapshotCard: {
    borderRadius: radius.xl,
    padding: 20,
    marginTop: 14,
    backgroundColor: colors.white,
  },
  snapshotHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
  },
  snapshotEyebrow: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  snapshotTitle: {
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
    marginTop: 5,
  },
  snapshotStatus: {
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 7,
    backgroundColor: colors.canvasMuted,
  },
  snapshotStatusActive: {
    backgroundColor: colors.lime,
  },
  snapshotStatusText: {
    color: colors.navy,
    fontSize: 7,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  snapshotReadiness: {
    flexDirection: 'row',
    paddingTop: 18,
    marginTop: 18,
    borderTopWidth: 1,
    borderTopColor: colors.canvasMuted,
  },
  readinessItem: {
    flex: 1,
  },
  readinessLabel: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
  },
  readinessValue: {
    color: colors.navy,
    fontSize: 12,
    fontWeight: '900',
    marginTop: 4,
  },
  readinessValueReady: {
    color: '#5C8A00',
  },
  snapshotProgressTrack: {
    height: 7,
    borderRadius: 999,
    overflow: 'hidden',
    backgroundColor: colors.canvasMuted,
    marginTop: 18,
  },
  snapshotProgressValue: {
    height: '100%',
    borderRadius: 999,
    backgroundColor: colors.lime,
  },
  snapshotProgressCopy: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 7,
  },
  snapshotProgressLabel: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
  },
  snapshotProgressNumber: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  snapshotPerformance: {
    minHeight: 68,
    borderRadius: radius.md,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.navy,
    marginTop: 18,
    paddingHorizontal: 12,
  },
  performanceItem: {
    width: 42,
    alignItems: 'center',
  },
  performanceItemWide: {
    flex: 1,
    alignItems: 'flex-end',
  },
  performanceValue: {
    color: colors.warmWhite,
    fontSize: 17,
    fontWeight: '900',
  },
  performanceLabel: {
    color: colors.mutedLight,
    fontSize: 7,
    fontWeight: '900',
    marginTop: 3,
  },
  nextMatchCard: {
    minHeight: 86,
    borderRadius: radius.md,
    paddingHorizontal: 17,
    marginTop: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: colors.limeSoft,
  },
  nextMatchEmpty: {
    minHeight: 74,
    borderRadius: radius.md,
    paddingHorizontal: 17,
    marginTop: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: colors.canvas,
  },
  nextMatchEyebrow: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  nextMatchTitle: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
    marginTop: 5,
  },
  nextMatchDate: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '800',
    marginTop: 5,
  },
  nextMatchEmptyTitle: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
    marginTop: 5,
  },
  nextMatchArrow: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
  },
  movementsHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: 20,
    marginBottom: 5,
  },
  movementsTitle: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
  },
  movementsLink: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  movementRow: {
    minHeight: 58,
    flexDirection: 'row',
    alignItems: 'center',
    borderTopWidth: 1,
    borderTopColor: colors.canvasMuted,
  },
  movementIcon: {
    width: 32,
    height: 32,
    borderRadius: 11,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  movementIconText: {
    color: colors.lime,
    fontSize: 10,
    fontWeight: '900',
  },
  movementCopy: {
    flex: 1,
    marginLeft: 10,
  },
  movementName: {
    color: colors.navy,
    fontSize: 12,
    fontWeight: '900',
  },
  movementType: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '800',
    marginTop: 3,
  },
  movementCredits: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  movementCreditsPositive: {
    color: '#5C8A00',
  },
  movementsEmpty: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 17,
    paddingTop: 12,
    borderTopWidth: 1,
    borderTopColor: colors.canvasMuted,
  },
  inviteCard: {
    minHeight: 76,
    borderRadius: radius.lg,
    paddingHorizontal: 19,
    marginTop: 14,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: colors.white,
  },
  inviteLabel: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
  },
  inviteCode: {
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
    letterSpacing: 1.4,
    marginTop: 4,
  },
  shareButton: {
    height: 34,
    paddingHorizontal: 13,
    borderRadius: 17,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  shareButtonText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
  },
  teamManageButton: {
    minHeight: 80,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    paddingHorizontal: 17,
    marginTop: 12,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.white,
  },
  teamManageIcon: {
    width: 42,
    height: 42,
    borderRadius: 15,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  teamManageIconText: {
    color: colors.lime,
    fontSize: 10,
    fontWeight: '900',
  },
  teamManageCopy: {
    flex: 1,
    marginLeft: 13,
  },
  teamManageEyebrow: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  teamManageTitle: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
    marginTop: 3,
  },
  teamManageSubtitle: {
    color: colors.muted,
    fontSize: 10,
    marginTop: 3,
  },
  teamManageArrow: {
    color: colors.navy,
    fontSize: 24,
  },
  stat: {
    flex: 1,
  },
  statLabel: {
    color: colors.mutedLight,
    fontSize: 9,
    fontWeight: '800',
  },
  statValue: {
    color: colors.warmWhite,
    fontSize: 19,
    fontWeight: '900',
    marginTop: 5,
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 21,
    fontWeight: '900',
    marginTop: 24,
    marginBottom: 12,
  },
  actionsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'space-between',
    rowGap: 12,
  },
  actionCard: {
    width: '48.5%',
    minHeight: 142,
    borderRadius: radius.lg,
    backgroundColor: colors.white,
    padding: 16,
  },
  actionIcon: {
    width: 38,
    height: 38,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  actionSymbol: {
    color: colors.lime,
    fontSize: 14,
    fontWeight: '900',
  },
  actionTitle: {
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
    marginTop: 15,
  },
  actionSubtitle: {
    color: colors.muted,
    fontSize: 12,
    marginTop: 5,
  },
  playersButton: {
    minHeight: 86,
    borderRadius: radius.lg,
    paddingHorizontal: 17,
    marginTop: 15,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.navy,
  },
  playersIcon: {
    width: 42,
    height: 42,
    borderRadius: 15,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  playersIconText: {
    color: colors.navy,
    fontSize: 22,
    fontWeight: '900',
  },
  playersCopy: {
    flex: 1,
    marginLeft: 13,
  },
  playersEyebrow: {
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  playersTitle: {
    color: colors.warmWhite,
    fontSize: 15,
    fontWeight: '900',
    marginTop: 3,
  },
  playersSubtitle: {
    color: colors.mutedLight,
    fontSize: 10,
    marginTop: 3,
  },
  playersArrow: {
    color: colors.lime,
    fontSize: 24,
  },
  presidentButton: {
    minHeight: 86,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.navy,
    paddingHorizontal: 17,
    marginTop: 15,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.white,
  },
  presidentIcon: {
    width: 42,
    height: 42,
    borderRadius: 15,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  presidentIconText: {
    color: colors.lime,
    fontSize: 16,
    fontWeight: '900',
  },
  presidentCopy: {
    flex: 1,
    marginLeft: 13,
  },
  presidentEyebrow: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  presidentTitle: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
    marginTop: 3,
  },
  presidentSubtitle: {
    color: colors.muted,
    fontSize: 10,
    marginTop: 3,
  },
  presidentArrow: {
    color: colors.navy,
    fontSize: 24,
  },
  auctionButton: {
    minHeight: 78,
    borderRadius: radius.lg,
    backgroundColor: colors.lime,
    paddingHorizontal: 20,
    marginTop: 18,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  auctionEyebrow: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
  },
  auctionTitle: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
    marginTop: 4,
  },
  auctionArrow: {
    color: colors.navy,
    fontSize: 28,
    fontWeight: '500',
  },
  standingsHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  allLink: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
    marginTop: 16,
  },
  membersCard: {
    borderRadius: radius.lg,
    padding: 8,
    backgroundColor: colors.white,
  },
  membersLoading: {
    minHeight: 78,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 10,
  },
  membersLoadingText: {
    color: colors.muted,
    fontSize: 11,
    fontWeight: '800',
  },
  membersError: {
    color: colors.danger,
    fontSize: 12,
    lineHeight: 18,
    padding: 14,
  },
  memberRow: {
    minHeight: 64,
    borderRadius: 16,
    paddingHorizontal: 10,
    flexDirection: 'row',
    alignItems: 'center',
  },
  memberRowCurrent: {
    backgroundColor: colors.limeSoft,
  },
  memberRowPressed: {
    opacity: 0.72,
  },
  memberAvatar: {
    width: 40,
    height: 40,
    borderRadius: 15,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  memberAvatarCurrent: {
    backgroundColor: colors.navy,
  },
  memberAvatarText: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
  memberAvatarTextCurrent: {
    color: colors.lime,
  },
  memberCopy: {
    flex: 1,
    marginLeft: 12,
  },
  memberTeam: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
  },
  memberManager: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '800',
    marginTop: 4,
  },
  memberArrow: {
    color: colors.muted,
    fontSize: 22,
    marginHorizontal: 6,
  },
  openSlotsRow: {
    minHeight: 64,
    borderRadius: 16,
    paddingHorizontal: 10,
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1,
    borderStyle: 'dashed',
    borderColor: colors.canvasMuted,
  },
  openSlotsIcon: {
    width: 40,
    height: 40,
    borderRadius: 15,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  openSlotsIconText: {
    color: colors.lime,
    fontSize: 19,
    fontWeight: '900',
  },
  openSlotsTitle: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
  },
  table: {
    borderRadius: radius.lg,
    backgroundColor: colors.white,
    padding: 8,
  },
  tableRow: {
    minHeight: 48,
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: 14,
    paddingHorizontal: 12,
  },
  tableRowPressed: {
    opacity: 0.72,
  },
  currentRow: {
    backgroundColor: colors.limeSoft,
  },
  tablePosition: {
    width: 28,
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
  },
  tableName: {
    flex: 1,
    color: colors.navy,
    fontSize: 14,
    fontWeight: '700',
  },
  tablePoints: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
  },
  waitingCard: {
    borderRadius: radius.lg,
    padding: 20,
    backgroundColor: colors.white,
  },
  waitingTitle: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
  },
  waitingBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 7,
  },
});
