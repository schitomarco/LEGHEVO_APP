import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useLeagueSettings } from '../hooks/useLeagueSettings';
import { useTeamRoster } from '../hooks/useTeamRoster';
import { colors, radius } from '../theme';
import type {
  LeagueSummary,
  PublicTeamSelection,
  RosterPlayer,
} from '../types';

type Props = {
  league: LeagueSummary | null;
  team: PublicTeamSelection | null;
  onBack: () => void;
  onOpenPlayer: (playerId: string) => void;
};

export function PublicRosterScreen({
  league,
  team,
  onBack,
  onOpenPlayer,
}: Props) {
  const rules = useLeagueSettings(league);
  const roster = useTeamRoster(
    team?.id ?? null,
    league?.mode ?? 'classic',
    Boolean(league?.isDemo),
  );

  if (!league || !team) {
    return (
      <View style={styles.centerRoot}>
        <Text style={styles.centerTitle}>Squadra non disponibile.</Text>
        <Pressable onPress={onBack} style={styles.primaryButton}>
          <Text style={styles.primaryButtonText}>TORNA ALLA LEGA</Text>
        </Pressable>
      </View>
    );
  }

  const spent = roster.players.reduce(
    (total, player) => total + player.purchasePrice,
    0,
  );
  const grouped = groupPlayers(roster.players);
  const quotaByGroup: Record<string, number> = {
    PORTIERI: rules.settings.rosterGoalkeepers,
    DIFENSORI: rules.settings.rosterDefenders,
    CENTROCAMPISTI: rules.settings.rosterMidfielders,
    ATTACCANTI: rules.settings.rosterAttackers,
  };
  const quotaLabels =
    league.mode === 'classic'
      ? ['P', 'D', 'C', 'A']
      : ['Por', 'Dc/Dd/Ds/E', 'M/C/W/T', 'A/Pc'];
  const quotaGroups = [
    'PORTIERI',
    'DIFENSORI',
    'CENTROCAMPISTI',
    'ATTACCANTI',
  ];
  const completion = league.rosterSize
    ? Math.round((roster.players.length / league.rosterSize) * 100)
    : 0;

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
    >
      <View style={styles.header}>
        <Pressable
          accessibilityLabel="Torna indietro"
          accessibilityRole="button"
          onPress={onBack}
          style={styles.backButton}
        >
          <Text style={styles.backText}>‹</Text>
        </Pressable>
        <View style={styles.headerCopy}>
          <Text style={styles.eyebrow}>ROSA PUBBLICA</Text>
          <Text numberOfLines={1} style={styles.title}>
            {team.name}
          </Text>
          {team.managerName ? (
            <Text numberOfLines={1} style={styles.managerName}>
              Allenata da {team.managerName}
            </Text>
          ) : null}
        </View>
      </View>

      <View style={styles.summaryCard}>
        <View>
          <Text style={styles.summaryLabel}>DISTINTA AVVERSARIA</Text>
          <Text style={styles.summaryTitle}>
            {roster.players.length}/{league.rosterSize} calciatori
          </Text>
        </View>
        <View style={styles.summaryRow}>
          <SummaryStat label="SPESI" value={String(spent)} />
          <SummaryStat
            label="MEDIA"
            value={
              roster.players.length
                ? (spent / roster.players.length).toFixed(1)
                : '0'
            }
          />
          <SummaryStat label="COMPLETA" value={`${completion}%`} />
        </View>
      </View>

      <View style={styles.quotaCard}>
        <Text style={styles.quotaEyebrow}>COMPOSIZIONE ROSA</Text>
        <View style={styles.quotaRow}>
          {quotaGroups.map((group, index) => (
            <View key={group} style={styles.quotaItem}>
              <Text style={styles.quotaValue}>
                {grouped[group]?.length ?? 0}/{quotaByGroup[group]}
              </Text>
              <Text numberOfLines={1} style={styles.quotaLabel}>
                {quotaLabels[index]}
              </Text>
            </View>
          ))}
        </View>
      </View>

      {roster.loading ? (
        <View style={styles.loadingCard}>
          <ActivityIndicator color={colors.navy} />
          <Text style={styles.loadingText}>Apro l’armadietto…</Text>
        </View>
      ) : roster.error ? (
        <View style={styles.errorCard}>
          <Text style={styles.errorTitle}>Rosa non disponibile</Text>
          <Text style={styles.errorBody}>{roster.error}</Text>
          <Pressable onPress={() => void roster.refresh()} style={styles.retryButton}>
            <Text style={styles.retryButtonText}>RIPROVA</Text>
          </Pressable>
        </View>
      ) : roster.players.length === 0 ? (
        <View style={styles.emptyCard}>
          <Text style={styles.emptyTitle}>Rosa ancora vuota</Text>
          <Text style={styles.emptyBody}>
            {team.name} non ha ancora acquistato calciatori. La distinta si
            aggiornerà automaticamente dopo il primo colpo di mercato.
          </Text>
        </View>
      ) : (
        Object.entries(grouped).map(([role, players]) => (
          <View key={role}>
            <View style={styles.roleHeader}>
              <Text style={styles.roleTitle}>{role}</Text>
              <Text style={styles.roleCount}>
                {players.length}/{quotaByGroup[role]}
              </Text>
            </View>
            <View style={styles.playersCard}>
              {players.map((player) => (
                <PlayerRow
                  key={player.id}
                  onPress={() => onOpenPlayer(player.id)}
                  player={player}
                />
              ))}
            </View>
          </View>
        ))
      )}
    </ScrollView>
  );
}

function SummaryStat({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.summaryStat}>
      <Text style={styles.summaryStatLabel}>{label}</Text>
      <Text style={styles.summaryStatValue}>{value}</Text>
    </View>
  );
}

function PlayerRow({
  player,
  onPress,
}: {
  player: RosterPlayer;
  onPress: () => void;
}) {
  const initials = player.name
    .split(/\s+/)
    .map((part) => part[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();

  return (
    <Pressable
      accessibilityHint="Apre la scheda del calciatore"
      accessibilityLabel={`Apri la scheda di ${player.name}`}
      accessibilityRole="button"
      onPress={onPress}
      style={({ pressed }) => [
        styles.playerRow,
        pressed && styles.playerRowPressed,
      ]}
    >
      <View style={styles.playerAvatar}>
        <Text style={styles.playerAvatarText}>{initials}</Text>
      </View>
      <View style={styles.playerCopy}>
        <Text style={styles.playerName}>{player.name}</Text>
        <Text style={styles.playerClub}>
          {player.clubName}
          {player.shirtNumber ? ` · #${player.shirtNumber}` : ''}
        </Text>
      </View>
      <View style={styles.roleBadge}>
        <Text style={styles.roleBadgeText}>{player.role}</Text>
      </View>
      <View style={styles.priceBox}>
        <Text style={styles.priceValue}>{player.purchasePrice}</Text>
        <Text style={styles.priceLabel}>CR</Text>
      </View>
      <Text style={styles.playerArrow}>›</Text>
    </Pressable>
  );
}

function groupPlayers(players: RosterPlayer[]) {
  return players.reduce<Record<string, RosterPlayer[]>>((groups, player) => {
    const group = roleGroup(player.role);
    groups[group] = [...(groups[group] ?? []), player];
    return groups;
  }, {});
}

function roleGroup(role: string) {
  const roles = role.split('/').map((item) => item.trim());
  if (roles.some((item) => item === 'P' || item === 'Por')) {
    return 'PORTIERI';
  }
  if (roles.some((item) => ['D', 'Dc', 'Dd', 'Ds', 'E'].includes(item))) {
    return 'DIFENSORI';
  }
  if (roles.some((item) => ['C', 'M', 'W', 'T'].includes(item))) {
    return 'CENTROCAMPISTI';
  }
  return 'ATTACCANTI';
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
  content: {
    padding: 20,
    paddingBottom: 42,
  },
  centerRoot: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 25,
    backgroundColor: colors.canvas,
  },
  centerTitle: {
    color: colors.navy,
    fontSize: 20,
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
    fontWeight: '900',
  },
  title: {
    color: colors.navy,
    fontSize: 25,
    fontWeight: '900',
    marginTop: 4,
  },
  managerName: {
    color: colors.muted,
    fontSize: 10,
    marginTop: 4,
  },
  summaryCard: {
    minHeight: 165,
    borderRadius: radius.xl,
    padding: 22,
    backgroundColor: colors.navy,
  },
  summaryLabel: {
    color: colors.mutedLight,
    fontSize: 9,
    fontWeight: '900',
  },
  summaryTitle: {
    color: colors.warmWhite,
    fontSize: 22,
    fontWeight: '900',
    marginTop: 6,
  },
  summaryRow: {
    flexDirection: 'row',
    borderTopWidth: 1,
    borderTopColor: colors.navyLine,
    paddingTop: 18,
    marginTop: 20,
  },
  summaryStat: {
    flex: 1,
  },
  summaryStatLabel: {
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '900',
  },
  summaryStatValue: {
    color: colors.lime,
    fontSize: 19,
    fontWeight: '900',
    marginTop: 4,
  },
  quotaCard: {
    borderRadius: radius.lg,
    padding: 16,
    backgroundColor: colors.white,
    marginTop: 14,
  },
  quotaEyebrow: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  quotaRow: {
    flexDirection: 'row',
    marginTop: 12,
  },
  quotaItem: {
    flex: 1,
    alignItems: 'center',
  },
  quotaValue: {
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
  },
  quotaLabel: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
    marginTop: 3,
  },
  loadingCard: {
    minHeight: 120,
    borderRadius: radius.lg,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
    marginTop: 16,
  },
  loadingText: {
    color: colors.muted,
    fontSize: 11,
    marginTop: 9,
  },
  errorCard: {
    borderRadius: radius.lg,
    padding: 22,
    backgroundColor: colors.white,
    marginTop: 16,
  },
  errorTitle: {
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
  },
  errorBody: {
    color: colors.danger,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 8,
  },
  retryButton: {
    alignSelf: 'flex-start',
    minHeight: 42,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 18,
    backgroundColor: colors.navy,
    marginTop: 16,
  },
  retryButtonText: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
  },
  emptyCard: {
    borderRadius: radius.lg,
    padding: 22,
    backgroundColor: colors.white,
    marginTop: 16,
  },
  emptyTitle: {
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
  },
  emptyBody: {
    color: colors.muted,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 8,
  },
  primaryButton: {
    minHeight: 52,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 20,
    backgroundColor: colors.lime,
    marginTop: 18,
  },
  primaryButtonText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  roleHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: 23,
    marginBottom: 9,
  },
  roleTitle: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
  roleCount: {
    color: colors.muted,
    fontSize: 10,
    fontWeight: '900',
  },
  playersCard: {
    borderRadius: radius.lg,
    padding: 7,
    backgroundColor: colors.white,
  },
  playerRow: {
    minHeight: 67,
    borderRadius: 16,
    paddingHorizontal: 9,
    flexDirection: 'row',
    alignItems: 'center',
  },
  playerRowPressed: {
    backgroundColor: colors.canvasMuted,
  },
  playerAvatar: {
    width: 42,
    height: 42,
    borderRadius: 15,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  playerAvatarText: {
    color: colors.lime,
    fontSize: 10,
    fontWeight: '900',
  },
  playerCopy: {
    flex: 1,
    marginLeft: 11,
  },
  playerName: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
  },
  playerClub: {
    color: colors.muted,
    fontSize: 9,
    marginTop: 4,
  },
  roleBadge: {
    minWidth: 34,
    height: 28,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 7,
    backgroundColor: colors.canvasMuted,
  },
  roleBadgeText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  priceBox: {
    minWidth: 36,
    alignItems: 'flex-end',
    marginLeft: 8,
  },
  playerArrow: {
    color: colors.muted,
    fontSize: 22,
    marginLeft: 7,
  },
  priceValue: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
  },
  priceLabel: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
  },
});
